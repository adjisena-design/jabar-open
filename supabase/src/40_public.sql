-- =====================================================================
--  Fungsi PUBLIK (dipanggil dari situs: pendaftaran, status, hasil)
--  Nama diawali public_ -> boleh dipanggil pengunjung (anon & authenticated)
-- =====================================================================

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
      'open', coalesce(jo.setting_bool('registration_open'), false)
              and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
      'deadline', jo.setting_text('registration_deadline'),
      'deadline_label', jo.setting_text('payment_deadline_label'),
      'max_athletes', coalesce(jo.setting_int('max_athletes'), 10),
      'form_version', 8,
      'priangan_fee', coalesce(jo.setting_int('priangan_fee'), 150000),
      'team_fee', coalesce(jo.setting_int('team_fee'), 650000),
      'team_max', coalesce(jo.setting_int('team_max'), 6),
      'team_counting', coalesce(jo.setting_int('team_counting'), 4),
      'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb),
      'qris_cap', coalesce(jo.setting_int('qris_cap'), 10000000)),
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

-- ---------------------------------------------------------------------
-- Pendaftaran
-- ---------------------------------------------------------------------
create or replace function jo.valid_drive_url(u text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(trim(u), '') ~* '^https://(drive|docs)\.google\.com/[^\s]+$'
$$;

-- ---------------------------------------------------------------------
-- v6: dokumen identitas atlet terpisah (Akte wajib; KTP & Ijazah bila ada;
--     WNA: paspor wajib; BPJS Ketenagakerjaan opsional saat daftar)
-- ---------------------------------------------------------------------
create or replace function jo.check_athlete_docs(a jsonb, p_label text, p_uid uuid) returns void
language plpgsql stable set search_path = '' as $$
declare k text;
begin
  if coalesce(a->>'nationality','WNI') = 'WNA' then
    if coalesce(a->>'passport_path','') = '' then
      raise exception '%: unggah paspor.', p_label using hint = 'ERR_ATHLETE_DOC';
    end if;
  elsif coalesce(a->>'akte_path','') = '' then
    raise exception '%: unggah Akte Kelahiran.', p_label using hint = 'ERR_ATHLETE_DOC';
  end if;
  if coalesce(a->>'photo_path','') = '' then
    raise exception '%: unggah pas foto (wajib untuk Athlete Identification Card).', p_label using hint = 'ERR_ATHLETE_PHOTO';
  end if;
  if coalesce(a->>'photo_thumb','') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(a->>'photo_thumb') > 150000 then
    raise exception '%: pas foto tidak terbaca. Unggah ulang pas foto (JPG atau PNG).', p_label using hint = 'ERR_ATHLETE_PHOTO';
  end if;
  foreach k in array array['akte_path','ktp_path','ijazah_path','passport_path','bpjs_path','photo_path'] loop
    if coalesce(a->>k,'') <> '' and split_part(a->>k, '/', 1) <> p_uid::text then
      raise exception 'Berkas unggahan tidak valid. Unggah ulang dokumen.' using hint = 'ERR_UPLOAD';
    end if;
  end loop;
end $$;

create or replace function jo.apparatus_label(p_disc text, p_code text) returns text
language sql stable set search_path = '' as $$
  select coalesce((select x->>'id' from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x
                    where d.code = p_disc and x->>'code' = p_code), p_code)
$$;

-- v6: pendaftaran QRIS tanpa bukti bayar dalam 15 menit dihapus otomatis
create or replace function jo.expire_unpaid() returns integer
language plpgsql volatile set search_path = '' as $$
declare r record; n integer := 0;
begin
  for r in select id, code, contact_name, discipline, total_amount from jo.submissions
            where payment_method = 'qris' and status = 'menunggu_pembayaran' and proof_path is null
              and created_at < now() - interval '15 minutes'
            for update skip locked loop
    perform jo.purge_submission(r.id);
    perform jo.log(null, 'pendaftaran_kedaluwarsa', 'submission', r.id::text,
      jsonb_build_object('code', r.code, 'contact', r.contact_name, 'discipline', r.discipline, 'total', r.total_amount,
                         'reason', 'Tidak ada bukti bayar dalam 15 menit'));
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

-- Hapus satu pendaftaran beserta atlet, entri, tim, nilai, dan riwayat musiknya.
-- Mengembalikan daftar berkas (bucket/path) agar konsol bisa menghapusnya dari penyimpanan.
create or replace function jo.purge_submission(p_id uuid) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_files jsonb;
begin
  select coalesce(jsonb_agg(distinct f), '[]'::jsonb) into v_files from (
    select jsonb_build_object('bucket', 'bukti', 'path', s.proof_path) f from jo.submissions s where s.id = p_id and s.proof_path is not null
    union all
    select jsonb_build_object('bucket', 'dokumen', 'path', x) from jo.athletes a
      cross join lateral unnest(array[a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path]) x
     where a.submission_id = p_id and x is not null
  ) z;
  delete from jo.score_log where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.scores where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.music_log where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.team_members where team_id in (select id from jo.teams where submission_id = p_id)
     or entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.teams where submission_id = p_id;
  delete from jo.entry_athletes where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.entries where submission_id = p_id;
  delete from jo.athletes where submission_id = p_id;
  update jo.mutations set submission_id = null, match_status = 'belum' where submission_id = p_id;
  delete from jo.submissions where id = p_id;
  return v_files;
end $$;

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
  v_pm        text := 'qris';
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

  if (select count(*) from jo.rate_events where uid = v_uid and action = 'register' and at > now() - interval '1 hour') >= 12 then
    raise exception 'Terlalu banyak pendaftaran dari perangkat ini dalam satu jam. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;

  -- Status pendaftaran
  if not coalesce(jo.setting_bool('registration_open'), false)
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
    raise exception 'Beregu hanya untuk Artistik Putri Level 1–6.' using hint = 'ERR_TEAM';
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
  if v_people > v_max then
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
      values (trim(p->'club'->'new'->>'name'),
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
  values (v_sub_id, v_code, v_token, v_disc.code, v_type, trim(v_contact->>'name'), lower(trim(v_contact->>'email')),
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
      v_pm := 'manual';
      if length(trim(coalesce(a->>'country',''))) < 2 then
        raise exception 'Atlet %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
      end if;
    end if;
    perform jo.check_athlete_docs(a, 'Atlet ' || i, v_uid);
    if jo.is_minor((a->>'birth_date')::date) then
      v_any_minor := true;
      if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
         or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
         or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Atlet %: atlet di bawah 18 tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i using hint = 'ERR_GUARDIAN';
      end if;
    end if;

    insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
       id_doc_path, akte_path, ktp_path, ijazah_path, passport_path, bpjs_path, photo_thumb,
       photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
    values (v_sub_id, trim(a->>'full_name'), a->>'gender', (a->>'birth_date')::date,
       coalesce(a->>'nationality','WNI'),
       case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
       nullif(trim(coalesce(a->>'province','')),''), nullif(trim(coalesce(a->>'kab_kota','')),''),
       coalesce(nullif(a->>'akte_path',''), nullif(a->>'passport_path','')),
       nullif(a->>'akte_path',''), nullif(a->>'ktp_path',''), nullif(a->>'ijazah_path',''), nullif(a->>'passport_path',''), nullif(a->>'bpjs_path',''), nullif(a->>'photo_thumb',''),
       nullif(a->>'photo_path',''),
       nullif(trim(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
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
      -- aturan jumlah nomor per atlet
      if v_disc.code in ('MAG','WAG','RG') then
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
      -- kelayakan Priangan: WNI, alamat identitas di Jawa Barat, dan klub di Jawa Barat
      if v_ath.nationality <> 'WNI' or coalesce(v_ath.province,'') <> 'Jawa Barat'
         or (v_club_id is not null and coalesce(v_club.province,'') <> 'Jawa Barat') then
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
      raise exception '% khusus atlet WNI dengan alamat identitas di Jawa Barat dan klub di Jawa Barat.', v_cat.name_id using hint = 'ERR_PRIANGAN';
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
    v_tname := regexp_replace(trim(coalesce(v_team->>'name','')), '\s+', ' ', 'g');
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
      v_mname := trim(coalesce(a->>'full_name',''));
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
          v_pm := 'manual';
          if length(trim(coalesce(a->>'country',''))) < 2 then
            raise exception 'Anggota %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
          end if;
        end if;
        perform jo.check_athlete_docs(a, 'Anggota ' || i, v_uid);
        v_sortn := v_sortn + 1;
        if jo.is_minor(v_mbirth) then
          v_any_minor := true;
          if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
             or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
             or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
            raise exception 'Anggota %: pesenam di bawah 18 tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i using hint = 'ERR_GUARDIAN';
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
           nullif(trim(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
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
    raise exception 'Persetujuan orang tua/wali wajib dicentang untuk atlet di bawah 18 tahun.' using hint = 'ERR_CONSENT';
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
  perform jo.queue_registration_email(v_sub_id);

  return jsonb_build_object(
    'code', v_code, 'token', v_token, 'status', 'menunggu_pembayaran', 'payment_method', v_pm,
    'base_amount', v_base, 'team_amount', v_team_amt, 'priangan_amount', v_pri, 'unique_code', v_uc, 'total_amount', v_total,
    'expires_at', case when v_pm = 'qris' then now() + interval '15 minutes' end);
end $$;

-- ---------------------------------------------------------------------
-- Beregu: periksa anggota "juga perorangan" sebelum mengirim
-- ---------------------------------------------------------------------
create or replace function public.public_team_check(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_club uuid; m jsonb; i integer := 0; out jsonb := '[]'::jsonb; v_found boolean; v_in_team boolean; v_e uuid;
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'team_check' and at > now() - interval '1 hour') >= 60 then
    raise exception 'Terlalu banyak pemeriksaan. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'team_check');
  v_club := nullif(p->>'club_id','')::uuid;
  if v_club is not null then
    select coalesce(merged_into, id) into v_club from jo.clubs where id = v_club;
  end if;
  for m in select * from jsonb_array_elements(coalesce(p->'members','[]'::jsonb)) loop
    i := i + 1;
    v_e := null;
    if v_club is not null and coalesce(m->>'birth_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
      select en.id into v_e
        from jo.athletes at2
        join jo.entry_athletes ea on ea.athlete_id = at2.id
        join jo.entries en on en.id = ea.entry_id
        join jo.categories c on c.id = en.category_id
        join jo.submissions s on s.id = en.submission_id
       where c.discipline = p->>'discipline' and c.level = p->>'level' and not en.team_only
         and en.status <> 'dibatalkan' and s.status <> 'dibatalkan' and s.club_id = v_club
         and at2.birth_date = (m->>'birth_date')::date and jo.norm_name(at2.full_name) = jo.norm_name(m->>'full_name')
       order by en.created_at limit 1;
    end if;
    v_found := v_e is not null;
    v_in_team := v_found and exists (select 1 from jo.team_members tm join jo.teams t2 on t2.id = tm.team_id
                   join jo.submissions s2 on s2.id = t2.submission_id where tm.entry_id = v_e and s2.status <> 'dibatalkan');
    out := out || jsonb_build_object('i', i, 'found', v_found, 'in_team', v_in_team);
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- Halaman status (akses dengan kode + token dari email)
-- ---------------------------------------------------------------------
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
                       then s.created_at + interval '15 minutes' end,
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

create or replace function public.public_get_submission(p_code text, p_token text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions;
begin
  perform jo.expire_unpaid();
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan. Periksa tautan dari email Anda. Pendaftaran yang tidak mengunggah bukti bayar dalam 15 menit dihapus otomatis; silakan daftar ulang.' using hint = 'ERR_NOT_FOUND';
  end if;
  return jo.submission_public_json(s);
end $$;

create or replace function public.public_attach_proof(p_code text, p_token text, p_path text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  -- sengaja tidak memanggil expire_unpaid di sini: bukti yang tiba tepat di menit ke-15 tetap diterima
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan atau sudah kedaluwarsa (bukti bayar tidak diunggah dalam 15 menit). Silakan daftar ulang.' using hint = 'ERR_NOT_FOUND';
  end if;
  if s.status not in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan') then
    raise exception 'Pendaftaran ini sudah tidak menunggu pembayaran.' using hint = 'ERR_STATUS';
  end if;
  if split_part(coalesce(p_path,''), '/', 1) <> v_uid::text then
    raise exception 'Berkas unggahan tidak valid. Unggah ulang.' using hint = 'ERR_UPLOAD';
  end if;
  update jo.submissions
     set proof_path = p_path, proof_uploaded_at = now(), status = 'menunggu_verifikasi'
   where id = s.id;
  perform jo.log(null, 'bukti_bayar_diunggah', 'submission', s.id::text, jsonb_build_object('code', s.code));
  select * into s from jo.submissions where id = s.id;
  return jo.submission_public_json(s);
end $$;

create or replace function public.public_resend_link(p_code text, p_email text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; v_uid uuid := auth.uid();
begin
  if (select count(*) from jo.rate_events where action = 'resend' and (uid = v_uid or v_uid is null)
        and at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('ok', true);
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'resend');
  select * into s from jo.submissions
   where code = upper(trim(p_code)) and lower(contact_email) = lower(trim(p_email));
  if s.id is not null
     and not exists (select 1 from jo.outbox o where o.submission_id = s.id and o.kind = 'tautan'
                      and o.created_at > now() - interval '10 minutes') then
    perform jo.queue_link_email(s.id);
  end if;
  -- jawaban selalu sama agar tidak bisa dipakai menebak data
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Statistik, daftar start, hasil, medali, verifikasi QR
-- ---------------------------------------------------------------------
create or replace function public.public_stats() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status <> 'dibatalkan'),
    'athletes_paid', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status = 'lunas'),
    'clubs', (select count(distinct s.club_id) from jo.submissions s where s.status <> 'dibatalkan' and s.club_id is not null),
    'regions', (select count(distinct coalesce(c.kab_kota, a.kab_kota, a.country))
                  from jo.athletes a join jo.submissions s on s.id = a.submission_id
                  left join jo.clubs c on c.id = s.club_id where s.status <> 'dibatalkan'),
    'by_discipline', (select coalesce(jsonb_object_agg(d.code, (
        select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
         where s.status <> 'dibatalkan' and s.discipline = d.code)), '{}'::jsonb) from jo.disciplines d)
  )
$$;

create or replace function public.public_startlist(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category_id', c.id, 'discipline', c.discipline, 'name_id', c.name_id, 'name_en', c.name_en, 'level', c.level,
    'age_label', c.age_label, 'apparatus', c.apparatus, 'exhibition', c.exhibition,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'start_order', en.start_order, 'group_no', en.group_no,
        'session', ses.name, 'day', ses.day, 'start_time', ses.start_time,
        'athletes', jo.entry_athletes_json(en.id), 'team_only', en.team_only,
        'club', jo.entry_club_label(en.id), 'region', jo.entry_region(en.id))
        order by ses.sort nulls last, ses.day nulls last, ses.start_time nulls last, en.group_no nulls last, en.start_order nulls last), '[]'::jsonb)
      from jo.entries en join jo.submissions s on s.id = en.submission_id
      left join jo.sessions ses on ses.id = en.session_id
      where en.category_id = c.id and en.status = 'aktif' and s.status = 'lunas')
  ) order by c.sort, c.id), '[]'::jsonb)
  from jo.categories c
  where c.startlist_published and c.active and (p_discipline is null or c.discipline = p_discipline)
$$;

create or replace function public.public_results(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category_id', c.id, 'discipline', c.discipline, 'name_id', c.name_id, 'name_en', c.name_en,
    'level', c.level, 'age_label', c.age_label, 'apparatus', c.apparatus,
    'exhibition', c.exhibition, 'published_at', c.results_published_at,
    'results', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(jo.category_results(c.id)) x
                 where not coalesce((x->>'team_only')::boolean, false))
  ) order by c.sort, c.id), '[]'::jsonb)
  from jo.categories c
  where c.results_published and c.active and (p_discipline is null or c.discipline = p_discipline)
