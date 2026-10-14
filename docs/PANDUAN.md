# Jabar Open 2026 — Panduan Sistem Pendaftaran & Konsol Panitia

*Versi 3, 14 Oktober 2026 (aturan penghargaan dari lampiran Medali & Piala Artistik, beregu hanya WAG L1–6, tanda tangan sertifikat, ekspor Nominative Form & kebutuhan medali, tampilan konsol baru). Disusun untuk Daffa Adjisena (owner sistem).*

## 1. Gambaran sistem

Dua situs, satu backend.

- **Situs publik** (`https://adjisena-design.github.io/jabar-open/`): beranda, pendaftaran, cek status & e-ticket, ganti musik Ritmik (`musik.html`), start list, hasil & medali, verifikasi QR.
- **Konsol panitia** (`…/jabar-open/panitia/`): masuk dengan kode akses pribadi.
- **Backend** Supabase proyek `jabar-open-2026` (region Tokyo): database, penyimpanan berkas privat, sesi anonim. Semua akses data lewat fungsi database yang memeriksa hak; tabel tidak bisa dibaca langsung.
- **Email**: Google Apps Script di akun Gmail panitia mengambil antrean email setiap menit.

### Peran kode akses
| Peran | Bisa | Contoh pemegang |
|---|---|---|
| Owner | Semua, termasuk pengaturan sistem, kode superadmin, secret email | Daffa Adjisena |
| Superadmin | Semua data, ledger & impor GoBiz, log, kode admin/juri, tandai lunas tanpa bukti, atlet WNA | Andi Juliandi |
| Admin (verifikator) | Verifikasi bayar, dokumen, Priangan; ubah data atlet; pindah kategori; start list; penilaian; publikasi hasil. Bisa dibatasi satu disiplin | Fegie (MAG), Vicy (WAG), Yuanita (RG), Mustika (AER) |
| Juri | Input nilai saja, bisa dibatasi disiplin, alat, dan komponen (D/E/A/PEN) | Panel juri |

Kode akses bisa ditambah kapan saja dari **Konsol → Kode akses**. Kode hanya tampil sekali; bila hilang, buat kode baru (kode lama langsung mati).

## 2. Langkah setup yang tersisa

1. **Jalankan ulang `supabase/setup.sql` versi terbaru** di SQL Editor (aman diulang; data dan kode owner tetap).
2. **Masuk konsol** di `…/panitia/` dengan kode owner.
3. **Pengaturan → QRIS pembayaran**: unggah gambar QRIS dari GoBiz. Isi nama merchant.
4. **Kode akses**: buat kode superadmin Pak Andi, empat admin disiplin, lalu juri.
5. **Pengirim email** (10 menit):
   1. Buka `script.google.com` dengan akun Gmail pengirim (`jabaropen2026@gmail.com`).
   2. Proyek baru → tempel isi `email/Code.gs`.
   3. Project Settings → Script properties: `SUPABASE_URL`, `SUPABASE_KEY` (anon key), `SECRET` (secret_email dari setup), `REPLY_TO` = `jabaropen2026@gmail.com`.
   4. Kontak di situs dan footer email: `jabaropen2026@gmail.com` untuk pendaftaran; `adjisena.daffa@gmail.com` sebagai Project Manager untuk permintaan khusus atau bila email utama lama dibalas (Pengaturan: `contact_email`, `pm_email`).
   5. Jalankan `ujiKoneksi`, izinkan akses. Lalu jalankan `pasangJadwal`.
   6. Cek **Konsol → Pengaturan → Pengirim email**: status "Terakhir terhubung" muncul.
6. **Periksa tabel kategori** (Konsol → Kategori) terhadap asumsi di bagian 6.

## 3. Alur peserta

