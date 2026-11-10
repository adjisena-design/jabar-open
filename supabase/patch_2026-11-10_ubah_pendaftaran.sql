-- Patch 10 Nov 2026: owner & superadmin mengubah isi pendaftaran (sumber: src/68_ubah.sql + src/50_console.sql)
-- Aman dijalankan ulang.

-- =====================================================================
--  v12 (10 Nov 2026): owner & superadmin mengubah isi pendaftaran
--  Penanggung jawab, klub, kategori (tambah/hapus), atlet (tambah),
--  tim beregu (buat/ubah/hapus/anggota), tautan musik Ritmik.
--  Aturan:
--   * alasan wajib, tercatat di Log dengan nilai sebelum & sesudah;
--   * tagihan dihitung ulang; bila sudah lunas, paid_amount tetap dan
--     konsol menampilkan selisih (tidak ada tagihan otomatis);
--   * perubahan yang tampil di AIC menandai "AIC baru" (kirim ulang manual);
--   * ganti disiplin tidak didukung (kode & nomor atlet memuat disiplin);
--   * atlet/kategori yang sudah punya nilai tidak bisa dipindah/dihapus.
-- =====================================================================

create or replace function jo.need_reason(p text) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if length(trim(coalesce(p,''))) < 3 then raise exception 'Tulis alasan perubahan (masuk Log).'; end if;
  return trim(p);
end $$;

