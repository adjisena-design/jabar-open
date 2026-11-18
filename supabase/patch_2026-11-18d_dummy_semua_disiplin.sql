-- 18 Nov 2026 (d): kode DUMMY (Asisten Juri / Verifikator) berlaku untuk semua disiplin; bisa ganti disiplin di konsol juri.
-- Diterapkan lewat penggantian di dalam fungsi: jo.staff_create, public.console_staff_update, public.console_juri_switch (lihat src/71_penilaian.sql).
update jo.staff set disc_group = null, discipline = null where is_dummy;