$$;

create or replace function public.public_medal_table(p_priangan boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jo.medal_table(coalesce(p_priangan, false), true)
$$;

create or replace function public.public_verify(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v text := upper(trim(coalesce(p_code,''))); a jo.athletes; s jo.submissions; ea jo.entry_athletes;
        en jo.entries; c jo.categories; r jsonb; club text;
begin
  select * into a from jo.athletes where ticket_code = v;
  if a.id is not null then
    select * into s from jo.submissions where id = a.submission_id;
    select coalesce(k.name, 'Perorangan') into club from jo.submissions x left join jo.clubs k on k.id = x.club_id where x.id = s.id;
    return jsonb_build_object('type', 'ticket', 'valid', s.status = 'lunas', 'status', s.status,
      'athlete_no', a.athlete_no, 'name', a.full_name, 'club', club, 'discipline', s.discipline,
      'photo', case when s.status = 'lunas' then a.photo_thumb end,
      'registered_by', case when s.status = 'lunas' then s.contact_name || coalesce(' (' || case s.contact_role
          when 'pemilik' then 'pemilik klub' when 'admin' then 'admin klub' when 'pelatih' then 'pelatih'
          when 'manajer' then 'manajer/official' end || ')', '') end,
      'categories', (select jsonb_agg(cc.name_id) from jo.entry_athletes x join jo.entries e on e.id = x.entry_id
                     join jo.categories cc on cc.id = e.category_id where x.athlete_id = a.id and e.status <> 'dibatalkan'));
  end if;
  -- sertifikat juara beregu
  declare tm jo.team_members; tt jo.teams; ts jo.submissions; tr jsonb; tpub boolean;
  begin
    select * into tm from jo.team_members where cert_code = v;
    if tm.team_id is not null then
      select * into tt from jo.teams where id = tm.team_id;
      select * into ts from jo.submissions where id = tt.submission_id;
      select coalesce(published, false) into tpub from jo.team_levels where discipline = tt.discipline and level = tt.level;
      if not coalesce(tpub, false) or ts.status <> 'lunas' then
        return jsonb_build_object('type', 'team_certificate', 'valid', false);
      end if;
      select x into tr from jsonb_array_elements(jo.team_results(tt.discipline, tt.level, false)) x where x->>'team_id' = tt.id::text;
      select * into a from jo.athletes where id = tm.athlete_id;
      return jsonb_build_object('type', 'team_certificate', 'valid', coalesce((tr->>'trophy')::boolean, false),
        'name', a.full_name, 'athlete_no', a.athlete_no, 'team', tt.name, 'club', tr->>'club',
        'discipline', tt.discipline, 'level', tt.level, 'rank', tr->'rank', 'total', tr->'total');
    end if;
  end;
  -- sertifikat medali per alat: <kode sertifikat>-<alat>, mis. CABC123XYZ-VT
  declare v_app text;
  begin
    if v ~ '^[A-Z0-9]+-[A-Z]+$' then
      v_app := split_part(v, '-', 2);
      select * into ea from jo.entry_athletes where cert_code = split_part(v, '-', 1);
      if ea.entry_id is not null then
        select * into en from jo.entries where id = ea.entry_id;
        select * into c from jo.categories where id = en.category_id;
        select * into a from jo.athletes where id = ea.athlete_id;
        select * into s from jo.submissions where id = en.submission_id;
        select x into r from jsonb_array_elements(jo.category_results(c.id)) x where x->>'entry_id' = en.id::text;
        if not c.results_published or s.status <> 'lunas' or (r->'app_medals'->>v_app) is null then
          return jsonb_build_object('type', 'apparatus_certificate', 'valid', false);
        end if;
        return jsonb_build_object('type', 'apparatus_certificate', 'valid', true,
          'name', a.full_name, 'athlete_no', a.athlete_no, 'club', r->>'club', 'region', r->>'region',
          'category_name_id', c.name_id, 'category_name_en', c.name_en, 'discipline', c.discipline,
          'apparatus', v_app,
          'apparatus_name_id', (select x->>'id' from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x where d.code = c.discipline and x->>'code' = v_app),
          'apparatus_name_en', (select x->>'en' from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x where d.code = c.discipline and x->>'code' = v_app),
          'medal', r->'app_medals'->>v_app, 'score', r->'scores'->v_app);
      end if;
    end if;
  end;
  select * into ea from jo.entry_athletes where cert_code = v;
  if ea.entry_id is not null then
    select * into en from jo.entries where id = ea.entry_id;
    select * into c from jo.categories where id = en.category_id;
    select * into a from jo.athletes where id = ea.athlete_id;
    select * into s from jo.submissions where id = en.submission_id;
    if not c.results_published or s.status <> 'lunas' then
      return jsonb_build_object('type', 'certificate', 'valid', false);
    end if;
    select x into r from jsonb_array_elements(jo.category_results(c.id)) x where x->>'entry_id' = en.id::text;
    return jsonb_build_object('type', 'certificate', 'valid', true,
      'name', a.full_name, 'athlete_no', a.athlete_no, 'club', r->>'club', 'region', r->>'region',
      'category_id', c.id, 'category_name_id', c.name_id, 'category_name_en', c.name_en, 'discipline', c.discipline,
      'rank', r->'rank', 'award_rank', r->'award_rank', 'medal', r->'medal', 'mini', r->'mini', 'total', r->'total',
      'priangan', r->'priangan', 'priangan_rank', r->'priangan_rank', 'priangan_medal', r->'priangan_medal');
  end if;
  return jsonb_build_object('type', null, 'valid', false);
end $$;


-- ---------------------------------------------------------------------
-- Musik Ritmik: lihat & ganti tautan (kode pendaftaran + email)
-- ---------------------------------------------------------------------
create or replace function jo.music_json(s jo.submissions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code', s.code, 'contact_name', s.contact_name, 'status', s.status,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'athlete_name', a.full_name, 'athlete_no', a.athlete_no,
        'category_name_id', c.name_id, 'category_name_en', c.name_en, 'apparatus', c.apparatus,
        'music', e.music, 'music_status', e.music_status, 'music_note', e.music_note,
        'music_changes', e.music_changes, 'music_updated_at', e.music_updated_at,
        'startlist_published', c.startlist_published,
        'complete', (select bool_and(coalesce(e.music->>x, '') <> '') from unnest(c.apparatus) x),
        'can_fill', not c.scores_locked and exists (select 1 from unnest(c.apparatus) x where coalesce(e.music->>x, '') = ''),
        'can_fix', e.music_status = 'tidak_bisa' and not c.scores_locked,
        'can_change', e.music_status <> 'tidak_bisa' and e.music_changes < 1 and not c.startlist_published
      ) order by a.sort), '[]'::jsonb)
      from jo.entries e join jo.categories c on c.id = e.category_id
      join jo.entry_athletes ea on ea.entry_id = e.id join jo.athletes a on a.id = ea.athlete_id
      where e.submission_id = s.id and e.status <> 'dibatalkan' and c.discipline = 'RG')
  )
