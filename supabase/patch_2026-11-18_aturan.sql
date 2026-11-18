-- Patch 18 Nov 2026: Aturan pendaftaran dikelola dari konsol, cek kelayakan, filter kategori.
-- Jalankan seluruhnya di Supabase SQL Editor (aman diulang).
-- =====================================================================
--  ATURAN PENDAFTARAN (18 November 2026)
--  Semua aturan pendaftaran yang sebelumnya tertanam di kode kini disimpan
--  di jo.settings ('reg_rules') dan diubah dari Konsol → Aturan pendaftaran.
--  Formulir biasa, portal massal, dan server membaca aturan yang sama.
-- =====================================================================

insert into jo.settings (key, value) values ('reg_rules', '{}'::jsonb) on conflict (key) do nothing;

-- Nilai bawaan (sama persis dengan aturan sebelum 18 Nov 2026)
create or replace function jo.rule_defaults() returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'guardian_age', 18,                       -- data orang tua/wali wajib untuk atlet di bawah usia ini
    'proof_minutes', 15,                      -- pendaftaran QRIS tanpa bukti bayar dihapus setelah sekian menit (0 = tidak dihapus)
    'rate_per_hour', 12,                      -- batas pendaftaran per perangkat per jam
    'pair_with_individual', jsonb_build_array('AER'),  -- disiplin yang membolehkan 1 nomor perorangan + 1 nomor pasangan
    'priangan', jsonb_build_object('wni', true, 'athlete_province', 'Jawa Barat', 'club_province', 'Jawa Barat'),
    'docs', jsonb_build_object(
      'WNI', jsonb_build_object('akte','wajib','ktp','opsional','ijazah','opsional','bpjs','opsional','passport','tidak','photo','wajib'),
      'WNA', jsonb_build_object('akte','tidak','ktp','tidak','ijazah','tidak','bpjs','tidak','passport','wajib','photo','wajib')))
$$;

create or replace function jo.rules() returns jsonb
language sql stable set search_path = '' as $$
  select d || s
    || jsonb_build_object('priangan', (d->'priangan') || coalesce(s->'priangan', '{}'::jsonb))
    || jsonb_build_object('docs', jsonb_build_object(
         'WNI', (d->'docs'->'WNI') || coalesce(s->'docs'->'WNI', '{}'::jsonb),
         'WNA', (d->'docs'->'WNA') || coalesce(s->'docs'->'WNA', '{}'::jsonb)))
  from (select jo.rule_defaults() as d, coalesce(jo.setting('reg_rules'), '{}'::jsonb) as s) x
$$;

create or replace function jo.rule_int(k text) returns integer
language sql stable set search_path = '' as $$
  select (jo.rules()->>k)::integer
$$;

-- Usia wajib data wali (bawaan 18)
create or replace function jo.is_minor(p_birth date) returns boolean
language sql stable set search_path = '' as $$
  select p_birth > (current_date - make_interval(years => coalesce(jo.rule_int('guardian_age'), 18)))::date
$$;

-- Syarat kategori khusus daerah (Priangan). Null = memenuhi.
-- p_club_province null = klub belum dipilih (tidak diperiksa); '' = klub tanpa provinsi.
create or replace function jo.priangan_reason(p_nat text, p_province text, p_club_province text) returns text
language plpgsql stable set search_path = '' as $$
declare r jsonb := jo.rules()->'priangan';
  ap text := nullif(trim(coalesce(r->>'athlete_province','')), '');
  cp text := nullif(trim(coalesce(r->>'club_province','')), '');
begin
  if coalesce((r->>'wni')::boolean, true) and coalesce(p_nat, 'WNI') <> 'WNI' then
    return 'khusus atlet WNI';
  end if;
  if ap is not null and coalesce(p_province, '') <> ap then
    return 'alamat identitas atlet harus di ' || ap;
  end if;
  if cp is not null and p_club_province is not null and p_club_province <> cp then
    return 'klub harus dari ' || cp;
  end if;
  return null;
end $$;

create or replace function jo.priangan_desc() returns text
language plpgsql stable set search_path = '' as $$
declare r jsonb := jo.rules()->'priangan'; parts text[] := '{}';
  ap text := nullif(trim(coalesce(r->>'athlete_province','')), '');
  cp text := nullif(trim(coalesce(r->>'club_province','')), '');
begin
  if ap is not null then parts := parts || ('alamat identitas di ' || ap); end if;
  if cp is not null then parts := parts || ('klub di ' || cp); end if;
  return 'Khusus atlet' || case when coalesce((r->>'wni')::boolean, true) then ' WNI' else '' end
    || case when array_length(parts, 1) > 0 then ' dengan ' || array_to_string(parts, ' dan ') else '' end;
end $$;

-- Label usia otomatis dari tahun lahir. Gaya "Kelahiran ..." dipertahankan bila label lama memakai gaya itu.
create or replace function jo.age_label_for(p_min integer, p_max integer, p_style text default null) returns text
language plpgsql stable set search_path = '' as $$
declare y integer := coalesce(jo.setting_int('event_year'), 2026); lo integer; hi integer;
begin
  if coalesce(p_style, '') ilike 'kelahiran%' then
    if p_min is not null and p_max is not null then
      return 'Kelahiran ' || case when p_min = p_max then p_min::text else p_min || '–' || p_max end;
    elsif p_min is not null then return 'Kelahiran ' || p_min || ' ke atas';
    elsif p_max is not null then return 'Kelahiran ' || p_max || ' ke bawah';
    else return 'Usia terbuka'; end if;
  end if;
  lo := y - p_max; hi := y - p_min;
  if p_min is not null and p_max is not null then
    return case when lo = hi then lo || ' tahun' else lo || '–' || hi || ' tahun' end;
  elsif p_min is not null then return hi || ' tahun ke bawah';
  elsif p_max is not null then return lo || ' tahun ke atas';
  end if;
  return 'Usia terbuka';
end $$;

create or replace function jo.age_label_en(p_min integer, p_max integer) returns text
language plpgsql stable set search_path = '' as $$
declare y integer := coalesce(jo.setting_int('event_year'), 2026); lo integer := y - p_max; hi integer := y - p_min;
begin
  if p_min is not null and p_max is not null then return case when lo = hi then lo::text else lo || '–' || hi end;
  elsif p_min is not null then return hi || ' & under';
  elsif p_max is not null then return lo || ' & over';
  end if;
  return 'open age';
end $$;

-- Setelah tahun lahir berubah: perbarui label usia dan bagian usia di nama kategori
create or replace function jo.category_relabel(p_id integer, p_old jo.categories) returns void
language plpgsql set search_path = '' as $$
declare c jo.categories; v_new text; v_new_en text; v_old_en text; v_name text; v_name_en text;
begin
  select * into c from jo.categories where id = p_id;
  if c.birth_year_min is not distinct from p_old.birth_year_min and c.birth_year_max is not distinct from p_old.birth_year_max then
    return;
  end if;
  v_new := jo.age_label_for(c.birth_year_min, c.birth_year_max, p_old.age_label);
  v_name := c.name_id;
  if coalesce(p_old.age_label, '') <> '' then
    if position(p_old.age_label in v_name) > 0 then v_name := replace(v_name, p_old.age_label, v_new);
    elsif position(lower(p_old.age_label) in v_name) > 0 then v_name := replace(v_name, lower(p_old.age_label), lower(v_new));
    end if;
  end if;
  v_old_en := jo.age_label_en(p_old.birth_year_min, p_old.birth_year_max);
  v_new_en := jo.age_label_en(c.birth_year_min, c.birth_year_max);
  v_name_en := c.name_en;
  if position('(' || v_old_en || ')' in v_name_en) > 0 then
    v_name_en := replace(v_name_en, '(' || v_old_en || ')', '(' || v_new_en || ')');
  end if;
  update jo.categories set age_label = v_new, name_id = v_name, name_en = v_name_en where id = p_id;
end $$;

-- =====================================================================
--  Konsol: membaca dan menyimpan aturan
-- =====================================================================
create or replace function public.console_rules() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(null);
  return jsonb_build_object(
    'rules', jo.rules(),
    'defaults', jo.rule_defaults(),
    'can_edit', st.role in ('owner', 'superadmin'),
    'settings', jsonb_build_object(
      'event_year', coalesce(jo.setting_int('event_year'), 2026),
      'max_athletes', coalesce(jo.setting_int('max_athletes'), 10),
      'team_max', coalesce(jo.setting_int('team_max'), 6),
      'team_fee', coalesce(jo.setting_int('team_fee'), 650000),
      'team_counting', coalesce(jo.setting_int('team_counting'), 4),
      'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb),
      'qris_cap', coalesce(jo.setting_int('qris_cap'), 10000000),
      'bulk_min', coalesce(jo.setting_int('bulk_min'), 30),
      'bulk_max', coalesce(jo.setting_int('bulk_max'), 250),
      'bulk_days', coalesce(jo.setting_int('bulk_days'), 7)),
    'updated', (select jsonb_build_object('at', s.updated_at, 'by', f.name)
                  from jo.settings s left join jo.staff f on f.id = s.updated_by where s.key = 'reg_rules'),
    'disciplines', (select coalesce(jsonb_agg(jsonb_build_object('code', d.code, 'name_id', d.name_id,
                       'levels', (select coalesce(jsonb_agg(distinct c.level), '[]'::jsonb) from jo.categories c
                                   where c.discipline = d.code and c.entry_type = 'individual'))
                     order by d.sort), '[]'::jsonb) from jo.disciplines d));
end $$;

create or replace function public.console_save_rules(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jo.staff; r jsonb := coalesce(p->'rules', '{}'::jsonb); s jsonb := coalesce(p->'settings', '{}'::jsonb);
  v_old jsonb := jo.rules(); v_new jsonb; k text; nat text; v integer; v_changes jsonb := '{}'::jsonb;
  v_old_set jsonb; v_slots text[] := array['akte','ktp','ijazah','bpjs','passport','photo'];
  v_ints jsonb := '{"max_athletes":[1,100],"team_max":[1,20],"team_fee":[0,100000000],"team_counting":[1,20],
                    "qris_cap":[100000,1000000000],"bulk_min":[1,250],"bulk_max":[1,250],"bulk_days":[1,30]}';
  v_labels jsonb := '{"max_athletes":"Maks. atlet per pendaftaran","team_max":"Maks. pesenam per tim","team_fee":"Biaya beregu",
                      "team_counting":"Nilai yang dihitung per tim","qris_cap":"Batas satu transaksi QRIS","bulk_min":"Minimal atlet pendaftaran massal",
                      "bulk_max":"Maksimal atlet pendaftaran massal","bulk_days":"Masa berlaku kode massal (hari)"}';
