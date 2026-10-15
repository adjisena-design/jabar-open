# Jabar Open 2026 — Panduan Sistem Pendaftaran & Konsol Panitia

*Versi 8, 15 Oktober 2026 (pendaftaran hanya lewat klub, maksimal 10 atlet per pendaftaran, beregu menjadi langkah di pendaftaran klub, peran penanggung jawab wajib). Versi 7 (jam tugas juri, peran Pemantau, konsol ramah ponsel). Versi 6 (FAQ situs dikelola dari konsol; AIC hanya terbuka saat lunas dengan tautan unduh langsung di email). Versi 5, 14 Oktober 2026 (revisi PDF panitia: Priangan menjadi kategori Ritmik tersendiri, musik per nomor, dokumen atlet terpisah + BPJS TK, pas foto wajib dan Athlete Identification Card (AIC), juri satu disiplin + BPJS TK, batas 15 menit bukti bayar, hapus data oleh owner/superadmin). Versi 4: chat panitia, laporan masalah, halaman kontak WhatsApp, pendaftaran juri, peran TD, daftar 53 klub di formulir, hapus klub). Versi 3: aturan penghargaan dari lampiran Medali & Piala Artistik, beregu hanya WAG L1–6, tanda tangan sertifikat, ekspor Nominative Form & kebutuhan medali, tampilan konsol baru). Disusun untuk Daffa Adjisena (owner sistem).*

## 1. Gambaran sistem

Dua situs, satu backend.

- **Situs publik** (`https://adjisena-design.github.io/jabar-open/`): beranda, pendaftaran, pendaftaran juri (`juri.html`), cek status & e-ticket, ganti musik Ritmik (`musik.html`), start list, hasil & medali, verifikasi QR.
- **Konsol panitia** (`…/jabar-open/panitia/`): masuk dengan kode akses pribadi.
- **Backend** Supabase proyek `jabar-open-2026` (region Tokyo): database, penyimpanan berkas privat, sesi anonim. Semua akses data lewat fungsi database yang memeriksa hak; tabel tidak bisa dibaca langsung.
- **Email**: Google Apps Script di akun Gmail panitia mengambil antrean email setiap menit.

### Peran kode akses
| Peran | Bisa | Contoh pemegang |
|---|---|---|
| Owner | Semua, termasuk pengaturan sistem, kode superadmin, secret email | Daffa Adjisena |
| Superadmin | Semua data, ledger & impor GoBiz, log, kode admin/juri, tandai lunas tanpa bukti, atlet WNA | Andi Juliandi |
| Admin (verifikator) | Verifikasi bayar, dokumen, Priangan; ubah data atlet; pindah kategori; start list; penilaian; publikasi hasil. Bisa dibatasi satu disiplin | Fegie (MAG), Vici (WAG), Yuanita (RG), Mustika (AER) |
| TD (Technical Director) | Hanya baca: Kategori, Start list, Penilaian (nilai juri yang masuk), Hasil & medali. Chat, laporan masalah, semua kontak termasuk pendaftar. Tidak bisa mengubah, menyetujui, atau memublikasikan. Bisa dibatasi satu disiplin | TD per disiplin |
| Pemantau | Hanya lihat halaman pertandingan: Kategori, Start list, Penilaian, Hasil & medali (termasuk beregu dan tabel medali). Tanpa chat, laporan masalah, kontak, atau data pendaftar. Bisa dibatasi satu disiplin | Pengamat KONI, tamu |
| Juri | Input nilai saja, bisa dibatasi disiplin, alat, dan komponen (D/E/A/PEN). Juga chat, laporan masalah, dan kontak panitia & juri (bukan kontak pendaftar) | Panel juri |

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