$$;

create or replace function jo.music_auth(p_code text, p_email text) returns jo.submissions
language plpgsql volatile set search_path = '' as $$
declare v_uid uuid := auth.uid(); s jo.submissions;
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'music' and at > now() - interval '1 hour') >= 30 then
    raise exception 'Terlalu banyak percobaan. Coba lagi dalam satu jam.' using hint = 'ERR_RATE';
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'music');
  select * into s from jo.submissions
   where code = upper(trim(coalesce(p_code,''))) and lower(contact_email) = lower(trim(coalesce(p_email,'')))
     and discipline = 'RG' and status <> 'dibatalkan';
  if s.id is null then
    raise exception 'Kode pendaftaran Ritmik dan email penanggung jawab tidak cocok.' using hint = 'ERR_NOT_FOUND';
  end if;
  return s;
end $$;

create or replace function public.public_music_lookup(p_code text, p_email text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions;
begin
  s := jo.music_auth(p_code, p_email);
  return jo.music_json(s);
end $$;

drop function if exists public.public_music_set(text, text, uuid, text);
-- v6: tautan per nomor (alat). Mengganti tautan yang sudah ada = satu kesempatan ganti per atlet
-- (boleh beberapa nomor sekaligus). Mengisi nomor yang kosong atau memperbaiki tautan "tidak bisa dibuka" tidak memakai jatah.
create or replace function public.public_music_set(p_code text, p_email text, p_entry uuid, p_music jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; e jo.entries; c jo.categories; k text; v_url text; v_old text;
        v_new jsonb; v_replaced integer := 0; v_changed integer := 0; v_action text;
begin
  s := jo.music_auth(p_code, p_email);
  select * into e from jo.entries where id = p_entry and submission_id = s.id and status <> 'dibatalkan' for update;
  if e.id is null then raise exception 'Atlet tidak ditemukan di pendaftaran ini.' using hint = 'ERR_NOT_FOUND'; end if;
  select * into c from jo.categories where id = e.category_id;
  if c.discipline <> 'RG' then raise exception 'Tautan musik hanya untuk Ritmik.'; end if;
  if c.scores_locked then
    raise exception 'Nilai kategori ini sudah dikunci; musik tidak bisa diubah lagi.' using hint = 'ERR_MUSIC_CLOSED';
  end if;
  v_new := e.music;
  foreach k in array c.apparatus loop
    v_url := trim(coalesce(p_music->>k, ''));
    v_old := nullif(e.music->>k, '');
    if v_url = '' then
      if v_old is null then
        raise exception 'Isi tautan musik %.', jo.apparatus_label('RG', k) using hint = 'ERR_MUSIC';
      end if;
      continue;
    end if;
    if not jo.valid_drive_url(v_url) then
      raise exception 'Tautan % harus dari Google Drive (diawali https://drive.google.com/).', jo.apparatus_label('RG', k) using hint = 'ERR_MUSIC';
    end if;
    if v_old is distinct from v_url then
      v_changed := v_changed + 1;
      if v_old is not null then v_replaced := v_replaced + 1; end if;
      v_new := v_new || jsonb_build_object(k, v_url);
    end if;
  end loop;
  if v_changed = 0 then raise exception 'Tidak ada tautan yang berubah.' using hint = 'ERR_MUSIC'; end if;
  if e.music_status = 'tidak_bisa' then
    v_action := 'perbaiki';
  elsif v_replaced > 0 then
    v_action := 'ganti';
    if c.startlist_published then
      raise exception 'Batas ganti musik sudah lewat: start list kategori ini sudah terbit. Hubungi narahubung Ritmik.' using hint = 'ERR_MUSIC_CLOSED';
    end if;
    if e.music_changes >= 1 then
      raise exception 'Musik atlet ini sudah pernah diganti. Kesempatan ganti hanya satu kali.' using hint = 'ERR_MUSIC_USED';
    end if;
  else
    v_action := 'isi';
  end if;
  update jo.entries set music = v_new, music_status = 'menunggu', music_note = null, music_updated_at = now(),
    music_changes = music_changes + case when v_action = 'ganti' then 1 else 0 end,
    music_checked_by = null, music_checked_at = null
   where id = e.id;
  insert into jo.music_log (entry_id, action, apparatus, old_url, new_url)
  select e.id, v_action, x.key, e.music->>x.key, x.value from jsonb_each_text(v_new) x
   where (e.music->>x.key) is distinct from x.value;
  perform jo.log(null, 'musik_' || v_action, 'entry', e.id::text, jsonb_build_object('code', s.code, 'old', e.music, 'new', v_new));
  perform jo.queue_music_email(e.id, 'musik_diterima');
  return jo.music_json(s);
end $$;

-- ---------------------------------------------------------------------
-- Hasil beregu yang sudah dipublikasikan
-- ---------------------------------------------------------------------
create or replace function public.public_team_results(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'discipline', tl.discipline, 'level', tl.level, 'published_at', tl.published_at,
    'results', jo.team_results(tl.discipline, tl.level, false)
  ) order by tl.discipline, (select min(c.sort) from jo.categories c where c.discipline = tl.discipline and c.level = tl.level)), '[]'::jsonb)
  from jo.team_levels tl
  where tl.published and (p_discipline is null or tl.discipline = p_discipline)
