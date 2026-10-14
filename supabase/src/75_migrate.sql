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
