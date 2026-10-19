-- =====================================================================
--  Penyesuaian data untuk instalasi yang sudah berjalan (aman diulang)
-- =====================================================================
-- v3: email kontak resmi pindah ke jabaropen2026@gmail.com, PM tetap tercantum
update jo.settings set value = '"jabaropen2026@gmail.com"'::jsonb, updated_at = now()
 where key = 'contact_email' and value = '"adjisena.daffa@gmail.com"'::jsonb;

-- v4 (14/10/2026): lampiran Medali & Piala Artistik — sekali jalan (ditandai di settings)
do $$
begin
  if not exists (select 1 from jo.settings where key = 'migrasi_v4_medali') then
    -- kelompok usia WAG Level 4–6
    update jo.categories set age_label = '10 tahun ke bawah', name_id = 'Artistik Putri Level 4 (10 tahun ke bawah)', name_en = 'Women''s Artistic Level 4 (10 & under)', birth_year_min = 2016, birth_year_max = null where code = 'WAG-L4-A';
    update jo.categories set age_label = '11 tahun ke atas', name_id = 'Artistik Putri Level 4 (11 tahun ke atas)', name_en = 'Women''s Artistic Level 4 (11 & over)', birth_year_min = null, birth_year_max = 2015 where code = 'WAG-L4-B';
    update jo.categories set age_label = '11 tahun ke bawah', name_id = 'Artistik Putri Level ' || substr(code, 6, 1) || ' (11 tahun ke bawah)', name_en = 'Women''s Artistic Level ' || substr(code, 6, 1) || ' (11 & under)', birth_year_min = 2015, birth_year_max = null where code in ('WAG-L5-A','WAG-L6-A');
    update jo.categories set age_label = '12 tahun ke atas', name_id = 'Artistik Putri Level ' || substr(code, 6, 1) || ' (12 tahun ke atas)', name_en = 'Women''s Artistic Level ' || substr(code, 6, 1) || ' (12 & over)', birth_year_min = null, birth_year_max = 2014 where code in ('WAG-L5-B','WAG-L6-B');
    -- aturan penghargaan
    update jo.categories set medal_rule = '{"type":"rank","places":3,"aa_places":6}'::jsonb where discipline in ('MAG','WAG');
    update jo.categories set medal_rule = medal_rule || '{"apparatus_medals":true}'::jsonb
     where code in ('WAG-L4-A','WAG-L4-B','WAG-L5-A','WAG-L5-B','WAG-L6-A','WAG-L6-B','WAG-PJ','WAG-JR','MAG-JR');
    update jo.categories set medal_rule = medal_rule || '{"club_cap":2}'::jsonb
     where code in ('WAG-L4-A','WAG-L4-B','WAG-L5-A','WAG-L5-B','WAG-L6-A','WAG-L6-B','WAG-PJ','WAG-JR');
    -- tanda tangan Ketua GI Jawa Barat
    update jo.settings set value = (
      select jsonb_agg(case when x->>'name' ilike 'Dika%' and not (x ? 'sig') then x || '{"sig":"assets/img/ttd/dika.png"}'::jsonb else x end)
        from jsonb_array_elements(value) x), updated_at = now()
     where key = 'signatories' and jsonb_typeof(value) = 'array';
    insert into jo.settings (key, value) values ('team_levels', '{"WAG":["Level 1","Level 2","Level 3","Level 4","Level 5","Level 6"]}'::jsonb)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    insert into jo.settings (key, value) values ('migrasi_v4_medali', to_jsonb(now()));
  end if;
end $$;