begin
  st := jo.require_staff(array['owner','superadmin']);

  -- ---------- aturan ----------
  v_new := v_old;
  if r ? 'guardian_age' then
    v := (r->>'guardian_age')::integer;
    if v is null or v < 0 or v > 30 then raise exception 'Usia wajib data wali harus 0–30 tahun.'; end if;
    v_new := v_new || jsonb_build_object('guardian_age', v);
  end if;
  if r ? 'proof_minutes' then
    v := (r->>'proof_minutes')::integer;
    if v is null or v < 0 or v > 1440 then raise exception 'Batas unggah bukti bayar harus 0–1440 menit (0 = tidak dihapus otomatis).'; end if;
    v_new := v_new || jsonb_build_object('proof_minutes', v);
  end if;
  if r ? 'rate_per_hour' then
    v := (r->>'rate_per_hour')::integer;
    if v is null or v < 1 or v > 1000 then raise exception 'Batas pendaftaran per perangkat harus 1–1000 per jam.'; end if;
    v_new := v_new || jsonb_build_object('rate_per_hour', v);
  end if;
  if r ? 'pair_with_individual' then
    if jsonb_typeof(r->'pair_with_individual') <> 'array'
       or exists (select 1 from jsonb_array_elements_text(r->'pair_with_individual') x where not exists (select 1 from jo.disciplines d where d.code = x)) then
      raise exception 'Daftar disiplin untuk nomor pasangan tidak valid.';
    end if;
    v_new := v_new || jsonb_build_object('pair_with_individual', r->'pair_with_individual');
  end if;
  if r ? 'priangan' then
    if length(coalesce(r->'priangan'->>'athlete_province','')) > 60 or length(coalesce(r->'priangan'->>'club_province','')) > 60 then
      raise exception 'Nama provinsi terlalu panjang.';
    end if;
    v_new := v_new || jsonb_build_object('priangan', jsonb_build_object(
      'wni', coalesce((r->'priangan'->>'wni')::boolean, true),
      'athlete_province', trim(coalesce(r->'priangan'->>'athlete_province','')),
      'club_province', trim(coalesce(r->'priangan'->>'club_province',''))));
  end if;
  if r ? 'docs' then
    foreach nat in array array['WNI','WNA'] loop
      for k in select jsonb_object_keys(coalesce(r->'docs'->nat, '{}'::jsonb)) loop
        if not (k = any(v_slots)) or coalesce(r->'docs'->nat->>k, '') not in ('wajib','opsional','tidak') then
          raise exception 'Pengaturan dokumen % tidak valid.', k;
        end if;
      end loop;
    end loop;
    v_new := v_new || jsonb_build_object('docs', jsonb_build_object(
      'WNI', (v_old->'docs'->'WNI') || coalesce(r->'docs'->'WNI', '{}'::jsonb),
      'WNA', (v_old->'docs'->'WNA') || coalesce(r->'docs'->'WNA', '{}'::jsonb)));
  end if;

  if v_new is distinct from v_old then
    insert into jo.settings (key, value, updated_at, updated_by) values ('reg_rules', v_new, now(), st.id)
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    for k in select jsonb_object_keys(v_new) loop
      if v_new->k is distinct from v_old->k then
        v_changes := v_changes || jsonb_build_object(k, jsonb_build_object('before', v_old->k, 'after', v_new->k));
      end if;
    end loop;
  end if;

  -- ---------- pengaturan pendaftaran lain ----------
  for k in select jsonb_object_keys(s) loop
    if k = 'team_levels' then
      if jsonb_typeof(s->k) <> 'object' then raise exception 'Level beregu tidak valid.'; end if;
      if exists (select 1 from jsonb_each(s->k) x where x.key not in ('MAG','WAG') or jsonb_typeof(x.value) <> 'array') then
        raise exception 'Beregu hanya bisa untuk Artistik Putra atau Artistik Putri.';
      end if;
      if exists (select 1 from jsonb_each(s->k) x, jsonb_array_elements_text(x.value) lv
                  where not exists (select 1 from jo.categories c where c.discipline = x.key and c.level = lv)) then
        raise exception 'Ada level beregu yang tidak punya kategori.';
      end if;
    elsif v_ints ? k then
      v := (s->>k)::integer;
      if v is null or v < (v_ints->k->>0)::integer or v > (v_ints->k->>1)::integer then
        raise exception '% harus % sampai %.', coalesce(v_labels->>k, k), v_ints->k->>0, v_ints->k->>1;
      end if;
    else
      raise exception 'Pengaturan % tidak bisa diubah di sini.', k;
    end if;
  end loop;
  if coalesce((s->>'bulk_min')::integer, jo.setting_int('bulk_min'), 30) > coalesce((s->>'bulk_max')::integer, jo.setting_int('bulk_max'), 250) then
    raise exception 'Minimal atlet pendaftaran massal tidak boleh lebih besar dari maksimalnya.';
  end if;
  if coalesce((s->>'team_counting')::integer, jo.setting_int('team_counting'), 4) > coalesce((s->>'team_max')::integer, jo.setting_int('team_max'), 6) then
    raise exception 'Jumlah nilai yang dihitung untuk tim tidak boleh lebih dari jumlah maksimal pesenam per tim.';
  end if;
  for k in select jsonb_object_keys(s) loop
    v_old_set := jo.setting(k);
    if v_old_set is distinct from (case when k = 'team_levels' then s->k else to_jsonb((s->>k)::integer) end) then
      insert into jo.settings (key, value, updated_at, updated_by)
      values (k, case when k = 'team_levels' then s->k else to_jsonb((s->>k)::integer) end, now(), st.id)
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
      v_changes := v_changes || jsonb_build_object(k, jsonb_build_object('before', v_old_set, 'after', s->k));
    end if;
  end loop;

  if v_changes <> '{}'::jsonb then
    perform jo.log(st.id, 'aturan_diubah', 'setting', 'reg_rules', v_changes);
  end if;
  return public.console_rules();
end $$;

-- =====================================================================
--  Konsol: kategori (ubah, tambah, hapus)
-- =====================================================================
create or replace function public.console_update_category(p_id integer, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; k text;
  allowed text[] := array['name_id','name_en','age_label','birth_year_min','birth_year_max','fee','apparatus',
                          'max_per_club','allow_priangan','medal_rule','exhibition','active','note','sort',
                          'level','division','gender','entry_type','jabar_only','code'];
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_id for update;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  for k in select jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) loop
    if not (k = any(allowed)) then raise exception 'Kolom % tidak bisa diubah.', k; end if;
    if st.role = 'admin' and k not in ('exhibition','note') then
      raise exception 'Admin disiplin hanya bisa mengubah status eksibisi dan catatan. Perubahan lain oleh superadmin.';
    end if;
  end loop;
  if p_patch ? 'gender' and p_patch->>'gender' not in ('M','F','X') then raise exception 'Jenis kelamin kategori tidak valid.'; end if;
  if p_patch ? 'entry_type' and p_patch->>'entry_type' not in ('individual','pair') then raise exception 'Jenis nomor tidak valid.'; end if;
  if coalesce(p_patch->>'entry_type', c.entry_type) = 'individual' and coalesce(p_patch->>'gender', c.gender) = 'X' then
    raise exception 'Kategori perorangan harus putra atau putri. "Campuran" hanya untuk pasangan.';
  end if;
  if p_patch ? 'level' and length(trim(coalesce(p_patch->>'level',''))) < 1 then raise exception 'Isi level kategori.'; end if;
  if p_patch ? 'code' then
    if coalesce(p_patch->>'code','') !~ '^[A-Z0-9][A-Z0-9-]{1,30}$' then raise exception 'Kode kategori hanya huruf kapital, angka, dan tanda hubung.'; end if;
    if exists (select 1 from jo.categories where code = p_patch->>'code' and id <> c.id) then raise exception 'Kode % sudah dipakai kategori lain.', p_patch->>'code'; end if;
  end if;
  if nullif(p_patch->>'birth_year_min','')::integer > nullif(p_patch->>'birth_year_max','')::integer then
    raise exception 'Tahun lahir paling awal tidak boleh setelah tahun lahir paling akhir.';
  end if;
  if (p_patch ? 'fee') and coalesce((p_patch->>'fee')::integer, -1) < 0 then raise exception 'Biaya tidak boleh negatif.'; end if;
  update jo.categories set
    name_id = coalesce(nullif(trim(p_patch->>'name_id'),''), name_id),
    name_en = coalesce(nullif(trim(p_patch->>'name_en'),''), name_en),
    age_label = case when p_patch ? 'age_label' then nullif(trim(p_patch->>'age_label'),'') else age_label end,
    birth_year_min = case when p_patch ? 'birth_year_min' then nullif(p_patch->>'birth_year_min','')::integer else birth_year_min end,
    birth_year_max = case when p_patch ? 'birth_year_max' then nullif(p_patch->>'birth_year_max','')::integer else birth_year_max end,
    fee = coalesce((p_patch->>'fee')::integer, fee),
    apparatus = case when p_patch ? 'apparatus' then (select coalesce(array_agg(upper(x)), '{}') from jsonb_array_elements_text(p_patch->'apparatus') x) else apparatus end,
    max_per_club = case when p_patch ? 'max_per_club' then nullif(p_patch->>'max_per_club','')::integer else max_per_club end,
    allow_priangan = coalesce((p_patch->>'allow_priangan')::boolean, allow_priangan),
    medal_rule = coalesce(p_patch->'medal_rule', medal_rule),
    exhibition = coalesce((p_patch->>'exhibition')::boolean, exhibition),
    active = coalesce((p_patch->>'active')::boolean, active),
    note = case when p_patch ? 'note' then p_patch->>'note' else note end,
    sort = coalesce((p_patch->>'sort')::integer, sort),
    level = coalesce(nullif(trim(p_patch->>'level'),''), level),
    division = case when p_patch ? 'division' then nullif(trim(p_patch->>'division'),'') else division end,
    gender = coalesce(p_patch->>'gender', gender),
    entry_type = coalesce(p_patch->>'entry_type', entry_type),
    jabar_only = coalesce((p_patch->>'jabar_only')::boolean, jabar_only),
    code = coalesce(nullif(p_patch->>'code',''), code)
  where id = c.id;
  if not (p_patch ? 'age_label') then perform jo.category_relabel(c.id, c); end if;
  perform jo.log(st.id, 'kategori_diubah', 'category', c.id::text,
    jsonb_build_object('category', c.name_id,
      'before', (select jsonb_object_agg(x.key, to_jsonb(c)->x.key) from jsonb_object_keys(p_patch) x(key)), 'after', p_patch));
  return public.console_categories(c.discipline);
end $$;

