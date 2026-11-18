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
  if not v_staff then raise exception 'Cek kelayakan hanya untuk panitia.' using hint = 'ERR_SESSION'; end if;
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