-- tagihan = jumlah biaya nomor yang tidak dibatalkan + biaya beregu (+ kode unik)
create or replace function jo.recalc_bill(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare v_base integer;
begin
  select coalesce(sum(e.fee), 0) into v_base from jo.entries e where e.submission_id = p_sub and e.status <> 'dibatalkan';
  update jo.submissions set base_amount = v_base + team_amount, priangan_amount = 0,
    total_amount = v_base + team_amount + unique_code, updated_at = now()
   where id = p_sub and status <> 'dibatalkan';   -- pendaftaran batal: tagihan terakhir dibiarkan sebagai catatan
end $$;

-- AIC atlet berubah: tandai untuk dikirim ulang (hanya bila pendaftarannya sudah lunas)
create or replace function jo.mark_aic(p_athlete uuid) returns void
language sql volatile set search_path = '' as $$
  update jo.athletes a set aic_reissued_at = now(), aic_update_pending = true
   where a.id = p_athlete
     and exists (select 1 from jo.submissions s where s.id = a.submission_id and s.status = 'lunas')
$$;

create or replace function jo.mark_aic_sub(p_sub uuid) returns void
language sql volatile set search_path = '' as $$
  update jo.athletes a set aic_reissued_at = now(), aic_update_pending = true
   where a.submission_id = p_sub
     and exists (select 1 from jo.submissions s where s.id = p_sub and s.status = 'lunas')
$$;

-- ---------------------------------------------------------------------
-- Penanggung jawab
-- ---------------------------------------------------------------------
create or replace function public.console_update_contact(p_id uuid, p_patch jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; k text; v_reason text; v_name text; v_email text; v_phone text; v_role text;
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  for k in select jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) loop
    if k not in ('contact_name','contact_email','contact_phone','contact_role') then raise exception 'Kolom % tidak bisa diubah.', k; end if;
  end loop;
  v_name  := case when p_patch ? 'contact_name'  then jo.name_case(p_patch->>'contact_name') else s.contact_name end;
  v_email := case when p_patch ? 'contact_email' then lower(trim(p_patch->>'contact_email')) else s.contact_email end;
  v_phone := case when p_patch ? 'contact_phone' then trim(p_patch->>'contact_phone') else s.contact_phone end;
  v_role  := case when p_patch ? 'contact_role'  then lower(trim(p_patch->>'contact_role')) else s.contact_role end;
  if length(coalesce(v_name,'')) < 3 then raise exception 'Isi nama penanggung jawab.'; end if;
  if coalesce(v_email,'') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Alamat email penanggung jawab tidak valid.'; end if;
  if length(regexp_replace(coalesce(v_phone,''), '[^0-9]', '', 'g')) < 9 then raise exception 'Nomor WhatsApp penanggung jawab tidak valid.'; end if;
  if p_patch ? 'contact_role' and v_role not in ('pemilik','admin','pelatih','manajer','lainnya') then raise exception 'Peran tidak dikenal.'; end if;

  update jo.submissions set contact_name = v_name, contact_email = v_email, contact_phone = v_phone, contact_role = v_role, updated_at = now()
   where id = s.id;
  perform jo.log(st.id, 'penanggung_jawab_diubah', 'submission', s.id::text, jsonb_build_object('code', s.code, 'reason', v_reason,
    'before', jsonb_build_object('contact_name', s.contact_name, 'contact_email', s.contact_email, 'contact_phone', s.contact_phone, 'contact_role', s.contact_role),
    'after',  jsonb_build_object('contact_name', v_name, 'contact_email', v_email, 'contact_phone', v_phone, 'contact_role', v_role)));
  -- AIC memuat "Didaftarkan oleh"
  if v_name is distinct from s.contact_name then perform jo.mark_aic_sub(s.id); end if;
  -- email berubah: kirim tautan halaman status ke alamat baru agar klub tidak kehilangan akses
  if v_email is distinct from s.contact_email and s.status <> 'dibatalkan' then perform jo.queue_link_email(s.id); end if;
  return public.console_submission(s.id);
end $$;

-- ---------------------------------------------------------------------
-- Klub
-- ---------------------------------------------------------------------
create or replace function public.console_change_club(p_id uuid, p_club uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; c_old jo.clubs; c_new jo.clubs; v_reason text; v_warn text[] := '{}'; r record;
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  select * into c_new from jo.clubs where id = p_club;
  if c_new.id is null then raise exception 'Klub tujuan tidak ditemukan.'; end if;
  if c_new.merged_into is not null then raise exception 'Klub ini sudah digabung ke klub lain. Pilih klub tujuannya.'; end if;
  if c_new.id = s.club_id then raise exception 'Pendaftaran ini sudah atas nama klub tersebut.'; end if;
  select * into c_old from jo.clubs where id = s.club_id;

  update jo.submissions set club_id = c_new.id, updated_at = now() where id = s.id;
  -- syarat Priangan bergantung pada klub: periksa ulang
  update jo.entries e set priangan_status = 'menunggu', priangan_note = null
    from jo.categories c where c.id = e.category_id and e.submission_id = s.id and c.jabar_only;
  if found then v_warn := v_warn || 'Syarat Priangan dikembalikan ke "menunggu": periksa ulang.'::text; end if;
  -- batas peserta per klub per kategori
  for r in
    select c.name_id, c.max_per_club, count(*) n
      from jo.entries e join jo.submissions s2 on s2.id = e.submission_id join jo.categories c on c.id = e.category_id
     where s2.club_id = c_new.id and s2.status <> 'dibatalkan' and e.status = 'aktif' and c.max_per_club is not null
       and c.id in (select category_id from jo.entries where submission_id = s.id)
     group by c.name_id, c.max_per_club having count(*) > c.max_per_club
  loop
    v_warn := v_warn || format('%s: klub ini sekarang punya %s peserta (batas %s).', r.name_id, r.n, r.max_per_club);
  end loop;
  if exists (select 1 from jo.team_members m join jo.teams t on t.id = m.team_id join jo.entries e on e.id = m.entry_id
              where (t.submission_id = s.id) <> (e.submission_id = s.id) and (t.submission_id = s.id or e.submission_id = s.id)) then
    v_warn := v_warn || 'Ada anggota tim beregu yang berasal dari pendaftaran lain: periksa susunan tim.'::text;
  end if;
  perform jo.mark_aic_sub(s.id);
  perform jo.log(st.id, 'klub_diubah', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'from', c_old.name, 'to', c_new.name, 'reason', v_reason, 'warnings', to_jsonb(v_warn)));
  return public.console_submission(s.id) || jsonb_build_object('warnings', to_jsonb(v_warn));
end $$;

-- ---------------------------------------------------------------------
-- Kategori: tambah / hapus
-- ---------------------------------------------------------------------
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
    if s.discipline in ('MAG','WAG','RG') then
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

create or replace function public.console_remove_entry(p_entry uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions; c jo.categories; v_reason text; v_names text[]; v_lonely text; v_ath uuid[];
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into e from jo.entries where id = p_entry for update;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id for update;
  select * into c from jo.categories where id = e.category_id;
  if e.team_only then raise exception 'Ini entri anggota khusus beregu. Hapus atletnya lewat Hapus atlet.'; end if;
  if exists (select 1 from jo.scores sc where sc.entry_id = e.id) then
    raise exception 'Kategori ini sudah punya nilai, tidak bisa dihapus. Tandai "Tidak tampil (DNS)" bila atlet batal tampil.';
  end if;
  if exists (select 1 from jo.team_members m where m.entry_id = e.id) then
    raise exception 'Atlet ini anggota tim beregu lewat kategori ini. Keluarkan dari tim dulu.';
  end if;
  v_ath := array(select ea.athlete_id from jo.entry_athletes ea where ea.entry_id = e.id);
  select string_agg(a.full_name, ', ') into v_lonely from jo.athletes a
   where a.id = any(v_ath)
     and not exists (select 1 from jo.entry_athletes ea where ea.athlete_id = a.id and ea.entry_id <> e.id);
  if v_lonely is not null then
    raise exception 'Ini satu-satunya kategori %. Gunakan Pindah kategori, atau Hapus atlet bila atlet batal ikut.', v_lonely;
  end if;
  v_names := array(select a.full_name from jo.athletes a where a.id = any(v_ath) order by a.sort);

  delete from jo.music_log where entry_id = e.id;
  delete from jo.entry_athletes where entry_id = e.id;
  delete from jo.entries where id = e.id;
  perform jo.mark_aic(x) from unnest(v_ath) x;
  perform jo.recalc_bill(s.id);
  perform jo.log(st.id, 'kategori_dihapus', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'category', c.name_id, 'athletes', to_jsonb(v_names), 'fee', e.fee, 'reason', v_reason, 'old_total', s.total_amount));
  return public.console_submission(s.id);
end $$;

-- ---------------------------------------------------------------------
-- Atlet: tambah ke pendaftaran yang sudah ada (berkas diunggah lewat Kelola berkas)
--   p: full_name, gender, birth_date, nationality, country, province, kab_kota,
--      guardian{name,phone,email,relation}, category_id | (team_id), partner (untuk nomor pasangan)
-- ---------------------------------------------------------------------
create or replace function public.console_add_athlete(p_id uuid, p jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; c jo.categories; t jo.teams; pa jo.athletes; v_reason text;
        v_name text := jo.name_case(coalesce(p->>'full_name','')); v_gender text := coalesce(p->>'gender','');
        v_birth date; v_nat text := coalesce(nullif(p->>'nationality',''), 'WNI'); v_ath uuid; v_entry uuid; v_next integer; v_sort integer;
        v_team_max integer := coalesce(jo.setting_int('team_max'), 6);
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  if s.status = 'dibatalkan' then raise exception 'Pendaftaran ini sudah dibatalkan.'; end if;
  if length(v_name) < 3 then raise exception 'Isi nama lengkap sesuai identitas.'; end if;
  if coalesce(p->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Tanggal lahir tidak valid.'; end if;
  v_birth := (p->>'birth_date')::date;
  if v_birth < date '1950-01-01' or v_birth > current_date then raise exception 'Tanggal lahir tidak valid.'; end if;
  if v_nat not in ('WNI','WNA') then raise exception 'Pilih kewarganegaraan.'; end if;
  if v_nat = 'WNA' and length(trim(coalesce(p->>'country',''))) < 2 then raise exception 'Isi negara asal.'; end if;
  if exists (select 1 from jo.athletes a where a.submission_id = s.id and a.birth_date = v_birth and jo.norm_name(a.full_name) = jo.norm_name(v_name)) then
    raise exception '% (lahir %) sudah ada di pendaftaran ini.', v_name, to_char(v_birth, 'DD-MM-YYYY');
  end if;

  if nullif(p->>'team_id','') is not null then
    -- anggota khusus beregu: kelompok usia ditentukan dari tanggal lahir di level tim
    select * into t from jo.teams where id = (p->>'team_id')::uuid and submission_id = s.id;
    if t.id is null then raise exception 'Tim tidak ditemukan di pendaftaran ini.'; end if;
    if (select count(*) from jo.team_members m where m.team_id = t.id) >= v_team_max then
      raise exception 'Tim % sudah berisi % pesenam.', t.name, v_team_max;
    end if;
    v_gender := case when s.discipline = 'MAG' then 'M' else 'F' end;
    select cc.* into c from jo.categories cc
     where cc.discipline = s.discipline and cc.level = t.level and cc.active and cc.entry_type = 'individual'
       and jo.category_mismatch(cc, v_gender, v_birth) is null
     order by cc.sort limit 1;
    if c.id is null then
      raise exception 'Tidak ada kelompok usia % yang sesuai dengan tanggal lahir %.', t.level, to_char(v_birth, 'DD-MM-YYYY');
    end if;
  else
    if v_gender not in ('M','F') then raise exception 'Pilih jenis kelamin.'; end if;
    select * into c from jo.categories where id = nullif(p->>'category_id','')::integer and discipline = s.discipline and active;
    if c.id is null then raise exception 'Pilih kategori untuk atlet ini.'; end if;
    if c.entry_type = 'pair' then
      select * into pa from jo.athletes where id = nullif(p->>'partner','')::uuid and submission_id = s.id;
      if pa.id is null then raise exception 'Kategori % membutuhkan pasangan: pilih atlet pasangannya.', c.name_id; end if;
      if exists (select 1 from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cc on cc.id = e.category_id
                  where ea.athlete_id = pa.id and e.status <> 'dibatalkan' and cc.entry_type = 'pair') then
        raise exception '% sudah punya nomor pasangan.', pa.full_name;
      end if;
      if c.gender = 'X' and pa.gender = v_gender then raise exception 'Kategori % adalah pasangan campuran: satu putra dan satu putri.', c.name_id; end if;
    end if;
  end if;

  select coalesce(max(a.sort), 0) + 1 into v_sort from jo.athletes a where a.submission_id = s.id;
  insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
     guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
  values (s.id, v_name, v_gender, v_birth, v_nat,
     case when v_nat = 'WNI' then 'Indonesia' else trim(p->>'country') end,
     nullif(trim(coalesce(p->>'province','')),''), nullif(trim(coalesce(p->>'kab_kota','')),''),
     nullif(jo.name_case(coalesce(p->'guardian'->>'name','')),''), nullif(trim(coalesce(p->'guardian'->>'phone','')),''),
     nullif(lower(trim(coalesce(p->'guardian'->>'email',''))),''), nullif(trim(coalesce(p->'guardian'->>'relation','')),''),
     'T' || jo.rand_code(9), v_sort)
  returning id into v_ath;

  if t.id is not null then
    insert into jo.entries (submission_id, category_id, fee, team_only) values (s.id, c.id, 0, true) returning id into v_entry;
    insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry, v_ath, 'C' || jo.rand_code(9));
    insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
    values (t.id, v_entry, v_ath, true, 'B' || jo.rand_code(9), (select coalesce(max(m.sort), 0) + 1 from jo.team_members m where m.team_id = t.id));
  else
    insert into jo.entries (submission_id, category_id, fee, priangan_requested, priangan_fee, priangan_status, music, music_status)
    values (s.id, c.id, c.fee, c.jabar_only, 0, case when c.jabar_only then 'menunggu' else 'tidak' end,
            '{}'::jsonb, case when s.discipline = 'RG' then 'belum' else 'tidak_perlu' end)
    returning id into v_entry;
    insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry, v_ath, 'C' || jo.rand_code(9));
    if pa.id is not null then
      insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry, pa.id, 'C' || jo.rand_code(9));
      perform jo.mark_aic(pa.id);
    end if;
  end if;

  -- nomor atlet berikutnya di disiplin ini
  perform pg_advisory_xact_lock(4242027);
  select coalesce(max(nullif(regexp_replace(a.athlete_no, '^.*-', ''), '')::integer), 0) + 1
    into v_next from jo.athletes a where a.athlete_no like s.discipline || '-%';
  update jo.athletes set athlete_no = s.discipline || '-' || lpad(v_next::text, 3, '0') where id = v_ath;

  perform jo.mark_aic(v_ath);
  perform jo.recalc_bill(s.id);
  perform jo.log(st.id, 'atlet_ditambah', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'athlete', v_name, 'athlete_no', s.discipline || '-' || lpad(v_next::text, 3, '0'), 'birth_date', v_birth,
                       'category', c.name_id, 'team', t.name, 'fee', case when t.id is null then c.fee else 0 end,
                       'reason', v_reason, 'old_total', s.total_amount));
  return public.console_submission(s.id) || jsonb_build_object('new_athlete', v_ath);
