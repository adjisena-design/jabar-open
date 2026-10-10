-- =====================================================================
--  Fungsi PUBLIK (dipanggil dari situs: pendaftaran, status, hasil)
--  Nama diawali public_ -> boleh dipanggil pengunjung (anon & authenticated)
-- =====================================================================

create or replace function public.public_config() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'event', jsonb_build_object(
      'name', jo.setting_text('event_name'),
      'year', jo.setting_int('event_year'),
      'venue', jo.setting('venue'),
      'contact_email', jo.setting_text('contact_email'),
      'instagram', jo.setting_text('instagram')),
    'registration', jsonb_build_object(
      'open', coalesce(jo.setting_bool('registration_open'), false)
              and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
      'deadline', jo.setting_text('registration_deadline'),
      'deadline_label', jo.setting_text('payment_deadline_label'),
      'max_athletes', coalesce(jo.setting_int('max_athletes'), 5),
      'priangan_fee', coalesce(jo.setting_int('priangan_fee'), 150000),
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
        'max_per_club', c.max_per_club, 'allow_priangan', c.allow_priangan) order by c.sort, c.id), '[]'::jsonb)
        from jo.categories c where c.active),
    'clubs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'kind', k.kind, 'kab_kota', k.kab_kota,
        'province', k.province, 'country', k.country) order by k.name), '[]'::jsonb)
        from jo.clubs k where k.merged_into is null)
  )
$$;

