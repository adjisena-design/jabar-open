-- =====================================================================
--  Data awal: disiplin, kategori (Undangan 06/10/2026), pengaturan
--  'on conflict do nothing' -> perubahan dari konsol tidak tertimpa
-- =====================================================================

insert into jo.disciplines (code, name_id, name_en, date_start, date_end, apparatus, components, contact_name, contact_phone, sort) values
  ('MAG', 'Artistik Putra', 'Men''s Artistic', '2026-12-12', '2026-12-15', '[{"code": "FX", "id": "Lantai", "en": "Floor"}, {"code": "PH", "id": "Kuda Pelana", "en": "Pommel Horse"}, {"code": "SR", "id": "Gelang-gelang", "en": "Rings"}, {"code": "VT", "id": "Meja Lompat", "en": "Vault"}, {"code": "PB", "id": "Palang Sejajar", "en": "Parallel Bars"}, {"code": "HB", "id": "Palang Tunggal", "en": "High Bar"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Pengurangan netral", "en": "Neutral deductions"}]'::jsonb, 'Fegie Rizkia Mulyana', '0811-2348-753', 1),
  ('WAG', 'Artistik Putri', 'Women''s Artistic', '2026-12-12', '2026-12-15', '[{"code": "VT", "id": "Meja Lompat", "en": "Vault"}, {"code": "UB", "id": "Palang Bertingkat", "en": "Uneven Bars"}, {"code": "BB", "id": "Balok Keseimbangan", "en": "Balance Beam"}, {"code": "FX", "id": "Lantai", "en": "Floor"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Pengurangan netral", "en": "Neutral deductions"}]'::jsonb, 'Vicy Ayu', '0856-2383-455', 2),
  ('RG', 'Ritmik', 'Rhythmic', '2026-12-16', '2026-12-18', '[{"code": "FH", "id": "Tanpa Alat (Floor)", "en": "Freehand"}, {"code": "ROPE", "id": "Tali", "en": "Rope"}, {"code": "HOOP", "id": "Simpai", "en": "Hoop"}, {"code": "BALL", "id": "Bola", "en": "Ball"}, {"code": "CLUBS", "id": "Gada", "en": "Clubs"}, {"code": "RIBBON", "id": "Pita", "en": "Ribbon"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "A", "id": "Nilai A (artistik)", "en": "A score (artistry)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Penalti", "en": "Penalties"}]'::jsonb, 'Yuanita Vidya M', '0815-6361-1403', 3),
  ('AER', 'Aerobik', 'Aerobic', '2026-12-19', '2026-12-20', '[{"code": "RTN", "id": "Rangkaian", "en": "Routine"}]'::jsonb, '[{"code": "A", "id": "Nilai A (artistik)", "en": "A score (artistry)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "PEN", "id": "Penalti", "en": "Penalties"}]'::jsonb, 'Mustika Fitri', '0816-605-281', 4)
on conflict (code) do nothing;