end $$;

-- ---------------------------------------------------------------------
-- Tim beregu
-- ---------------------------------------------------------------------
create or replace function public.console_team_save(p_id uuid, p_team uuid, p_name text, p_level text, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; t jo.teams; v_reason text; v_name text := jo.org_case(coalesce(p_name,'')); v_level text := trim(coalesce(p_level,''));
        v_fee integer := coalesce(jo.setting_int('team_fee'), 650000);
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  if s.status = 'dibatalkan' then raise exception 'Pendaftaran ini sudah dibatalkan.'; end if;
  if not coalesce(jo.setting('team_levels')->s.discipline ? v_level, false)
     or not exists (select 1 from jo.categories where discipline = s.discipline and level = v_level and active) then
    raise exception 'Beregu tidak tersedia untuk %.', coalesce(nullif(v_level,''), 'level ini');
  end if;
  if length(v_name) < 2 then raise exception 'Isi nama tim.'; end if;
  if exists (select 1 from jo.teams x join jo.submissions sx on sx.id = x.submission_id
              where x.discipline = s.discipline and x.level = v_level and sx.club_id is not distinct from s.club_id
                and sx.status <> 'dibatalkan' and lower(x.name) = lower(v_name) and x.id is distinct from p_team) then
    raise exception 'Nama tim "%" sudah dipakai klub ini di %. Beri nama berbeda.', v_name, v_level;
  end if;

  if p_team is null then
    insert into jo.teams (id, submission_id, discipline, level, name) values (gen_random_uuid(), s.id, s.discipline, v_level, v_name) returning * into t;
    update jo.submissions set team_amount = team_amount + v_fee where id = s.id;
    perform jo.recalc_bill(s.id);
    perform jo.log(st.id, 'tim_dibuat', 'submission', s.id::text,
      jsonb_build_object('code', s.code, 'team', v_name, 'level', v_level, 'fee', v_fee, 'reason', v_reason, 'old_total', s.total_amount));
  else
    select * into t from jo.teams where id = p_team and submission_id = s.id for update;
    if t.id is null then raise exception 'Tim tidak ditemukan di pendaftaran ini.'; end if;
    if t.level <> v_level and exists (select 1 from jo.team_members m where m.team_id = t.id) then
      raise exception 'Level tim hanya bisa diubah saat tim belum punya anggota. Keluarkan anggotanya dulu.';
    end if;
    update jo.teams set name = v_name, level = v_level where id = t.id;
    perform jo.log(st.id, 'tim_diubah', 'submission', s.id::text,
      jsonb_build_object('code', s.code, 'reason', v_reason, 'before', jsonb_build_object('name', t.name, 'level', t.level),
                         'after', jsonb_build_object('name', v_name, 'level', v_level)));
  end if;
  return public.console_submission(s.id);
end $$;

-- calon anggota: atlet klub yang sama dengan nomor perorangan aktif di level tim dan belum masuk tim mana pun
create or replace function public.console_team_candidates(p_team uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; t jo.teams; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into t from jo.teams where id = p_team;
  if t.id is null then raise exception 'Tim tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = t.submission_id;
  return (select coalesce(jsonb_agg(jsonb_build_object('athlete_id', a.id, 'name', a.full_name, 'athlete_no', a.athlete_no,
              'category', c.name_id, 'code', s2.code, 'same_submission', s2.id = s.id) order by (s2.id = s.id) desc, a.full_name), '[]'::jsonb)
    from jo.athletes a
    join jo.entry_athletes ea on ea.athlete_id = a.id
    join jo.entries e on e.id = ea.entry_id
    join jo.categories c on c.id = e.category_id
    join jo.submissions s2 on s2.id = e.submission_id
   where c.discipline = t.discipline and c.level = t.level and c.entry_type = 'individual' and not e.team_only
     and e.status <> 'dibatalkan' and s2.status <> 'dibatalkan' and s2.club_id is not distinct from s.club_id
     and not exists (select 1 from jo.team_members m join jo.teams t2 on t2.id = m.team_id join jo.submissions s3 on s3.id = t2.submission_id
                      where m.entry_id = e.id and s3.status <> 'dibatalkan'));
end $$;

create or replace function public.console_team_member(p_team uuid, p_athlete uuid, p_add boolean, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; t jo.teams; s jo.submissions; a jo.athletes; m jo.team_members; v_reason text; v_entry uuid;
        v_team_max integer := coalesce(jo.setting_int('team_max'), 6);
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into t from jo.teams where id = p_team for update;
  if t.id is null then raise exception 'Tim tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = t.submission_id;
  select * into a from jo.athletes where id = p_athlete;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;

  if p_add then
    if (select count(*) from jo.team_members x where x.team_id = t.id) >= v_team_max then
      raise exception 'Tim % sudah berisi % pesenam.', t.name, v_team_max;
    end if;
    select e.id into v_entry
      from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories c on c.id = e.category_id
      join jo.submissions s2 on s2.id = e.submission_id
     where ea.athlete_id = a.id and c.discipline = t.discipline and c.level = t.level and c.entry_type = 'individual'
       and not e.team_only and e.status <> 'dibatalkan' and s2.status <> 'dibatalkan' and s2.club_id is not distinct from s.club_id
     order by e.created_at limit 1;
    if v_entry is null then
      raise exception '% tidak punya nomor perorangan aktif di % klub ini. Pindahkan kategorinya dulu, atau tambahkan sebagai anggota khusus beregu.', a.full_name, t.level;
    end if;
    if exists (select 1 from jo.team_members x join jo.teams t2 on t2.id = x.team_id join jo.submissions s3 on s3.id = t2.submission_id
                where x.entry_id = v_entry and s3.status <> 'dibatalkan') then
      raise exception '% sudah masuk tim lain di level ini.', a.full_name;
    end if;
    insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
    values (t.id, v_entry, a.id, false, 'B' || jo.rand_code(9), (select coalesce(max(x.sort), 0) + 1 from jo.team_members x where x.team_id = t.id));
  else
    select * into m from jo.team_members where team_id = t.id and athlete_id = a.id;
    if m.team_id is null then raise exception '% bukan anggota tim ini.', a.full_name; end if;
    if m.team_only then
      raise exception '% adalah anggota khusus beregu. Hapus atletnya lewat Hapus atlet di pendaftarannya.', a.full_name;
    end if;
    delete from jo.team_members where team_id = t.id and athlete_id = a.id;
  end if;
  perform jo.log(st.id, case when p_add then 'anggota_tim_ditambah' else 'anggota_tim_dikeluarkan' end, 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'team', t.name, 'level', t.level, 'athlete', a.full_name, 'athlete_no', a.athlete_no, 'reason', v_reason));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_team_delete(p_team uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; t jo.teams; s jo.submissions; v_reason text; v_fee integer := coalesce(jo.setting_int('team_fee'), 650000); v_members jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into t from jo.teams where id = p_team for update;
  if t.id is null then raise exception 'Tim tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = t.submission_id for update;
  if exists (select 1 from jo.team_members m where m.team_id = t.id and m.team_only) then
    raise exception 'Tim ini punya anggota khusus beregu. Hapus atlet tersebut dulu lewat Hapus atlet.';
  end if;
  if (select count(*) from jo.teams x where x.submission_id = s.id) <= 1
     and not exists (select 1 from jo.athletes a where a.submission_id = s.id) then
    raise exception 'Pendaftaran % hanya berisi tim ini. Hapus pendaftarannya.', s.code;
  end if;
  select coalesce(jsonb_agg(a.full_name order by m.sort), '[]'::jsonb) into v_members
    from jo.team_members m join jo.athletes a on a.id = m.athlete_id where m.team_id = t.id;
  delete from jo.team_members where team_id = t.id;
  delete from jo.teams where id = t.id;
  update jo.submissions set team_amount = greatest(team_amount - v_fee, 0) where id = s.id;
  perform jo.recalc_bill(s.id);
  perform jo.log(st.id, 'tim_dihapus', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'team', t.name, 'level', t.level, 'members', v_members, 'fee', v_fee, 'reason', v_reason, 'old_total', s.total_amount));
  return public.console_submission(s.id);
end $$;

-- ---------------------------------------------------------------------
-- Musik Ritmik: panitia mengisi/memperbaiki tautan (tidak memakai jatah ganti klub)
--   p_music: { "<alat>": "<tautan Google Drive>" | "" (kosongkan) }
-- ---------------------------------------------------------------------
create or replace function public.console_set_music(p_entry uuid, p_music jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions; c jo.categories; v_reason text; k text; v_url text; v_new jsonb; v_changed integer := 0;
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_reason := jo.need_reason(p_reason);
  select * into e from jo.entries where id = p_entry for update;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id;
  select * into c from jo.categories where id = e.category_id;
  if c.discipline <> 'RG' then raise exception 'Tautan musik hanya untuk Ritmik.'; end if;
  v_new := coalesce(e.music, '{}'::jsonb);
  for k in select jsonb_object_keys(coalesce(p_music, '{}'::jsonb)) loop
    if not (k = any(c.apparatus)) then raise exception 'Alat % tidak ada di kategori ini.', k; end if;
    v_url := trim(coalesce(p_music->>k, ''));
    if v_url = coalesce(e.music->>k, '') then continue; end if;
    if v_url <> '' and not jo.valid_drive_url(v_url) then
      raise exception 'Tautan % harus tautan Google Drive (diawali https://drive.google.com/).', jo.apparatus_label('RG', k);
    end if;
    insert into jo.music_log (entry_id, action, apparatus, old_url, new_url, staff_id, note)
    values (e.id, 'panitia', k, nullif(e.music->>k, ''), nullif(v_url, ''), st.id, v_reason);
    v_new := case when v_url = '' then v_new - k else v_new || jsonb_build_object(k, v_url) end;
    v_changed := v_changed + 1;
  end loop;
  if v_changed = 0 then raise exception 'Tidak ada tautan yang berubah.'; end if;
  update jo.entries set music = v_new, music_updated_at = now(), music_note = null, music_checked_by = null, music_checked_at = null,
    music_status = case when exists (select 1 from unnest(c.apparatus) x where coalesce(v_new->>x, '') = '') then 'belum' else 'menunggu' end
   where id = e.id;
  perform jo.log(st.id, 'musik_diubah_panitia', 'entry', e.id::text,
    jsonb_build_object('code', s.code, 'category', c.name_id, 'old', e.music, 'new', v_new, 'reason', v_reason));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_update_athlete(p_athlete uuid, p_patch jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions; b jsonb; k text;
  allowed text[] := array['full_name','gender','birth_date','nationality','country','province','kab_kota',
                          'guardian_name','guardian_phone','guardian_email','guardian_relation'];
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into a from jo.athletes where id = p_athlete for update;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan perubahan data.'; end if;
  for k in select jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) loop
    if not (k = any(allowed)) then raise exception 'Kolom % tidak bisa diubah.', k; end if;
  end loop;
  b := to_jsonb(a);
  update jo.athletes set
    full_name = coalesce(nullif(jo.name_case(p_patch->>'full_name'),''), full_name),
    gender = coalesce(nullif(p_patch->>'gender',''), gender),
    birth_date = coalesce(nullif(p_patch->>'birth_date','')::date, birth_date),
    nationality = coalesce(nullif(p_patch->>'nationality',''), nationality),
    country = coalesce(nullif(trim(p_patch->>'country'),''), country),
    province = case when p_patch ? 'province' then nullif(trim(p_patch->>'province'),'') else province end,
    kab_kota = case when p_patch ? 'kab_kota' then nullif(trim(p_patch->>'kab_kota'),'') else kab_kota end,
    guardian_name = case when p_patch ? 'guardian_name' then nullif(jo.name_case(p_patch->>'guardian_name'),'') else guardian_name end,
    guardian_phone = case when p_patch ? 'guardian_phone' then nullif(trim(p_patch->>'guardian_phone'),'') else guardian_phone end,
    guardian_email = case when p_patch ? 'guardian_email' then nullif(lower(trim(p_patch->>'guardian_email')),'') else guardian_email end,
    guardian_relation = case when p_patch ? 'guardian_relation' then nullif(trim(p_patch->>'guardian_relation'),'') else guardian_relation end
  where id = a.id;
  -- v12: nama, tanggal lahir, jenis kelamin, asal tampil di AIC -> tandai untuk dikirim ulang (bila sudah lunas)
  if exists (select 1 from jo.athletes n where n.id = a.id and (n.full_name, n.birth_date, n.gender, n.nationality, n.country, n.province, n.kab_kota)
                 is distinct from (a.full_name, a.birth_date, a.gender, a.nationality, a.country, a.province, a.kab_kota)) then
    perform jo.mark_aic(a.id);
  end if;
  perform jo.log(st.id, 'data_atlet_diubah', 'athlete', a.id::text,
    jsonb_build_object('reason', p_reason, 'before', (select jsonb_object_agg(x.key, b->x.key) from jsonb_object_keys(p_patch) x(key)), 'after', p_patch));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_move_entry(p_entry uuid, p_category integer, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions; c_old jo.categories; c_new jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into e from jo.entries where id = p_entry for update;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id;
  perform jo.check_discipline(st, s.discipline);
  select * into c_old from jo.categories where id = e.category_id;
  select * into c_new from jo.categories where id = p_category;
  if c_new.id is null or c_new.discipline <> c_old.discipline then
    raise exception 'Kategori tujuan harus di disiplin yang sama.';
  end if;
  if c_new.entry_type <> c_old.entry_type then
    raise exception 'Tidak bisa memindahkan antara nomor perorangan dan pasangan.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan pemindahan (mis. penggabungan kategori).'; end if;
  -- v12: kategori yang sudah punya nilai tidak dipindah; anggota tim tidak pindah level; biaya mengikuti kategori baru
  if exists (select 1 from jo.scores sc where sc.entry_id = e.id) then
    raise exception 'Entri ini sudah punya nilai, tidak bisa dipindah.';
  end if;
  if c_new.level <> c_old.level and exists (select 1 from jo.team_members m where m.entry_id = e.id) then
    raise exception 'Atlet ini anggota tim beregu %. Keluarkan dari tim dulu sebelum pindah level.', c_old.level;
  end if;
  if exists (select 1 from jo.entry_athletes ea join jo.entry_athletes eb on eb.athlete_id = ea.athlete_id and eb.entry_id <> ea.entry_id
              join jo.entries e2 on e2.id = eb.entry_id where ea.entry_id = e.id and e2.category_id = c_new.id) then
    raise exception 'Atlet ini sudah terdaftar di kategori tujuan.';
  end if;
  update jo.entries set fee = case when e.team_only then 0 else c_new.fee end where id = e.id;
  update jo.entries set category_id = c_new.id, session_id = null, group_no = null, start_order = null,
    priangan_requested = c_new.jabar_only,
    priangan_status = case when not c_new.jabar_only then 'tidak' when c_old.jabar_only then priangan_status else 'menunggu' end,
    music_status = case when c_new.discipline = 'RG' and exists (select 1 from unnest(c_new.apparatus) x where coalesce(e.music->>x,'') = '')
                        then 'belum' else music_status end
   where id = e.id;
  perform jo.mark_aic(ea.athlete_id) from jo.entry_athletes ea where ea.entry_id = e.id;
  if not e.team_only and c_new.fee <> e.fee then perform jo.recalc_bill(s.id); end if;
  perform jo.log(st.id, 'pindah_kategori', 'entry', e.id::text,
    jsonb_build_object('from', c_old.name_id, 'to', c_new.name_id, 'reason', p_reason,
                       'old_fee', e.fee, 'new_fee', case when e.team_only then 0 else c_new.fee end));
  return public.console_submission(s.id);
end $$;

revoke all on function jo.need_reason(text) from public, anon, authenticated;
revoke all on function jo.recalc_bill(uuid) from public, anon, authenticated;
revoke all on function jo.mark_aic(uuid) from public, anon, authenticated;
revoke all on function jo.mark_aic_sub(uuid) from public, anon, authenticated;
revoke all on function public.console_update_contact(uuid, jsonb, text) from public, anon;
grant execute on function public.console_update_contact(uuid, jsonb, text) to authenticated;
revoke all on function public.console_change_club(uuid, uuid, text) from public, anon;
grant execute on function public.console_change_club(uuid, uuid, text) to authenticated;
revoke all on function public.console_add_entry(uuid, integer, uuid[], text) from public, anon;
grant execute on function public.console_add_entry(uuid, integer, uuid[], text) to authenticated;
revoke all on function public.console_remove_entry(uuid, text) from public, anon;
grant execute on function public.console_remove_entry(uuid, text) to authenticated;
revoke all on function public.console_add_athlete(uuid, jsonb, text) from public, anon;
grant execute on function public.console_add_athlete(uuid, jsonb, text) to authenticated;
revoke all on function public.console_team_save(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.console_team_save(uuid, uuid, text, text, text) to authenticated;
revoke all on function public.console_team_candidates(uuid) from public, anon;
grant execute on function public.console_team_candidates(uuid) to authenticated;
revoke all on function public.console_team_member(uuid, uuid, boolean, text) from public, anon;
grant execute on function public.console_team_member(uuid, uuid, boolean, text) to authenticated;
revoke all on function public.console_team_delete(uuid, text) from public, anon;
grant execute on function public.console_team_delete(uuid, text) to authenticated;
revoke all on function public.console_set_music(uuid, jsonb, text) from public, anon;
grant execute on function public.console_set_music(uuid, jsonb, text) to authenticated;
