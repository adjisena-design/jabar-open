/**
 * JABAR OPEN 2026 — pengirim email otomatis (Google Apps Script + Gmail)
 *
 * Cara kerja: setiap menit skrip ini mengambil antrean email dari database
 * (fungsi outbox_claim), mengirimnya lewat akun Gmail pemilik skrip, lalu
 * melaporkan hasilnya (outbox_report). Tidak ada kunci rahasia Supabase di sini;
 * akses antrean dijaga oleh SECRET dari setup.
 *
 * Pemasangan (sekali saja):
 *  1. Buka https://script.google.com dengan akun Gmail yang akan menjadi pengirim
 *     (mis. jabaropen2026@gmail.com), buat proyek baru, tempel seluruh file ini.
 *  2. Project Settings (ikon roda gigi) -> Script properties -> tambahkan:
 *       SUPABASE_URL = https://eyacnqlmhyyyatnlwhbe.supabase.co
 *       SUPABASE_KEY = (anon public key, sama dengan di assets/js/config.js)
 *       SECRET       = (secret_email dari hasil setup.sql)
 *       REPLY_TO     = adjisena.daffa@gmail.com   (opsional)
 *  3. Pilih fungsi `ujiKoneksi` lalu Run. Izinkan akses saat diminta.
 *  4. Pilih fungsi `pasangJadwal` lalu Run. Selesai: email terkirim tiap menit.
 */

var NAMA_PENGIRIM = 'Jabar Open 2026';

function kirimEmail() {
  var p = PropertiesService.getScriptProperties();
  var url = p.getProperty('SUPABASE_URL'), key = p.getProperty('SUPABASE_KEY'), secret = p.getProperty('SECRET');
  var replyTo = p.getProperty('REPLY_TO') || '';
  var sisa = MailApp.getRemainingDailyQuota();
  // tetap memanggil database walau kuota habis, agar proyek Supabase tidak dijeda
  var batch = panggil_(url, key, 'outbox_claim', { p_secret: secret, p_limit: Math.max(1, Math.min(20, sisa)) }) || [];
  var hasil = [];
  batch.forEach(function (m) {
    var cc = m.cc ? m.cc.split(',').filter(function (x) { return x; }) : [];
    if (sisa < 1 + cc.length) {
      hasil.push({ id: m.id, ok: false, release: true, error: 'Kuota harian Gmail habis, dicoba lagi besok' });
      return;
    }
    try {
      var opt = { htmlBody: m.html, name: NAMA_PENGIRIM };
      if (cc.length) opt.cc = cc.join(',');
      if (replyTo) opt.replyTo = replyTo;
      MailApp.sendEmail(m.to, m.subject, 'Buka email ini dalam tampilan HTML.', opt);
      sisa -= 1 + cc.length;
      hasil.push({ id: m.id, ok: true });
    } catch (e) {
      hasil.push({ id: m.id, ok: false, error: String(e && e.message ? e.message : e) });
    }
  });
  if (hasil.length) panggil_(url, key, 'outbox_report', { p_secret: secret, p_results: hasil });
}

function panggil_(url, key, fn, body) {
  var r = UrlFetchApp.fetch(url.replace(/\/$/, '') + '/rest/v1/rpc/' + fn, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { apikey: key, Authorization: 'Bearer ' + key },
    payload: JSON.stringify(body),
  });
  var code = r.getResponseCode(), text = r.getContentText();
  if (code >= 300) throw new Error(fn + ' gagal (' + code + '): ' + text);
  return text ? JSON.parse(text) : null;
}

function pasangJadwal() {
  ScriptApp.getProjectTriggers().forEach(function (t) { ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('kirimEmail').timeBased().everyMinutes(1).create();
  Logger.log('Jadwal terpasang: kirimEmail berjalan setiap 1 menit.');
}

function ujiKoneksi() {
  var p = PropertiesService.getScriptProperties();
  ['SUPABASE_URL', 'SUPABASE_KEY', 'SECRET'].forEach(function (k) {
    if (!p.getProperty(k)) throw new Error('Script property ' + k + ' belum diisi.');
  });
  Logger.log('Kuota email hari ini: ' + MailApp.getRemainingDailyQuota());
  kirimEmail();
  Logger.log('Koneksi ke database berhasil. Cek konsol panitia > Pengaturan > Pengirim email.');
}