insert into jo.categories (discipline, code, level, age_label, division, name_id, name_en, gender, birth_year_min, birth_year_max, entry_type, fee, apparatus, max_per_club, sort, note) values
  ('MAG', 'MAG-L1-A', 'Level 1', '6 tahun ke bawah', null, 'Artistik Putra Level 1 (6 tahun ke bawah)', 'Men''s Artistic Level 1 (6 & under)', 'M', 2020, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 10, null),
  ('MAG', 'MAG-L1-B', 'Level 1', '7–8 tahun', null, 'Artistik Putra Level 1 (7–8 tahun)', 'Men''s Artistic Level 1 (7–8)', 'M', 2018, 2019, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 20, null),
  ('MAG', 'MAG-L1-C', 'Level 1', '9 tahun ke atas', null, 'Artistik Putra Level 1 (9 tahun ke atas)', 'Men''s Artistic Level 1 (9 & over)', 'M', null, 2017, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 30, null),
  ('MAG', 'MAG-L2-A', 'Level 2', '7 tahun ke bawah', null, 'Artistik Putra Level 2 (7 tahun ke bawah)', 'Men''s Artistic Level 2 (7 & under)', 'M', 2019, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 40, null),
  ('MAG', 'MAG-L2-B', 'Level 2', '8–9 tahun', null, 'Artistik Putra Level 2 (8–9 tahun)', 'Men''s Artistic Level 2 (8–9)', 'M', 2017, 2018, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 50, null),
  ('MAG', 'MAG-L2-C', 'Level 2', '10 tahun ke atas', null, 'Artistik Putra Level 2 (10 tahun ke atas)', 'Men''s Artistic Level 2 (10 & over)', 'M', null, 2016, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 60, null),
  ('MAG', 'MAG-L3', 'Level 3', 'Usia terbuka', null, 'Artistik Putra Level 3 (usia terbuka)', 'Men''s Artistic Level 3 (open age)', 'M', null, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 70, null),
  ('MAG', 'MAG-L4', 'Level 4', 'Usia terbuka', null, 'Artistik Putra Level 4 (usia terbuka)', 'Men''s Artistic Level 4 (open age)', 'M', null, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 80, null),
  ('MAG', 'MAG-JR', 'Junior', '12–16 tahun', null, 'Artistik Putra Junior (12–16 tahun)', 'Men''s Artistic Junior (12–16)', 'M', 2010, 2014, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 90, null),
  ('WAG', 'WAG-L1-A', 'Level 1', '6 tahun ke bawah', null, 'Artistik Putri Level 1 (6 tahun ke bawah)', 'Women''s Artistic Level 1 (6 & under)', 'F', 2020, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 100, null),
  ('WAG', 'WAG-L1-B', 'Level 1', '7–8 tahun', null, 'Artistik Putri Level 1 (7–8 tahun)', 'Women''s Artistic Level 1 (7–8)', 'F', 2018, 2019, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 110, null),
  ('WAG', 'WAG-L1-C', 'Level 1', '9 tahun ke atas', null, 'Artistik Putri Level 1 (9 tahun ke atas)', 'Women''s Artistic Level 1 (9 & over)', 'F', null, 2017, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 120, null),
  ('WAG', 'WAG-L2-A', 'Level 2', '6 tahun ke bawah', null, 'Artistik Putri Level 2 (6 tahun ke bawah)', 'Women''s Artistic Level 2 (6 & under)', 'F', 2020, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 130, null),
  ('WAG', 'WAG-L2-B', 'Level 2', '7–8 tahun', null, 'Artistik Putri Level 2 (7–8 tahun)', 'Women''s Artistic Level 2 (7–8)', 'F', 2018, 2019, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 140, null),
  ('WAG', 'WAG-L2-C', 'Level 2', '9 tahun ke atas', null, 'Artistik Putri Level 2 (9 tahun ke atas)', 'Women''s Artistic Level 2 (9 & over)', 'F', null, 2017, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 150, null),
  ('WAG', 'WAG-L3-A', 'Level 3', '9 tahun ke bawah', null, 'Artistik Putri Level 3 (9 tahun ke bawah)', 'Women''s Artistic Level 3 (9 & under)', 'F', 2017, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 160, null),
  ('WAG', 'WAG-L3-B', 'Level 3', '10 tahun ke atas', null, 'Artistik Putri Level 3 (10 tahun ke atas)', 'Women''s Artistic Level 3 (10 & over)', 'F', null, 2016, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 170, null),
  ('WAG', 'WAG-L4-A', 'Level 4', '11 tahun ke bawah', null, 'Artistik Putri Level 4 (11 tahun ke bawah)', 'Women''s Artistic Level 4 (11 & under)', 'F', 2015, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 180, null),
  ('WAG', 'WAG-L4-B', 'Level 4', '12 tahun ke atas', null, 'Artistik Putri Level 4 (12 tahun ke atas)', 'Women''s Artistic Level 4 (12 & over)', 'F', null, 2014, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 190, null),
  ('WAG', 'WAG-L5-A', 'Level 5', '12 tahun ke bawah', null, 'Artistik Putri Level 5 (12 tahun ke bawah)', 'Women''s Artistic Level 5 (12 & under)', 'F', 2014, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 200, null),
  ('WAG', 'WAG-L5-B', 'Level 5', '13 tahun ke atas', null, 'Artistik Putri Level 5 (13 tahun ke atas)', 'Women''s Artistic Level 5 (13 & over)', 'F', null, 2013, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 210, null),
  ('WAG', 'WAG-L6-A', 'Level 6', '12 tahun ke bawah', null, 'Artistik Putri Level 6 (12 tahun ke bawah)', 'Women''s Artistic Level 6 (12 & under)', 'F', 2014, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 220, null),
  ('WAG', 'WAG-L6-B', 'Level 6', '13 tahun ke atas', null, 'Artistik Putri Level 6 (13 tahun ke atas)', 'Women''s Artistic Level 6 (13 & over)', 'F', null, 2013, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 230, null),
  ('WAG', 'WAG-PJ', 'Pre Junior', '11–13 tahun', null, 'Artistik Putri Pre Junior (11–13 tahun)', 'Women''s Artistic Pre Junior (11–13)', 'F', 2013, 2015, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 240, null),
  ('WAG', 'WAG-JR', 'Junior', '14–15 tahun', null, 'Artistik Putri Junior (14–15 tahun)', 'Women''s Artistic Junior (14–15)', 'F', 2011, 2012, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 250, null),
  ('RG', 'RG-A-KU56', 'KU 5–6', 'Kelahiran 2020–2021', 'Profesional', 'Ritmik Profesional KU 5–6', 'Rhythmic Professional KU 5–6', 'F', 2020, 2021, 'individual', 750000, array['FH','BALL']::text[], null, 260, null),
  ('RG', 'RG-A-KU78', 'KU 7–8', 'Kelahiran 2018–2019', 'Profesional', 'Ritmik Profesional KU 7–8', 'Rhythmic Professional KU 7–8', 'F', 2018, 2019, 'individual', 750000, array['FH','HOOP']::text[], null, 270, null),
  ('RG', 'RG-A-KU910', 'KU 9–10', 'Kelahiran 2016–2017', 'Profesional', 'Ritmik Profesional KU 9–10', 'Rhythmic Professional KU 9–10', 'F', 2016, 2017, 'individual', 750000, array['FH','HOOP','BALL']::text[], null, 280, null),
  ('RG', 'RG-A-KU1112', 'KU 11–12', 'Kelahiran 2014–2015', 'Profesional', 'Ritmik Profesional KU 11–12', 'Rhythmic Professional KU 11–12', 'F', 2014, 2015, 'individual', 750000, array['FH','BALL','CLUBS']::text[], null, 290, null),
  ('RG', 'RG-A-JR', 'Junior', 'Kelahiran 2012–2013', 'Profesional', 'Ritmik Profesional Junior', 'Rhythmic Professional Junior', 'F', 2012, 2013, 'individual', 750000, array['HOOP','BALL','CLUBS','RIBBON']::text[], null, 300, null),
  ('RG', 'RG-B-KU56', 'KU 5–6', 'Kelahiran 2020–2021', 'Amatir', 'Ritmik Amatir KU 5–6', 'Rhythmic Amateur KU 5–6', 'F', 2020, 2021, 'individual', 750000, array['FH','BALL']::text[], null, 310, null),
  ('RG', 'RG-B-KU78', 'KU 7–8', 'Kelahiran 2018–2019', 'Amatir', 'Ritmik Amatir KU 7–8', 'Rhythmic Amateur KU 7–8', 'F', 2018, 2019, 'individual', 750000, array['FH','HOOP']::text[], null, 320, null),
  ('RG', 'RG-B-KU910', 'KU 9–10', 'Kelahiran 2016–2017', 'Amatir', 'Ritmik Amatir KU 9–10', 'Rhythmic Amateur KU 9–10', 'F', 2016, 2017, 'individual', 750000, array['FH','HOOP','BALL']::text[], null, 330, null),
  ('RG', 'RG-B-KU1112', 'KU 11–12', 'Kelahiran 2014–2015', 'Amatir', 'Ritmik Amatir KU 11–12', 'Rhythmic Amateur KU 11–12', 'F', 2014, 2015, 'individual', 750000, array['FH','BALL','CLUBS']::text[], null, 340, null),
  ('RG', 'RG-B-JR', 'Junior', 'Kelahiran 2012–2013', 'Amatir', 'Ritmik Amatir Junior', 'Rhythmic Amateur Junior', 'F', 2012, 2013, 'individual', 750000, array['HOOP','BALL','CLUBS','RIBBON']::text[], null, 350, null),
  ('AER', 'AER-JR-IM', 'Junior', '15–17 tahun', null, 'Aerobik Junior Perorangan Putra (IM)', 'Aerobic Junior Individual Men (IM)', 'M', 2009, 2011, 'individual', 300000, array['RTN']::text[], 4, 360, null),
  ('AER', 'AER-JR-IW', 'Junior', '15–17 tahun', null, 'Aerobik Junior Perorangan Putri (IW)', 'Aerobic Junior Individual Women (IW)', 'F', 2009, 2011, 'individual', 300000, array['RTN']::text[], 4, 370, null),
  ('AER', 'AER-JR-MP', 'Junior', '15–17 tahun', null, 'Aerobik Junior Pasangan Campuran (MP)', 'Aerobic Junior Mixed Pair (MP)', 'X', 2009, 2011, 'pair', 400000, array['RTN']::text[], 4, 380, null),
  ('AER', 'AER-YT-IM', 'Youth', '12–14 tahun', null, 'Aerobik Youth Perorangan Putra (IM)', 'Aerobic Youth Individual Men (IM)', 'M', 2012, 2014, 'individual', 300000, array['RTN']::text[], 4, 390, null),
  ('AER', 'AER-YT-IW', 'Youth', '12–14 tahun', null, 'Aerobik Youth Perorangan Putri (IW)', 'Aerobic Youth Individual Women (IW)', 'F', 2012, 2014, 'individual', 300000, array['RTN']::text[], 4, 400, null),
  ('AER', 'AER-YT-MP', 'Youth', '12–14 tahun', null, 'Aerobik Youth Pasangan Campuran (MP)', 'Aerobic Youth Mixed Pair (MP)', 'X', 2012, 2014, 'pair', 400000, array['RTN']::text[], 4, 410, null),
  ('AER', 'AER-ND-IM', 'National Development', '9–11 tahun', null, 'Aerobik National Development Perorangan Putra (IM)', 'Aerobic National Development Individual Men (IM)', 'M', 2015, 2017, 'individual', 300000, array['RTN']::text[], 4, 420, null),
  ('AER', 'AER-ND-IW', 'National Development', '9–11 tahun', null, 'Aerobik National Development Perorangan Putri (IW)', 'Aerobic National Development Individual Women (IW)', 'F', 2015, 2017, 'individual', 300000, array['RTN']::text[], 4, 430, null),
  ('AER', 'AER-PND-IM', 'Pre National Development', '6–8 tahun', null, 'Aerobik Pre National Development Perorangan Putra (IM)', 'Aerobic Pre National Development Individual Men (IM)', 'M', 2018, 2020, 'individual', 300000, array['RTN']::text[], 4, 440, null),
  ('AER', 'AER-PND-IW', 'Pre National Development', '6–8 tahun', null, 'Aerobik Pre National Development Perorangan Putri (IW)', 'Aerobic Pre National Development Individual Women (IW)', 'F', 2018, 2020, 'individual', 300000, array['RTN']::text[], 4, 450, null)
