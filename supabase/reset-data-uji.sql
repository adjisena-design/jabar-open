-- =====================================================================
--  JABAR OPEN 2026 — HAPUS DATA UJI COBA (jalankan sekali sebelum peluncuran)
--  Menghapus: pendaftaran, atlet, entri, nilai, mutasi, email, log, sesi,
--             klub yang dibuat dari formulir, dan sesi login panitia.
--  Menyimpan: pengaturan, disiplin, kategori, kode akses panitia, QRIS.
--  Berkas di Storage (dokumen, bukti) TIDAK terhapus oleh skrip ini:
--  kosongkan lewat Dashboard -> Storage -> pilih bucket -> pilih semua -> Delete.
-- =====================================================================
begin;
delete from jo.scores;
delete from jo.score_log;
delete from jo.mutations;
delete from jo.outbox;
delete from jo.entry_athletes;
delete from jo.entries;
delete from jo.athletes;
delete from jo.submissions;
delete from jo.sessions;
delete from jo.clubs where created_via = 'pendaftaran';
delete from jo.audit;
delete from jo.rate_events;
delete from jo.login_attempts;
delete from jo.staff_sessions;
update jo.categories set scores_locked = false, results_published = false, results_published_at = null, startlist_published = false;
alter sequence jo.submission_seq restart with 1;
commit;
select 'Data uji dihapus. Nomor pendaftaran mulai lagi dari JO26-xxx-0001.' as hasil;