1. Isi formulir (`daftar.html`): pilih perorangan atau klub (maks. 5 atlet), disiplin, penanggung jawab, klub, data atlet, unggah identitas, pilih kategori. Kategori yang tidak sesuai tanggal lahir/jenis kelamin otomatis abu-abu. Atlet di bawah 18 tahun wajib data orang tua/wali.
2. Centang pernyataan risiko, asuransi, data pribadi (UU PDP), peraturan, dan persetujuan wali.
3. Sistem membuat tagihan dengan **kode unik 1–999** di tiga digit terakhir. Peserta membayar lewat **satu QRIS** dan mengetik nominal persis.
4. Unggah bukti bayar (langsung atau dari halaman status). Status: *Menunggu verifikasi*.
5. Panitia menandai lunas → email e-ticket otomatis → e-ticket PDF per atlet (dengan QR verifikasi) bisa diunduh dari halaman status.
6. Tidak ada registrasi ulang. Start list dipublikasikan di situs; hasil dan sertifikat setelah UPP.

Atlet WNA: tanpa QRIS dan kode unik; panitia menghubungi lewat email, superadmin menandai lunas dengan nominal yang diterima.

### Beregu Artistik Putri (WAG Level 1–6)
- Pilihan ketiga di `daftar.html`: **Beregu Artistik**, Rp650.000 per tim, di luar biaya perorangan. Hanya Artistik Putri Level 1–6 (sesuai Piala Beregu di lampiran medali; daftar level diatur di pengaturan `team_levels`). Wajib klub; satu tim = satu level (kelompok usia boleh campur), 1–6 pesenam. Satu klub boleh beberapa tim per level dengan nama berbeda. Beregu Level 6 berjalan bila peminat cukup.
- Setiap anggota dipilih sebagai **Juga perorangan** (sudah terdaftar perorangan di level itu lewat klub yang sama; dicocokkan dari nama dan tanggal lahir) atau **Khusus beregu** (data lengkap + dokumen; dinilai di kelompok usianya tetapi tidak diperingkat perorangan; biaya sudah termasuk biaya tim; dapat e-ticket sendiri).
- Nilai tim = jumlah 4 nilai serba bisa terbaik. Peringkat dihitung otomatis dari nilai di halaman Penilaian. Setelah dipublikasikan, setiap anggota tim peringkat 1–3 mengunduh **Sertifikat Juara Beregu** (dengan QR verifikasi) dari halaman status.

### Musik Ritmik
- Setiap atlet Ritmik wajib mengisi **tautan folder Google Drive** (satu folder per atlet, berisi semua MP3) saat daftar.
- Ganti musik **satu kali** per atlet lewat `musik.html` (kode pendaftaran + email penanggung jawab), sampai start list kategorinya terbit. Berlaku langsung, tautan lama tersimpan di riwayat, email konfirmasi terkirim.
- Bila panitia menandai "tidak bisa dibuka", pendaftar mendapat email dan memperbaiki akses di halaman yang sama; perbaikan tidak memakai jatah ganti.

## 4. Alur panitia sehari-hari

**Verifikasi pembayaran** (Konsol → Pendaftaran → filter *Menunggu verifikasi*)
- Buka pendaftaran, lihat bukti bayar di panel kanan.
- Cocokkan nominal dengan mutasi GoBiz. Superadmin bisa **Ledger → Impor mutasi**: unggah laporan transaksi GoBiz (Excel/CSV); mutasi dengan nominal sama persis dengan satu tagihan cocok otomatis dan tampil di halaman pendaftaran.
- **Tandai lunas** (email e-ticket terkirim) atau **Tolak bukti** dengan alasan (email perbaikan terkirim, peserta unggah ulang).

**Dokumen identitas**: di setiap atlet, *Lihat dokumen identitas* → *Dokumen valid* / *Tidak valid* (dengan catatan). Bila tanggal lahir salah ketik: *Ubah data* dengan alasan.

**Priangan**: setujui bila alamat identitas di Jawa Barat dan klub di Jawa Barat; tolak dengan alasan bila tidak.

**Penggabungan kategori**: Ringkasan menampilkan kategori dengan kurang dari 3 peserta. Pindahkan entri lewat *Pindah kategori* (tercatat di log). Kategori Aerobik dengan kurang dari 4 peserta atau kurang dari 3 delegasi: tandai *Eksibisi* di Kategori.

**Start list**: Konsol → Start list → buat sesi (nama, hari, jam) → pilih kategori → atur sesi, grup, urutan (atau *Undi urutan acak*) → *Publikasikan*.