1. Isi formulir (`daftar.html`). **Semua atlet didaftarkan lewat klub** (klub, sekolah, pengkab/pengkot, atau lainnya; klub luar negeri boleh); tidak ada pendaftaran perorangan. Langkahnya: disiplin dan penanggung jawab (peran wajib: pemilik klub, admin klub, pelatih, manajer/official, atau lainnya) → klub (pilih dari daftar atau tambah klub baru) → atlet & kategori (**maks. 10 atlet per pendaftaran**, termasuk anggota khusus beregu; klub dengan lebih dari 10 atlet membuat pendaftaran berikutnya, tombol *Daftarkan atlet lain dari klub ini* menyimpan data klub) → **Beregu** (hanya Artistik Putri, opsional) → pernyataan & kirim. Unggah identitas dan pilih kategori per atlet. Kategori yang tidak sesuai tanggal lahir/jenis kelamin otomatis abu-abu. Atlet di bawah 18 tahun wajib data orang tua/wali.
2. Centang pernyataan risiko, asuransi, data pribadi (UU PDP), peraturan, dan pernyataan bahwa klub sudah mendapat persetujuan orang tua/wali atlet di bawah 18 tahun.
3. Sistem membuat tagihan dengan **kode unik 1–999** di tiga digit terakhir. Peserta membayar lewat **satu QRIS** dan mengetik nominal persis.
4. Unggah bukti bayar (langsung atau dari halaman status). Status: *Menunggu verifikasi*.
5. Panitia menandai lunas → email e-ticket otomatis → e-ticket PDF per atlet (dengan QR verifikasi) bisa diunduh dari halaman status.
6. Tidak ada registrasi ulang. Start list dipublikasikan di situs; hasil dan sertifikat setelah UPP.

Atlet WNA: tanpa QRIS dan kode unik; panitia menghubungi lewat email, superadmin menandai lunas dengan nominal yang diterima.

### Beregu Artistik Putri (WAG Level 1–6)
- Langkah **Beregu** di pendaftaran klub (muncul hanya untuk Artistik Putri): tombol *Tambah tim beregu*, Rp650.000 per tim, di luar biaya nomor perorangan. Hanya Level 1–6 (sesuai Piala Beregu di lampiran medali; daftar level diatur di pengaturan `team_levels`). Satu pendaftaran boleh berisi beberapa tim; satu tim = satu level (kelompok usia boleh campur), 1–6 pesenam. Satu klub boleh beberapa tim per level dengan nama berbeda. Klub juga boleh mengirim pendaftaran yang hanya berisi tim. Beregu Level 6 berjalan bila peminat cukup.
- Setiap anggota dipilih sebagai **Atlet di pendaftaran ini** (atlet di langkah sebelumnya yang memilih kategori di level tim), **Terdaftar sebelumnya** (sudah didaftarkan klub yang sama di level itu lewat pendaftaran sebelumnya; dicocokkan dari nama dan tanggal lahir; tidak tersedia untuk klub baru), atau **Khusus beregu** (data lengkap + dokumen; dinilai di kelompok usianya tetapi tidak diperingkat perorangan; biaya sudah termasuk biaya tim; dapat AIC sendiri; dihitung dalam batas 10 atlet).
- Tagihan memisahkan *Biaya pendaftaran* (nomor perorangan/pasangan) dan *Biaya beregu*; Ledger juga memisahkannya.
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

**Klub**: formulir pendaftaran menampilkan daftar klub yang bisa digulir dan disaring (53 klub dari daftar klub senam Indonesia sudah dimuat, ditambah klub yang dibuat pendaftar). Pendaftar tetap bisa memilih *Klub saya belum ada di daftar*. Di Konsol → Klub, admin ke atas bisa *Ubah*, lalu dari menu "…" *Gabungkan ke klub lain* (untuk salah ketik; semua pendaftaran pindah ke klub tujuan) atau *Hapus klub* (hanya klub yang belum dipakai pendaftaran).

**Chat panitia** (Konsol → Chat panitia): ruang *Semua panitia*, ruang per disiplin (*Tim Artistik Putri* dst.; pemegang kode satu disiplin hanya melihat ruangnya), dan pesan pribadi antarpemegang kode. Pesan baru muncul otomatis; lencana di menu menunjukkan pesan belum dibaca.

**Laporan masalah** (Konsol → Laporan masalah): siapa pun bisa melaporkan kendala dengan judul, penjelasan, dan tangkapan layar. Admin disiplin terkait, superadmin, dan owner mengubah status *Baru → Diproses → Selesai* dan menanggapi; pelapor mendapat lencana saat ada tanggapan. TD bisa melihat dan menanggapi tetapi tidak mengubah status.