$$;

-- ---------------------------------------------------------------------
-- Antrean email untuk Google Apps Script (diamankan dengan secret)
-- ---------------------------------------------------------------------
create or replace function public.outbox_claim(p_secret text, p_limit integer default 20) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r jsonb;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  insert into jo.settings (key, value) values ('outbox_last_poll', to_jsonb(now()))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform jo.expire_unpaid();
  with picked as (
    select id from jo.outbox
     where (status = 'pending')
        or (status = 'sending' and claimed_at < now() - interval '10 minutes')
        or (status = 'error' and attempts < 5 and claimed_at < now() - interval '15 minutes')
     order by id limit greatest(1, least(coalesce(p_limit, 20), 50))
     for update skip locked
  ), upd as (
    update jo.outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
      from picked where o.id = picked.id
    returning o.id, o.to_email, o.cc, o.subject, o.html
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'to', to_email, 'cc', cc, 'subject', subject, 'html', html) order by id), '[]'::jsonb)
    into r from upd;
  return r;
end $$;

create or replace function public.outbox_report(p_secret text, p_results jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; n integer := 0;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if coalesce((x->>'ok')::boolean, false) then
      update jo.outbox set status = 'sent', sent_at = now(), last_error = null where id = (x->>'id')::bigint;
    elsif coalesce((x->>'release')::boolean, false) then
      -- belum dicoba (mis. kuota harian Gmail habis): kembalikan ke antrean tanpa menambah percobaan
      update jo.outbox set status = 'pending', attempts = greatest(attempts - 1, 0), last_error = left(coalesce(x->>'error',''), 500)
       where id = (x->>'id')::bigint;
    else
      update jo.outbox set status = 'error', last_error = left(coalesce(x->>'error','tidak diketahui'), 500)
       where id = (x->>'id')::bigint;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('updated', n);
end $$;