**Penilaian**
- Juri masuk dengan kodenya di ponsel/laptop → pilih kategori → alat → isi nilai komponen. Tersimpan otomatis.
- Pencatat (admin) bisa mengisi **nilai akhir per alat** dari lembar juri; nilai akhir menggantikan hitungan komponen.
- Nilai alat = rata-rata D + E + A − penalti (bila 4 juri atau lebih untuk satu komponen, nilai tertinggi dan terendah dibuang).
- *Kunci nilai* setelah selesai. Koreksi setelah dikunci wajib alasan dan tercatat di **Log → Koreksi nilai** (dasar bila bagian protes diadakan lagi).

**Hasil & medali**: Konsol → Hasil & medali → pilih kategori → *Publikasikan hasil* setelah UPP. Hasil, tabel medali (per kab/kota dan per klub, umum dan Priangan), dan sertifikat langsung tersedia. *Unduh semua sertifikat (PDF)* untuk cetak.

**Beregu**: Konsol → Hasil & medali → tab *Beregu* → pilih disiplin. Tampil peringkat per level (hanya tim lunas), nilai tiap anggota (yang dihitung ditebalkan), tim yang belum lunas. *Publikasikan hasil beregu* setelah nilai level itu final; *Unduh sertifikat Juara Beregu* untuk cetak. Menarik publikasi hanya superadmin. Pendaftaran beregu bisa difilter di Pendaftaran → *Pendaftaran beregu*.

**Musik Ritmik**: Konsol → Musik Ritmik (admin RG dan superadmin). Buka setiap tautan, pastikan folder bisa diakses dan berisi MP3, lalu *Bisa dibuka* atau *Tidak bisa dibuka* (catatan dikirim ke pendaftar). Filter *Perlu tindakan* menampilkan yang belum beres; *Unduh Excel* untuk operator musik. Riwayat ganti per atlet ada di detail pendaftaran.

**Penghargaan** (lampiran Medali & Piala Artistik 12/10/2026), diatur per kategori di Kategori → Ubah (superadmin):
- Semua kategori Artistik: medali serba bisa peringkat 1–3, medali mini peringkat 4–6, sertifikat peserta untuk semua.
- WAG Level 4–6, Pre Junior, Junior dan MAG Junior: juga medali per alat peringkat 1–3, dengan sertifikat per alat (kode verifikasi `<kode>-<alat>`).
- WAG Level 4–6, Pre Junior, Junior: maks. 2 pesenam per klub untuk setiap penghargaan; pesenam ke-3 dst. dari klub yang sama dilewati dan penghargaan turun ke pesenam berikutnya. Nilai kembar per alat sementara berbagi peringkat (tie-break FIG belum diterapkan).
- Tabel medali menghitung medali serba bisa dan per alat; medali mini tidak dihitung.

**Ekspor**: Data atlet → *Nominative Form* (format lampiran panitia: Gymnasts List + Team, per klub atau semua). Hasil & medali → Tabel medali → *Kebutuhan medali (Excel)* (format lampiran medali, dari jumlah pendaftar; baris Cadangan diisi manual).

**Tanda tangan sertifikat**: Pengaturan → Penanda tangan sertifikat → *Unggah tanda tangan* (PNG/JPG; latar putih dibuat transparan) → Simpan pengaturan. Tanda tangan Pak Dika sudah terpasang.

**Ledger** (superadmin): ringkasan per disiplin (biaya perorangan, beregu dan jumlah tim, Priangan, kode unik), semua tagihan dengan jenis dan nama tim, siapa yang memverifikasi, unduh Excel.

## 5. Skenario demo Senin (± 15 menit)

1. Buka beranda di proyektor: angka atlet terdaftar langsung dari database, hitung mundur, tombol Daftar.
2. Peserta uji (ponsel masing-masing) membuka `daftar.html`, mendaftarkan atlet fiktif. Tunjukkan kategori abu-abu saat tanggal lahir diisi, dan opsi Priangan.
3. Tagihan muncul dengan tiga digit kode unik bergaris bawah emas. Unggah tangkapan layar apa pun sebagai bukti.
4. Di laptop, konsol owner: Ringkasan → pendaftaran baru muncul → buka → lihat bukti & dokumen → Tandai lunas.
5. Di ponsel peserta: halaman status menjadi Lunas → unduh e-ticket PDF → pindai QR-nya → halaman verifikasi.
6. Buat kode juri di depan audiens → juri masuk di ponselnya → isi nilai.
7. Publikasikan hasil → buka `hasil.html` → tabel medali dan sertifikat.