on conflict (code) do nothing;

insert into jo.settings (key, value) values
  ('event_name', '"Jabar Open 2026"'::jsonb),
  ('event_year', '2026'::jsonb),
  ('site_url', '"https://adjisena-design.github.io/jabar-open/"'::jsonb),
  ('registration_open', 'true'::jsonb),
  ('registration_deadline', '"2026-11-12T23:59:59+07:00"'::jsonb),
  ('payment_deadline_label', '"12 November 2026"'::jsonb),
  ('priangan_fee', '150000'::jsonb),
  ('qris_cap', '10000000'::jsonb),
  ('max_athletes', '5'::jsonb),
  ('qris_image_url', 'null'::jsonb),
  ('qris_merchant', '"Jabar Open 2026"'::jsonb),
  ('payment_note', '"Scan QRIS dengan aplikasi bank atau dompet digital apa pun, lalu ketik nominal persis seperti tertera (termasuk tiga digit kode unik)."'::jsonb),
  ('contact_email', '"jabaropen2026@gmail.com"'::jsonb),
  ('pm_email', '"adjisena.daffa@gmail.com"'::jsonb),
  ('team_fee', '650000'::jsonb),
  ('team_max', '6'::jsonb),
  ('team_counting', '4'::jsonb),
  ('instagram', '"gimnastikjabar"'::jsonb),
  ('email_guardians', 'true'::jsonb),
  ('venue', '{"name": "Gymnasium Arcamanik", "address": "Jl. Pacuan Kuda No. 15b, Sukamiskin, Arcamanik, Kota Bandung, Jawa Barat 40231"}'::jsonb),
  ('signatories', '[{"name": "Andi Juliandi", "title": "Ketua Pelaksana Jabar Open 2026"}, {"name": "Dika Chrisna Irzandi, S.A.B., M.B.A", "title": "Ketua Gimnastik Indonesia (GI) Jawa Barat"}]'::jsonb)
on conflict (key) do nothing;