**Kontak** (Konsol → Kontak): nomor WhatsApp semua pemegang kode dan narahubung disiplin, dengan tombol *WhatsApp* dan *Chat*. Tab *Pendaftar* (pelatih, manajer, orang tua) hanya untuk admin ke atas dan TD, sesuai disiplinnya; bisa diunduh Excel. Setiap pemegang kode mengisi nomor WA-nya sendiri lewat tombol *Lengkapi nomor WA* atau klik inisial di kanan atas; superadmin juga bisa mengisinya di Kode akses.

**Pendaftaran juri** (Konsol → Pendaftaran juri, admin ke atas): calon juri mendaftar di `juri.html` (tautan di bagian Kontak dan footer situs): nama, WA, email, kota, disiplin dan tingkat brevet per disiplin (FIG Kategori 1–4, Nasional, Provinsi/Daerah, Belum ada, atau Lainnya), hari tersedia 12–20 Desember, KTP, pas foto, sertifikat brevet (opsional). Pendaftar menerima email konfirmasi. Admin bisa juga *Tambah juri* manual. *Setujui* → pilih disiplin dan batasan alat/komponen → kode akses juri dibuat dan tampil sekali, dengan tombol *Kirim ke WhatsApp* ke nomor pendaftar. Email persetujuan tidak memuat kode. *Tolak* mengirim email dengan pesan opsional.

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

## 8. Revisi 14 Oktober 2026 (versi 5)

- **Priangan** hanya di Ritmik, sebagai kategori tersendiri di bawah Amatir: Ritmik Profesional, Ritmik Amatir, Ritmik Priangan (KU 5–6, 7–8, 9–10, 11–12, Junior), Rp750.000, tanpa biaya tambahan. Syarat: atlet WNI dengan alamat identitas di Jawa Barat dan klub di Jawa Barat (asal penanggung jawab/pelatih tidak berpengaruh). Satu atlet satu level. Admin menandai "Memenuhi / Tidak memenuhi" di halaman pendaftaran; bila tidak memenuhi, pindahkan ke Amatir. Tabel medali Priangan = kategori Ritmik Priangan saja. Priangan di Artistik dihapus.
- **Junior Ritmik**: kelahiran 2011–2013 (13–15 tahun).
- **Musik Ritmik**: satu tautan Google Drive per nomor (mis. KU 9–10: Tanpa Alat, Simpai, Bola; Junior: Simpai, Bola, Gada, Pita), semua wajib saat daftar. Ganti satu kali per atlet (boleh beberapa nomor sekaligus) sampai start list terbit, lewat `musik.html`.
- **Dokumen atlet** diunggah terpisah: Akte Kelahiran (wajib), KTP dan Ijazah (bila ada), BPJS Ketenagakerjaan (opsional saat daftar; bila tidak diunggah, wajib dibawa ke meja panitia di venue, tanpa unggah susulan), pas foto (wajib). Atlet WNA: paspor dan pas foto. Atlet tanpa BPJS ditandai di konsol, email, halaman status, dan AIC.
- **Pas foto & AIC**: pas foto wajib (wajah jelas, bukan swafoto, bukan pose santai). Kartu atlet sekarang bernama **Athlete Identification Card (AIC) Jabar Open 2026**, memuat pas foto dan "Didaftarkan oleh". Ditunjukkan dalam bentuk digital di venue, tidak dicetak. Memindai QR di AIC membuka halaman verifikasi yang menampilkan pas foto, data atlet, dan nama pendaftar. AIC tersedia setelah pembayaran lunas.
- **Batas 15 menit**: pendaftaran QRIS tanpa bukti bayar dihapus otomatis 15 menit setelah dikirim (tanpa email). Formulir dan halaman status menampilkan hitung mundur. Setelah bukti diunggah, pendaftaran aman walau belum diverifikasi. Atlet WNA tidak terkena aturan ini.
- **Hapus data (owner & superadmin)**: hapus pendaftaran permanen (halaman pendaftaran), hapus atlet (Data atlet atau halaman pendaftaran; tagihan dihitung ulang bila belum lunas), hapus pendaftar juri, laporan masalah, dan pesan chat. Semua tercatat di Log (hanya owner & superadmin). Berkasnya ikut dihapus. Pengaturan → Berkas tak terpakai membersihkan berkas sisa (mis. dari pendaftaran yang kedaluwarsa).
- **Juri**: satu disiplin saja (Artistik Putra, Artistik Putri, atau Ritmik; Aerobik tidak membuka pendaftaran juri), tanpa bagian ketersediaan, kartu BPJS Ketenagakerjaan wajib.
- **Klub**: BJS Gymnastic (sekolah/klub, Jawa Barat) ditambahkan ke daftar.