create or replace function public.console_create_category(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jo.staff; v_disc jo.disciplines; v_code text; v_id integer; v_n integer := 1; c jo.categories;
  v_level text := trim(coalesce(p->>'level',''));
  v_min integer := nullif(p->>'birth_year_min','')::integer; v_max integer := nullif(p->>'birth_year_max','')::integer;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into v_disc from jo.disciplines where code = p->>'discipline';
  if v_disc.code is null then raise exception 'Pilih disiplin.'; end if;
  perform jo.check_discipline(st, v_disc.code);
  if v_level = '' then raise exception 'Isi level kategori.'; end if;
  if length(trim(coalesce(p->>'name_id',''))) < 3 then raise exception 'Isi nama kategori.'; end if;
  if coalesce(p->>'gender','') not in ('M','F','X') then raise exception 'Pilih jenis kelamin kategori.'; end if;
  if coalesce(p->>'entry_type','individual') not in ('individual','pair') then raise exception 'Jenis nomor tidak valid.'; end if;
  if coalesce(p->>'entry_type','individual') = 'individual' and p->>'gender' = 'X' then
    raise exception 'Kategori perorangan harus putra atau putri. "Campuran" hanya untuk pasangan.';
  end if;
  if v_min > v_max then raise exception 'Tahun lahir paling awal tidak boleh setelah tahun lahir paling akhir.'; end if;
  if coalesce((p->>'fee')::integer, -1) < 0 then raise exception 'Isi biaya kategori.'; end if;
  v_code := upper(trim(coalesce(p->>'code','')));
  if v_code = '' then
    v_code := v_disc.code || '-' || upper(regexp_replace(v_level, '[^A-Za-z0-9]', '', 'g'));
    while exists (select 1 from jo.categories where code = v_code || '-' || v_n) loop v_n := v_n + 1; end loop;
    v_code := v_code || '-' || v_n;
  end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{1,30}$' then raise exception 'Kode kategori hanya huruf kapital, angka, dan tanda hubung.'; end if;
  if exists (select 1 from jo.categories where code = v_code) then raise exception 'Kode % sudah dipakai kategori lain.', v_code; end if;

  insert into jo.categories (discipline, code, level, age_label, division, name_id, name_en, gender, birth_year_min, birth_year_max,
     entry_type, fee, apparatus, max_per_club, allow_priangan, medal_rule, exhibition, active, sort, note, jabar_only)
  values (v_disc.code, v_code, v_level,
     coalesce(nullif(trim(p->>'age_label'),''), jo.age_label_for(v_min, v_max, p->>'label_style')),
     nullif(trim(coalesce(p->>'division','')),''),
     trim(p->>'name_id'), coalesce(nullif(trim(p->>'name_en'),''), trim(p->>'name_id')),
     p->>'gender', v_min, v_max, coalesce(p->>'entry_type','individual'), (p->>'fee')::integer,
     coalesce((select array_agg(upper(x)) from jsonb_array_elements_text(coalesce(p->'apparatus','[]'::jsonb)) x), '{}'),
     nullif(p->>'max_per_club','')::integer, false,
     coalesce(p->'medal_rule', '{"type":"rank","places":3}'::jsonb),
     coalesce((p->>'exhibition')::boolean, false), coalesce((p->>'active')::boolean, true),
     coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 1 from jo.categories where discipline = v_disc.code)),
     nullif(trim(coalesce(p->>'note','')),''), coalesce((p->>'jabar_only')::boolean, false))
  returning * into c;
  perform jo.log(st.id, 'kategori_dibuat', 'category', c.id::text,
    jsonb_build_object('category', c.name_id, 'code', c.code, 'copied_from', p->>'copied_from'));
  return public.console_categories(c.discipline) || jsonb_build_object('created_id', c.id);
end $$;

create or replace function public.console_delete_category(p_id integer, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; n integer;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into c from jo.categories where id = p_id for update;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  select count(*) into n from jo.entries where category_id = c.id;
  if n > 0 then
    raise exception 'Kategori % sudah punya % entri pendaftaran (termasuk yang dibatalkan), jadi tidak bisa dihapus. Nonaktifkan saja.', c.name_id, n;
  end if;
  if exists (select 1 from jo.bulk_rows r where r.data->>'category_id' = c.id::text or r.data->>'pair_category_id' = c.id::text) then
    raise exception 'Kategori % sedang dipakai di lembar pendaftaran massal, jadi tidak bisa dihapus. Nonaktifkan saja.', c.name_id;
  end if;
  delete from jo.categories where id = c.id;
  perform jo.log(st.id, 'kategori_dihapus_permanen', 'category', c.id::text,
    jsonb_build_object('category', c.name_id, 'code', c.code, 'reason', p_reason, 'data', to_jsonb(c)));
  return public.console_categories(c.discipline);
end $$;

-- =====================================================================
--  Cek kelayakan (publik dan konsol): hasil dihitung server dengan aturan yang sama
--  seperti saat mendaftar.
-- =====================================================================
create or replace function public.public_check_eligibility(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b date; g text := p->>'gender'; nat text := coalesce(nullif(p->>'nationality',''), 'WNI');
  prov text := nullif(trim(coalesce(p->>'province','')), ''); v_club jo.clubs; cprov text; st jo.staff; v_staff boolean;
  v_pri text;
begin
  if coalesce(p->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Isi tanggal lahir.' using hint = 'ERR_ATHLETE_BIRTH'; end if;
  b := (p->>'birth_date')::date;
  if b < date '1950-01-01' or b > current_date then raise exception 'Tanggal lahir tidak valid.' using hint = 'ERR_ATHLETE_BIRTH'; end if;
  if coalesce(g,'') not in ('M','F') then raise exception 'Pilih jenis kelamin.' using hint = 'ERR_ATHLETE_GENDER'; end if;
  if nat not in ('WNI','WNA') then nat := 'WNI'; end if;
  if nullif(p->>'club_id','') is not null then
    select * into v_club from jo.clubs where id = (p->>'club_id')::uuid;
    if v_club.merged_into is not null then select * into v_club from jo.clubs where id = v_club.merged_into; end if;
    cprov := coalesce(v_club.province, '');
  elsif p ? 'club_province' then
    cprov := coalesce(p->>'club_province', '');
  end if;
  select * into st from jo.current_staff();
  v_staff := st.id is not null;
  v_pri := jo.priangan_reason(nat, case when nat = 'WNI' then prov end, cprov);

  return jsonb_build_object(
    'age', jo.comp_age(b),
    'year', coalesce(jo.setting_int('event_year'), 2026),
    'minor', jo.is_minor(b),
    'guardian_age', coalesce(jo.rule_int('guardian_age'), 18),
    'priangan_reason', v_pri,
    'priangan_desc', jo.priangan_desc(),
    'club', case when v_club.id is not null then jsonb_build_object('id', v_club.id, 'name', v_club.name, 'province', v_club.province) end,
    'registration_open', jo.reg_is_open() and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
    'disciplines', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', d.code, 'name_id', d.name_id, 'name_en', d.name_en, 'open', d.registration_open,
        'categories', (select coalesce(jsonb_agg(x.j order by x.sort, x.id), '[]'::jsonb) from (
            select c.sort, c.id, jsonb_build_object(
              'id', c.id, 'code', c.code, 'name_id', c.name_id, 'name_en', c.name_en, 'level', c.level, 'division', c.division,
              'age_label', c.age_label, 'gender', c.gender, 'entry_type', c.entry_type, 'fee', c.fee, 'active', c.active,
              'jabar_only', c.jabar_only, 'birth_year_min', c.birth_year_min, 'birth_year_max', c.birth_year_max,
              'max_per_club', c.max_per_club, 'quota_left', q.left_n,
              'reason', coalesce(
                  case when not c.active then 'Kategori nonaktif (tidak tampil di formulir)' end,
                  jo.category_mismatch(c, g, b),
                  case when c.jabar_only and v_pri is not null then initcap(left(v_pri, 1)) || substr(v_pri, 2) end,
                  case when q.left_n is not null and q.left_n <= 0 then 'Kuota klub ini untuk kategori ini sudah penuh (' || c.max_per_club || ' peserta)' end),
              'note', case when c.entry_type = 'pair' and c.gender = 'X' then 'Pasangan campuran: satu putra dan satu putri' end) as j
            from jo.categories c
            left join lateral (
              select c.max_per_club - (select count(*) from jo.entries en join jo.submissions s on s.id = en.submission_id
                                        where en.category_id = c.id and en.status = 'aktif' and s.status <> 'dibatalkan'
                                          and s.club_id = v_club.id) as left_n
               where v_club.id is not null and c.max_per_club is not null) q on true
            where c.discipline = d.code and (c.active or v_staff)) x)
      ) order by d.sort), '[]'::jsonb) from jo.disciplines d));
end $$;

-- Aturan ringkas untuk halaman publik (beranda, cek kelayakan)
create or replace function public.public_rules() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('rules', jo.rules(), 'priangan_desc', jo.priangan_desc(),
    'event_year', coalesce(jo.setting_int('event_year'), 2026),
    'max_athletes', coalesce(jo.setting_int('max_athletes'), 10))
$$;

revoke all on function public.console_rules() from public, anon;
grant execute on function public.console_rules() to authenticated;
revoke all on function public.console_save_rules(jsonb) from public, anon;
grant execute on function public.console_save_rules(jsonb) to authenticated;
revoke all on function public.console_create_category(jsonb) from public, anon;
grant execute on function public.console_create_category(jsonb) to authenticated;
revoke all on function public.console_delete_category(integer, text) from public, anon;
grant execute on function public.console_delete_category(integer, text) to authenticated;
revoke all on function public.public_check_eligibility(jsonb) from public;
grant execute on function public.public_check_eligibility(jsonb) to anon, authenticated;
revoke all on function public.public_rules() from public;
grant execute on function public.public_rules() to anon, authenticated;

-- dari supabase/src/40_public.sql
create or replace function jo.check_athlete_docs(a jsonb, p_label text, p_uid uuid) returns void
language plpgsql stable set search_path = '' as $$
-- Dokumen wajib/opsional per kewarganegaraan diatur di Konsol → Aturan pendaftaran (reg_rules.docs)
declare k text;
  v_nat text := case when coalesce(a->>'nationality','WNI') = 'WNA' then 'WNA' else 'WNI' end;
  v_req jsonb := jo.rules()->'docs'->v_nat;
  v_lbl jsonb := '{"akte":"Akte Kelahiran","passport":"paspor","ktp":"KTP","ijazah":"Ijazah","bpjs":"kartu BPJS Ketenagakerjaan"}';
begin
  foreach k in array array['akte','passport','ktp','ijazah','bpjs'] loop
    if v_req->>k = 'wajib' and coalesce(a->>(k || '_path'),'') = '' then
      raise exception '%: unggah %.', p_label, v_lbl->>k using hint = 'ERR_ATHLETE_DOC';
    end if;
  end loop;
  if v_req->>'photo' = 'wajib' and coalesce(a->>'photo_path','') = '' then
    raise exception '%: unggah pas foto (wajib untuk Athlete Identification Card).', p_label using hint = 'ERR_ATHLETE_PHOTO';
  end if;
  if coalesce(a->>'photo_path','') <> ''
     and (coalesce(a->>'photo_thumb','') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(a->>'photo_thumb') > 150000) then
    raise exception '%: pas foto tidak terbaca. Unggah ulang pas foto (JPG atau PNG).', p_label using hint = 'ERR_ATHLETE_PHOTO';
  end if;
  foreach k in array array['akte_path','ktp_path','ijazah_path','passport_path','bpjs_path','photo_path'] loop
    if p_uid is not null and coalesce(a->>k,'') <> '' and split_part(a->>k, '/', 1) <> p_uid::text then
      raise exception 'Berkas unggahan tidak valid. Unggah ulang dokumen.' using hint = 'ERR_UPLOAD';
    end if;
  end loop;
end $$;

