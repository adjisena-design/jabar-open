-- =====================================================================
--  Jabar Open 2026 — Pendaftaran Massal (dipasang 6 Nov 2026)
--  Semua fungsi & tabel ada di src/66_massal.sql (ikut setup.sql), dan perubahan
--  pada public_register, check_athlete_docs, outbox_claim, console_verify_payment,
--  console_submissions, console_orphan_files sudah ada di src/40, 50, 56.
--
--  Patch ini hanya data yang khusus untuk database live:
--  siapa (selain owner) yang boleh membuat/mencabut kode massal, memperpanjang,
--  dan memverifikasi transfer. Saat ini: Inda Sofia (superadmin, Finance Manager).
-- =====================================================================
insert into jo.settings (key, value)
values ('bulk_manager_ids', '["8d96b19f-49bd-4ee4-ac26-6f722bd6ae13"]'::jsonb)
on conflict (key) do update set value = excluded.value, updated_at = now();

-- Setelah menjalankan setup.sql ulang, jalankan juga patch_2026-11-02_turnstile.sql
-- (public_register hanya boleh dipanggil Edge Function).