-- v5 (14/10/2026): daftar 53 klub senam Indonesia untuk pilihan di formulir pendaftaran — sekali jalan
do $$
begin
  if not exists (select 1 from jo.settings where key = 'migrasi_v5_klub') then
    insert into jo.clubs (name, kind, kab_kota, province, country, verified, created_via, note)
    select v.name, v.kind, v.kab, v.prov, 'Indonesia', true, 'daftar_awal', v.note
      from (values
      ('Jakritmik', 'klub', null, 'DKI Jakarta', 'Rhythmic Gymnastics (RG) · Lokasi: DKI Jakarta'),
      ('Arena Gymnastic', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Milicent', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Idola Gymnastic Lampung', 'klub', null, 'Lampung', 'Rhythmic Gymnastics (RG) · Lokasi: Lampung'),
      ('Poza', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('She RG', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Solo RG', 'klub', 'Kota Surakarta', 'Jawa Tengah', 'Rhythmic Gymnastics (RG) · Lokasi: Surakarta (Jawa Tengah)'),
      ('Persani Surakarta', 'pengkab', 'Kota Surakarta', 'Jawa Tengah', 'Rhythmic, Artistic, Aerobic · Lokasi: Surakarta (Jawa Tengah)'),
      ('Fahmi Gymnastic', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Citra Indra', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Wimilia Gym', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat / Semarang'),
      ('Dyra Gym', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Rozora', 'klub', 'Kota Denpasar', 'Bali', 'Rhythmic Gymnastics (RG) · Lokasi: Denpasar (Bali)'),
      ('Flexa Gym', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Monalisa Gymnastic', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Blitz Gym', 'klub', null, 'Jawa Barat', 'Rhythmic Gymnastics (RG) · Lokasi: Jawa Barat'),
      ('Gavrila Gymnastics Club', 'klub', null, 'DKI Jakarta', 'Men''s & Women''s Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta (Mampang / Kelapa Gading)'),
      ('Fast Gym Artistic Gymnastics Club', 'klub', 'Kota Jakarta Selatan', 'DKI Jakarta', 'Men''s & Women''s Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta (Jaksel)'),
      ('Circle Gymnastics Club', 'klub', null, 'DKI Jakarta', 'Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta'),
      ('Sky Gymnastics Club', 'klub', null, 'DKI Jakarta', 'Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta'),
      ('Jonathan''s Gymnastics Club', 'klub', null, 'DKI Jakarta', 'Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta'),
      ('Roland Gymnastics Club', 'klub', null, 'DKI Jakarta', 'Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta'),
      ('Dian Gymnastics', 'klub', null, 'DKI Jakarta', 'Artistic Gymnastics (MAG/WAG) · Lokasi: DKI Jakarta'),
      ('Nika Gymnastics Club', 'klub', null, null, 'Artistic Gymnastics (MAG/WAG) & Foundations · Lokasi: Jabodetabek'),
      ('Kanika Gymnastics Club', 'klub', null, null, 'Artistic Gymnastics (MAG/WAG) · Lokasi: Bintaro / Bojongsari'),
      ('Phoenix Gym Academy', 'klub', 'Kota Depok', 'Jawa Barat', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Depok'),
      ('Tangerang Gymnastics Club (TGC)', 'klub', null, 'Banten', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Tangerang (Banten)'),
      ('Cirebon Gymnastics Club', 'klub', null, 'Jawa Barat', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Cirebon (Jawa Barat)'),
      ('Zasis Gymnastics Club', 'klub', 'Kota Surabaya', 'Jawa Timur', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Surabaya & Sidoarjo'),
      ('Jenggirat Tangi', 'klub', 'Kabupaten Banyuwangi', 'Jawa Timur', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Banyuwangi (Jawa Timur)'),
      ('A.Q. Gymnastic Club', 'klub', 'Kota Medan', 'Sumatera Utara', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Medan (Sumatra Utara)'),
      ('Wan-Jun Gymnastics Club', 'klub', 'Kota Medan', 'Sumatera Utara', 'Artistic Gymnastics & Rhythmic · Lokasi: Medan (Sumatra Utara)'),
      ('Galaxy Reborn Gymnastics Club', 'klub', 'Kota Denpasar', 'Bali', 'Artistic Gymnastics (MAG/WAG) · Lokasi: Denpasar (Bali)'),
      ('UNJ Gymnastics Club (Universitas Negeri Jakarta)', 'klub', null, 'DKI Jakarta', 'Aerobic Gymnastics (AER), Artistic, Rhythmic · Lokasi: DKI Jakarta'),
      ('FPOK UPI Gymnastics', 'klub', 'Kota Bandung', 'Jawa Barat', 'Aerobic Gymnastics (AER), Artistic, Rhythmic · Lokasi: Bandung (Jawa Barat)'),
      ('UNESA Gymnastics Club (Universitas Negeri Surabaya)', 'klub', 'Kota Surabaya', 'Jawa Timur', 'Aerobic Gymnastics (AER), Artistic · Lokasi: Surabaya (Jawa Timur)'),
      ('FIK UNNES Gymnastics', 'klub', 'Kota Semarang', 'Jawa Tengah', 'Aerobic Gymnastics (AER) & Rhythmic · Lokasi: Semarang (Jawa Tengah)'),
      ('UNY Gymnastics Club (Universitas Negeri Yogyakarta)', 'klub', null, 'DI Yogyakarta', 'Aerobic Gymnastics (AER) & Artistic · Lokasi: Yogyakarta (DIY)'),
      ('Studio 8 Aerobic Gymnastics', 'klub', null, 'Jawa Timur', 'Competitive Aerobic Gymnastics (AER) · Lokasi: Malang (Jawa Timur)'),
      ('Klub Senam Udanawu', 'klub', 'Kabupaten Blitar', 'Jawa Timur', 'Competitive Aerobic Gymnastics (AER) · Lokasi: Blitar (Jawa Timur)'),
      ('Persani Jambi (Puslatda)', 'klub', null, 'Jambi', 'Strong focus on Aerobic Gymnastics (AER) · Lokasi: Jambi (Sumatra)'),
      ('Persani Riau (Puslatda)', 'klub', 'Kota Pekanbaru', 'Riau', 'Aerobic Gymnastics (AER) & Artistic · Lokasi: Pekanbaru (Riau)'),
      ('Sanggar Senam Studio 5', 'klub', null, 'DKI Jakarta', 'Aerobic Gymnastics (AER) · Lokasi: DKI Jakarta'),
      ('Puslatcab Persani Gresik', 'pengkab', 'Kabupaten Gresik', 'Jawa Timur', 'Aerobic Gymnastics (AER) & Artistic · Lokasi: Gresik (Jawa Timur)'),
      ('Bazgym Indonesia', 'klub', 'Kota Jakarta Selatan', 'DKI Jakarta', 'General Gymnastics & Foundations · Lokasi: DKI Jakarta (Jaksel)'),
      ('Hom Kids Academy', 'klub', null, null, 'General Gymnastics for Kids · Lokasi: Jabodetabek'),
      ('The Funtastic Gym Indonesia', 'klub', null, 'DKI Jakarta', 'General Gymnastics for Kids · Lokasi: DKI Jakarta'),
      ('Club Serenia Gymnastics', 'klub', null, 'DKI Jakarta', 'General / Lifestyle Gymnastics · Lokasi: DKI Jakarta'),
      ('Ninos BSJ Gymnastics Club', 'klub', null, 'DKI Jakarta', 'General Gymnastics (Student Community) · Lokasi: DKI Jakarta'),
      ('STARLA Kids Gymnastics', 'klub', 'Kota Bandung', 'Jawa Barat', 'Toddler & Special Needs Gymnastics · Lokasi: Bandung (Jawa Barat)'),
      ('Kidsville Gymschool', 'klub', 'Kota Bandung', 'Jawa Barat', 'Early Childhood Gymnastics · Lokasi: Bandung (Jawa Barat)'),
      ('Baby Bright Gymnastics', 'klub', 'Kota Surabaya', 'Jawa Timur', 'Early Childhood Gymnastics · Lokasi: Surabaya (Jatim)'),
      ('Rockstar Academy (Gymnastics Div.)', 'klub', null, null, 'General Gymnastics & Trampoline · Lokasi: Jabodetabek & Bali')
      ) as v(name, kind, kab, prov, note)
     where not exists (select 1 from jo.clubs k where lower(k.name) = lower(v.name) and k.merged_into is null);
    insert into jo.settings (key, value) values ('migrasi_v5_klub', to_jsonb(now()));
  end if;
end $$;

-- v6 (14/10/2026, revisi PDF): Priangan hanya Ritmik sebagai kategori tersendiri, Junior Ritmik 13–15 tahun,
--     musik per nomor, urutan kategori — sekali jalan
do $$
begin
  if not exists (select 1 from jo.settings where key = 'migrasi_v6_revisi') then
    update jo.categories set allow_priangan = false;
    update jo.categories set jabar_only = (code like 'RG-C-%');
    update jo.categories set birth_year_min = 2011, birth_year_max = 2013, age_label = 'Kelahiran 2011–2013'
     where code in ('RG-A-JR','RG-B-JR','RG-C-JR');
    update jo.categories c set sort = v.sort from (values
      ('MAG-L1-A', 10),
      ('MAG-L1-B', 20),
      ('MAG-L1-C', 30),
      ('MAG-L2-A', 40),
      ('MAG-L2-B', 50),
      ('MAG-L2-C', 60),
      ('MAG-L3', 70),
      ('MAG-L4', 80),
      ('MAG-JR', 90),
      ('WAG-L1-A', 100),
      ('WAG-L1-B', 110),
      ('WAG-L1-C', 120),
      ('WAG-L2-A', 130),
      ('WAG-L2-B', 140),
      ('WAG-L2-C', 150),
      ('WAG-L3-A', 160),
      ('WAG-L3-B', 170),
      ('WAG-L4-A', 180),
      ('WAG-L4-B', 190),
      ('WAG-L5-A', 200),
      ('WAG-L5-B', 210),
      ('WAG-L6-A', 220),
      ('WAG-L6-B', 230),
      ('WAG-PJ', 240),
      ('WAG-JR', 250),
      ('RG-A-KU56', 260),
      ('RG-A-KU78', 270),
      ('RG-A-KU910', 280),
      ('RG-A-KU1112', 290),
      ('RG-A-JR', 300),
      ('RG-B-KU56', 310),
      ('RG-B-KU78', 320),
      ('RG-B-KU910', 330),
      ('RG-B-KU1112', 340),
      ('RG-B-JR', 350),
      ('RG-C-KU56', 360),
      ('RG-C-KU78', 370),
      ('RG-C-KU910', 380),
      ('RG-C-KU1112', 390),
      ('RG-C-JR', 400),
      ('AER-JR-IM', 410),
      ('AER-JR-IW', 420),
      ('AER-JR-MP', 430),
      ('AER-YT-IM', 440),
      ('AER-YT-IW', 450),
      ('AER-YT-MP', 460),
      ('AER-ND-IM', 470),
      ('AER-ND-IW', 480),
      ('AER-PND-IM', 490),
      ('AER-PND-IW', 500)
    ) as v(code, sort) where c.code = v.code;
    -- Priangan lama (tambahan pada kategori biasa) dihapus; tagihan Priangan menjadi nol untuk yang belum lunas
    update jo.entries e set priangan_requested = false, priangan_status = 'tidak', priangan_fee = 0
      from jo.categories c where c.id = e.category_id and not c.jabar_only and e.priangan_requested;
    update jo.submissions s set total_amount = total_amount - priangan_amount, priangan_amount = 0
     where priangan_amount > 0 and status in ('menunggu_pembayaran','perlu_perbaikan');
    -- satu tautan lama dipakai untuk semua nomor
    update jo.entries e set music = (select jsonb_object_agg(x, e.music_url) from unnest(c.apparatus) x)
      from jo.categories c where c.id = e.category_id and e.music_url is not null and e.music = '{}'::jsonb;
    insert into jo.clubs (name, kind, province, country, verified, created_via, note)
    select 'BJS Gymnastic', 'sekolah', 'Jawa Barat', 'Indonesia', true, 'daftar_awal', 'Sekolah / Club · Lokasi: Jawa Barat'
     where not exists (select 1 from jo.clubs where lower(name) = 'bjs gymnastic' and merged_into is null);
    insert into jo.settings (key, value) values ('migrasi_v6_revisi', to_jsonb(now()));
  end if;
end $$;

-- v6: hapus data uji coba 14/10/2026 (dibuat sebelum 22.30 WIB) — sekali jalan, disetujui PM
do $$
declare r record; v_bound timestamptz := '2026-10-14 15:30:00+00'; n integer := 0;
begin
  if not exists (select 1 from jo.settings where key = 'migrasi_v6_hapus_uji') then
    for r in select id from jo.submissions where created_at < v_bound loop
      perform jo.purge_submission(r.id); n := n + 1;
    end loop;
    delete from jo.sessions s where not exists (select 1 from jo.entries e where e.session_id = s.id);
    delete from jo.clubs k where k.created_via = 'pendaftaran' and k.created_at < v_bound
       and not exists (select 1 from jo.submissions s where s.club_id = k.id)
       and not exists (select 1 from jo.clubs m where m.merged_into = k.id);
    delete from jo.outbox where created_at < v_bound;
    delete from jo.rate_events where at < v_bound;
    delete from jo.login_attempts where at < v_bound;
    delete from jo.audit where at < v_bound;
    update jo.categories c set scores_locked = false, results_published = false, results_published_at = null, startlist_published = false
     where not exists (select 1 from jo.entries e where e.category_id = c.id);
    update jo.team_levels set published = false, published_at = null;
    perform setval('jo.submission_seq',
      greatest(1, coalesce((select max(nullif(regexp_replace(code, '^.*-', ''), '')::integer) from jo.submissions), 0) + 1), false);
    if n > 0 then
      perform jo.log((select id from jo.staff where role = 'owner' limit 1), 'data_uji_dihapus', 'system', 'v6',
        jsonb_build_object('submissions', n, 'note', 'Data uji coba 14 Okt 2026 dihapus atas permintaan PM'));
    end if;
    insert into jo.settings (key, value) values ('migrasi_v6_hapus_uji', to_jsonb(now()));
  end if;
end $$;

-- v8 (15/10/2026): batas atlet per pendaftaran naik dari 5 ke 10; beregu lama dicatat sebagai biaya beregu
update jo.settings set value = '10'::jsonb, updated_at = now() where key = 'max_athletes' and value = '5'::jsonb;
update jo.submissions set team_amount = base_amount where registrant_type = 'beregu' and team_amount = 0;

-- v8b (15/10/2026): domain resmi gimnastikjabaropen2026.com; semua pertanyaan ke email Jabar Open (email PM tidak lagi ditampilkan)
update jo.settings set value = '"https://gimnastikjabaropen2026.com/"'::jsonb, updated_at = now()
 where key = 'site_url' and value = '"https://adjisena-design.github.io/jabar-open/"'::jsonb;
update jo.settings set value = '""'::jsonb, updated_at = now()
 where key = 'pm_email' and value = '"adjisena.daffa@gmail.com"'::jsonb;

-- v9 (19/10/2026): nama orang, klub, dan tim memakai huruf kapital di awal setiap kata (jo.name_case)
update jo.clubs set name = jo.name_case(name) where name is distinct from jo.name_case(name);
update jo.athletes set full_name = jo.name_case(full_name) where full_name is distinct from jo.name_case(full_name);
update jo.athletes set guardian_name = jo.name_case(guardian_name) where guardian_name is not null and guardian_name is distinct from jo.name_case(guardian_name);
update jo.submissions set contact_name = jo.name_case(contact_name) where contact_name is distinct from jo.name_case(contact_name);
update jo.teams set name = jo.name_case(name) where name is distinct from jo.name_case(name);
update jo.jury_applications set full_name = jo.name_case(full_name) where full_name is distinct from jo.name_case(full_name);