-- dari supabase/src/40_public.sql
create or replace function public.public_config() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform jo.expire_unpaid();
  return jsonb_build_object(
    'event', jsonb_build_object(
      'name', jo.setting_text('event_name'),
      'year', jo.setting_int('event_year'),
      'venue', jo.setting('venue'),
      'contact_email', jo.setting_text('contact_email'),
      'pm_email', jo.setting_text('pm_email'),
      'instagram', jo.setting_text('instagram')),
    'registration', jsonb_build_object(
      'open', jo.reg_is_open()
              and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
      'deadline', jo.setting_text('registration_deadline'),
      'reopen_at', jo.reg_reopen_at(),
      'deadline_label', jo.setting_text('payment_deadline_label'),
      'max_athletes', coalesce(jo.setting_int('max_athletes'), 10),
      'form_version', 8,
      'priangan_fee', coalesce(jo.setting_int('priangan_fee'), 150000),
      'team_fee', coalesce(jo.setting_int('team_fee'), 650000),
      'team_max', coalesce(jo.setting_int('team_max'), 6),
      'team_counting', coalesce(jo.setting_int('team_counting'), 4),
      'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb),
      'qris_cap', coalesce(jo.setting_int('qris_cap'), 10000000),
      'rules', jo.rules(),
      'priangan_desc', jo.priangan_desc()),
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note')),
    'disciplines', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', d.code, 'name_id', d.name_id, 'name_en', d.name_en,
        'date_start', d.date_start, 'date_end', d.date_end,
        'apparatus', d.apparatus, 'contact_name', d.contact_name, 'contact_phone', d.contact_phone,
        'registration_open', d.registration_open) order by d.sort), '[]'::jsonb) from jo.disciplines d),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'discipline', c.discipline, 'code', c.code, 'level', c.level,
        'age_label', c.age_label, 'division', c.division,
        'name_id', c.name_id, 'name_en', c.name_en, 'gender', c.gender,
        'birth_year_min', c.birth_year_min, 'birth_year_max', c.birth_year_max,
        'entry_type', c.entry_type, 'fee', c.fee, 'apparatus', c.apparatus,
        'max_per_club', c.max_per_club, 'allow_priangan', c.allow_priangan, 'jabar_only', c.jabar_only) order by c.sort, c.id), '[]'::jsonb)
        from jo.categories c where c.active),
    'clubs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'kind', k.kind, 'kab_kota', k.kab_kota,
        'province', k.province, 'country', k.country) order by k.name), '[]'::jsonb)
        from jo.clubs k where k.merged_into is null)
  );
end $$;