-- ---------------------------------------------------------------------
-- Pendaftaran
-- ---------------------------------------------------------------------
create or replace function public.public_register(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid       uuid := auth.uid();
  v_disc      jo.disciplines;
  v_type      text := p->>'registrant_type';
  v_contact   jsonb := coalesce(p->'contact', '{}'::jsonb);
  v_max       integer := coalesce(jo.setting_int('max_athletes'), 5);
  v_pri_fee   integer := coalesce(jo.setting_int('priangan_fee'), 150000);
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
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman lalu coba lagi.' using hint = 'ERR_SESSION';
  end if;

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

  if v_type not in ('individu','klub') then
    raise exception 'Pilih jenis pendaftar: perorangan atau klub/sekolah.' using hint = 'ERR_TYPE';
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

  -- Atlet
  v_n_ath := coalesce(jsonb_array_length(p->'athletes'), 0);
  if v_n_ath < 1 then
    raise exception 'Tambahkan minimal satu atlet.' using hint = 'ERR_NO_ATHLETE';
  end if;
  if v_type = 'individu' and v_n_ath > 1 then
    raise exception 'Pendaftaran perorangan hanya untuk satu atlet. Pilih klub/sekolah untuk mendaftarkan beberapa atlet.' using hint = 'ERR_INDIVIDU_MULTI';
  end if;
  if v_n_ath > v_max then
    raise exception 'Satu pendaftaran maksimal % atlet. Kirim sisanya sebagai pendaftaran terpisah.', v_max using hint = 'ERR_MAX_ATHLETES';
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
    if v_type = 'klub' then
      raise exception 'Pilih atau tambahkan klub/sekolah.' using hint = 'ERR_CLUB';
    end if;
    v_club_id := null;
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
     trim(v_contact->>'phone'), nullif(trim(coalesce(v_contact->>'role','')),''), v_club_id, 'qris',
     v_consents || jsonb_build_object('at', now()), v_lang, v_uid);

  -- Simpan atlet
  for a in select * from jsonb_array_elements(p->'athletes') loop
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
    if coalesce(a->>'id_doc_path','') = '' then
      raise exception 'Atlet %: unggah dokumen identitas (KTP / Akte Kelahiran / Ijazah / Paspor).', i using hint = 'ERR_ATHLETE_DOC';
    end if;
    if split_part(a->>'id_doc_path', '/', 1) <> v_uid::text
       or (coalesce(a->>'photo_path','') <> '' and split_part(a->>'photo_path', '/', 1) <> v_uid::text) then
      raise exception 'Berkas unggahan tidak valid. Unggah ulang dokumen.' using hint = 'ERR_UPLOAD';
    end if;
    if jo.is_minor((a->>'birth_date')::date) then
      v_any_minor := true;
      if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
         or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
         or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Atlet %: atlet di bawah 18 tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i using hint = 'ERR_GUARDIAN';
      end if;
    end if;

    insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
       id_doc_path, photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
    values (v_sub_id, trim(a->>'full_name'), a->>'gender', (a->>'birth_date')::date,
       coalesce(a->>'nationality','WNI'),
       case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
       nullif(trim(coalesce(a->>'province','')),''), nullif(trim(coalesce(a->>'kab_kota','')),''),
       a->>'id_doc_path', nullif(a->>'photo_path',''),
       nullif(trim(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
       nullif(lower(trim(coalesce(a->'guardian'->>'email',''))),''), nullif(trim(coalesce(a->'guardian'->>'relation','')),''),
       'T' || jo.rand_code(9), i)
    returning id into v_ath_id;
    -- simpan pemetaan kunci -> id di tabel sementara (jsonb)
    p := jsonb_set(p, '{_map}', coalesce(p->'_map','{}'::jsonb) || jsonb_build_object(k, v_ath_id));
  end loop;

  if v_any_minor and not coalesce((v_consents->>'guardian')::boolean, false) then
    raise exception 'Persetujuan orang tua/wali wajib dicentang untuk atlet di bawah 18 tahun.' using hint = 'ERR_CONSENT';
  end if;

  -- Entri (nomor lomba)
  if coalesce(jsonb_array_length(p->'entries'), 0) < 1 then
    raise exception 'Pilih kategori lomba untuk setiap atlet.' using hint = 'ERR_NO_ENTRY';
  end if;

  for e in select * from jsonb_array_elements(p->'entries') loop
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

    if coalesce((e->>'priangan')::boolean, false) then
      if not v_cat.allow_priangan then
        raise exception 'Kategori % tidak membuka penilaian Priangan.', v_cat.name_id using hint = 'ERR_PRIANGAN';
      end if;
      if not v_pri_ok then
        raise exception 'Kategori Priangan hanya untuk atlet WNI dengan alamat identitas di Jawa Barat dan klub di Jawa Barat (%).', v_cat.name_id using hint = 'ERR_PRIANGAN';
      end if;
    end if;

    insert into jo.entries (submission_id, category_id, fee, priangan_requested, priangan_fee, priangan_status)
    values (v_sub_id, v_cat.id, v_cat.fee,
            coalesce((e->>'priangan')::boolean, false),
            case when coalesce((e->>'priangan')::boolean, false) then v_pri_fee else 0 end,
            case when coalesce((e->>'priangan')::boolean, false) then 'menunggu' else 'tidak' end)
    returning id into v_entry_id;

    foreach k in array v_eath loop
      insert into jo.entry_athletes (entry_id, athlete_id, cert_code)
      values (v_entry_id, (p->'_map'->>k)::uuid, 'C' || jo.rand_code(9));
    end loop;

    v_base := v_base + v_cat.fee;
    if coalesce((e->>'priangan')::boolean, false) then v_pri := v_pri + v_pri_fee; end if;
  end loop;

  -- setiap atlet harus punya minimal satu nomor
  if exists (select 1 from jo.athletes a where a.submission_id = v_sub_id
              and not exists (select 1 from jo.entry_athletes ea where ea.athlete_id = a.id)) then
    raise exception 'Setiap atlet harus memilih minimal satu kategori.' using hint = 'ERR_NO_ENTRY';
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
     set code = v_code, base_amount = v_base, priangan_amount = v_pri, unique_code = v_uc, total_amount = v_total,
         payment_method = v_pm
   where id = v_sub_id;

  insert into jo.rate_events (uid, action) values (v_uid, 'register');
  perform jo.log(null, 'pendaftaran_baru', 'submission', v_sub_id::text,
    jsonb_build_object('code', v_code, 'athletes', v_n_ath, 'total', v_total));
  perform jo.queue_registration_email(v_sub_id);

  return jsonb_build_object(
    'code', v_code, 'token', v_token, 'status', 'menunggu_pembayaran', 'payment_method', v_pm,
    'base_amount', v_base, 'priangan_amount', v_pri, 'unique_code', v_uc, 'total_amount', v_total);
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
    'contact', jsonb_build_object('name', s.contact_name, 'email', s.contact_email, 'phone', s.contact_phone),
    'club', case when c.id is null then null else jsonb_build_object('name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) end,
    'payment_method', s.payment_method,
    'base_amount', s.base_amount, 'priangan_amount', s.priangan_amount,
    'unique_code', s.unique_code, 'total_amount', s.total_amount,
    'proof_uploaded_at', s.proof_uploaded_at, 'paid_at', s.paid_at,
    'verify_note', case when s.status = 'perlu_perbaikan' then s.verify_note end,
    'created_at', s.created_at,
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note'),
      'deadline_label', jo.setting_text('payment_deadline_label')),
    'signatories', jo.setting('signatories'),
    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'athlete_no', a.athlete_no, 'full_name', a.full_name, 'gender', a.gender,
        'birth_date', a.birth_date, 'nationality', a.nationality, 'province', a.province, 'kab_kota', a.kab_kota,
        'doc_status', a.doc_status,
        'ticket_code', case when s.status = 'lunas' then a.ticket_code end
      ) order by a.sort), '[]'::jsonb) from jo.athletes a where a.submission_id = s.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', en.id, 'category_id', cat.id, 'category_name_id', cat.name_id, 'category_name_en', cat.name_en,
        'level', cat.level, 'age_label', cat.age_label, 'apparatus', cat.apparatus,
        'fee', en.fee, 'priangan_requested', en.priangan_requested, 'priangan_status', en.priangan_status,
        'status', en.status,
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
      where en.submission_id = s.id and en.status <> 'dibatalkan')
  )
  from jo.disciplines d left join jo.clubs c on c.id = s.club_id
  where d.code = s.discipline
$$;

create or replace function public.public_get_submission(p_code text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare s jo.submissions;
begin
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan. Periksa kembali tautan dari email Anda.' using hint = 'ERR_NOT_FOUND';
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
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan.' using hint = 'ERR_NOT_FOUND';
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
        'athletes', jo.entry_athletes_json(en.id),
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
    'results', jo.category_results(c.id)
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
      'categories', (select jsonb_agg(cc.name_id) from jo.entry_athletes x join jo.entries e on e.id = x.entry_id
                     join jo.categories cc on cc.id = e.category_id where x.athlete_id = a.id and e.status <> 'dibatalkan'));
  end if;
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
      'rank', r->'rank', 'medal', r->'medal', 'total', r->'total',
      'priangan', r->'priangan', 'priangan_rank', r->'priangan_rank', 'priangan_medal', r->'priangan_medal');
  end if;
  return jsonb_build_object('type', null, 'valid', false);
end $$;

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
