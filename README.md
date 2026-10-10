# Jabar Open 2026

Situs resmi dan sistem pendaftaran Jabar Open 2026 (Gimnastik Indonesia (GI) Jawa Barat).
Gymnasium Arcamanik, Bandung, 12–20 Desember 2026.

## Halaman publik
| Halaman | Isi |
|---|---|
| `index.html` | Beranda: informasi, jadwal, biaya, cara daftar |
| `daftar.html` | Formulir pendaftaran (perorangan atau klub, maks. 5 atlet) |
| `status.html` | Status pendaftaran, pembayaran QRIS, unggah bukti, e-ticket PDF, sertifikat |
| `startlist.html` | Start list resmi (sesi, grup, urutan) |
| `hasil.html` | Hasil per kategori dan tabel medali (umum dan Priangan; per klub dan per kab/kota) |
| `verifikasi.html` | Verifikasi QR e-ticket dan sertifikat |

## Konsol panitia
`panitia/` — masuk dengan kode akses pribadi. Peran: owner, superadmin, admin (verifikator), juri.

## Backend
Supabase (PostgreSQL + Storage + sesi anonim). Semua data diakses lewat fungsi database yang memeriksa hak akses.
- `supabase/setup.sql` — jalankan seluruhnya di Supabase SQL Editor (aman diulang).
- `supabase/src/` — sumber SQL per bagian; `supabase/tools/build.sh` menggabungkannya.
- `assets/js/config.js` — URL proyek dan anon key (publik).

## Email
`email/Code.gs` — Google Apps Script yang mengirim email antrean lewat Gmail panitia.

Panduan lengkap: `docs/PANDUAN.md`.