-- dari supabase/src/40_public.sql
create or replace function public.public_register(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid       uuid := auth.uid();
  v_disc      jo.disciplines;
  v_type      text := p->>'registrant_type';
  v_contact   jsonb := coalesce(p->'contact', '{}'::jsonb);
  v_max       integer := coalesce(jo.setting_int('max_athletes'), 10);
  v_pri_fee   integer := coalesce(jo.setting_int('priangan_fee'), 150000);
  v_team_fee  integer := coalesce(jo.setting_int('team_fee'), 650000);
  v_team_max  integer := coalesce(jo.setting_int('team_max'), 6);
  v_cap       integer := coalesce(jo.setting_int('qris_cap'), 10000000);
  v_lang      text := case when p->>'lang' = 'en' then 'en' else 'id' end;
  v_club      jo.clubs;
  v_club_id   uuid;
  v_pm        text := case when jo.in_bulk() then 'transfer' else 'qris' end;   -- pendaftaran massal: transfer bank
  v_sub_id    uuid := gen_random_uuid();
  v_code      text;
  v_token     text := lower(jo.rand_code(28, '23456789abcdefghjkmnpqrstuvwxyz'));
  v_n_ath     integer;
  a           jsonb;
  e           jsonb;
  k           text;
  v_keys      text[] := '{}';
  v_ath_id    uuid;
  v_ath       jo.athletes;
  v_cat       jo.categories;
  v_entry_id  uuid;
  v_eath      text[];
  v_genders   text[];
  v_reason    text;
  v_base      integer := 0;
  v_pri       integer := 0;
  v_uc        integer := 0;
  v_total     integer;
  v_any_minor boolean := false;
  v_cnt       integer;
  v_next      integer;
  v_pri_ok    boolean;
  v_consents  jsonb := coalesce(p->'consents', '{}'::jsonb);
  i           integer := 0;
  ti          integer := 0;
  -- beregu
  v_team      jsonb := coalesce(p->'team', '{}'::jsonb);
  v_level     text;
  v_tname     text;
  v_team_id   uuid;
  v_seen      uuid[] := '{}';
  v_mname     text;
  v_mbirth    date;
  v_mgender   text;
  v_music     text;
  v_mus       jsonb;
  v_teams     jsonb;
  v_tm        jsonb;
  v_n_teams   integer;
  v_people    integer;
  v_team_amt  integer := 0;
  v_sortn     integer := 0;
  v_role      text := lower(trim(coalesce(v_contact->>'role','')));
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman lalu coba lagi.' using hint = 'ERR_SESSION';
  end if;
  perform jo.expire_unpaid();

  if not jo.in_bulk() and (select count(*) from jo.rate_events where uid = v_uid and action = 'register' and at > now() - interval '1 hour') >= coalesce(jo.rule_int('rate_per_hour'), 12) then
    raise exception 'Terlalu banyak pendaftaran dari perangkat ini dalam satu jam. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;

  -- Status pendaftaran
  if not jo.reg_is_open()
     or now() > coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()) then
    raise exception 'Pendaftaran sedang ditutup.' using hint = 'ERR_CLOSED';
  end if;

  select * into v_disc from jo.disciplines where code = p->>'discipline';
  if v_disc.code is null then
    raise exception 'Pilih disiplin terlebih dahulu.' using hint = 'ERR_DISCIPLINE';
  end if;
  if not v_disc.registration_open then
    raise exception 'Pendaftaran disiplin % sedang ditutup.', v_disc.name_id using hint = 'ERR_CLOSED';
  end if;

  -- v8: semua pendaftaran lewat klub; beregu adalah bagian opsional dari pendaftaran klub
  if coalesce(v_type, 'klub') <> 'klub' then
    raise exception 'Pendaftaran kini hanya lewat klub (perorangan dan beregu terpisah sudah tidak tersedia). Muat ulang halaman pendaftaran.' using hint = 'ERR_TYPE';
  end if;
  v_type := 'klub';
  v_teams := case when jsonb_typeof(p->'teams') = 'array' then p->'teams'
                  when jsonb_typeof(p->'team') = 'object' and p->'team' <> '{}'::jsonb then jsonb_build_array(p->'team')
                  else '[]'::jsonb end;
  v_n_teams := jsonb_array_length(v_teams);
  if v_n_teams > 0 and not (jo.setting('team_levels') ? v_disc.code) then
    raise exception 'Beregu tidak tersedia untuk disiplin %.', v_disc.name_id using hint = 'ERR_TEAM';
  end if;

  -- Kontak
  if length(trim(coalesce(v_contact->>'name',''))) < 3 then
    raise exception 'Isi nama penanggung jawab pendaftaran.' using hint = 'ERR_CONTACT_NAME';
  end if;
  if coalesce(v_contact->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Alamat email penanggung jawab tidak valid.' using hint = 'ERR_CONTACT_EMAIL';
  end if;
  if length(regexp_replace(coalesce(v_contact->>'phone',''), '[^0-9]', '', 'g')) < 9 then
    raise exception 'Nomor WhatsApp penanggung jawab tidak valid.' using hint = 'ERR_CONTACT_PHONE';
  end if;
  if v_role not in ('pemilik','admin','pelatih','manajer','lainnya') then
    raise exception 'Pilih peran Anda di klub (pemilik, admin, pelatih, manajer/official, atau lainnya).' using hint = 'ERR_CONTACT_ROLE';
  end if;

  -- Jumlah atlet: atlet perorangan + anggota "khusus beregu" (orang baru) maksimal v_max
  v_n_ath := coalesce(jsonb_array_length(p->'athletes'), 0);
  select v_n_ath + coalesce(sum((select count(*) from jsonb_array_elements(coalesce(t->'members','[]'::jsonb)) m
                                  where m->>'kind' = 'tim')), 0)::integer
    into v_people from jsonb_array_elements(v_teams) t;
  if v_n_ath < 1 and v_n_teams < 1 then
    raise exception 'Tambahkan minimal satu atlet atau satu tim beregu.' using hint = 'ERR_NO_ATHLETE';
  end if;
  if v_people > v_max and not jo.in_bulk() then
    raise exception 'Satu pendaftaran maksimal % atlet (termasuk anggota khusus beregu). Kirim sisanya sebagai pendaftaran terpisah.', v_max using hint = 'ERR_MAX_ATHLETES';
  end if;

  -- Klub
  if p->'club'->>'id' is not null then
    select * into v_club from jo.clubs where id = (p->'club'->>'id')::uuid;
    if v_club.id is null then
      raise exception 'Klub yang dipilih tidak ditemukan. Muat ulang halaman.' using hint = 'ERR_CLUB';
    end if;
    if v_club.merged_into is not null then
      select * into v_club from jo.clubs where id = v_club.merged_into;
    end if;
    v_club_id := v_club.id;
  elsif p->'club'->'new' is not null then
    if length(trim(coalesce(p->'club'->'new'->>'name',''))) < 3 then
      raise exception 'Isi nama klub/sekolah.' using hint = 'ERR_CLUB';
    end if;
    if coalesce(p->'club'->'new'->>'country','Indonesia') = 'Indonesia'
       and (coalesce(p->'club'->'new'->>'province','') = '' or coalesce(p->'club'->'new'->>'kab_kota','') = '') then
      raise exception 'Isi provinsi dan kabupaten/kota klub.' using hint = 'ERR_CLUB';
    end if;
    select * into v_club from jo.clubs
     where merged_into is null
       and lower(name) = lower(trim(p->'club'->'new'->>'name'))
       and lower(coalesce(kab_kota,'')) = lower(coalesce(trim(p->'club'->'new'->>'kab_kota'),''))
       and lower(country) = lower(coalesce(p->'club'->'new'->>'country','Indonesia'))
     limit 1;
    if v_club.id is null then
      insert into jo.clubs (name, kind, kab_kota, province, country, created_via)
      values (jo.org_case(p->'club'->'new'->>'name'),
              coalesce(nullif(p->'club'->'new'->>'kind',''), 'klub'),
              nullif(trim(coalesce(p->'club'->'new'->>'kab_kota','')),''),
              nullif(trim(coalesce(p->'club'->'new'->>'province','')),''),
              coalesce(nullif(trim(coalesce(p->'club'->'new'->>'country','')),''), 'Indonesia'),
              'pendaftaran')
      returning * into v_club;
    end if;
    v_club_id := v_club.id;
  else
    raise exception 'Pendaftaran hanya lewat klub. Pilih atau tambahkan klub/sekolah.' using hint = 'ERR_CLUB';
  end if;

  -- Persetujuan
  if not (coalesce((v_consents->>'waiver')::boolean, false)
      and coalesce((v_consents->>'insurance')::boolean, false)
      and coalesce((v_consents->>'data')::boolean, false)
      and coalesce((v_consents->>'rules')::boolean, false)) then
    raise exception 'Centang semua pernyataan persetujuan sebelum mengirim.' using hint = 'ERR_CONSENT';
  end if;

  v_code := 'TMP-' || v_sub_id::text;   -- kode final diberikan setelah semua validasi lolos

  insert into jo.submissions (id, code, token, discipline, registrant_type, contact_name, contact_email,
     contact_phone, contact_role, club_id, payment_method, consents, lang, auth_uid)
  values (v_sub_id, v_code, v_token, v_disc.code, v_type, jo.name_case(v_contact->>'name'), lower(trim(v_contact->>'email')),
     trim(v_contact->>'phone'), v_role, v_club_id, 'qris',
     v_consents || jsonb_build_object('at', now()), v_lang, v_uid);

  -- =================================================================
  --  ATLET & NOMOR PERORANGAN / PASANGAN
  -- =================================================================
  for a in select * from jsonb_array_elements(coalesce(p->'athletes','[]'::jsonb)) loop
    i := i + 1;
    k := coalesce(a->>'key', 'a' || i);
    if k = any(v_keys) then
      raise exception 'Data atlet ganda.' using hint = 'ERR_ATHLETE';
    end if;
    v_keys := v_keys || k;

    if length(trim(coalesce(a->>'full_name',''))) < 3 then
      raise exception 'Atlet %: isi nama lengkap sesuai identitas.', i using hint = 'ERR_ATHLETE_NAME';
    end if;
    if coalesce(a->>'gender','') not in ('M','F') then
      raise exception 'Atlet %: pilih jenis kelamin.', i using hint = 'ERR_ATHLETE_GENDER';
    end if;
    if coalesce(a->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$'
       or (a->>'birth_date')::date < date '1950-01-01' or (a->>'birth_date')::date > current_date then
      raise exception 'Atlet %: tanggal lahir tidak valid.', i using hint = 'ERR_ATHLETE_BIRTH';
    end if;
    if coalesce(a->>'nationality','WNI') not in ('WNI','WNA') then
      raise exception 'Atlet %: pilih kewarganegaraan.', i using hint = 'ERR_ATHLETE';
    end if;
    if coalesce(a->>'nationality','WNI') = 'WNI' then
      if coalesce(a->>'province','') = '' or coalesce(a->>'kab_kota','') = '' then
        raise exception 'Atlet %: isi provinsi dan kabupaten/kota sesuai alamat di identitas.', i using hint = 'ERR_ATHLETE_ADDRESS';
      end if;
    else
      null; -- WNA juga membayar lewat QRIS (patch 1 Nov 2026)
      if length(trim(coalesce(a->>'country',''))) < 2 then
        raise exception 'Atlet %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
      end if;
    end if;
    perform jo.check_athlete_docs(a, 'Atlet ' || i, case when jo.in_bulk() then null else v_uid end);
    if jo.is_minor((a->>'birth_date')::date) then
      v_any_minor := true;
      if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
         or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
         or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Atlet %: atlet di bawah % tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i, coalesce(jo.rule_int('guardian_age'), 18) using hint = 'ERR_GUARDIAN';
      end if;
    end if;

    insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
       id_doc_path, akte_path, ktp_path, ijazah_path, passport_path, bpjs_path, photo_thumb,
       photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
    values (v_sub_id, jo.name_case(a->>'full_name'), a->>'gender', (a->>'birth_date')::date,
       coalesce(a->>'nationality','WNI'),
       case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
       nullif(trim(coalesce(a->>'province','')),''), nullif(trim(coalesce(a->>'kab_kota','')),''),
       coalesce(nullif(a->>'akte_path',''), nullif(a->>'passport_path','')),
       nullif(a->>'akte_path',''), nullif(a->>'ktp_path',''), nullif(a->>'ijazah_path',''), nullif(a->>'passport_path',''), nullif(a->>'bpjs_path',''), nullif(a->>'photo_thumb',''),
       nullif(a->>'photo_path',''),
       nullif(jo.name_case(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
       nullif(lower(trim(coalesce(a->'guardian'->>'email',''))),''), nullif(trim(coalesce(a->'guardian'->>'relation','')),''),
       'T' || jo.rand_code(9), i)
    returning id into v_ath_id;
    -- simpan pemetaan kunci -> id di tabel sementara (jsonb)
    p := jsonb_set(p, '{_map}', coalesce(p->'_map','{}'::jsonb) || jsonb_build_object(k, v_ath_id));
  end loop;

  -- Entri (nomor lomba)
  if v_n_ath > 0 and coalesce(jsonb_array_length(p->'entries'), 0) < 1 then
    raise exception 'Pilih kategori lomba untuk setiap atlet.' using hint = 'ERR_NO_ENTRY';
  end if;

  for e in select * from jsonb_array_elements(coalesce(p->'entries','[]'::jsonb)) loop
    select * into v_cat from jo.categories
     where id = nullif(e->>'category_id','')::integer and discipline = v_disc.code and active;
    if v_cat.id is null then
      raise exception 'Kategori yang dipilih tidak tersedia untuk disiplin ini.' using hint = 'ERR_CATEGORY';
    end if;

    select array_agg(x) into v_eath from jsonb_array_elements_text(e->'athletes') x;
    v_eath := coalesce(v_eath, '{}');
    if v_cat.entry_type = 'individual' and array_length(v_eath, 1) is distinct from 1 then
      raise exception 'Kategori % hanya untuk satu atlet.', v_cat.name_id using hint = 'ERR_CATEGORY';
    end if;
    if v_cat.entry_type = 'pair' and (array_length(v_eath, 1) is distinct from 2 or v_eath[1] = v_eath[2]) then
      raise exception 'Kategori % membutuhkan dua atlet (pasangan).', v_cat.name_id using hint = 'ERR_PAIR';
    end if;

    v_genders := '{}';
    v_pri_ok := true;
    foreach k in array v_eath loop
      if (p->'_map'->>k) is null then
        raise exception 'Atlet pada kategori % tidak ditemukan dalam formulir.', v_cat.name_id using hint = 'ERR_ENTRY';
      end if;
      select * into v_ath from jo.athletes where id = (p->'_map'->>k)::uuid;
      v_genders := v_genders || v_ath.gender;
      v_reason := jo.category_mismatch(v_cat, v_ath.gender, v_ath.birth_date);
      if v_reason is not null then
        raise exception '% tidak bisa ikut % (%).', v_ath.full_name, v_cat.name_id, v_reason using hint = 'ERR_ELIGIBILITY';
      end if;
      -- satu atlet tidak boleh dua kali di kategori yang sama
      if exists (select 1 from jo.entry_athletes ea join jo.entries en on en.id = ea.entry_id
                  where ea.athlete_id = v_ath.id and en.category_id = v_cat.id) then
        raise exception '% terdaftar dua kali di kategori %.', v_ath.full_name, v_cat.name_id using hint = 'ERR_DUPLICATE';
      end if;
      -- aturan jumlah nomor per atlet (Konsol → Aturan pendaftaran: disiplin yang membolehkan nomor pasangan tambahan)
      if not coalesce(jo.rules()->'pair_with_individual' ? v_disc.code, false) then
        if exists (select 1 from jo.entry_athletes ea where ea.athlete_id = v_ath.id) then
          raise exception '% hanya boleh mengikuti satu kategori di disiplin ini.', v_ath.full_name using hint = 'ERR_ONE_CATEGORY';
        end if;
      else
        if exists (select 1 from jo.entry_athletes ea join jo.entries en on en.id = ea.entry_id
                    join jo.categories cc on cc.id = en.category_id
                    where ea.athlete_id = v_ath.id and cc.entry_type = v_cat.entry_type) then
          raise exception '% hanya boleh mengikuti satu nomor perorangan dan satu nomor pasangan.', v_ath.full_name using hint = 'ERR_ONE_CATEGORY';
        end if;
      end if;
      -- kelayakan kategori khusus daerah (Priangan), syarat diatur di Konsol → Aturan pendaftaran
      if jo.priangan_reason(v_ath.nationality, v_ath.province,
                            case when v_club_id is not null then coalesce(v_club.province,'') end) is not null then
        v_pri_ok := false;
      end if;
    end loop;

    if v_cat.entry_type = 'pair' and v_cat.gender = 'X'
       and not (('M' = any(v_genders)) and ('F' = any(v_genders))) then
      raise exception 'Kategori % adalah pasangan campuran: satu putra dan satu putri.', v_cat.name_id using hint = 'ERR_PAIR';
    end if;

    -- batas peserta per klub per kategori
    if v_club_id is not null and v_cat.max_per_club is not null then
      select count(*) into v_cnt
        from jo.entries en join jo.submissions s on s.id = en.submission_id
       where en.category_id = v_cat.id and en.status = 'aktif'
         and s.club_id = v_club_id and s.status <> 'dibatalkan';
      if v_cnt + 1 > v_cat.max_per_club then
        raise exception 'Klub ini sudah mencapai batas % peserta untuk kategori %.', v_cat.max_per_club, v_cat.name_id using hint = 'ERR_CLUB_LIMIT';
      end if;
    end if;

    -- v6: Priangan bukan tambahan; kategori Priangan (khusus Jawa Barat) berdiri sendiri, tanpa biaya tambahan
    if coalesce((e->>'priangan')::boolean, false) and not v_cat.allow_priangan then
      raise exception 'Priangan kini kategori tersendiri (khusus Ritmik). Pilih kategori Ritmik Priangan.' using hint = 'ERR_PRIANGAN';
    end if;
    if v_cat.jabar_only and not v_pri_ok then
      raise exception '%: %.', v_cat.name_id, jo.priangan_desc() using hint = 'ERR_PRIANGAN';
    end if;

    -- musik Ritmik (v6): satu tautan Google Drive untuk setiap nomor (alat) kategori, semua wajib
    v_mus := '{}'::jsonb;
    if v_disc.code = 'RG' then
      foreach k in array v_cat.apparatus loop
        v_music := trim(coalesce(e->'music'->>k, ''));
        if not jo.valid_drive_url(v_music) then
          raise exception 'Isi tautan Google Drive musik % untuk % (diawali https://drive.google.com/).',
            jo.apparatus_label(v_disc.code, k), v_ath.full_name using hint = 'ERR_MUSIC';
        end if;
        v_mus := v_mus || jsonb_build_object(k, v_music);
      end loop;
    end if;

    insert into jo.entries (submission_id, category_id, fee, priangan_requested, priangan_fee, priangan_status,
                            music, music_status, music_updated_at)
    values (v_sub_id, v_cat.id, v_cat.fee,
            v_cat.jabar_only, 0,
            case when v_cat.jabar_only then 'menunggu' else 'tidak' end,
            v_mus, case when v_mus <> '{}'::jsonb then 'menunggu' else 'tidak_perlu' end,
            case when v_mus <> '{}'::jsonb then now() end)
    returning id into v_entry_id;
    if v_mus <> '{}'::jsonb then
      insert into jo.music_log (entry_id, action, apparatus, new_url)
      select v_entry_id, 'daftar', x.key, x.value from jsonb_each_text(v_mus) x;
    end if;

    foreach k in array v_eath loop
      insert into jo.entry_athletes (entry_id, athlete_id, cert_code)
      values (v_entry_id, (p->'_map'->>k)::uuid, 'C' || jo.rand_code(9));
    end loop;

    v_base := v_base + v_cat.fee;
  end loop;

  -- setiap atlet harus punya minimal satu nomor
  if exists (select 1 from jo.athletes a where a.submission_id = v_sub_id
              and not exists (select 1 from jo.entry_athletes ea where ea.athlete_id = a.id)) then
    raise exception 'Setiap atlet harus memilih minimal satu kategori.' using hint = 'ERR_NO_ENTRY';
  end if;

  v_sortn := v_n_ath;

  -- =================================================================
  --  BEREGU (opsional, Artistik Putri): satu atau beberapa tim, 1–6 pesenam per tim
  -- =================================================================
  for v_tm in select * from jsonb_array_elements(v_teams) loop
    ti := ti + 1;
    v_team := v_tm;
    i := 0;
    v_level := trim(coalesce(v_team->>'level',''));
    if not exists (select 1 from jo.categories where discipline = v_disc.code and level = v_level and active)
       or not coalesce(jo.setting('team_levels')->v_disc.code ? v_level, false) then
      raise exception 'Beregu tidak tersedia untuk %.', coalesce(nullif(v_level,''), 'level ini') using hint = 'ERR_TEAM_LEVEL';
    end if;
    v_tname := jo.org_case(coalesce(v_team->>'name',''));
    if length(v_tname) < 2 then
      raise exception 'Tim %: isi nama tim.', ti using hint = 'ERR_TEAM_NAME';
    end if;
    if exists (select 1 from jo.teams t join jo.submissions s on s.id = t.submission_id
                where t.discipline = v_disc.code and t.level = v_level and s.club_id = v_club_id
                  and s.status <> 'dibatalkan' and lower(t.name) = lower(v_tname)) then
      raise exception 'Nama tim "%" sudah dipakai klub ini di % %. Beri nama berbeda, mis. "% B".', v_tname, v_disc.name_id, v_level, v_tname using hint = 'ERR_TEAM_NAME';
    end if;
    if coalesce(jsonb_array_length(v_team->'members'), 0) < 1 or jsonb_array_length(v_team->'members') > v_team_max then
      raise exception 'Tim %: satu tim berisi 1 sampai % pesenam.', v_tname, v_team_max using hint = 'ERR_TEAM_SIZE';
    end if;
    v_mgender := case when v_disc.code = 'MAG' then 'M' else 'F' end;

    v_team_id := gen_random_uuid();
    insert into jo.teams (id, submission_id, discipline, level, name) values (v_team_id, v_sub_id, v_disc.code, v_level, v_tname);

    for a in select * from jsonb_array_elements(v_team->'members') loop
      i := i + 1;
      if coalesce(a->>'kind','') = 'form' then
        select a || jsonb_build_object('full_name', x.full_name, 'birth_date', x.birth_date::text) into a
          from jo.athletes x where x.id = nullif(p->'_map'->>coalesce(a->>'key',''), '')::uuid and x.submission_id = v_sub_id;
      end if;
      v_mname := jo.name_case(coalesce(a->>'full_name',''));
      if length(v_mname) < 3 then
        raise exception 'Anggota %: isi nama lengkap sesuai identitas.', i using hint = 'ERR_ATHLETE_NAME';
      end if;
      if coalesce(a->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$'
         or (a->>'birth_date')::date < date '1950-01-01' or (a->>'birth_date')::date > current_date then
        raise exception 'Anggota %: tanggal lahir tidak valid.', i using hint = 'ERR_ATHLETE_BIRTH';
      end if;
      v_mbirth := (a->>'birth_date')::date;

      -- cari atlet perorangan klub ini di level yang sama
      v_entry_id := null; v_ath_id := null;
      select en.id, at2.id into v_entry_id, v_ath_id
        from jo.athletes at2
        join jo.entry_athletes ea on ea.athlete_id = at2.id
        join jo.entries en on en.id = ea.entry_id
        join jo.categories c on c.id = en.category_id
        join jo.submissions s on s.id = en.submission_id
       where c.discipline = v_disc.code and c.level = v_level and not en.team_only
         and en.status <> 'dibatalkan' and s.status <> 'dibatalkan' and s.club_id = v_club_id
         and at2.birth_date = v_mbirth and jo.norm_name(at2.full_name) = jo.norm_name(v_mname)
       order by en.created_at limit 1;

      if coalesce(a->>'kind','') = 'form' then
        -- atlet dari pendaftaran ini yang punya nomor perorangan di level tim
        v_entry_id := null; v_ath_id := nullif(p->'_map'->>coalesce(a->>'key',''), '')::uuid;
        if v_ath_id is null then
          raise exception 'Anggota %: atlet tidak ditemukan di pendaftaran ini.', i using hint = 'ERR_TEAM_MEMBER';
        end if;
        select en.id into v_entry_id
          from jo.entries en join jo.entry_athletes ea on ea.entry_id = en.id join jo.categories c on c.id = en.category_id
         where en.submission_id = v_sub_id and ea.athlete_id = v_ath_id and c.level = v_level
           and c.entry_type = 'individual' and not en.team_only
         limit 1;
        if v_entry_id is null then
          raise exception 'Anggota %: % tidak memilih kategori % % di pendaftaran ini.', i,
            (select full_name from jo.athletes where id = v_ath_id), v_disc.name_id, v_level using hint = 'ERR_TEAM_MEMBER';
        end if;
        if v_entry_id = any(v_seen) or exists (select 1 from jo.team_members tm where tm.entry_id = v_entry_id) then
          raise exception 'Anggota %: % sudah masuk tim lain.', i, (select full_name from jo.athletes where id = v_ath_id) using hint = 'ERR_TEAM_MEMBER';
        end if;
        v_seen := v_seen || v_entry_id;
        insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
        values (v_team_id, v_entry_id, v_ath_id, false, 'B' || jo.rand_code(9), i);

      elsif coalesce(a->>'kind','') = 'individu' then
        if v_entry_id is null then
          raise exception 'Anggota %: % (lahir %) belum terdaftar sebagai atlet perorangan % % di klub ini. Periksa ejaan nama dan tanggal lahir, tambahkan sebagai atlet di pendaftaran ini, atau pilih "Khusus beregu".',
            i, v_mname, to_char(v_mbirth, 'DD-MM-YYYY'), v_disc.name_id, v_level using hint = 'ERR_TEAM_MEMBER';
        end if;
        if v_entry_id = any(v_seen) then
          raise exception 'Anggota %: % tercantum dua kali.', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        if exists (select 1 from jo.team_members tm join jo.teams t2 on t2.id = tm.team_id
                    join jo.submissions s2 on s2.id = t2.submission_id
                    where tm.entry_id = v_entry_id and s2.status <> 'dibatalkan') then
          raise exception 'Anggota %: % sudah masuk tim lain di level ini.', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        v_seen := v_seen || v_entry_id;
        insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
        values (v_team_id, v_entry_id, v_ath_id, false, 'B' || jo.rand_code(9), i);

      elsif coalesce(a->>'kind','') = 'tim' then
        if v_entry_id is not null then
          raise exception 'Anggota %: % sudah terdaftar dengan kategori perorangan di level ini (di pendaftaran ini atau sebelumnya). Pilih atlet itu dari daftar, bukan "Khusus beregu".', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        if coalesce(a->>'nationality','WNI') not in ('WNI','WNA') then
          raise exception 'Anggota %: pilih kewarganegaraan.', i using hint = 'ERR_ATHLETE';
        end if;
        if coalesce(a->>'nationality','WNI') = 'WNA' then
          null; -- WNA juga membayar lewat QRIS (patch 1 Nov 2026)
          if length(trim(coalesce(a->>'country',''))) < 2 then
            raise exception 'Anggota %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
          end if;
        end if;
        perform jo.check_athlete_docs(a, 'Anggota ' || i, case when jo.in_bulk() then null else v_uid end);
        v_sortn := v_sortn + 1;
        if jo.is_minor(v_mbirth) then
          v_any_minor := true;
          if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
             or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
             or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
            raise exception 'Anggota %: pesenam di bawah % tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i, coalesce(jo.rule_int('guardian_age'), 18) using hint = 'ERR_GUARDIAN';
          end if;
        end if;
        -- kategori usia di level ini (ditentukan dari tanggal lahir)
        v_cat := null;
        select c.* into v_cat from jo.categories c
         where c.discipline = v_disc.code and c.level = v_level and c.active and c.entry_type = 'individual'
           and jo.category_mismatch(c, v_mgender, v_mbirth) is null
         order by (c.id = nullif(a->>'category_id','')::integer) desc, c.sort limit 1;
        if v_cat.id is null then
          raise exception 'Anggota %: tidak ada kelompok usia % % yang sesuai dengan tanggal lahir %.', i, v_disc.name_id, v_level, to_char(v_mbirth, 'DD-MM-YYYY') using hint = 'ERR_ELIGIBILITY';
        end if;
        if v_cat.max_per_club is not null then
          select count(*) into v_cnt
            from jo.entries en join jo.submissions s on s.id = en.submission_id
           where en.category_id = v_cat.id and en.status = 'aktif'
             and s.club_id = v_club_id and s.status <> 'dibatalkan';
          if v_cnt + 1 > v_cat.max_per_club then
            raise exception 'Klub ini sudah mencapai batas % peserta untuk kategori %.', v_cat.max_per_club, v_cat.name_id using hint = 'ERR_CLUB_LIMIT';
          end if;
        end if;
        insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
           id_doc_path, akte_path, ktp_path, ijazah_path, passport_path, bpjs_path, photo_thumb,
           photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
        values (v_sub_id, v_mname, v_mgender, v_mbirth, coalesce(a->>'nationality','WNI'),
           case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
           null, null, coalesce(nullif(a->>'akte_path',''), nullif(a->>'passport_path','')),
           nullif(a->>'akte_path',''), nullif(a->>'ktp_path',''), nullif(a->>'ijazah_path',''), nullif(a->>'passport_path',''), nullif(a->>'bpjs_path',''), nullif(a->>'photo_thumb',''),
           nullif(a->>'photo_path',''),
           nullif(jo.name_case(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
           nullif(lower(trim(coalesce(a->'guardian'->>'email',''))),''), nullif(trim(coalesce(a->'guardian'->>'relation','')),''),
           'T' || jo.rand_code(9), v_sortn)
        returning id into v_ath_id;
        insert into jo.entries (submission_id, category_id, fee, team_only)
        values (v_sub_id, v_cat.id, 0, true) returning id into v_entry_id;
        insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry_id, v_ath_id, 'C' || jo.rand_code(9));
        insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
        values (v_team_id, v_entry_id, v_ath_id, true, 'B' || jo.rand_code(9), i);
      else
        raise exception 'Anggota %: pilih atlet dari pendaftaran ini, "Juga perorangan", atau "Khusus beregu".', i using hint = 'ERR_TEAM_MEMBER';
      end if;
    end loop;

    v_team_amt := v_team_amt + v_team_fee;
  end loop;
  v_base := v_base + v_team_amt;

  if v_any_minor and not coalesce((v_consents->>'guardian')::boolean, false) then
    raise exception 'Persetujuan orang tua/wali wajib dicentang untuk atlet di bawah % tahun.', coalesce(jo.rule_int('guardian_age'), 18) using hint = 'ERR_CONSENT';
  end if;

  -- nomor atlet per disiplin (MAG-001, ...)
  perform pg_advisory_xact_lock(4242027);
  select coalesce(max(nullif(regexp_replace(a.athlete_no, '^.*-', ''), '')::integer), 0)
    into v_next from jo.athletes a where a.athlete_no like v_disc.code || '-%';
  for v_ath in select * from jo.athletes where submission_id = v_sub_id order by sort loop
    v_next := v_next + 1;
    update jo.athletes set athlete_no = v_disc.code || '-' || lpad(v_next::text, 3, '0') where id = v_ath.id;
  end loop;

  -- nominal & kode unik
  if v_pm = 'qris' then
    v_uc := jo.pick_unique_code(v_base + v_pri);
  end if;
  v_total := v_base + v_pri + v_uc;
  if v_pm = 'qris' and v_total > v_cap then
    raise exception 'Total % melebihi batas satu transaksi QRIS (%). Bagi atlet ke dalam dua pendaftaran.',
      jo.fmt_rp(v_total), jo.fmt_rp(v_cap) using hint = 'ERR_QRIS_CAP';
  end if;

  v_code := 'JO26-' || v_disc.code || '-' || lpad(nextval('jo.submission_seq')::text, 4, '0');
  update jo.submissions
     set code = v_code, base_amount = v_base, team_amount = v_team_amt, priangan_amount = v_pri, unique_code = v_uc, total_amount = v_total,
         payment_method = v_pm
   where id = v_sub_id;

  insert into jo.rate_events (uid, action) values (v_uid, 'register');
  perform jo.log(null, 'pendaftaran_baru', 'submission', v_sub_id::text,
    jsonb_build_object('code', v_code, 'athletes', v_people, 'teams', v_n_teams, 'total', v_total, 'type', v_type));
  if not jo.in_bulk() then perform jo.queue_registration_email(v_sub_id); end if;   -- massal: email per batch

  return jsonb_build_object(
    'code', v_code, 'token', v_token, 'status', 'menunggu_pembayaran', 'payment_method', v_pm,
    'base_amount', v_base, 'team_amount', v_team_amt, 'priangan_amount', v_pri, 'unique_code', v_uc, 'total_amount', v_total,
    'expires_at', case when v_pm = 'qris' and coalesce(jo.rule_int('proof_minutes'), 15) > 0
                       then now() + make_interval(mins => coalesce(jo.rule_int('proof_minutes'), 15)) end);
end $$;

-- dari supabase/src/40_public.sql
create or replace function jo.submission_public_json(s jo.submissions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code', s.code, 'status', s.status, 'discipline', s.discipline,
    'discipline_name_id', d.name_id, 'discipline_name_en', d.name_en,
    'registrant_type', s.registrant_type,
    'contact', jsonb_build_object('name', s.contact_name, 'email', s.contact_email, 'phone', s.contact_phone, 'role', s.contact_role),
    'club', case when c.id is null then null else jsonb_build_object('name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) end,
    'payment_method', s.payment_method,
    'base_amount', s.base_amount, 'priangan_amount', s.priangan_amount,
    'unique_code', s.unique_code, 'total_amount', s.total_amount,
    'proof_uploaded_at', s.proof_uploaded_at, 'paid_at', s.paid_at,
    'verify_note', case when s.status = 'perlu_perbaikan' then s.verify_note end,
    'created_at', s.created_at,
    'expires_at', case when s.payment_method = 'qris' and s.status = 'menunggu_pembayaran' and s.proof_path is null
                            and coalesce(jo.rule_int('proof_minutes'), 15) > 0
                       then s.created_at + make_interval(mins => coalesce(jo.rule_int('proof_minutes'), 15)) end,
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note'),
      'deadline_label', jo.setting_text('payment_deadline_label')),
    'signatories', jo.setting('signatories'),
    'apparatus_names', (select jsonb_object_agg(x->>'code', jsonb_build_object('id', x->>'id', 'en', x->>'en')) from jsonb_array_elements(d.apparatus) x),
    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'athlete_no', a.athlete_no, 'full_name', a.full_name, 'gender', a.gender,
        'birth_date', a.birth_date, 'nationality', a.nationality, 'province', a.province, 'kab_kota', a.kab_kota,
        'doc_status', a.doc_status, 'has_bpjs', a.bpjs_path is not null, 'photo_thumb', a.photo_thumb,
        'aic_reissued_at', a.aic_reissued_at,
        'docs', jsonb_build_object('akte', a.akte_path is not null, 'ktp', a.ktp_path is not null, 'ijazah', a.ijazah_path is not null,
                                   'passport', a.passport_path is not null, 'bpjs', a.bpjs_path is not null),
        'ticket_code', case when s.status = 'lunas' then a.ticket_code end
      ) order by a.sort), '[]'::jsonb) from jo.athletes a where a.submission_id = s.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', en.id, 'category_id', cat.id, 'category_name_id', cat.name_id, 'category_name_en', cat.name_en,
        'level', cat.level, 'age_label', cat.age_label, 'apparatus', cat.apparatus,
        'fee', en.fee, 'priangan_requested', en.priangan_requested, 'priangan_status', en.priangan_status,
        'status', en.status, 'team_only', en.team_only,
        'music', en.music, 'music_status', en.music_status, 'music_note', en.music_note,
        'music_changes', en.music_changes, 'startlist_published', cat.startlist_published, 'jabar_only', cat.jabar_only,
        'athlete_ids', (select jsonb_agg(ea.athlete_id) from jo.entry_athletes ea where ea.entry_id = en.id),
        'start', case when cat.startlist_published and s.status = 'lunas' then jsonb_build_object(
            'session', ses.name, 'day', ses.day, 'start_time', ses.start_time,
            'group_no', en.group_no, 'start_order', en.start_order) end,
        'result', case when cat.results_published and s.status = 'lunas' then (
            select r from jsonb_array_elements(jo.category_results(cat.id)) r
             where r->>'entry_id' = en.id::text limit 1) end,
        'certificates', case when cat.results_published and s.status = 'lunas' then (
            select jsonb_agg(jsonb_build_object('athlete_id', ea.athlete_id, 'cert_code', ea.cert_code))
              from jo.entry_athletes ea where ea.entry_id = en.id) end
      ) order by cat.sort), '[]'::jsonb)
      from jo.entries en join jo.categories cat on cat.id = en.category_id
      left join jo.sessions ses on ses.id = en.session_id
      where en.submission_id = s.id and en.status <> 'dibatalkan'),
    'team_amount', s.team_amount,
    'teams', (select coalesce(jsonb_agg(jsonb_build_object(
        'name', t.name, 'level', t.level,
        'published', coalesce(tl.published, false) and s.status = 'lunas',
        'members', (select coalesce(jsonb_agg(jsonb_build_object(
            'athlete_id', m.athlete_id, 'name', a.full_name, 'athlete_no', a.athlete_no, 'team_only', m.team_only,
            'category_name_id', c2.name_id, 'category_name_en', c2.name_en,
            'cert_code', case when coalesce(tl.published, false) and s.status = 'lunas' then m.cert_code end) order by m.sort), '[]'::jsonb)
          from jo.team_members m join jo.athletes a on a.id = m.athlete_id
          join jo.entries e2 on e2.id = m.entry_id join jo.categories c2 on c2.id = e2.category_id
          where m.team_id = t.id),
        'result', case when coalesce(tl.published, false) and s.status = 'lunas' then (
            select r from jsonb_array_elements(jo.team_results(t.discipline, t.level, false)) r
             where r->>'team_id' = t.id::text limit 1) end) order by t.level, t.name), '[]'::jsonb)
      from jo.teams t left join jo.team_levels tl on tl.discipline = t.discipline and tl.level = t.level
      where t.submission_id = s.id)
  )
  from jo.disciplines d left join jo.clubs c on c.id = s.club_id
  where d.code = s.discipline