## 9. Revisi 15 Oktober 2026 (versi 6)

- **AIC hanya saat lunas**: sebelum lunas, tombol *Unduh AIC* di halaman status terkunci dengan alasan (unggah bukti bayar / sedang diverifikasi / bukti perlu diperbaiki / menunggu konfirmasi panitia untuk atlet WNA). Email *Pembayaran lunas* memuat tautan *Unduh AIC* per atlet yang langsung mengunduh PDF, plus *Unduh semua AIC (1 PDF)* bila atletnya lebih dari satu. Halaman status juga punya tombol *Unduh semua AIC*.
- **FAQ situs**: halaman `faq.html` dan bagian FAQ di beranda (sebelum Kontak), dengan pencarian, tab kategori, ID/EN (bila versi Inggris kosong, tampil teks Indonesia), dan tautan per pertanyaan (`faq.html#<tautan>`, tombol *Salin tautan*) untuk membalas pertanyaan lewat WhatsApp. Menu FAQ dan bagian beranda baru muncul setelah ada minimal satu pertanyaan *Terbit*.
- **Konsol → FAQ situs** (owner, superadmin, admin): *Tambah pertanyaan*, *Ubah* (dengan pratinjau langsung), panah urutan, dan menu "…": *Terbitkan*, *Jadikan draf*, *Arsipkan* / *Pulihkan*, *Salin tautan*. Tidak ada hapus permanen. *Kelola kategori*: ganti nama ID/EN, urutan tab, aktif/nonaktif, tambah kategori. Semua perubahan tercatat di Log. Format jawaban: baris kosong = paragraf, baris diawali "- " = daftar, `**tebal**`, `[teks](tautan)`.
- **Draf awal**: 31 pertanyaan dalam 7 kategori (Umum, Pendaftaran & Kategori, Pembayaran, Dokumen Atlet, Musik Ritmik, Hari Pertandingan & AIC, Juri), semuanya berstatus Draf sampai ditinjau dan diterbitkan. Belum ditulis karena aturannya belum ditetapkan: refund/pembatalan, musik lantai Artistik Putri Level 1–3, tiket penonton dan akses pendamping, lama verifikasi pembayaran.

## 10. Revisi 15 Oktober 2026 (versi 7)

- **Jam tugas juri**: di Kode akses (Buat kode baru / Ubah, peran Juri) dan saat menyetujui pendaftar juri, isi *Jam tugas (WIB)*: tambah hari, lalu jam mulai dan selesai untuk tiap hari. Di luar jam itu juri tetap bisa masuk dan melihat lembar nilai, tetapi kolom nilai terkunci dan sistem menolak penyimpanan nilai, dengan keterangan jam tugas berikutnya. Kosongkan bila juri boleh mengisi kapan saja. Daftar Kode akses menampilkan jam tugas dan status *sedang bertugas* / *di luar jam*. Chat, laporan masalah, dan kontak tetap bisa dipakai juri di luar jam.
- **Peran Pemantau**: kode hanya-baca untuk halaman pertandingan (lihat tabel peran). Dibuat dari Kode akses → Peran *Pemantau*.
- **Konsol di ponsel**: tabel tampil sebagai kartu berlabel; tombol aksi di bawah kartu; filter dan tombol selebar layar. Di desktop tinggi tombol dan kolom isian sejajar.
