/* Jabar Open 2026 — formulir pendaftaran */
(function () {
  'use strict';
  const { t, esc, fmtRp, rpc } = JO;
  const R = window.JO_REGIONS;

  JO.addDict({
    d_title: ['Pendaftaran atlet', 'Athlete registration'],
    d_lead: ['Semua atlet didaftarkan lewat klub (klub, sekolah, atau pengkab/pengkot) oleh pemilik, admin, atau pelatih klub. Satu pendaftaran untuk satu disiplin, maksimal 10 atlet. Tim beregu Artistik Putri ditambahkan di pendaftaran yang sama.', "Every athlete is registered through a club (club, school or regency/city association) by the club's owner, admin or coach. One registration covers one discipline, up to 10 athletes. Women's Artistic teams are added in the same registration."],
    d_ready_t: ['Siapkan sebelum mendaftar', 'Have this ready'],
    d_ready: ['Akte Kelahiran atlet (wajib), KTP dan Ijazah bila sudah punya, kartu BPJS Ketenagakerjaan bila ada (wajib saat bertanding), data orang tua/wali untuk atlet di bawah 18 tahun. Atlet asing: paspor. Ritmik: satu tautan Google Drive musik untuk setiap nomor. Siapkan juga pembayaran QRIS: bukti bayar harus diunggah dalam 15 menit setelah mendaftar.', "Athlete's birth certificate (required), national ID and school certificate if they have them, BPJS Ketenagakerjaan card if available (required on competition day), parent/guardian details for athletes under 18. Foreign athletes: passport. Rhythmic: one Google Drive music link per routine. Have your QRIS payment ready: the payment proof must be uploaded within 15 minutes of registering."],
    st_team: ['Beregu', 'Team'],
    tm_intro: ['Opsional. Tambahkan tim beregu Artistik Putri bila klub ikut nomor beregu. Satu tim berisi 1–{n} pesenam dari satu level, {fee} per tim. Tidak ikut beregu? Langsung tekan Lanjut.', "Optional. Add a Women's Artistic team if the club enters the team event. One team has 1–{n} gymnasts from one level, {fee} per team. Not entering a team? Just press Continue."],
    add_team: ['Tambah tim beregu', 'Add a team'], rm_team: ['Hapus tim', 'Remove team'], tm_n: ['Tim {n}', 'Team {n}'],
    tm_title: ['Tim', 'Team'], tm_level: ['Level', 'Level'], tm_name: ['Nama tim', 'Team name'], tm_name_ph: ['mis. {c} A', 'e.g. {c} A'],
    tm_hint: ['Satu tim untuk satu level; kelompok usia boleh campur. Satu klub boleh mengirim beberapa tim di level yang sama dengan nama berbeda.', 'One team per level; age groups can be mixed. A club may enter several teams in the same level under different names.'],
    tm_rule: ['Nilai tim adalah jumlah {k} nilai serba bisa terbaik dari anggotanya. Biaya {fee} per tim, di luar biaya perorangan.', 'The team score is the sum of the best {k} all-around scores among its members. {fee} per team, on top of individual fees.'],
    mb: ['Pesenam {n}', 'Gymnast {n}'], add_mb: ['Tambah pesenam', 'Add gymnast'],
    mb_kind: ['Pesenam ini', 'This gymnast is'], kind_form: ['Atlet di pendaftaran ini', 'An athlete in this registration'], kind_individu: ['Terdaftar sebelumnya', 'Registered earlier'], kind_tim: ['Khusus beregu', 'Team only'],
    mb_form_hint: ['Juga ikut perorangan. Pilih atlet yang di langkah Atlet memilih kategori di level tim ini.', "Also competes individually. Choose an athlete who picked a category in this team's level in the Athletes step."],
    mb_form_pick: ['Pilih atlet', 'Choose athlete'], mb_form_none: ['Belum ada atlet di pendaftaran ini dengan kategori {l}.', 'No athlete in this registration has a {l} category yet.'],
    mb_individu_hint: ['Juga ikut perorangan, dan sudah didaftarkan klub ini di level yang sama lewat pendaftaran sebelumnya. Tulis nama dan tanggal lahir persis seperti di pendaftaran itu.', 'Also competes individually, and was entered by this club in the same level in an earlier registration. Enter the name and date of birth exactly as in that registration.'],
    mb_tim_hint: ['Tidak ikut peringkat perorangan. Nilainya dihitung untuk tim, biayanya sudah termasuk biaya beregu, dan ia dihitung dalam batas {max} atlet.', 'Not ranked individually. Their scores count for the team, the team fee covers them, and they count toward the {max}-athlete limit.'],
    mb_new_club: ['Klub baru belum punya pendaftaran sebelumnya, jadi pilihan "Terdaftar sebelumnya" tidak tersedia.', 'A new club has no earlier registrations, so "Registered earlier" is not available.'],
    err_mb_form: ['Pilih atlet.', 'Choose an athlete.'],
    err_mb_inform: ['Atlet ini sudah ada di langkah Atlet. Pilih "Atlet di pendaftaran ini".', 'This athlete is already in the Athletes step. Choose "An athlete in this registration".'],
    mb_cat: ['Kelompok usia: {c}', 'Age group: {c}'],
    mb_cat_none: ['Tidak ada kelompok usia di level ini yang sesuai dengan tanggal lahir.', 'No age group in this level matches the date of birth.'],
    mb_found: ['Ditemukan di pendaftaran perorangan klub ini.', "Found in this club's individual registrations."],
    err_tm_level: ['Pilih level.', 'Choose a level.'], err_tm_name: ['Isi nama tim.', 'Enter a team name.'],
    err_mb_kind: ['Pilih "Juga perorangan" atau "Khusus beregu".', 'Choose "Also individual" or "Team only".'],
    err_mb_notfound: ['Belum ditemukan di pendaftaran sebelumnya klub ini pada level tersebut. Periksa ejaan nama dan tanggal lahir, tambahkan dia sebagai atlet di pendaftaran ini, atau pilih "Khusus beregu".', "Not found in this club's earlier registrations at this level. Check the spelling and date of birth, add them as an athlete in this registration, or choose \"Team only\"."],
    err_mb_inteam: ['Atlet ini sudah masuk tim lain.', 'This athlete is already in another team.'],
    err_mb_isind: ['Atlet ini sudah punya kategori perorangan di level ini. Pilih "Terdaftar sebelumnya".', 'This athlete already has an individual category in this level. Choose "Registered earlier".'],
    err_mb_dup: ['Pesenam ini tercantum dua kali.', 'This gymnast is listed twice.'],
    err_mb_cat: ['Tidak ada kelompok usia yang sesuai di level ini.', 'No matching age group in this level.'],
    checking: ['Memeriksa…', 'Checking…'],
    sum_team: ['Biaya beregu', 'Team fee'],
    sum_member_ind: ['juga perorangan', 'also individual'], sum_member_tim: ['khusus beregu', 'team only'], sum_member_prev: ['juga perorangan, pendaftaran sebelumnya', 'also individual, earlier registration'],
    music: ['Tautan musik per nomor (Google Drive)', 'Music link per routine (Google Drive)'],
    music_hint: ['Satu tautan Google Drive (file MP3 atau folder) untuk setiap nomor, semua wajib diisi. Atur akses ke "Siapa saja yang memiliki link". Musik bisa diganti satu kali per atlet sebelum start list terbit.', 'One Google Drive link (MP3 file or folder) for each routine; all are required. Set access to "Anyone with the link". Music can be changed once per athlete before the start list is published.'],
    music_pick: ['Pilih kategori dulu untuk melihat nomor yang perlu musik.', 'Choose a category first to see which routines need music.'],
    err_music: ['Isi tautan Google Drive (diawali https://drive.google.com/).', 'Enter a Google Drive link (starting with https://drive.google.com/).'],
    st1: ['Pendaftar', 'Registrant'], st2: ['Klub', 'Club'], st3: ['Atlet & kategori', 'Athletes & categories'], st4: ['Pernyataan & kirim', 'Declarations & submit'],
    ath_count: ['{n} dari {max} atlet di pendaftaran ini (termasuk anggota khusus beregu).', '{n} of {max} athletes in this registration (including team-only members).'],
    ath_full: ['Batas {max} atlet per pendaftaran tercapai. Daftarkan atlet lainnya sebagai pendaftaran terpisah.', 'The limit of {max} athletes per registration is reached. Register the others in a separate registration.'],
    ath_empty: ['Belum ada atlet perorangan. Tambahkan atlet, atau tekan Lanjut untuk mendaftarkan tim beregu saja.', 'No individual athletes yet. Add an athlete, or press Continue to register a team only.'],
    err_none: ['Tambahkan minimal satu atlet atau satu tim beregu.', 'Add at least one athlete or one team.'],
    err_max: ['Satu pendaftaran maksimal {max} atlet, termasuk anggota khusus beregu. Kurangi atlet atau kirim sebagai pendaftaran terpisah.', 'One registration has at most {max} athletes, including team-only members. Remove some or send them in a separate registration.'],
    form_old: ['Formulir sedang diperbarui panitia. Coba lagi beberapa menit lagi.', 'The committee is updating the form. Please try again in a few minutes.'],
    next: ['Lanjut', 'Continue'], back: ['Kembali', 'Back'],
    q_disc: ['Disiplin', 'Discipline'],
    disc_closed: ['Pendaftaran ditutup', 'Registration closed'],
    q_contact: ['Penanggung jawab dari klub', 'Club contact'],
    q_contact_hint: ['Pendaftaran hanya lewat klub: diisi pemilik, admin, pelatih, atau official klub. Konfirmasi, tagihan, dan AIC dikirim ke email ini.', "Registration is through clubs only: filled in by the club's owner, admin, coach or official. Confirmation, invoice and AIC are sent to this email."],
    c_name: ['Nama lengkap', 'Full name'], c_email: ['Email', 'Email'], c_phone: ['Nomor WhatsApp', 'WhatsApp number'], c_role: ['Peran di klub', 'Role in the club'],
    role_pemilik: ['Pemilik klub', 'Club owner'], role_admin: ['Admin klub', 'Club admin'], role_pelatih: ['Pelatih', 'Coach'], role_manajer: ['Manajer / official', 'Manager / official'], role_lainnya: ['Lainnya', 'Other'],
    err_role: ['Pilih peran Anda di klub.', 'Choose your role in the club.'], err_disc: ['Pilih disiplin.', 'Choose a discipline.'],
    err_name: ['Isi nama lengkap.', 'Enter a full name.'], err_email: ['Isi email yang valid.', 'Enter a valid email.'], err_phone: ['Isi nomor WhatsApp yang valid.', 'Enter a valid WhatsApp number.'],
    q_club: ['Klub, sekolah, atau pengkab', 'Club, school or regency'],
    q_club_hint: ['Semua atlet didaftarkan lewat klub. Ketik untuk mencari; bila belum ada, tambahkan klub baru. Klub dipakai untuk tabel medali dan batas peserta per klub.', 'Every athlete is registered through a club. Type to search; if it is not listed, add it as a new club. The club is used for the medal table and per-club entry limits.'],
    club_search: ['Cari nama klub atau kota', 'Search club or city'],
    club_count: ['{n} klub di daftar. Pilih dari daftar, atau ketik untuk menyaring.', '{n} clubs listed. Pick from the list, or type to filter.'],
    club_found: ['{n} klub cocok.', '{n} matching clubs.'],
    club_new: ['Klub saya belum ada di daftar', 'My club is not listed'],
    club_selected: ['Terpilih', 'Selected'], club_change: ['Ganti', 'Change'],
    club_name: ['Nama klub / sekolah', 'Club / school name'], club_kind: ['Jenis', 'Type'],
    kind_klub: ['Klub', 'Club'], kind_sekolah: ['Sekolah', 'School'], kind_pengkab: ['Pengkab / pengkot', 'Regency / city association'], kind_lainnya: ['Lainnya', 'Other'],
    in_indonesia: ['Di Indonesia', 'In Indonesia'], abroad: ['Luar negeri', 'Abroad'],
    province: ['Provinsi', 'Province'], kabkota: ['Kabupaten / kota', 'Regency / city'], country: ['Negara', 'Country'],
    choose: ['Pilih…', 'Choose…'],
    err_club: ['Pilih klub atau tambahkan klub baru.', 'Choose a club or add a new one.'],
    err_club_new: ['Lengkapi nama klub, provinsi, dan kabupaten/kota.', 'Complete the club name, province and regency/city.'],
    no_match: ['Tidak ada yang cocok. Tambahkan sebagai klub baru.', 'No match. Add it as a new club.'],
    ath: ['Atlet {n}', 'Athlete {n}'], add_ath: ['Tambah atlet', 'Add athlete'], remove: ['Hapus', 'Remove'],
    a_name: ['Nama lengkap sesuai identitas', 'Full name as on ID'], a_gender: ['Jenis kelamin', 'Sex'],
    a_birth: ['Tanggal lahir', 'Date of birth'], a_birth_hint: ['Kategori ditentukan dari tahun lahir (usia pada tahun 2026).', 'Categories follow the birth year (age in 2026).'],
    a_nat: ['Kewarganegaraan', 'Nationality'], wni: ['WNI', 'Indonesian'], wna: ['WNA', 'Foreign'],
    a_addr_hint: ['Sesuai alamat pada identitas. Dipakai untuk kelayakan kategori Priangan.', 'As on the ID. Used for Priangan category eligibility.'],
    a_docs: ['Dokumen (unggah satu per satu; foto atau PDF, maks. 5 MB)', 'Documents (upload one by one; photo or PDF, max 5 MB)'],
    d_akte: ['Akte Kelahiran (wajib)', 'Birth certificate (required)'],
    d_ktp: ['KTP (bila sudah punya)', 'National ID / KTP (if they have one)'],
    d_ijazah: ['Ijazah (bila ada)', 'School certificate / Ijazah (if any)'],
    d_passport: ['Paspor (wajib)', 'Passport (required)'],
    d_bpjs: ['BPJS Ketenagakerjaan (opsional saat daftar)', 'BPJS Ketenagakerjaan (optional now)'],
    d_photo: ['Pas foto (wajib)', 'Photo (required)'],
    photo_rules_t: ['Ketentuan pas foto', 'Photo rules'],
    photo_rules: ['Wajah menghadap ke depan dan terlihat jelas, latar polos, pakaian rapi, setengah badan (kepala sampai dada). Bukan swafoto (selfie), bukan pose santai atau bergaya, tanpa kacamata hitam, topi, atau filter. Foto ini dipasang di Athlete Identification Card (AIC) dan tampil saat panitia memindai QR di venue.', 'Face looking straight at the camera and clearly visible, plain background, neat clothing, head-and-shoulders framing. No selfies, no casual or posed shots, no sunglasses, hats or filters. This photo goes on the Athlete Identification Card (AIC) and appears when the committee scans its QR code at the venue.'],
    photo_ok: ['Benar', 'Correct'], photo_no1: ['Swafoto', 'Selfie'], photo_no2: ['Pose santai / miring', 'Casual / side pose'],
    err_a_photo: ['Unggah pas foto.', 'Upload a photo.'],
    d_bpjs_note: ['Wajib saat bertanding. Bila belum diunggah sekarang, bawa kartu BPJS Ketenagakerjaan ke meja panitia di venue; tidak ada unggah susulan.', 'Required on competition day. If not uploaded now, bring the BPJS Ketenagakerjaan card to the committee desk at the venue; it cannot be uploaded later.'],
    up_btn: ['Unggah', 'Upload'],
    jabar_only: ['Khusus atlet WNI beralamat di Jawa Barat dari klub di Jawa Barat. Tanpa biaya tambahan.', 'Only for Indonesian athletes with a West Java address, from a West Java club. No extra fee.'],
    uploading: ['Mengunggah…', 'Uploading…'], uploaded: ['Terunggah', 'Uploaded'], replace: ['Ganti berkas', 'Replace file'],
    g_title: ['Orang tua / wali', 'Parent / guardian'], g_hint: ['Wajib untuk atlet di bawah 18 tahun.', 'Required for athletes under 18.'],
    g_name: ['Nama orang tua / wali', 'Parent / guardian name'], g_phone: ['WhatsApp orang tua / wali', 'Parent / guardian WhatsApp'], g_email: ['Email orang tua / wali', 'Parent / guardian email'], g_rel: ['Hubungan', 'Relationship'],
    cat_title: ['Kategori', 'Category'],
    cat_need: ['Isi jenis kelamin dan tanggal lahir untuk melihat kategori yang sesuai.', 'Enter sex and date of birth to see matching categories.'],
    cat_age: ['Usia 2026: {a} tahun', 'Age in 2026: {a}'],
    cat_off: ['{n} kategori lain tidak sesuai usia atau jenis kelamin', '{n} other categories do not match age or sex'],
    cat_none: ['Tidak ada kategori di disiplin ini yang sesuai dengan usia dan jenis kelamin atlet. Periksa tanggal lahir, atau hubungi panitia.', 'No category in this discipline matches the athlete\'s age and sex. Check the date of birth or contact the committee.'],
    why_gender_M: ['khusus putra', 'men only'], why_gender_F: ['khusus putri', 'women only'],
    why_min: ['kelahiran {y} ke atas', 'born {y} or later'], why_max: ['kelahiran {y} ke bawah', 'born {y} or earlier'],
    pri_no: ['Priangan hanya untuk atlet WNI beralamat (sesuai identitas) di Jawa Barat dari klub di Jawa Barat.', 'Priangan is only for Indonesian athletes with a West Java address on their ID, from a West Java club.'],
    pri_no_ath: ['Isi alamat atlet di Jawa Barat (provinsi pada identitas) untuk memilih Priangan.', "Set the athlete's ID address to West Java to choose Priangan."],
    pri_no_club: ['Klub yang dipilih bukan dari Jawa Barat, jadi Priangan tidak bisa dipilih. Penanggung jawab (pelatih/manajer) boleh dari mana saja.', 'The chosen club is not from West Java, so Priangan is not available. The contact person (coach/manager) may be from anywhere.'],
    pri_no_wna: ['Priangan hanya untuk atlet WNI.', 'Priangan is only for Indonesian athletes.'],
    pair_title: ['Nomor pasangan campuran (MP)', 'Mixed pair (MP)'],
    pair_hint: ['Opsional. Pasangan terdiri dari satu putra dan satu putri dari atlet di pendaftaran ini. Biaya {fee} per pasangan.', 'Optional. A pair is one man and one woman from the athletes in this registration. Fee {fee} per pair.'],
    pair_add: ['Tambah pasangan', 'Add pair'], pair_m: ['Atlet putra', 'Male athlete'], pair_f: ['Atlet putri', 'Female athlete'],
    pair_need: ['Tambahkan minimal satu atlet putra dan satu atlet putri untuk membuat pasangan.', 'Add at least one male and one female athlete to form a pair.'],
    err_a_name: ['Isi nama lengkap atlet.', 'Enter the athlete\'s full name.'], err_a_gender: ['Pilih jenis kelamin.', 'Choose sex.'],
    err_a_birth: ['Isi tanggal lahir.', 'Enter date of birth.'], err_a_addr: ['Pilih provinsi dan kabupaten/kota.', 'Choose province and regency/city.'],
    err_a_country: ['Isi negara.', 'Enter country.'], err_a_doc: ['Unggah Akte Kelahiran.', 'Upload the birth certificate.'], err_a_pass: ['Unggah paspor.', 'Upload the passport.'],
    err_a_cat: ['Pilih kategori.', 'Choose a category.'], err_g: ['Lengkapi nama, WhatsApp, dan email orang tua/wali.', 'Complete parent/guardian name, WhatsApp and email.'],
    err_pair: ['Lengkapi kategori, atlet putra, dan atlet putri untuk setiap pasangan.', 'Complete category, male and female athlete for each pair.'],
    err_pair_age: ['Pasangan {c}: {n} tidak sesuai usia kategori.', 'Pair {c}: {n} does not fit the category age.'],
    err_uploading: ['Tunggu sampai semua berkas selesai diunggah.', 'Wait until all files finish uploading.'],
    err_fix: ['Periksa isian yang ditandai merah.', 'Check the fields marked in red.'],
    cons_title: ['Pernyataan', 'Declarations'],
    cons_waiver: ['Saya memahami bahwa gimnastik memiliki risiko cedera fisik, termasuk cedera serius yang dapat berakibat fatal. Panitia menyiapkan tenaga medis dan penanganan darurat, dan saya/atlet mengikuti kejuaraan atas tanggung jawab sendiri.', 'I understand gymnastics carries a risk of physical injury, including serious injury that can be fatal. The committee provides medical staff and emergency response, and I/the athlete take part at our own risk.'],
    cons_insurance: ['Saya memahami bahwa panitia hanya memberikan pertolongan pertama. Biaya perawatan lanjutan menjadi tanggung jawab peserta atau delegasi, dan peserta wajib memiliki BPJS atau asuransi sesuai Undangan.', 'I understand the committee only provides first aid. Further treatment costs are the participant\'s or delegation\'s responsibility, and participants must hold BPJS or insurance as stated in the Invitation.'],
    cons_data: ['Saya menyetujui panitia mengolah data pribadi dan dokumen identitas hanya untuk keperluan kejuaraan (verifikasi usia, start list, hasil, sertifikat), sesuai UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi. Nama, klub, dan hasil atlet dipublikasikan; tanggal lahir dan dokumen tidak. Dokumen identitas dihapus setelah kejuaraan selesai.', 'I agree the committee may process personal data and identity documents only for this championship (age checks, start lists, results, certificates), under Indonesian Law No. 27 of 2022 on Personal Data Protection. Athlete name, club and results are published; birth dates and documents are not. Identity documents are deleted after the championship.'],
    cons_rules: ['Saya telah membaca ketentuan Jabar Open 2026 (kategori, biaya, jadwal) dan menerima keputusan juri dan panitia.', 'I have read the Jabar Open 2026 rules (categories, fees, schedule) and accept the decisions of the judges and committee.'],
    cons_guardian: ['Klub telah mendapat persetujuan orang tua/wali dari setiap atlet di bawah 18 tahun dalam pendaftaran ini untuk keikutsertaan dan pengolahan data anak tersebut.', 'The club has the consent of the parent/guardian of every under-18 athlete in this registration for their participation and the processing of their data.'],
    err_cons: ['Centang semua pernyataan untuk melanjutkan.', 'Tick all declarations to continue.'],
    sum_title: ['Ringkasan biaya', 'Fee summary'],
    sum_fees: ['Biaya pendaftaran', 'Entry fees'], sum_pri: ['Kategori Priangan', 'Priangan category'],
    sum_uc: ['Kode unik', 'Unique code'], sum_uc_val: ['ditambahkan setelah kirim (Rp1–Rp999)', 'added after submitting (Rp1–Rp999)'],
    sum_total: ['Perkiraan total', 'Estimated total'],
    sum_intl: ['Ada atlet WNA: pembayaran dilakukan terpisah. Panitia akan menghubungi Anda lewat email.', 'Includes a foreign athlete: payment is handled separately. The committee will contact you by email.'],
    sum_cap: ['Total melebihi batas satu transaksi QRIS ({cap}). Bagi atlet ke dalam dua pendaftaran.', 'The total exceeds the single QRIS transaction limit ({cap}). Split the athletes into two registrations.'],
    submit: ['Kirim pendaftaran', 'Submit registration'], submitting: ['Mengirim…', 'Submitting…'],
    done_title: ['Pendaftaran terkirim', 'Registration submitted'],
    done_code: ['Kode pendaftaran', 'Registration code'],
    done_email: ['Rincian dan tautan halaman status dikirim ke {e}. Periksa juga folder spam.', 'Details and the status page link were sent to {e}. Check your spam folder too.'],
    pay_title: ['Bayar dengan QRIS', 'Pay with QRIS'],
    pay_exact: ['Ketik nominal persis, termasuk tiga digit terakhir.', 'Type the exact amount, including the last three digits.'],
    pay_why: ['Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Transfer dengan nominal berbeda akan memperlambat verifikasi.', 'The last three digits are a unique code that matches your payment to this registration. A different amount slows down verification.'],
    pay_steps: ['1. Buka aplikasi bank atau dompet digital, pilih Scan QRIS.<br>2. Pindai kode QRIS ini dan ketik nominal di atas.<br>3. Simpan bukti bayar, lalu unggah di bawah.', '1. Open your banking or e-wallet app and choose Scan QRIS.<br>2. Scan this QRIS and type the amount above.<br>3. Save the receipt and upload it below.'],
    pay_noqris: ['Gambar QRIS sedang disiapkan panitia. Buka halaman status nanti, atau tunggu email dari panitia.', 'The QRIS image is being prepared. Check the status page later or wait for an email from the committee.'],
    pay_deadline: ['Batas pembayaran: {d}', 'Payment deadline: {d}'],
    pay_intl: ['Atlet internasional membayar terpisah. Panitia akan menghubungi {e} dengan instruksi pembayaran.', 'International athletes pay separately. The committee will contact {e} with payment instructions.'],
    proof_title: ['Unggah bukti pembayaran', 'Upload payment proof'],
    proof_hint: ['Tangkapan layar atau foto struk dari aplikasi.', 'A screenshot or photo of the receipt.'],
    timer_t: ['Unggah bukti bayar dalam {m}', 'Upload the payment proof within {m}'],
    timer_d: ['Pendaftaran tanpa bukti bayar dihapus otomatis 15 menit setelah dikirim (pukul {h}). Setelah bukti terunggah, pendaftaran aman walau belum diverifikasi panitia.', 'Registrations without a payment proof are deleted automatically 15 minutes after submitting (at {h}). Once the proof is uploaded, the registration is safe even before the committee verifies it.'],
    timer_over: ['Waktu 15 menit sudah habis. Bila bukti belum terunggah, pendaftaran ini dihapus; silakan daftar ulang.', 'The 15 minutes have passed. If no proof was uploaded, this registration has been deleted; please register again.'],
    sum_15: ['Setelah dikirim, Anda punya 15 menit untuk membayar lewat QRIS dan mengunggah bukti bayar. Bila tidak, pendaftaran dihapus otomatis.', 'After submitting you have 15 minutes to pay by QRIS and upload the payment proof. Otherwise the registration is deleted automatically.'],
    sum_bpjs: ['Tanpa BPJS Ketenagakerjaan: {n}. Bawa kartunya ke meja panitia di venue sebelum bertanding.', 'No BPJS Ketenagakerjaan uploaded: {n}. Bring the card to the committee desk at the venue before competing.'],
    proof_done: ['Bukti terkirim. Panitia akan memverifikasi dan mengirim AIC lewat email.', 'Proof received. The committee will verify it and email the AIC.'],
    open_status: ['Buka halaman status', 'Open status page'], register_more: ['Daftarkan atlet lain dari klub ini', 'Register more athletes from this club'],
    closed: ['Pendaftaran sedang ditutup.', 'Registration is currently closed.'],
    load_fail: ['Formulir tidak bisa dimuat.', 'The form could not be loaded.'], retry: ['Coba lagi', 'Try again'],
    draft_restored: ['Isian sebelumnya dipulihkan. Berkas perlu diunggah ulang.', 'Your previous answers were restored. Files need to be uploaded again.'],
  });

  let CFG = null;
  const S = {
    step: 1, type: 'klub', discipline: null,
    contact: { name: '', email: '', phone: '', role: '' },
    club: { mode: null, id: null, label: '', name: '', kind: 'klub', province: '', kab_kota: '', country: 'Indonesia', abroad: false },
    athletes: [], pairs: [], consents: {}, result: null,
    teams: [],
  };
  let seq = 0;
  const DOC_KINDS = ['akte', 'ktp', 'ijazah', 'passport', 'bpjs', 'photo'];
  const noDocs = () => ({ akte: null, ktp: null, ijazah: null, passport: null, bpjs: null, photo: null });
  const newAthlete = () => ({ key: 'a' + (++seq), full_name: '', gender: '', birth_date: '', nationality: 'WNI', country: '', province: '', kab_kota: '',
    ...noDocs(), uploading: 0, guardian: { name: '', phone: '', email: '', relation: '' }, cat: null, music: {} });
  const newMember = (T) => ({ key: 'm' + (++seq), kind: formChoices(T, null).length ? 'form' : 'tim', ref: '', full_name: '', birth_date: '', nationality: 'WNI', country: '',
    ...noDocs(), uploading: 0, guardian: { name: '', phone: '', email: '', relation: '' } });
  const newTeam = () => ({ key: 't' + (++seq), level: '', name: '', members: [] });
  const docPaths = (o) => (o.nationality === 'WNA'
    ? { passport_path: o.passport && o.passport.path, photo_path: o.photo && o.photo.path, photo_thumb: o.photo && o.photo.thumb }
    : { akte_path: o.akte && o.akte.path, ktp_path: o.ktp && o.ktp.path, ijazah_path: o.ijazah && o.ijazah.path,
        bpjs_path: o.bpjs && o.bpjs.path, photo_path: o.photo && o.photo.path, photo_thumb: o.photo && o.photo.thumb });
  const docsOk = (o) => (o.nationality === 'WNA' ? !!o.passport : !!o.akte);
  const docErr = (o) => (!docsOk(o) ? [o.nationality === 'WNA' ? '.up-passport' : '.up-akte', o.nationality === 'WNA' ? 'err_a_pass' : 'err_a_doc']
    : !o.photo ? ['.up-photo', 'err_a_photo'] : null);
  const teamLevels = () => (CFG && CFG.registration.team_levels) || { WAG: ['Level 1', 'Level 2', 'Level 3', 'Level 4', 'Level 5', 'Level 6'] };
  const teamOK = (d) => Object.prototype.hasOwnProperty.call(teamLevels(), d);
  const teamFee = () => (CFG && CFG.registration.team_fee) || 650000;
  const teamMax = () => (CFG && CFG.registration.team_max) || 6;
  const teamCount = () => (CFG && CFG.registration.team_counting) || 4;
  const validDrive = (u) => /^https:\/\/(drive|docs)\.google\.com\/\S+$/i.test((u || '').trim());
  const normName = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  const levels = () => [...new Set(cats().filter((c) => c.entry_type === 'individual').map((c) => c.level))].filter((l) => (teamLevels()[S.discipline] || []).includes(l));
  const memberCat = (T, m) => {
    if (!T.level || !m.birth_date) return null;
    const g = S.discipline === 'MAG' ? 'M' : 'F';
    return cats().find((c) => c.level === T.level && c.entry_type === 'individual' && !mismatch(c, { gender: g, birth_date: m.birth_date })) || null;
  };
  // atlet di pendaftaran ini yang kategorinya ada di level tim dan belum dipakai anggota tim lain
  function formChoices(T, self) {
    if (!T || !T.level) return [];
    const used = new Set();
    S.teams.forEach((x) => x.members.forEach((m) => { if (m !== self && m.kind === 'form' && m.ref) used.add(m.ref); }));
    return S.athletes.filter((a) => a.cat && catById(a.cat) && catById(a.cat).level === T.level && !used.has(a.key));
  }
  const teamOnlyCount = () => S.teams.reduce((n, T) => n + T.members.filter((m) => m.kind === 'tim').length, 0);
  const people = () => S.athletes.length + teamOnlyCount();
  const hasTeamStep = () => !!S.discipline && teamOK(S.discipline);
  const stepKeys = () => ['st1', 'st2', 'st3'].concat(hasTeamStep() ? ['st_team'] : []).concat(['st4']);

  const app = document.getElementById('app');
  const maxAth = () => (CFG && CFG.registration.max_athletes) || 10;
  const disc = () => CFG.disciplines.find((d) => d.code === S.discipline);
  const appLabel = (x) => { const d = disc().apparatus.find((y) => y.code === x); return d ? (JO.lang === 'en' ? d.en : d.id) : x; };
  const cats = () => CFG.categories.filter((c) => c.discipline === S.discipline);
  const catById = (id) => CFG.categories.find((c) => c.id === Number(id));
  const dName = (d) => (JO.lang === 'en' ? d.name_en : d.name_id);
  const cName = (c) => (JO.lang === 'en' ? c.name_en : c.name_id);

  // ---------- draf (tanpa berkas) ----------
  function saveDraft() {
    try {
      const d = { v: 8, discipline: S.discipline, contact: S.contact, club: S.club,
        athletes: S.athletes.map((a) => ({ ...a, ...noDocs(), uploading: 0 })), pairs: S.pairs, seq,
        teams: S.teams.map((T) => ({ ...T, members: T.members.map((m) => ({ ...m, ...noDocs(), uploading: 0, check: null })) })) };
      localStorage.setItem('jo26-draft', JSON.stringify(d));
    } catch (e) {}
  }
  function loadDraft() {
    try {
      const d = JSON.parse(localStorage.getItem('jo26-draft') || 'null');
      if (!d || !d.discipline || d.v !== 8) { if (d) clearDraft(); return false; }
      Object.assign(S, { discipline: d.discipline, contact: d.contact, club: d.club, athletes: d.athletes || [], pairs: d.pairs || [] });
      if (Array.isArray(d.teams)) S.teams = d.teams;
      if (S.club.mode === 'none') S.club.mode = null;
      seq = d.seq || 10;
      return S.athletes.length > 0 || S.teams.length > 0;
    } catch (e) { return false; }
  }
  function clearDraft() { try { localStorage.removeItem('jo26-draft'); } catch (e) {} }

  // ---------- kelayakan kategori ----------
  function mismatch(c, a) {
    if (!a.gender || !a.birth_date) return t('cat_need');
    const y = Number(a.birth_date.slice(0, 4));
    if ((c.gender === 'M' || c.gender === 'F') && c.gender !== a.gender) return t('why_gender_' + c.gender);
    if (c.birth_year_min && y < c.birth_year_min) return t('why_min', { y: c.birth_year_min });
    if (c.birth_year_max && y > c.birth_year_max) return t('why_max', { y: c.birth_year_max });
    return null;
  }
  function clubProvince() {
    if (S.club.mode === 'existing') { const k = CFG.clubs.find((x) => x.id === S.club.id); return k ? k.province : ''; }
    if (S.club.mode === 'new') return S.club.abroad ? '' : S.club.province;
    return null;
  }
  // Priangan: hanya alamat identitas atlet dan provinsi klub yang menentukan (bukan asal penanggung jawab)
  function priReason(a) {
    if (a.nationality !== 'WNI') return 'pri_no_wna';
    if (a.province !== 'Jawa Barat') return 'pri_no_ath';
    const cp = clubProvince();
    if (cp !== null && cp !== 'Jawa Barat') return 'pri_no_club';
    return null;
  }
  const priEligible = (a) => !priReason(a);

  // ---------- kerangka ----------
  function render() {
    const steps = stepKeys();
    if (S.step > steps.length) S.step = steps.length;
    app.innerHTML = `<ol class="steps" aria-label="Langkah">${steps.map((k, i) =>
      `<li class="${i + 1 < S.step ? 'done' : i + 1 === S.step ? 'now' : ''}" ${i + 1 === S.step ? 'aria-current="step"' : ''}><span>${esc(t(k))}</span></li>`).join('')}</ol>
      <div id="stepbox"></div>`;
    const box = document.getElementById('stepbox');
    ({ st1: renderStep1, st2: renderStep2, st3: renderStep3, st_team: renderStepTeams, st4: renderStep4 })[steps[S.step - 1]](box);
    window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
  }
  function actions(box, { back, nextLabel, onNext }) {
    const d = document.createElement('div');
    d.className = 'step-actions';
    d.innerHTML = `${back ? `<button type="button" class="btn btn-ghost" data-act="back">${esc(t('back'))}</button>` : '<span></span>'}
      <button type="button" class="btn btn-primary" data-act="next">${esc(nextLabel || t('next'))}</button>`;
    box.appendChild(d);
    if (back) d.querySelector('[data-act=back]').onclick = () => { S.step--; saveDraft(); render(); };
    d.querySelector('[data-act=next]').onclick = onNext;
    return d;
  }
  function fieldErr(input, msg) {
    input.setAttribute('aria-invalid', 'true');
    let e = input.parentElement.querySelector(':scope > .f-err');
    if (!e) { e = document.createElement('div'); e.className = 'f-err'; input.parentElement.appendChild(e); }
    e.textContent = msg;
  }
  function clearErrs(root) {
    root.querySelectorAll('[aria-invalid]').forEach((x) => x.removeAttribute('aria-invalid'));
    root.querySelectorAll('.f-err').forEach((x) => x.remove());
  }
  function focusFirstErr(root) {
    const f = root.querySelector('[aria-invalid="true"], .f-err');
    if (f) { (f.matches('input,select,textarea') ? f : f.parentElement).scrollIntoView({ block: 'center', behavior: 'smooth' }); if (f.focus) f.focus({ preventScroll: true }); }
  }

  // ---------- langkah 1 ----------
  function renderStep1(box) {
    const ds = CFG.disciplines;
    box.innerHTML = `
      <section class="card">
        <h2>${esc(t('q_disc'))}</h2>
        <div class="choices two" role="radiogroup" id="discs"></div>
      </section>
      <section class="card">
        <h2>${esc(t('q_contact'))}</h2>
        <p class="muted small">${esc(t('q_contact_hint'))}</p>
        <div class="grid-2">
          <div class="field"><label class="f" for="c_name">${esc(t('c_name'))}</label><input id="c_name" type="text" autocomplete="name" value="${esc(S.contact.name)}"></div>
          <div class="field"><label class="f" for="c_role">${esc(t('c_role'))}</label>
            <select id="c_role"><option value="">${esc(t('choose'))}</option>
            ${['pemilik', 'admin', 'pelatih', 'manajer', 'lainnya'].map((r) => `<option value="${r}" ${S.contact.role === r ? 'selected' : ''}>${esc(t('role_' + r))}</option>`).join('')}</select></div>
          <div class="field"><label class="f" for="c_email">${esc(t('c_email'))}</label><input id="c_email" type="email" autocomplete="email" inputmode="email" value="${esc(S.contact.email)}"></div>
          <div class="field"><label class="f" for="c_phone">${esc(t('c_phone'))}</label><input id="c_phone" type="tel" autocomplete="tel" inputmode="tel" placeholder="08…" value="${esc(S.contact.phone)}"></div>
        </div>
      </section>`;
    const discBox = box.querySelector('#discs');
    function drawDiscs() {
      discBox.innerHTML = ds.map((d) => {
        const fees = [...new Set(CFG.categories.filter((c) => c.discipline === d.code).map((c) => c.fee))].sort((a, b) => a - b);
        const closed = !d.registration_open;
        const off = closed;
        const sub = closed ? t('disc_closed') : fees.map(fmtRp).join(' / ') + (teamOK(d.code) ? (JO.lang === 'en' ? ' · team ' : ' · beregu ') + fmtRp(teamFee()) : '');
        return `<label class="choice ${off ? 'disabled' : ''}"><input type="radio" name="disc" value="${d.code}" ${S.discipline === d.code && !off ? 'checked' : ''} ${off ? 'disabled' : ''}>
          <span><span class="c-title">${esc(dName(d))}</span><br>
          <span class="c-sub">${esc(JO.fmtDate(d.date_start, { day: 'numeric' }))}–${esc(JO.fmtDate(d.date_end))}</span><br>
          <span class="c-sub">${esc(sub)}</span></span></label>`;
      }).join('');
      discBox.querySelectorAll('input[name=disc]').forEach((r) => r.onchange = () => {
        if (S.discipline && S.discipline !== r.value) {
          S.athletes.forEach((a) => { a.cat = null; }); S.pairs = [];
          S.teams = [];
        }
        S.discipline = r.value; saveDraft();
        const ol = app.querySelector('.steps');
        if (ol) ol.innerHTML = stepKeys().map((k, i) => `<li class="${i === 0 ? 'now' : ''}" ${i === 0 ? 'aria-current="step"' : ''}><span>${esc(t(k))}</span></li>`).join('');
      });
    }
    drawDiscs();
    for (const k of ['name', 'email', 'phone', 'role']) {
      const el = box.querySelector('#c_' + k);
      el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => { S.contact[k] = el.value; saveDraft(); });
    }
    actions(box, { back: false, onNext: () => {
      clearErrs(box);
      let bad = false;
      if (!S.discipline) { fieldErr(box.querySelector('#discs'), t('err_disc')); bad = true; }
      if (S.contact.name.trim().length < 3) { fieldErr(box.querySelector('#c_name'), t('err_name')); bad = true; }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(S.contact.email.trim())) { fieldErr(box.querySelector('#c_email'), t('err_email')); bad = true; }
      if (S.contact.phone.replace(/\D/g, '').length < 9) { fieldErr(box.querySelector('#c_phone'), t('err_phone')); bad = true; }
      if (!['pemilik', 'admin', 'pelatih', 'manajer', 'lainnya'].includes(S.contact.role)) { fieldErr(box.querySelector('#c_role'), t('err_role')); bad = true; }
      if (bad) return focusFirstErr(box);
      if (S.club.mode === 'none') S.club.mode = null;
      S.step = 2; saveDraft(); render();
    } });
  }

  // ---------- langkah 2: klub ----------
  function regionFields(prefix, val, onChange) {
    const prov = val.province || '';
    const isJabar = prov === 'Jawa Barat';
    return `<div class="grid-2">
      <div class="field"><label class="f" for="${prefix}_prov">${esc(t('province'))}</label>
        <select id="${prefix}_prov"><option value="">${esc(t('choose'))}</option>${R.provinces.map((p) => `<option ${p === prov ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
      <div class="field"><label class="f" for="${prefix}_kab">${esc(t('kabkota'))}</label>
        ${isJabar
          ? `<select id="${prefix}_kab"><option value="">${esc(t('choose'))}</option>${R.jabar.map((k) => `<option ${k === val.kab_kota ? 'selected' : ''}>${esc(k)}</option>`).join('')}</select>`
          : `<input id="${prefix}_kab" type="text" value="${esc(val.kab_kota || '')}" ${prov ? '' : 'disabled'}>`}</div>
    </div>`;
  }
  function renderStep2(box) {
    const c = S.club;
    const chosen = c.mode === 'existing' ? CFG.clubs.find((x) => x.id === c.id) : null;
    box.innerHTML = `<section class="card">
      <h2>${esc(t('q_club'))}</h2>
      <p class="muted small">${esc(t('q_club_hint'))}</p>
      <div id="clubpick"></div>
    </section>`;
    const pick = box.querySelector('#clubpick');

    function drawPicker() {
      if (c.mode === 'existing' && chosen) {
        pick.innerHTML = `<div class="choice" style="cursor:default"><span><span class="c-title">${esc(chosen.name)}</span><br>
          <span class="c-sub">${esc([chosen.kab_kota, chosen.province, chosen.country !== 'Indonesia' ? chosen.country : ''].filter(Boolean).join(', '))}</span></span>
          <span class="spacer"></span><button type="button" class="btn btn-ghost btn-sm" id="chg">${esc(t('club_change'))}</button></div>`;
        pick.querySelector('#chg').onclick = () => { c.mode = null; c.id = null; saveDraft(); renderStep2Body(); };
        return;
      }
      if (c.mode === 'new') return drawNew();
      pick.innerHTML = `<div class="field"><label class="sr-only" for="club_q">${esc(t('club_search'))}</label>
        <input id="club_q" type="search" autocomplete="off" placeholder="${esc(t('club_search'))}"></div>
        <p class="tiny muted" id="club_n" style="margin:-4px 0 6px"></p>
        <div id="club_res" class="club-list" role="listbox" aria-label="${esc(t('q_club'))}"></div>
        <div class="row" style="margin-top:12px">
          <button type="button" class="btn btn-ghost" id="club_new">${esc(t('club_new'))}</button>
        </div>`;
      const q = pick.querySelector('#club_q'); const res = pick.querySelector('#club_res');
      const draw = () => {
        const s = q.value.trim().toLowerCase();
        const list = CFG.clubs.filter((k) => !s || (k.name + ' ' + (k.kab_kota || '') + ' ' + (k.province || '')).toLowerCase().includes(s));
        pick.querySelector('#club_n').textContent = t(s ? 'club_found' : 'club_count', { n: list.length });
        res.innerHTML = list.length ? list.map((k) => `<button type="button" role="option" class="club-opt" data-id="${k.id}">
            <span class="c-title">${esc(k.name)}</span><span class="c-sub">${esc([k.kab_kota, k.province, k.country !== 'Indonesia' ? k.country : ''].filter(Boolean).join(', '))}</span></button>`).join('')
          : `<p class="muted small" style="padding:10px 12px;margin:0">${esc(t('no_match'))}</p>`;
        res.querySelectorAll('[data-id]').forEach((b) => b.onclick = () => { c.mode = 'existing'; c.id = b.dataset.id; saveDraft(); renderStep2Body(); });
      };
      q.oninput = draw; draw();
      pick.querySelector('#club_new').onclick = () => { c.mode = 'new'; c.name = q.value.trim() || c.name; saveDraft(); drawNew(); };
    }
    function drawNew() {
      pick.innerHTML = `<div class="field"><label class="f" for="cn_name">${esc(t('club_name'))}</label><input id="cn_name" type="text" value="${esc(c.name)}"></div>
        <div class="grid-2">
          <div class="field"><label class="f" for="cn_kind">${esc(t('club_kind'))}</label><select id="cn_kind">
            ${['klub', 'sekolah', 'pengkab', 'lainnya'].map((k) => `<option value="${k}" ${c.kind === k ? 'selected' : ''}>${esc(t('kind_' + k))}</option>`).join('')}</select></div>
          <div class="field"><span class="f">&nbsp;</span><div class="seg" role="radiogroup">
            <label><input type="radio" name="cn_abroad" value="0" ${!c.abroad ? 'checked' : ''}>${esc(t('in_indonesia'))}</label>
            <label><input type="radio" name="cn_abroad" value="1" ${c.abroad ? 'checked' : ''}>${esc(t('abroad'))}</label></div></div>
        </div>
        <div id="cn_region"></div>
        <button type="button" class="btn-link small" id="cn_back">${esc(t('back'))}</button>`;
      const reg = pick.querySelector('#cn_region');
      const drawRegion = () => {
        if (c.abroad) {
          reg.innerHTML = `<div class="field"><label class="f" for="cn_country">${esc(t('country'))}</label><input id="cn_country" type="text" value="${esc(c.country === 'Indonesia' ? '' : c.country)}"></div>`;
          reg.querySelector('#cn_country').oninput = (e) => { c.country = e.target.value; saveDraft(); };
        } else {
          reg.innerHTML = regionFields('cn', c);
          reg.querySelector('#cn_prov').onchange = (e) => { c.province = e.target.value; c.kab_kota = ''; saveDraft(); drawRegion(); };
          const kab = reg.querySelector('#cn_kab');
          kab.addEventListener(kab.tagName === 'SELECT' ? 'change' : 'input', (e) => { c.kab_kota = e.target.value; saveDraft(); });
        }
      };
      drawRegion();
      pick.querySelector('#cn_name').oninput = (e) => { c.name = e.target.value; saveDraft(); };
      pick.querySelector('#cn_kind').onchange = (e) => { c.kind = e.target.value; saveDraft(); };
      pick.querySelectorAll('input[name=cn_abroad]').forEach((r) => r.onchange = () => {
        c.abroad = r.value === '1'; c.country = c.abroad ? '' : 'Indonesia'; saveDraft(); drawRegion(); });
      pick.querySelector('#cn_back').onclick = () => { c.mode = null; saveDraft(); drawPicker(); };
    }
    function renderStep2Body() { renderStep2(box); }
    drawPicker();
    actions(box, { back: true, onNext: () => {
      clearErrs(box);
      if (c.mode === 'existing' && c.id) { S.step = 3; saveDraft(); return render(); }
      if (c.mode === 'new') {
        const okName = c.name.trim().length >= 3;
        const okReg = c.abroad ? c.country.trim().length >= 2 : (c.province && c.kab_kota.trim());
        if (okName && okReg) { S.step = 3; saveDraft(); return render(); }
        const tgt = box.querySelector('#cn_name'); fieldErr(tgt, t('err_club_new')); return focusFirstErr(box);
      }
      const q = box.querySelector('#club_q') || box.querySelector('#clubpick');
      fieldErr(q, t('err_club')); focusFirstErr(box);
    } });
  }

  // ---------- bagian bersama: unggah berkas & orang tua/wali ----------
  const DOC_LABEL = { akte: 'd_akte', ktp: 'd_ktp', ijazah: 'd_ijazah', passport: 'd_passport', bpjs: 'd_bpjs', photo: 'd_photo' };
  function uploadSlot(slot, o, kind) {
    const f = o[kind];
    slot.classList.toggle('done', !!f);
    slot.innerHTML = `${f ? `<span class="small"><strong>${esc(t('uploaded'))}:</strong> ${esc(f.name)}</span>` : ''}
      <label class="btn btn-ghost btn-sm" style="position:relative;overflow:hidden">${esc(f ? t('replace') : t('up_btn'))}
        <input type="file" accept="${kind === 'photo' ? 'image/*' : 'image/*,application/pdf'}" style="position:absolute;inset:0;opacity:0;cursor:pointer"></label>
      <span class="small muted" data-st></span>`;
    slot.querySelector('input').onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      const st = slot.querySelector('[data-st]'); st.innerHTML = `<span class="spinner"></span> ${esc(t('uploading'))}`;
      o.uploading++;
      try {
        const r = await JO.uploadFile('dokumen', file);
        o[kind] = { path: r.path, name: file.name };
        if (kind === 'photo') { try { o.photo.thumb = await JO.photoThumb(file); } catch (x) { o.photo.thumb = null; } }
        slot.parentElement.querySelectorAll('.f-err').forEach((x) => x.remove());
        uploadSlot(slot, o, kind);
        const note = slot.closest('.docs') && slot.closest('.docs').querySelector('[data-bpjs-note]');
        if (kind === 'bpjs' && note) note.hidden = true;
      } catch (err) { st.textContent = err.message; st.style.color = 'var(--bad)'; }
      finally { o.uploading--; }
    };
  }
  // dokumen terpisah: WNI Akte (wajib), KTP & Ijazah (bila ada), BPJS TK (opsional), pas foto; WNA paspor (wajib), pas foto
  function docsBlock(box, o) {
    const kinds = o.nationality === 'WNA' ? ['passport', 'photo'] : ['akte', 'ktp', 'ijazah', 'bpjs', 'photo'];
    box.innerHTML = `<span class="f">${esc(t('a_docs'))}</span><div class="doc-grid">${kinds.map((k) =>
      `<div class="field doc-slot" data-doc="${k}"><span class="f small">${esc(t(DOC_LABEL[k]))}</span><div class="upload up-${k}"></div></div>`).join('')}</div>
      <details class="photo-rules"><summary class="small"><b>${esc(t('photo_rules_t'))}</b></summary>
        <div class="pr-body"><p class="small" style="margin:0 0 8px">${esc(t('photo_rules'))}</p>
        <div class="pr-ex"><figure class="ok"><img src="assets/img/pasfoto/benar.svg" alt="" width="90" height="120"><figcaption>${esc(t('photo_ok'))}</figcaption></figure>
          <figure class="no"><img src="assets/img/pasfoto/swafoto.svg" alt="" width="90" height="120"><figcaption>${esc(t('photo_no1'))}</figcaption></figure>
          <figure class="no"><img src="assets/img/pasfoto/santai.svg" alt="" width="90" height="120"><figcaption>${esc(t('photo_no2'))}</figcaption></figure></div></div></details>
      ${o.nationality === 'WNA' ? '' : `<p class="note warn small" data-bpjs-note ${o.bpjs ? 'hidden' : ''}>${esc(t('d_bpjs_note'))}</p>`}`;
    kinds.forEach((k) => uploadSlot(box.querySelector('.up-' + k), o, k));
  }
  function guardBlock(g, o) {
    if (!o.birth_date || !JO.isMinor(o.birth_date)) { g.innerHTML = ''; return; }
    g.innerHTML = `<div class="note info" style="margin-bottom:12px"><strong>${esc(t('g_title'))}.</strong> ${esc(t('g_hint'))}</div>
      <div class="grid-2">
        <div class="field"><label class="f" for="${o.key}_gn">${esc(t('g_name'))}</label><input id="${o.key}_gn" data-g="name" type="text" value="${esc(o.guardian.name)}"></div>
        <div class="field"><label class="f" for="${o.key}_gr">${esc(t('g_rel'))}</label><input id="${o.key}_gr" data-g="relation" type="text" placeholder="Ibu / Ayah / Wali" value="${esc(o.guardian.relation)}"></div>
        <div class="field"><label class="f" for="${o.key}_gp">${esc(t('g_phone'))}</label><input id="${o.key}_gp" data-g="phone" type="tel" inputmode="tel" value="${esc(o.guardian.phone)}"></div>
        <div class="field"><label class="f" for="${o.key}_ge">${esc(t('g_email'))}</label><input id="${o.key}_ge" data-g="email" type="email" inputmode="email" value="${esc(o.guardian.email)}"></div>
      </div>`;
    g.querySelectorAll('[data-g]').forEach((inp) => inp.oninput = () => { o.guardian[inp.dataset.g] = inp.value; saveDraft(); });
  }
  const guardOk = (g) => g.name.trim().length >= 3 && g.phone.replace(/\D/g, '').length >= 9 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(g.email.trim());

  // ---------- langkah beregu (opsional, Artistik Putri): satu atau beberapa tim ----------
  function renderStepTeams(box) {
    const newClub = S.club.mode !== 'existing';
    const clubLabel = S.club.mode === 'existing' ? ((CFG.clubs.find((x) => x.id === S.club.id) || {}).name || '') : S.club.name;
    S.teams.forEach((T) => {
      if (T.level && !levels().includes(T.level)) T.level = '';
      T.members.forEach((m) => { if (newClub && m.kind === 'individu') m.kind = 'tim'; });
    });
    box.innerHTML = `<section class="card">
        <h2>${esc(t('st_team'))} · ${esc(dName(disc()))}</h2>
        <p class="muted small" style="margin-bottom:6px">${esc(t('tm_intro', { n: teamMax(), fee: fmtRp(teamFee()) }))}</p>
        <p class="note info small" style="margin:0">${esc(t('tm_rule', { k: teamCount(), fee: fmtRp(teamFee()) }))}</p>
      </section>
      <p class="note small" id="ath_count" aria-live="polite"></p>
      ${newClub ? `<p class="note warn small">${esc(t('mb_new_club'))}</p>` : ''}
      <div id="teams"></div>
      <button type="button" class="btn btn-ghost" id="add_team">${esc(t('add_team'))}</button>`;
    const wrap = box.querySelector('#teams');
    function syncCount() {
      const n = people(), max = maxAth();
      const c = box.querySelector('#ath_count');
      c.textContent = n >= max ? t('ath_full', { max }) : t('ath_count', { n, max });
      c.className = 'note small ' + (n > max ? 'bad' : n >= max ? 'warn' : 'info');
      wrap.querySelectorAll('[data-k-tim]').forEach((inp) => {
        const m = memberByKey(inp.dataset.kTim);
        inp.disabled = m.kind !== 'tim' && people() >= maxAth();
        inp.closest('label').classList.toggle('is-off', inp.disabled);
      });
    }
    function memberByKey(k) { for (const T of S.teams) { const m = T.members.find((x) => x.key === k); if (m) return m; } return null; }
    function drawAll() {
      wrap.innerHTML = '';
      S.teams.forEach((T, ti) => wrap.appendChild(teamCard(T, ti)));
      syncCount();
    }
    box.querySelector('#add_team').onclick = () => {
      const T = newTeam(); S.teams.push(T); saveDraft();
      wrap.appendChild(teamCard(T, S.teams.length - 1)); syncCount();
      wrap.lastElementChild.querySelector('select').focus();
    };

    function teamCard(T, ti) {
      const el = document.createElement('section');
      el.className = 'card team-card'; el.dataset.team = T.key;
      el.innerHTML = `<div class="ath-head" style="margin:-4px 0 12px"><strong class="ath-title">${esc(t('tm_n', { n: ti + 1 }))}</strong>
          <span class="spacer"></span><button type="button" class="btn btn-bad btn-sm" data-rmt>${esc(t('rm_team'))}</button></div>
        <p class="muted small">${esc(t('tm_hint'))}</p>
        <div class="grid-2">
          <div class="field"><label class="f" for="${T.key}_level">${esc(t('tm_level'))}</label>
            <select id="${T.key}_level" data-tk="level"><option value="">${esc(t('choose'))}</option>${levels().map((l) => `<option ${l === T.level ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>
          <div class="field"><label class="f" for="${T.key}_name">${esc(t('tm_name'))}</label>
            <input id="${T.key}_name" data-tk="name" type="text" maxlength="60" autocomplete="off" placeholder="${esc(t('tm_name_ph', { c: clubLabel.trim() || 'Klub' }))}" value="${esc(T.name)}"></div>
        </div>
        <div class="mbs"></div>
        <button type="button" class="btn btn-ghost btn-sm" data-addm>${esc(t('add_mb'))}</button>`;
      const list = el.querySelector('.mbs');
      const addm = el.querySelector('[data-addm]');
      const syncAdd = () => { addm.hidden = T.members.length >= teamMax(); };
      const renumber = () => list.querySelectorAll('.ath').forEach((x, i) => { x.querySelector('.n').textContent = i + 1; x.querySelector('.ath-title').textContent = t('mb', { n: i + 1 }); });
      el.querySelector('[data-tk=level]').onchange = (e) => {
        T.level = e.target.value;
        T.members.forEach((m) => {
          m.check = null; if (m.kind === 'form') m.ref = '';
          // anggota yang belum diisi: utamakan atlet dari pendaftaran ini bila ada di level ini
          if (m.kind === 'tim' && !m.full_name.trim() && !m.akte && !m.passport && !m.photo) m.kind = formChoices(T, m).length ? 'form' : 'tim';
        });
        list.innerHTML = ''; T.members.forEach((m, i) => list.appendChild(memberCard(T, m, i)));
        saveDraft(); syncCount();
      };
      el.querySelector('[data-tk=name]').oninput = (e) => { T.name = e.target.value; saveDraft(); };
      el.querySelector('[data-rmt]').onclick = () => { S.teams = S.teams.filter((x) => x !== T); saveDraft(); drawAll(); };
      if (!T.members.length) T.members.push(newMember(T));
      T.members.forEach((m, i) => list.appendChild(memberCard(T, m, i)));
      syncAdd();
      addm.onclick = () => {
        if (T.members.length >= teamMax()) return;
        const m = newMember(T);
        if (m.kind === 'tim' && people() >= maxAth()) m.kind = newClub ? 'form' : 'individu';
        T.members.push(m); saveDraft();
        list.appendChild(memberCard(T, m, T.members.length - 1)); syncAdd(); syncCount();
      };

      function memberCard(T, m, i) {
        const mel = document.createElement('div');
        mel.className = 'ath mb'; mel.dataset.key = m.key;
        mel.innerHTML = `<div class="ath-head"><span class="n">${i + 1}</span><strong class="ath-title">${esc(t('mb', { n: i + 1 }))}</strong>
            <span class="spacer"></span><button type="button" class="btn btn-bad btn-sm" data-rm>${esc(t('remove'))}</button></div>
          <div class="ath-body">
            <div class="field"><span class="f">${esc(t('mb_kind'))}</span><div class="seg seg-kind" role="radiogroup">
              <label><input type="radio" name="${m.key}_k" value="form" ${m.kind === 'form' ? 'checked' : ''}>${esc(t('kind_form'))}</label>
              <label class="${newClub ? 'is-off' : ''}"><input type="radio" name="${m.key}_k" value="individu" ${m.kind === 'individu' ? 'checked' : ''} ${newClub ? 'disabled' : ''}>${esc(t('kind_individu'))}</label>
              <label><input type="radio" name="${m.key}_k" value="tim" data-k-tim="${m.key}" ${m.kind === 'tim' ? 'checked' : ''}>${esc(t('kind_tim'))}</label></div>
              <div class="f-hint" data-kh></div></div>
            <div class="mb-body"></div>
          </div>`;
        const q = (sel) => mel.querySelector(sel);
        mel.querySelectorAll(`input[name=${m.key}_k]`).forEach((r) => r.onchange = () => { m.kind = r.value; m.check = null; clearErrs(mel); drawBody(); saveDraft(); syncCount(); });
        q('[data-rm]').onclick = () => {
          if (T.members.length === 1) { Object.assign(m, newMember(T), { key: m.key }); mel.replaceWith(memberCard(T, m, i)); saveDraft(); syncCount(); return; }
          T.members = T.members.filter((x) => x !== m); mel.remove(); saveDraft(); renumber(); syncAdd(); syncCount();
        };
        function drawBody() {
          q('[data-kh]').textContent = m.kind === 'form' ? t('mb_form_hint') : m.kind === 'individu' ? t('mb_individu_hint') : t('mb_tim_hint', { max: maxAth() });
          const b = q('.mb-body');
          if (m.kind === 'form') {
            const ch = formChoices(T, m);
            if (m.ref && !ch.some((a) => a.key === m.ref)) m.ref = '';
            b.innerHTML = !T.level ? '' : ch.length
              ? `<div class="field"><label class="f" for="${m.key}_ref">${esc(t('mb_form_pick'))}</label><select id="${m.key}_ref" data-k="ref"><option value="">${esc(t('choose'))}</option>
                  ${ch.map((a) => `<option value="${a.key}" ${m.ref === a.key ? 'selected' : ''}>${esc(a.full_name.trim() || t('ath', { n: S.athletes.indexOf(a) + 1 }))} · ${esc(cName(catById(a.cat)))}</option>`).join('')}</select></div>`
              : `<p class="note warn small" style="margin:0" data-k="ref">${esc(t('mb_form_none', { l: T.level }))}</p>`;
            const sel = b.querySelector('select');
            if (sel) sel.onchange = () => { m.ref = sel.value; saveDraft(); };
            return;
          }
          b.innerHTML = `<div class="grid-2">
              <div class="field"><label class="f" for="${m.key}_name">${esc(t('a_name'))}</label><input id="${m.key}_name" data-k="full_name" type="text" autocomplete="off" value="${esc(m.full_name)}"></div>
              <div class="field"><label class="f" for="${m.key}_birth">${esc(t('a_birth'))}</label><input id="${m.key}_birth" data-k="birth_date" type="date" min="1950-01-01" max="${new Date().toISOString().slice(0, 10)}" value="${esc(m.birth_date)}"></div>
            </div>
            <div class="mb-check small" data-chk aria-live="polite"></div>
            <div class="mb-tim"></div>`;
          const clearCheck = () => { m.check = null; const c = b.querySelector('[data-chk]'); if (c) c.innerHTML = ''; clearErrs(b); };
          b.querySelector('[data-k=full_name]').oninput = (e) => { m.full_name = e.target.value; clearCheck(); saveDraft(); };
          b.querySelector('[data-k=birth_date]').addEventListener('change', (e) => { m.birth_date = e.target.value; clearCheck(); drawTim(); saveDraft(); });
          drawTim();
        }
        function drawTim() {
          const box2 = q('.mb-tim');
          if (!box2) return;
          if (m.kind !== 'tim') { box2.innerHTML = ''; return; }
          box2.innerHTML = `<div class="field"><span class="f">${esc(t('a_nat'))}</span><div class="seg" role="radiogroup">
              <label><input type="radio" name="${m.key}_n" value="WNI" ${m.nationality === 'WNI' ? 'checked' : ''}>${esc(t('wni'))}</label>
              <label><input type="radio" name="${m.key}_n" value="WNA" ${m.nationality === 'WNA' ? 'checked' : ''}>${esc(t('wna'))}</label></div></div>
            ${m.nationality === 'WNA' ? `<div class="field"><label class="f" for="${m.key}_country">${esc(t('country'))}</label><input id="${m.key}_country" data-k="country" type="text" value="${esc(m.country)}"></div>` : ''}
            <div class="field docs"></div>
            <div class="guard"></div>
            <p class="mb-cat small" data-cat></p>`;
          box2.querySelectorAll(`input[name=${m.key}_n]`).forEach((r) => r.onchange = () => { m.nationality = r.value; drawTim(); saveDraft(); });
          const ct = box2.querySelector('[data-k=country]');
          if (ct) ct.oninput = (e) => { m.country = e.target.value; saveDraft(); };
          docsBlock(box2.querySelector('.docs'), m);
          guardBlock(box2.querySelector('.guard'), m);
          const p = box2.querySelector('[data-cat]');
          if (T.level && m.birth_date) { const c = memberCat(T, m); p.innerHTML = c ? esc(t('mb_cat', { c: cName(c) })) : `<span class="bad-t">${esc(t('mb_cat_none'))}</span>`; }
        }
        drawBody();
        return mel;
      }
      return el;
    }
    drawAll();

    actions(box, { back: true, onNext: async () => {
      clearErrs(box);
      wrap.querySelectorAll('[data-chk]').forEach((x) => { x.innerHTML = ''; });
      let bad = false;
      if (S.teams.some((T) => T.members.some((m) => m.uploading))) { JO.toast(t('err_uploading'), 'bad'); return; }
      if (people() > maxAth()) { JO.toast(t('err_max', { max: maxAth() }), 'bad'); return; }
      if (!S.athletes.length && !S.teams.length) { JO.toast(t('err_none'), 'bad'); return; }
      const seen = new Map();
      const names = new Set();
      S.teams.forEach((T) => {
        const tel = wrap.querySelector(`[data-team="${T.key}"]`);
        if (!T.level) { fieldErr(tel.querySelector('[data-tk=level]'), t('err_tm_level')); bad = true; }
        if (T.name.trim().length < 2) { fieldErr(tel.querySelector('[data-tk=name]'), t('err_tm_name')); bad = true; }
        const nk = T.level + '|' + T.name.trim().toLowerCase();
        if (T.name.trim() && names.has(nk)) { fieldErr(tel.querySelector('[data-tk=name]'), t('err_tm_name')); bad = true; } else names.add(nk);
        T.members.forEach((m) => {
          const el = tel.querySelector(`[data-key="${m.key}"]`); const q = (x) => el.querySelector(x);
          if (m.kind === 'form') {
            if (!m.ref) { const r = q('[data-k=ref]') || q('.seg-kind'); fieldErr(r, t('err_mb_form')); bad = true; }
            return;
          }
          if (m.full_name.trim().length < 3) { fieldErr(q('[data-k=full_name]'), t('err_a_name')); bad = true; }
          if (!m.birth_date) { fieldErr(q('[data-k=birth_date]'), t('err_a_birth')); bad = true; }
          const id = normName(m.full_name) + '|' + m.birth_date;
          if (m.full_name.trim() && m.birth_date) {
            const dupForm = S.athletes.some((a) => normName(a.full_name) + '|' + a.birth_date === id);
            if (seen.has(id) || (m.kind === 'tim' && dupForm)) { fieldErr(q('[data-k=full_name]'), t(dupForm ? 'err_mb_inform' : 'err_mb_dup')); bad = true; } else seen.set(id, m);
          }
          if (m.kind === 'tim') {
            if (m.nationality === 'WNA' && m.country.trim().length < 2) { fieldErr(q('[data-k=country]'), t('err_a_country')); bad = true; }
            { const de = docErr(m); if (de) { fieldErr(q(de[0]), t(de[1])); bad = true; } }
            if (m.birth_date && JO.isMinor(m.birth_date) && !guardOk(m.guardian)) { fieldErr(q('[data-g=name]'), t('err_g')); bad = true; }
            if (T.level && m.birth_date && !memberCat(T, m)) { fieldErr(q('[data-cat]'), t('err_mb_cat')); bad = true; }
          }
        });
      });
      if (bad) { JO.toast(t('err_fix'), 'bad'); return focusFirstErr(box); }
      // periksa ke server: "Terdaftar sebelumnya" harus sudah ada, "Khusus beregu" belum punya kategori perorangan
      if (S.club.mode === 'existing' && S.teams.some((T) => T.members.some((m) => m.kind !== 'form'))) {
        const btn = box.querySelector('.step-actions [data-act=next]');
        btn.disabled = true; const label = btn.textContent; btn.textContent = t('checking');
        try {
          await JO.ensureSession();
          for (const T of S.teams) {
            const ms = T.members.filter((m) => m.kind !== 'form');
            if (!ms.length) continue;
            const res = await rpc('public_team_check', { p: { club_id: S.club.id, discipline: S.discipline, level: T.level,
              members: ms.map((m) => ({ full_name: m.full_name.trim(), birth_date: m.birth_date })) } });
            const tel = wrap.querySelector(`[data-team="${T.key}"]`);
            ms.forEach((m, i) => {
              const r = (res || []).find((x) => x.i === i + 1) || {};
              const el = tel.querySelector(`[data-key="${m.key}"]`); const nameEl = el.querySelector('[data-k=full_name]');
              if (m.kind === 'individu' && !r.found) { fieldErr(nameEl, t('err_mb_notfound')); bad = true; }
              else if (m.kind === 'individu' && r.in_team) { fieldErr(nameEl, t('err_mb_inteam')); bad = true; }
              else if (m.kind === 'tim' && r.found) { fieldErr(nameEl, t('err_mb_isind')); bad = true; }
              else if (m.kind === 'individu') el.querySelector('[data-chk]').innerHTML = `<span class="ok-t">${esc(t('mb_found'))}</span>`;
            });
          }
        } catch (err) { JO.toast(err.message, 'bad'); return; }
        finally { btn.disabled = false; btn.textContent = label; }
        if (bad) { JO.toast(t('err_fix'), 'bad'); return focusFirstErr(box); }
      }
      S.step++; saveDraft(); render();
    } });
  }

  // ---------- langkah 3: atlet ----------
  function renderStep3(box) {
    if (!S.athletes.length && !(hasTeamStep() && S.teams.length)) S.athletes.push(newAthlete());
    box.innerHTML = `<p class="note info small" id="ath_count" aria-live="polite"></p>
      <div id="aths"></div>
      <p class="note info small" id="ath_empty" hidden>${esc(t('ath_empty'))}</p>
      <button type="button" class="btn btn-ghost" id="add_ath">${esc(t('add_ath'))}</button>
      <div id="pairs"></div>`;
    const list = box.querySelector('#aths');
    S.athletes.forEach((a, i) => list.appendChild(athleteCard(a, i)));
    const add = box.querySelector('#add_ath');
    function syncCount() {
      const n = people(), max = maxAth();
      const c = box.querySelector('#ath_count');
      c.textContent = n >= max ? t('ath_full', { max }) : t('ath_count', { n, max });
      c.className = 'note small ' + (n > max ? 'bad' : n >= max ? 'warn' : 'info');
      add.hidden = n >= max;
      box.querySelector('#ath_empty').hidden = S.athletes.length > 0;
    }
    box._syncCount = syncCount;
    syncCount();
    add.onclick = () => {
      if (people() >= maxAth()) return;
      const a = newAthlete(); S.athletes.push(a); saveDraft();
      list.appendChild(athleteCard(a, S.athletes.length - 1));
      syncCount(); drawPairs(); renumber();
      list.lastElementChild.querySelector('input').focus();
    };
    function renumber() {
      list.querySelectorAll('.ath').forEach((el, i) => { el.querySelector('.n').textContent = i + 1; el.querySelector('.ath-title').textContent = t('ath', { n: i + 1 }); });
    }
    box._renumber = renumber;
    const pairsBox = box.querySelector('#pairs');
    function drawPairs() {
      const mp = cats().filter((c) => c.entry_type === 'pair');
      if (!mp.length) { pairsBox.innerHTML = ''; return; }
      const males = S.athletes.filter((a) => a.gender === 'M'); const females = S.athletes.filter((a) => a.gender === 'F');
      const label = (a) => a.full_name.trim() || t('ath', { n: S.athletes.indexOf(a) + 1 });
      pairsBox.innerHTML = `<section class="card" style="margin-top:16px"><h2>${esc(t('pair_title'))}</h2>
        <p class="muted small">${esc(t('pair_hint', { fee: fmtRp(mp[0].fee) }))}</p>
        ${(!males.length || !females.length) ? `<p class="note info">${esc(t('pair_need'))}</p>` : ''}
        <div id="pair_list"></div>
        ${males.length && females.length ? `<button type="button" class="btn btn-ghost btn-sm" id="pair_add">${esc(t('pair_add'))}</button>` : ''}</section>`;
      const pl = pairsBox.querySelector('#pair_list');
      S.pairs.forEach((p, i) => {
        const el = document.createElement('div');
        el.className = 'ath'; el.style.marginTop = '12px';
        const m = S.athletes.find((a) => a.key === p.m), f = S.athletes.find((a) => a.key === p.f);
        el.innerHTML = `<div class="ath-body"><div class="grid-3">
          <div class="field"><label class="f">${esc(t('cat_title'))}</label><select data-k="category_id"><option value="">${esc(t('choose'))}</option>
            ${mp.map((c) => `<option value="${c.id}" ${Number(p.category_id) === c.id ? 'selected' : ''}>${esc(cName(c))}</option>`).join('')}</select></div>
          <div class="field"><label class="f">${esc(t('pair_m'))}</label><select data-k="m"><option value="">${esc(t('choose'))}</option>
            ${males.map((a) => `<option value="${a.key}" ${p.m === a.key ? 'selected' : ''}>${esc(label(a))}</option>`).join('')}</select></div>
          <div class="field"><label class="f">${esc(t('pair_f'))}</label><select data-k="f"><option value="">${esc(t('choose'))}</option>
            ${females.map((a) => `<option value="${a.key}" ${p.f === a.key ? 'selected' : ''}>${esc(label(a))}</option>`).join('')}</select></div></div>
          <button type="button" class="btn btn-bad btn-sm" data-rm>${esc(t('remove'))}</button></div>`;
        el.querySelectorAll('select').forEach((s) => s.onchange = () => { p[s.dataset.k] = s.value; saveDraft(); drawPairs(); });
        el.querySelector('[data-rm]').onclick = () => { S.pairs.splice(i, 1); saveDraft(); drawPairs(); };
        pl.appendChild(el);
      });
      const pa = pairsBox.querySelector('#pair_add');
      if (pa) pa.onclick = () => { S.pairs.push({ key: 'p' + (++seq), category_id: '', m: '', f: '', priangan: false }); saveDraft(); drawPairs(); };
    }
    box._drawPairs = drawPairs;
    drawPairs();

    actions(box, { back: true, onNext: () => {
      clearErrs(box);
      let bad = false;
      if (S.athletes.some((a) => a.uploading)) { JO.toast(t('err_uploading'), 'bad'); return; }
      if (people() > maxAth()) { JO.toast(t('err_max', { max: maxAth() }), 'bad'); return; }
      if (!S.athletes.length && !hasTeamStep()) { JO.toast(t('err_none'), 'bad'); return; }
      const inPair = new Set();
      S.pairs.forEach((p) => { inPair.add(p.m); inPair.add(p.f); });
      list.querySelectorAll('.ath').forEach((el) => {
        const a = S.athletes.find((x) => x.key === el.dataset.key);
        const q = (s) => el.querySelector(s);
        if (a.full_name.trim().length < 3) { fieldErr(q('[data-k=full_name]'), t('err_a_name')); bad = true; }
        if (!a.gender) { fieldErr(q('.seg-gender'), t('err_a_gender')); bad = true; }
        if (!a.birth_date) { fieldErr(q('[data-k=birth_date]'), t('err_a_birth')); bad = true; }
        if (a.nationality === 'WNI' && (!a.province || !a.kab_kota.trim())) { fieldErr(q('[data-r=prov]') || q('.regbox'), t('err_a_addr')); bad = true; }
        if (a.nationality === 'WNA' && a.country.trim().length < 2) { fieldErr(q('[data-k=country]'), t('err_a_country')); bad = true; }
        { const de = docErr(a); if (de) { fieldErr(q(de[0]), t(de[1])); bad = true; } }
        if (!a.cat && !inPair.has(a.key)) { fieldErr(q('.cat-list'), t('err_a_cat')); bad = true; }
        if (S.discipline === 'RG' && a.cat) {
          (catById(a.cat).apparatus || []).forEach((ap) => { if (!validDrive((a.music || {})[ap])) { fieldErr(q(`[data-mu="${ap}"]`), t('err_music')); bad = true; } });
        }
        if (a.cat && catById(a.cat).jabar_only && !priEligible(a)) { fieldErr(q('.cat-list'), t(priReason(a))); bad = true; }
        if (a.birth_date && JO.isMinor(a.birth_date)) {
          const g = a.guardian;
          if (g.name.trim().length < 3 || g.phone.replace(/\D/g, '').length < 9 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(g.email.trim())) { fieldErr(q('[data-g=name]'), t('err_g')); bad = true; }
        }
      });
      for (const p of S.pairs) {
        const c = catById(p.category_id), m = S.athletes.find((a) => a.key === p.m), f = S.athletes.find((a) => a.key === p.f);
        if (!c || !m || !f) { JO.toast(t('err_pair'), 'bad'); bad = true; break; }
        for (const a of [m, f]) {
          if (mismatch({ ...c, gender: a.gender }, a)) { JO.toast(t('err_pair_age', { c: cName(c), n: a.full_name }), 'bad'); bad = true; }
        }
      }
      if (bad) { JO.toast(t('err_fix'), 'bad'); return focusFirstErr(box); }
      // anggota tim "atlet di pendaftaran ini" yang kategorinya berubah dilepas
      S.teams.forEach((T) => T.members.forEach((m) => {
        if (m.kind === 'form' && m.ref && !formChoices(T, m).some((a) => a.key === m.ref)) m.ref = '';
      }));
      S.step++; saveDraft(); render();
    } });
  }

  function athleteCard(a, i) {
    const el = document.createElement('div');
    el.className = 'ath'; el.dataset.key = a.key;
    el.innerHTML = `<div class="ath-head"><span class="n">${i + 1}</span><strong class="ath-title">${esc(t('ath', { n: i + 1 }))}</strong>
        <span class="spacer"></span><button type="button" class="btn btn-bad btn-sm" data-rm>${esc(t('remove'))}</button></div>
      <div class="ath-body">
        <div class="field"><label class="f" for="${a.key}_name">${esc(t('a_name'))}</label><input id="${a.key}_name" data-k="full_name" type="text" autocomplete="off" value="${esc(a.full_name)}"></div>
        <div class="grid-2">
          <div class="field"><span class="f">${esc(t('a_gender'))}</span><div class="seg seg-gender" role="radiogroup">
            <label><input type="radio" name="${a.key}_g" value="M" ${a.gender === 'M' ? 'checked' : ''}>${esc(t('gender_M'))}</label>
            <label><input type="radio" name="${a.key}_g" value="F" ${a.gender === 'F' ? 'checked' : ''}>${esc(t('gender_F'))}</label></div></div>
          <div class="field"><label class="f" for="${a.key}_birth">${esc(t('a_birth'))}</label><input id="${a.key}_birth" data-k="birth_date" type="date" min="1950-01-01" max="${new Date().toISOString().slice(0, 10)}" value="${esc(a.birth_date)}">
            <div class="f-hint" data-age>${esc(t('a_birth_hint'))}</div></div>
        </div>
        <div class="field"><span class="f">${esc(t('a_nat'))}</span><div class="seg" role="radiogroup">
          <label><input type="radio" name="${a.key}_n" value="WNI" ${a.nationality === 'WNI' ? 'checked' : ''}>${esc(t('wni'))}</label>
          <label><input type="radio" name="${a.key}_n" value="WNA" ${a.nationality === 'WNA' ? 'checked' : ''}>${esc(t('wna'))}</label></div></div>
        <div class="regbox"></div>
        <div class="field docs"></div>
        <div class="guard"></div>
        <div class="field"><span class="f">${esc(t('cat_title'))}</span><div class="cat-list"></div></div>
        ${S.discipline === 'RG' ? `<div class="field music"><span class="f">${esc(t('music'))}</span><div class="mu-list"></div>
          <div class="f-hint">${esc(t('music_hint'))}</div></div>` : ''}
      </div>`;
    const q = (s) => el.querySelector(s);
    q('[data-k=full_name]').oninput = (e) => { a.full_name = e.target.value; saveDraft(); };
    if (typeof a.music !== 'object' || !a.music) a.music = {};
    function drawMusic() {
      const box = q('.mu-list'); if (!box) return;
      const c = a.cat && catById(a.cat);
      if (!c) { box.innerHTML = `<p class="small muted" style="margin:0">${esc(t('music_pick'))}</p>`; return; }
      box.innerHTML = (c.apparatus || []).map((ap) => `<div class="mu-row"><label class="small" for="${a.key}_mu_${ap}">${esc(appLabel(ap))}</label>
        <input id="${a.key}_mu_${ap}" data-mu="${ap}" type="url" inputmode="url" autocomplete="off" spellcheck="false" placeholder="https://drive.google.com/…" value="${esc(a.music[ap] || '')}"></div>`).join('');
      box.querySelectorAll('[data-mu]').forEach((inp) => inp.oninput = () => { a.music[inp.dataset.mu] = inp.value; saveDraft(); });
    }
    el.querySelectorAll(`input[name=${a.key}_g]`).forEach((r) => r.onchange = () => { a.gender = r.value; validCat(); drawCats(); redrawPairs(); saveDraft(); });
    q('[data-k=birth_date]').addEventListener('change', (e) => { a.birth_date = e.target.value; validCat(); drawAge(); drawGuard(); drawCats(); saveDraft(); });
    el.querySelectorAll(`input[name=${a.key}_n]`).forEach((r) => r.onchange = () => { a.nationality = r.value; drawRegion(); drawDocs(); drawCats(); redrawPairs(); saveDraft(); });
    const rm = q('[data-rm]');
    if (rm) rm.onclick = () => {
      if (S.athletes.length === 1 && !hasTeamStep()) { Object.assign(a, newAthlete(), { key: a.key }); el.replaceWith(athleteCard(a, i)); saveDraft(); return; }
      S.athletes = S.athletes.filter((x) => x !== a);
      S.pairs = S.pairs.filter((p) => p.m !== a.key && p.f !== a.key);
      S.teams.forEach((T) => T.members.forEach((m) => { if (m.kind === 'form' && m.ref === a.key) m.ref = ''; }));
      el.remove(); saveDraft();
      const box = document.getElementById('stepbox');
      box._renumber && box._renumber(); box._drawPairs && box._drawPairs(); box._syncCount && box._syncCount();
    };
    function redrawPairs() { const box = document.getElementById('stepbox'); box && box._drawPairs && box._drawPairs(); }
    function validCat() { const c = a.cat && catById(a.cat); if (c && mismatch(c, a)) { a.cat = null; drawMusic(); } }
    function drawAge() {
      const h = q('[data-age]');
      h.textContent = a.birth_date ? t('cat_age', { a: JO.compAge(a.birth_date) }) : t('a_birth_hint');
    }
    function drawRegion() {
      const rb = q('.regbox');
      if (a.nationality === 'WNA') {
        rb.innerHTML = `<div class="field"><label class="f" for="${a.key}_country">${esc(t('country'))}</label><input id="${a.key}_country" data-k="country" type="text" value="${esc(a.country)}"></div>`;
        rb.querySelector('input').oninput = (e) => { a.country = e.target.value; saveDraft(); };
        return;
      }
      rb.innerHTML = regionFields(a.key, a) + `<div class="f-hint" style="margin-top:-8px;margin-bottom:12px">${esc(t('a_addr_hint'))}</div>`;
      const prov = rb.querySelector(`#${a.key}_prov`); prov.dataset.r = 'prov';
      prov.onchange = () => { a.province = prov.value; a.kab_kota = ''; drawRegion(); drawCats(); redrawPairs(); saveDraft(); };
      const kab = rb.querySelector(`#${a.key}_kab`);
      kab.addEventListener(kab.tagName === 'SELECT' ? 'change' : 'input', () => { a.kab_kota = kab.value; saveDraft(); });
    }
    function drawGuard() { guardBlock(q('.guard'), a); }
    function drawDocs() { docsBlock(q('.docs'), a); }
    function drawCats() {
      const box = q('.cat-list');
      const list = cats().filter((c) => c.entry_type === 'individual');
      const ready = a.gender && a.birth_date;
      if (!ready) { box.innerHTML = `<p class="note info small" style="margin:0">${esc(t('cat_need'))}</p>`; drawMusic(); return; }
      const priWhy = priReason(a);
      const why = (c) => mismatch(c, a) || (c.jabar_only && priWhy ? t(priWhy) : null);
      const row = (c) => {
        const w = why(c);
        const on = Number(a.cat) === c.id;
        const app = (c.apparatus || []).map(appLabel);
        return `<label class="cat ${w ? 'off' : ''}"><input type="radio" name="${a.key}_cat" value="${c.id}" ${on ? 'checked' : ''} ${w ? 'disabled' : ''}>
          <span><span class="t">${esc(cName(c))}</span><br><span class="s">${esc(app.join(', '))}</span>
          ${c.jabar_only ? `<br><span class="s pri-t">${esc(t('jabar_only'))}</span>` : ''}${w ? `<br><span class="why">${esc(w)}</span>` : ''}</span>
          <span class="fee num">${fmtRp(c.fee)}</span></label>`;
      };
      // kategori Priangan yang gagal hanya karena syarat Jawa Barat tetap tampil (dengan alasannya) agar jelas
      const ok = list.filter((c) => !mismatch(c, a)), off = list.filter((c) => mismatch(c, a));
      if (a.cat) { const c = catById(a.cat); if (c && why(c)) a.cat = null; }
      box.innerHTML = (ok.length ? ok.map(row).join('') : `<p class="note warn small" style="margin:0">${esc(t('cat_none'))}</p>`) +
        (off.length ? `<details class="cat-off"><summary class="small muted">${esc(t('cat_off', { n: off.length }))}</summary><div class="cat-list" style="margin-top:8px">${off.map(row).join('')}</div></details>` : '');
      box.querySelectorAll(`input[name=${a.key}_cat]`).forEach((r) => r.onchange = () => { a.cat = Number(r.value); drawCats(); saveDraft(); });
      drawMusic();
    }
    drawAge(); drawRegion(); drawDocs(); drawGuard(); drawCats();
    return el;
  }

  // ---------- langkah 4 ----------
  function buildEntries() {
    const entries = [];
    S.athletes.forEach((a) => {
      if (!a.cat) return;
      const e = { category_id: Number(a.cat), athletes: [a.key] };
      if (S.discipline === 'RG') {
        e.music = {};
        (catById(a.cat).apparatus || []).forEach((ap) => { e.music[ap] = ((a.music || {})[ap] || '').trim(); });
      }
      entries.push(e);
    });
    S.pairs.forEach((p) => {
      const m = S.athletes.find((a) => a.key === p.m), f = S.athletes.find((a) => a.key === p.f);
      entries.push({ category_id: Number(p.category_id), athletes: [p.m, p.f] });
    });
    return entries;
  }
  function renderStep4(box) {
    const teams = S.teams;
    const tim = [].concat(...teams.map((T) => T.members.filter((m) => m.kind === 'tim')));
    const entries = buildEntries();
    const entryFees = entries.reduce((s2, e) => s2 + catById(e.category_id).fee, 0);
    const teamFees = teams.length * teamFee();
    const base = entryFees + teamFees;
    const pri = 0;
    const intl = S.athletes.some((a) => a.nationality === 'WNA') || tim.some((m) => m.nationality === 'WNA');
    const minors = S.athletes.some((a) => JO.isMinor(a.birth_date)) || tim.some((m) => JO.isMinor(m.birth_date));
    const cap = CFG.registration.qris_cap;
    const over = !intl && base + pri + 999 > cap;
    const consents = ['waiver', 'insurance', 'data', 'rules'].concat(minors ? ['guardian'] : []);
    const athName = (k) => (S.athletes.find((a) => a.key === k) || {}).full_name;
    const memberLine = (T, m) => {
      if (m.kind === 'form') { const a = S.athletes.find((x) => x.key === m.ref) || {}; return [a.full_name, t('sum_member_ind')]; }
      if (m.kind === 'individu') return [m.full_name, t('sum_member_prev')];
      const c = memberCat(T, m); return [m.full_name, t('sum_member_tim') + (c ? ' · ' + cName(c) : '')];
    };
    const rows = entries.map((e) => { const c = catById(e.category_id); return `<tr><td>${esc(e.athletes.map(athName).join(' & '))}<br><span class="small muted">${esc(cName(c))}</span></td>
            <td class="r num">${fmtRp(c.fee)}</td></tr>`; }).join('')
      + teams.map((T) => `<tr><td><strong>${esc(t('st_team'))}: ${esc(T.name.trim())}</strong><br><span class="small muted">${esc(dName(disc()))} · ${esc(T.level)}</span></td><td class="r num">${fmtRp(teamFee())}</td></tr>
         ${T.members.map((m) => { const [n, k] = memberLine(T, m);
           return `<tr><td style="padding-left:18px">${esc((n || '').trim())}<br><span class="small muted">${esc(k)}</span></td><td class="r num muted">–</td></tr>`; }).join('')}`).join('');
    box.innerHTML = `<section class="card">
        <h2>${esc(t('sum_title'))}</h2>
        <div class="tbl-wrap" style="margin-bottom:14px"><table class="tbl"><tbody>${rows}</tbody></table></div>
        <table class="breakdown"><tbody>
          ${entryFees ? `<tr><td>${esc(t('sum_fees'))}</td><td>${fmtRp(entryFees)}</td></tr>` : ''}
          ${teamFees ? `<tr><td>${esc(t('sum_team'))} (${teams.length} × ${fmtRp(teamFee())})</td><td>${fmtRp(teamFees)}</td></tr>` : ''}
          ${pri ? `<tr><td>${esc(t('sum_pri'))}</td><td>${fmtRp(pri)}</td></tr>` : ''}
          ${!intl ? `<tr><td>${esc(t('sum_uc'))}</td><td class="muted">${esc(t('sum_uc_val'))}</td></tr>` : ''}
          <tr class="total"><td>${esc(t('sum_total'))}</td><td>${fmtRp(base + pri)}${intl ? '' : ' + ' + esc(t('sum_uc').toLowerCase())}</td></tr>
        </tbody></table>
        ${!intl ? `<p class="note warn small" style="margin-top:12px">${esc(t('sum_15'))}</p>` : ''}
        ${(() => { const list = S.athletes.concat(tim).filter((x) => x.nationality !== 'WNA' && !x.bpjs).map((x) => x.full_name.trim()).filter(Boolean);
            return list.length ? `<p class="note info small">${esc(t('sum_bpjs', { n: list.join(', ') }))}</p>` : ''; })()}
        ${intl ? `<p class="note info" style="margin-top:12px">${esc(t('sum_intl'))}</p>` : ''}
        ${over ? `<p class="note bad" style="margin-top:12px">${esc(t('sum_cap', { cap: fmtRp(cap) }))}</p>` : ''}
      </section>
      <section class="card"><h2>${esc(t('cons_title'))}</h2>
        ${consents.map((k) => `<label class="check"><input type="checkbox" data-c="${k}" ${S.consents[k] ? 'checked' : ''}><span>${esc(t('cons_' + k))}</span></label>`).join('')}
        <div id="cons_err"></div>
      </section>
      <div id="submit_err"></div>`;
    box.querySelectorAll('[data-c]').forEach((c) => c.onchange = () => { S.consents[c.dataset.c] = c.checked; });
    const act = actions(box, { back: true, nextLabel: t('submit'), onNext: async () => {
      const errBox = box.querySelector('#cons_err'); errBox.innerHTML = '';
      box.querySelector('#submit_err').innerHTML = '';
      if (!consents.every((k) => S.consents[k])) { errBox.innerHTML = `<p class="f-err">${esc(t('err_cons'))}</p>`; return; }
      if (over) return;
      const btn = act.querySelector('[data-act=next]');
      btn.disabled = true; btn.textContent = t('submitting');
      try {
        await JO.ensureSession();
        const payload = {
          registrant_type: 'klub', discipline: S.discipline, lang: JO.lang,
          contact: { name: S.contact.name.trim(), email: S.contact.email.trim(), phone: S.contact.phone.trim(), role: S.contact.role },
          club: S.club.mode === 'existing' ? { id: S.club.id }
            : { new: { name: S.club.name.trim(), kind: S.club.kind, province: S.club.abroad ? null : S.club.province, kab_kota: S.club.abroad ? null : S.club.kab_kota.trim(), country: S.club.abroad ? S.club.country.trim() : 'Indonesia' } },
          athletes: S.athletes.map((a) => ({ key: a.key, full_name: a.full_name.trim(), gender: a.gender, birth_date: a.birth_date, nationality: a.nationality,
            country: a.nationality === 'WNA' ? a.country.trim() : 'Indonesia', province: a.nationality === 'WNI' ? a.province : null, kab_kota: a.nationality === 'WNI' ? a.kab_kota.trim() : null,
            ...docPaths(a),
            guardian: JO.isMinor(a.birth_date) ? a.guardian : null })),
          entries: buildEntries(),
          teams: teams.map((T) => ({ level: T.level, name: T.name.trim(), members: T.members.map((m) => m.kind === 'form'
            ? { kind: 'form', key: m.ref }
            : m.kind === 'individu'
            ? { kind: 'individu', full_name: m.full_name.trim(), birth_date: m.birth_date }
            : { kind: 'tim', full_name: m.full_name.trim(), birth_date: m.birth_date, nationality: m.nationality,
                country: m.nationality === 'WNA' ? m.country.trim() : 'Indonesia',
                ...docPaths(m),
                guardian: JO.isMinor(m.birth_date) ? m.guardian : null, category_id: (memberCat(T, m) || {}).id }) })),
          consents: Object.fromEntries(consents.map((k) => [k, true])),
        };
        const r = await rpc('public_register', { p: payload });
        S.result = r;
        try {
          const my = JSON.parse(localStorage.getItem('jo26-my') || '[]');
          my.unshift({ code: r.code, token: r.token, at: new Date().toISOString(), discipline: S.discipline, n: people() });
          localStorage.setItem('jo26-my', JSON.stringify(my.slice(0, 30)));
        } catch (e) {}
        clearDraft();
        renderDone();
      } catch (err) {
        box.querySelector('#submit_err').innerHTML = `<p class="note bad" role="alert">${esc(err.message)}</p>`;
        btn.disabled = false; btn.textContent = t('submit');
      }
    } });
  }

  // ---------- selesai: tagihan & bayar ----------
  function renderDone() {
    const r = S.result;
    const statusUrl = `status.html?k=${encodeURIComponent(r.code)}&t=${encodeURIComponent(r.token)}`;
    const qris = CFG.payment.qris_image_url;
    app.innerHTML = `<section class="card">
        <p class="pill ok">${esc(t('done_title'))}</p>
        <p class="muted small" style="margin:14px 0 2px">${esc(t('done_code'))}</p>
        <p class="code" style="font-size:1.5rem;font-weight:800;color:var(--ink);margin:0 0 10px">${esc(r.code)}</p>
        <p class="small">${esc(t('done_email', { e: S.contact.email }))}</p>
      </section>
      ${r.payment_method === 'qris' ? `<section class="card timer" id="timer"></section><section class="card">
        <h2>${esc(t('pay_title'))}</h2>
        <div class="pay">
          <div class="qris">${qris ? `<img src="${esc(qris)}" alt="QRIS ${esc(CFG.payment.qris_merchant || 'Jabar Open 2026')}">` : `<p class="small muted" style="margin:8px">${esc(t('pay_noqris'))}</p>`}</div>
          <div>
            ${JO.amountHtml(r.total_amount, r.unique_code)}
            <p style="margin:10px 0 6px;font-weight:700">${esc(t('pay_exact'))}</p>
            <p class="small muted">${esc(t('pay_why'))}</p>
            <table class="breakdown" style="margin:12px 0"><tbody>
              ${r.base_amount - (r.team_amount || 0) ? `<tr><td>${esc(t('sum_fees'))}</td><td>${fmtRp(r.base_amount - (r.team_amount || 0))}</td></tr>` : ''}
              ${r.team_amount ? `<tr><td>${esc(t('sum_team'))}</td><td>${fmtRp(r.team_amount)}</td></tr>` : ''}
              <tr><td>${esc(t('sum_uc'))}</td><td>${fmtRp(r.unique_code)}</td></tr>
            </tbody></table>
            <p class="small">${t('pay_steps')}</p>
            <p class="small muted">${esc(t('pay_deadline', { d: CFG.registration.deadline_label || '12 November 2026' }))}</p>
          </div>
        </div>
      </section>
      <section class="card" id="proof">
        <h2>${esc(t('proof_title'))}</h2>
        <p class="small muted">${esc(t('proof_hint'))}</p>
        <div class="upload" id="proof_up"><label class="btn btn-dark" style="position:relative;overflow:hidden">${esc(t('proof_title'))}
          <input type="file" accept="image/*,application/pdf" style="position:absolute;inset:0;opacity:0;cursor:pointer"></label><span class="small" data-st></span></div>
      </section>` : `<section class="card"><p class="note info">${esc(t('pay_intl', { e: S.contact.email }))}</p></section>`}
      <div class="step-actions"><a class="btn btn-ghost" href="daftar.html" id="more">${esc(t('register_more'))}</a><a class="btn btn-primary" href="${statusUrl}">${esc(t('open_status'))}</a></div>`;
    const more = app.querySelector('#more');
    if (more) more.onclick = () => {
      // pendaftaran berikutnya dari klub yang sama: klub, disiplin, dan penanggung jawab dipertahankan
      S.athletes = []; S.pairs = []; S.teams = []; S.consents = {}; S.step = 3;
      saveDraft();
    };
    const up = app.querySelector('#proof_up');
    if (up) up.querySelector('input').onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      const st = up.querySelector('[data-st]'); st.innerHTML = `<span class="spinner"></span> ${esc(t('uploading'))}`;
      try {
        const u = await JO.uploadFile('bukti', file);
        await rpc('public_attach_proof', { p_code: r.code, p_token: r.token, p_path: u.path });
        up.classList.add('done'); up.innerHTML = `<span>${esc(t('proof_done'))}</span>`;
        r.proof_done = true; const tm = app.querySelector('#timer'); if (tm) tm.remove();
      } catch (err) { st.textContent = err.message; st.style.color = 'var(--bad)'; }
    };
    // hitung mundur 15 menit
    const tm = app.querySelector('#timer');
    if (tm && r.expires_at && !r.proof_done) {
      const end = new Date(r.expires_at).getTime();
      const hh = new Date(end).toLocaleTimeString(JO.lang === 'en' ? 'en-GB' : 'id-ID', { hour: '2-digit', minute: '2-digit' });
      const tick = () => {
        if (!document.body.contains(tm)) return clearInterval(iv);
        const left = Math.max(0, Math.round((end - Date.now()) / 1000));
        tm.classList.toggle('over', left === 0);
        tm.innerHTML = left > 0
          ? `<h2>${esc(t('timer_t', { m: Math.floor(left / 60) + ':' + String(left % 60).padStart(2, '0') }))}</h2><p class="small" style="margin:0">${esc(t('timer_d', { h: hh }))}</p>`
          : `<p class="note bad" style="margin:0">${esc(t('timer_over'))}</p>`;
        if (!left) clearInterval(iv);
      };
      const iv = setInterval(tick, 1000); tick();
    }
    window.scrollTo(0, 0);
  }

  // ---------- mulai ----------
  async function init() {
    JO.header('daftar.html'); JO.footer(); JO.applyI18n();
    try {
      CFG = await rpc('public_config');
    } catch (e) {
      app.innerHTML = `<div class="note bad">${esc(t('load_fail'))} ${esc(e.message)}</div><p><button class="btn btn-ghost" onclick="location.reload()">${esc(t('retry'))}</button></p>`;
      return;
    }
    if ((CFG.registration.form_version || 0) < 8) {
      const c = document.getElementById('closed'); c.hidden = false; c.textContent = t('form_old');
      app.innerHTML = ''; return;
    }
    if (!CFG.registration.open) {
      const c = document.getElementById('closed'); c.hidden = false; c.textContent = t('closed');
      app.innerHTML = ''; return;
    }
    const pre = JO.qs('disiplin');
    if (loadDraft()) JO.toast(t('draft_restored'));
    if (pre && CFG.disciplines.some((d) => d.code === pre.toUpperCase())) S.discipline = pre.toUpperCase();
    render();
    JO.onLang(() => { if (S.result) renderDone(); else render(); });
  }
  init();
})();
