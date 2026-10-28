/* Jabar Open 2026 — halaman FAQ */
(function () {
  'use strict';
  const { t, esc } = JO;
  JO.addDict({
    f_title: ['Pertanyaan yang sering diajukan', 'Frequently asked questions'],
    f_lead: ['Cari dengan kata kunci atau pilih kategori. Setiap pertanyaan punya tautan sendiri untuk dibagikan.', 'Search by keyword or pick a category. Every question has its own link to share.'],
    f_empty: ['Daftar pertanyaan sedang disiapkan panitia. Sementara itu, hubungi kami lewat kontak di bawah.', 'The committee is preparing the questions. Meanwhile, reach us through the contacts below.'],
    f_help_t: ['Belum menemukan jawabannya?', 'Still need an answer?'],
    f_mail_t: ['Pendaftaran dan pembayaran', 'Registration and payment'],
    f_mail_d: ['Sertakan kode pendaftaran (JO26-…) agar cepat ditangani.', 'Include your registration code (JO26-…) for a faster reply.'],
    f_ig: ['Pengumuman dan jadwal pertandingan dibagikan di Instagram lebih dulu.', 'Announcements and competition schedules appear on Instagram first.'],
    f_wa: ['Narahubung per disiplin (WhatsApp)', 'Discipline contacts (WhatsApp)'],
    f_send: ['Kirim email', 'Send an email'],
    cp_mag: ['Artistik Putra', "Men's Artistic"], cp_wag: ['Artistik Putri', "Women's Artistic"], cp_rg: ['Ritmik', 'Rhythmic'], cp_aer: ['Aerobik', 'Aerobic'],
  });
  const WA = [['cp_mag', 'Fegie Rizkia Mulyana', '0811-2348-753'], ['cp_wag', 'Vici Ayu', '0856-2383-455'],
    ['cp_rg', 'Yuanita Vidya M', '0815-6361-1403'], ['cp_aer', 'Mustika Fitri', '0816-605-281']];
  const waUrl = (n) => 'https://wa.me/62' + n.replace(/\D/g, '').replace(/^0/, '');

  function help() {
    document.getElementById('faq-help').innerHTML = `<h2>${esc(t('f_help_t'))}</h2>
      <div class="faq-contacts">
        <div><p class="small muted" style="margin:0 0 2px">${esc(t('f_mail_t'))}</p>
          <p style="margin:0"><a href="mailto:jabaropen2026@gmail.com"><strong>jabaropen2026@gmail.com</strong></a></p>
          <p class="small" style="margin:4px 0 0">${esc(t('f_mail_d'))}</p></div>
        <div><p class="small muted" style="margin:0 0 2px">Instagram</p>
          <p style="margin:0"><a href="https://www.instagram.com/gimnastikjabar/" target="_blank" rel="noopener"><strong>@gimnastikjabar</strong></a></p>
          <p class="small" style="margin:4px 0 0">${esc(t('f_ig'))}</p></div>
      </div>
      <h3 style="margin:18px 0 6px;font-size:1rem">${esc(t('f_wa'))}</h3>
      <ul class="faq-wa">${WA.map(([k, n, p]) => `<li><span class="small muted">${esc(t(k))}</span><span>${esc(n)}</span><a href="${waUrl(p)}" target="_blank" rel="noopener">${esc(p)}</a></li>`).join('')}</ul>`;
  }

  function init() {
    JO.header('faq.html'); JO.footer(); JO.applyI18n();
    help();
    const box = document.getElementById('faq-box');
    const w = window.JOFaq.mount(box, {
      lang: JO.lang, mode: 'page',
      onReady: (has) => {
        if (has === false) box.innerHTML = `<p class="note info" style="margin:0">${esc(t('f_empty'))}</p>`;
        try { sessionStorage.setItem('jo26-faq', has ? '1' : '0'); } catch (e) {}
      },
    });
    JO.onLang((l) => { w.setLang(l); help(); });
  }
  init();
})();