$$;

-- dari supabase/src/40_public.sql
create or replace function jo.expire_unpaid() returns integer
language plpgsql volatile set search_path = '' as $$
declare r record; n integer := 0; v_min integer := coalesce(jo.rule_int('proof_minutes'), 15);
begin
  if v_min <= 0 then return 0; end if;   -- 0 = pendaftaran tanpa bukti bayar tidak dihapus otomatis
  for r in select id, code, contact_name, discipline, total_amount from jo.submissions
            where payment_method = 'qris' and status = 'menunggu_pembayaran' and proof_path is null
              and created_at < now() - make_interval(mins => v_min)
            for update skip locked loop
    perform jo.purge_submission(r.id);
    perform jo.log(null, 'pendaftaran_kedaluwarsa', 'submission', r.id::text,
      jsonb_build_object('code', r.code, 'contact', r.contact_name, 'discipline', r.discipline, 'total', r.total_amount,
                         'reason', 'Tidak ada bukti bayar dalam ' || v_min || ' menit'));
    n := n + 1;
  end loop;
  if n > 0 then
    -- klub baru yang dibuat pendaftaran itu dan kini tidak dipakai
    delete from jo.clubs k
     where k.created_via = 'pendaftaran' and k.created_at < now() - interval '15 minutes'
       and not exists (select 1 from jo.submissions s where s.club_id = k.id)
       and not exists (select 1 from jo.clubs m where m.merged_into = k.id);
  end if;
  return n;