Setelah demo dan sebelum peluncuran: jalankan `supabase/reset-data-uji.sql` di SQL Editor untuk menghapus semua data uji (pengaturan, kategori, kode akses, dan QRIS tetap), lalu kosongkan bucket `dokumen` dan `bukti` di Dashboard → Storage.

## 6. Asumsi yang perlu dikonfirmasi

| Hal | Yang dipasang sekarang | Bisa diubah di |
|---|---|---|
| Usia | Usia 2026 = 2026 − tahun lahir (Undangan: "umur pada tahun kompetisi") | — |
| Ritmik kelompok umur | KU 5–6 = lahir 2020–2021, KU 7–8 = 2018–2019, KU 9–10 = 2016–2017, KU 11–12 = 2014–2015, Junior = 2012–2013 (Undangan hanya mencantumkan satu tahun) | Konsol → Kategori |
| Ritmik | Hanya putri; kategori A Profesional dan B Amatir. Kategori C "Priangan" di Undangan dijalankan sebagai Priangan lintas disiplin (sesuai arahan), sehingga alat khusus C (mis. KU 7–8 hanya simpai) tidak dipakai | Kategori |
| WAG Level 5–6 | Dua level terpisah (Level 5 dan Level 6), masing-masing 11 ke bawah dan 12 ke atas | Kategori |
| MAG Level 1–4 | Keenam alat dinilai | Kategori → alat |
| Batas per klub | MAG/WAG 10 per kategori, Aerobik 4 per kategori | Kategori |
| Biaya Priangan | Rp150.000 per entri (satu pasangan MP = satu entri) | Pengaturan |
| Medali Artistik | Sesuai lampiran medali 12/10/2026 (lihat bagian 4). Ambang 85/90% MAG L1–4 & WAG L1–3 belum diterapkan | Kategori → Ubah |
| Kelompok usia WAG L4–6 | L4: 10 ke bawah / 11 ke atas; L5–L6: 11 ke bawah / 12 ke atas (lampiran medali) | Kategori |
| Medali Ritmik & Aerobik | Peringkat 1–3; festival 50/30/20 Ritmik menunggu rumus resmi | — |
| Refund, juri klub Ritmik & denda Rp1.000.000 | Belum ditangani (sesuai arahan) | — |

## 7. Batasan & keamanan

- **Supabase gratis**: 500 MB database, 1 GB berkas, 5 GB transfer/bulan. Proyek dijeda setelah 7 hari tanpa aktivitas; pengirim email memanggil database tiap menit sehingga tidak dijeda. Pantau di dashboard Supabase.
- **Email Gmail**: kuota ±100 penerima per hari untuk akun Gmail biasa. Bila habis, email menunggu dan otomatis terkirim keesokan harinya (status terlihat di Pengaturan).
- **Sesi anonim**: batas pembuatan sesi per IP dinaikkan ke 150/jam. Untuk pengamanan tambahan sebelum peluncuran: aktifkan CAPTCHA (Cloudflare Turnstile) di Supabase Auth.
- **Berkas privat**: dokumen identitas dan bukti bayar hanya bisa dibuka panitia (admin ke atas) lewat tautan yang berlaku 15 menit. Juri tidak bisa membuka dokumen.
- **Data anak**: halaman publik hanya menampilkan nama, nomor atlet, klub, dan hasil; tanggal lahir dan dokumen tidak pernah tampil. Pernyataan persetujuan wali tersimpan bersama waktu persetujuan.
- **Sebelum peluncuran publik**: teks pernyataan dan persetujuan ditinjau Bidang Hukum (Pak Mangiring Sibagariang); jadwal penghapusan dokumen identitas setelah kejuaraan ditetapkan.
- **Uang masuk**: QRIS atas nama bendahara GI Jawa Barat / Jabar Open 2026. Ledger hanya akurat bila mutasi GoBiz diimpor rutin.
