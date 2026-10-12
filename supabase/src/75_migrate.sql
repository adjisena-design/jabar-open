-- =====================================================================
--  Penyesuaian data untuk instalasi yang sudah berjalan (aman diulang)
-- =====================================================================
-- v3: email kontak resmi pindah ke jabaropen2026@gmail.com, PM tetap tercantum
update jo.settings set value = '"jabaropen2026@gmail.com"'::jsonb, updated_at = now()
 where key = 'contact_email' and value = '"adjisena.daffa@gmail.com"'::jsonb;