end $$;

-- dari supabase/src/30_email.sql
create or replace function jo.queue_registration_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; d jo.disciplines; l text; body text; link text;
begin
  select * into s from jo.submissions where id = p_sub;
  select * into d from jo.disciplines where code = s.discipline;
  l := s.lang;
  link := jo.status_link(s.code, s.token);
  body := '<p>' || jo.tr(l, 'Halo ', 'Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l, 'Pendaftaran ', 'Your ')
    || jo.h(case when l = 'en' then d.name_en else d.name_id end)
    || jo.tr(l, ' sudah kami terima. Kode pendaftaran Anda:', ' registration has been received. Your registration code:')
    || '</p><p style="font-size:22px;font-weight:bold;letter-spacing:1px;margin:6px 0 14px">' || jo.h(s.code) || '</p>'
    || jo.email_roster(s.id, l) || coalesce(jo.email_team(s.id, l), '')
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:14px 0;font-size:14px">'
    || case when s.base_amount - s.team_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Biaya pendaftaran','Entry fees') || '</td><td align="right">' || jo.fmt_rp(s.base_amount - s.team_amount) || '</td></tr>' else '' end
    || case when s.team_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Biaya beregu','Team fees') || '</td><td align="right">' || jo.fmt_rp(s.team_amount) || '</td></tr>' else '' end
    || case when s.priangan_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kategori Priangan','Priangan category') || '</td><td align="right">' || jo.fmt_rp(s.priangan_amount) || '</td></tr>' else '' end
    || case when s.unique_code > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kode unik','Unique code') || '</td><td align="right">' || jo.fmt_rp(s.unique_code) || '</td></tr>' else '' end
    || '<tr><td style="padding:10px 0 0;font-weight:bold;font-size:16px">' || jo.tr(l,'Total yang harus dibayar','Total to pay') || '</td>'
    || '<td align="right" style="padding:10px 0 0;font-weight:bold;font-size:20px;color:#13284a">' || jo.fmt_rp(s.total_amount) || '</td></tr></table>';
  if s.payment_method = 'qris' then
    body := body || '<p>' || jo.tr(l,
      'Bayar lewat QRIS Jabar Open 2026 yang tampil di halaman status, lalu ketik nominal <b>tepat ',
      'Pay with the Jabar Open 2026 QRIS shown on the status page and type the <b>exact amount ')
      || jo.fmt_rp(s.total_amount) || '</b>. '
      || jo.tr(l,'Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Setelah membayar, unggah bukti pembayaran di halaman status.',
                 'The last three digits are a unique code that matches your payment to this registration. After paying, upload the payment proof on the status page.')
      || '</p><p style="background:#fdf3dc;border-left:4px solid #e4c87d;padding:10px 14px"><b>'
      || case when coalesce(jo.rule_int('proof_minutes'), 15) > 0 then
           jo.tr(l,'Penting: unggah bukti bayar paling lambat ' || jo.rule_int('proof_minutes') || ' menit setelah mendaftar',
                   'Important: upload the payment proof within ' || jo.rule_int('proof_minutes') || ' minutes of registering')
           || '</b> (' || to_char(s.created_at at time zone 'Asia/Jakarta' + make_interval(mins => jo.rule_int('proof_minutes')), 'HH24:MI') || ' WIB). '
           || jo.tr(l,'Bila tidak, pendaftaran ini dihapus otomatis dan Anda perlu mendaftar ulang.',
                      'Otherwise this registration is deleted automatically and you will need to register again.')
         else jo.tr(l,'Penting: segera unggah bukti bayar setelah membayar.','Important: upload the payment proof right after paying.') || '</b>'
         end || '</p>';
  else
    body := body || '<p>' || jo.tr(l,
      'Pendaftaran atlet internasional dibayar terpisah. Panitia akan menghubungi Anda melalui email ini untuk cara pembayaran.',
      'International registrations are paid separately. The committee will contact you at this email with payment instructions.')
      || '</p>';
  end if;
  body := body || jo.email_button(link, jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Batas pembayaran: ','Payment deadline: ')
    || jo.h(coalesce(jo.setting_text('payment_deadline_label'), '12 November 2026')) || '<br>'
    || jo.tr(l,'Simpan tautan di atas. Siapa pun yang memegang tautan ini dapat melihat data pendaftaran Anda.',
               'Keep the link above private. Anyone with it can see your registration details.')
    || '</p>';
  perform jo.queue_email(s.id, 'pendaftaran', s.contact_email, null,
    jo.tr(l,'Pendaftaran diterima — ','Registration received — ') || s.code,
    jo.email_layout(jo.tr(l,'Pendaftaran diterima','Registration received'), body, l));
end $$;

-- dari supabase/src/50_console.sql
create or replace function public.console_athletes(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter,'{}'::jsonb); d text; q text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.expire_unpaid();
  d := coalesce(st.discipline, nullif(f->>'discipline',''));
  q := '%' || lower(coalesce(f->>'q','')) || '%';
  return (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.athlete_no), '[]'::jsonb) from (
    select a.id, a.athlete_no, a.full_name, a.gender, a.birth_date, jo.comp_age(a.birth_date) as age,
      a.nationality, a.country, a.province, a.kab_kota, coalesce(c.name, 'Perorangan') as club,
      c.kab_kota as club_kab_kota, c.province as club_province,
      s.discipline, s.code as submission_code, s.id as submission_id, s.status as payment_status,
      a.doc_status, a.guardian_name, a.guardian_phone, a.guardian_email, a.guardian_relation,
      s.contact_name, s.contact_phone, s.contact_email,
      (select string_agg(cat.name_id || case when e.team_only then ' [khusus beregu]' else '' end
                         || case when e.priangan_requested then ' [cek Jawa Barat: ' || e.priangan_status || ']' else '' end, '; ' order by cat.sort)
         from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cat on cat.id = e.category_id
        where ea.athlete_id = a.id and e.status <> 'dibatalkan') as categories,
      a.id_doc_path, a.photo_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path,
      a.bpjs_path is not null as has_bpjs, a.aic_update_pending, a.aic_reissued_at,
      (select string_agg(cat.name_id || ': ' || coalesce(case when not cat.active then 'kategori dinonaktifkan' end,
                                                         jo.category_mismatch(cat, a.gender, a.birth_date)), '; ' order by cat.sort)
         from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cat on cat.id = e.category_id
        where ea.athlete_id = a.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issue
    from jo.athletes a join jo.submissions s on s.id = a.submission_id
    left join jo.clubs c on c.id = s.club_id
    where (d is null or s.discipline = d)
      and (coalesce(f->>'include_cancelled','false') = 'true' or s.status <> 'dibatalkan')
      and (nullif(f->>'status','') is null or s.status = f->>'status')
      and (coalesce(f->>'q','') = '' or lower(a.full_name) like q or lower(coalesce(a.athlete_no,'')) like q
           or lower(coalesce(c.name,'')) like q or lower(coalesce(a.kab_kota,'')) like q)
      and (nullif(f->>'category','') is null or exists (select 1 from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id
             where ea.athlete_id = a.id and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
  ) x where coalesce(f->>'flag','') <> 'aturan' or x.rule_issue is not null);
end $$;

-- dari supabase/src/50_console.sql
create or replace function public.console_submissions(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter, '{}'::jsonb); q text; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.expire_unpaid();
  d := coalesce(st.discipline, nullif(f->>'discipline',''));
  q := '%' || lower(coalesce(f->>'q','')) || '%';
  return (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.created_at desc), '[]'::jsonb) from (
    select s.id, s.code, s.created_at, s.discipline, s.registrant_type, s.contact_name, s.contact_phone, s.contact_email,
      c.name as club, coalesce(c.kab_kota, (select a.kab_kota from jo.athletes a where a.submission_id = s.id order by a.sort limit 1)) as region,
      (select count(*) from jo.athletes a where a.submission_id = s.id) as n_athletes,
      (select string_agg(a.full_name, ', ' order by a.sort) from jo.athletes a where a.submission_id = s.id) as athlete_names,
      (select string_agg(t.name || ' (' || t.level || ', ' || (select count(*) from jo.team_members m where m.team_id = t.id) || ' pesenam)', '; ' order by t.level, t.name) from jo.teams t where t.submission_id = s.id) as team_name,
      (select count(*) from jo.entries e where e.submission_id = s.id and e.status <> 'dibatalkan' and e.music_status in ('menunggu','belum','tidak_bisa')) as music_pending,
      s.total_amount, s.unique_code, s.status, s.payment_method, s.proof_uploaded_at, s.paid_at,
      (select b.code from jo.bulk_batches b where b.id = s.bulk_batch_id) as bulk_code,
      case when s.payment_method = 'qris' and s.status = 'menunggu_pembayaran' and s.proof_path is null
                and coalesce(jo.rule_int('proof_minutes'), 15) > 0
           then s.created_at + make_interval(mins => jo.rule_int('proof_minutes')) end as expires_at,
      (select count(*) from jo.athletes a where a.submission_id = s.id and a.doc_status = 'menunggu') as docs_pending,
      (select count(*) from jo.entries e where e.submission_id = s.id and e.priangan_status = 'menunggu') as priangan_pending,
      exists (select 1 from jo.mutations m where m.submission_id = s.id and m.match_status in ('otomatis','manual')) as mutation_matched,
      (select count(distinct ea.athlete_id) from jo.entries e join jo.entry_athletes ea on ea.entry_id = e.id
         join jo.athletes a on a.id = ea.athlete_id join jo.categories cat on cat.id = e.category_id
        where e.submission_id = s.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issues
    from jo.submissions s left join jo.clubs c on c.id = s.club_id
    where (d is null or s.discipline = d)
      and (nullif(f->>'status','') is null or s.status = f->>'status')
      and (coalesce(f->>'q','') = '' or lower(s.code) like q or lower(s.contact_name) like q
           or lower(coalesce(c.name,'')) like q or lower(s.contact_email) like q
           or s.total_amount::text like q
           or exists (select 1 from jo.athletes a where a.submission_id = s.id and lower(a.full_name) like q))
      and (coalesce(f->>'flag','') = ''
           or (f->>'flag' = 'docs' and exists (select 1 from jo.athletes a where a.submission_id = s.id and a.doc_status = 'menunggu') and s.status <> 'dibatalkan')
           or (f->>'flag' = 'priangan' and exists (select 1 from jo.entries e where e.submission_id = s.id and e.priangan_status = 'menunggu') and s.status <> 'dibatalkan')
           or (f->>'flag' = 'beregu' and exists (select 1 from jo.teams t where t.submission_id = s.id))
           or (f->>'flag' = 'musik' and exists (select 1 from jo.entries e where e.submission_id = s.id and e.status <> 'dibatalkan' and e.music_status in ('menunggu','belum','tidak_bisa')) and s.status <> 'dibatalkan')
           or (f->>'flag' = 'aturan' and s.status <> 'dibatalkan' and exists (select 1 from jo.entries e join jo.entry_athletes ea on ea.entry_id = e.id
                 join jo.athletes a on a.id = ea.athlete_id join jo.categories cat on cat.id = e.category_id
                where e.submission_id = s.id and e.status <> 'dibatalkan'
                  and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null))))
      and (nullif(f->>'category','') is null or exists (select 1 from jo.entries e where e.submission_id = s.id
             and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
    order by s.created_at desc
    limit 1000) x);
end $$;

-- dari supabase/src/68_ubah.sql
create or replace function public.console_add_entry(p_id uuid, p_category integer, p_athletes uuid[], p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; c jo.categories; a jo.athletes; v_reason text; v_ids uuid[]; v_id uuid; v_entry uuid;
        v_genders text[] := '{}'; v_names text[] := '{}';
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  if s.status = 'dibatalkan' then raise exception 'Pendaftaran ini sudah dibatalkan.'; end if;
  select * into c from jo.categories where id = p_category and discipline = s.discipline and active;
  if c.id is null then raise exception 'Kategori tidak tersedia untuk disiplin ini.'; end if;
  v_ids := array(select distinct x from unnest(coalesce(p_athletes, '{}'::uuid[])) x);
  if c.entry_type = 'individual' and coalesce(array_length(v_ids, 1), 0) <> 1 then raise exception 'Kategori % untuk satu atlet.', c.name_id; end if;
  if c.entry_type = 'pair' and coalesce(array_length(v_ids, 1), 0) <> 2 then raise exception 'Kategori % membutuhkan dua atlet berbeda (pasangan).', c.name_id; end if;

  foreach v_id in array v_ids loop
    select * into a from jo.athletes where id = v_id and submission_id = s.id;
    if a.id is null then raise exception 'Atlet tidak ada di pendaftaran ini.'; end if;
    v_genders := v_genders || a.gender; v_names := v_names || a.full_name;
    if exists (select 1 from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id where ea.athlete_id = a.id and e.category_id = c.id) then
      raise exception '% sudah terdaftar di kategori %.', a.full_name, c.name_id;
    end if;
    if not coalesce(jo.rules()->'pair_with_individual' ? s.discipline, false) then
      if exists (select 1 from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id where ea.athlete_id = a.id and e.status <> 'dibatalkan') then
        raise exception '% sudah punya kategori di disiplin ini (satu atlet satu kategori). Gunakan Pindah kategori.', a.full_name;
      end if;
    elsif exists (select 1 from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cc on cc.id = e.category_id
                   where ea.athlete_id = a.id and e.status <> 'dibatalkan' and cc.entry_type = c.entry_type) then
      raise exception '% sudah punya satu nomor % (maksimal satu perorangan dan satu pasangan).', a.full_name,
        case when c.entry_type = 'pair' then 'pasangan' else 'perorangan' end;
    end if;
  end loop;
  if c.entry_type = 'pair' and c.gender = 'X' and not (('M' = any(v_genders)) and ('F' = any(v_genders))) then
    raise exception 'Kategori % adalah pasangan campuran: satu putra dan satu putri.', c.name_id;
  end if;

  insert into jo.entries (submission_id, category_id, fee, priangan_requested, priangan_fee, priangan_status, music, music_status)
  values (s.id, c.id, c.fee, c.jabar_only, 0, case when c.jabar_only then 'menunggu' else 'tidak' end,
          '{}'::jsonb, case when s.discipline = 'RG' then 'belum' else 'tidak_perlu' end)
  returning id into v_entry;
  foreach v_id in array v_ids loop
    insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry, v_id, 'C' || jo.rand_code(9));
    perform jo.mark_aic(v_id);
  end loop;
  perform jo.recalc_bill(s.id);
  perform jo.log(st.id, 'kategori_ditambah', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'category', c.name_id, 'athletes', to_jsonb(v_names), 'fee', c.fee, 'reason', v_reason, 'old_total', s.total_amount));
  return public.console_submission(s.id);
end $$;
