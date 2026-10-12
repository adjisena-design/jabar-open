/* Jabar Open 2026 — verifikasi QR e-ticket & sertifikat */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    v_title: ['Verifikasi', 'Verification'],
    v_lead: ['Periksa keaslian e-ticket atau sertifikat Jabar Open 2026 dengan kode di bawah QR.', 'Check whether a Jabar Open 2026 e-ticket or certificate is genuine using the code under its QR.'],
    v_code: ['Kode verifikasi', 'Verification code'], v_check: ['Periksa', 'Check'],
    v_ticket_ok: ['E-ticket asli dan lunas', 'Genuine, paid e-ticket'],
    v_ticket_unpaid: ['E-ticket terdaftar, tetapi pembayaran belum lunas', 'Registered e-ticket, but payment is not confirmed'],
    v_cert_ok: ['Sertifikat asli', 'Genuine certificate'],
    v_cert_wait: ['Kode sertifikat dikenal, tetapi hasil kategorinya belum dipublikasikan', 'Known certificate code, but results for its category are not published yet'],
    v_none: ['Kode tidak dikenal. Periksa kembali penulisannya. Jika kode berasal dari dokumen resmi, hubungi panitia.', 'Unknown code. Check the spelling. If the code comes from an official document, contact the committee.'],
    v_name: ['Nama', 'Name'], v_no: ['Nomor atlet', 'Athlete number'], v_club: ['Klub', 'Club'], v_cat: ['Kategori', 'Category'],
    v_team_ok: ['Sertifikat Juara Beregu asli', 'Genuine team champion certificate'],
    v_team_wait: ['Kode sertifikat beregu dikenal, tetapi hasil beregu belum dipublikasikan atau tim tidak masuk tiga besar', 'Known team certificate code, but team results are not published yet or the team did not finish in the top three'],
    v_team: ['Tim', 'Team'], v_team_rank: ['Juara {r} beregu', 'Team rank {r}'],
    v_disc: ['Disiplin', 'Discipline'], v_result: ['Hasil', 'Result'], v_rank: ['Peringkat {r}', 'Rank {r}'], v_pri: ['Priangan: peringkat {r}', 'Priangan: rank {r}'],
  });
  const app = document.getElementById('app');
  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };

  function shell(inner, code) {
    app.innerHTML = `<div class="page-head"><h1>${esc(t('v_title'))}</h1><p>${esc(t('v_lead'))}</p></div>
      ${inner || ''}
      <section class="card"><form id="f" class="row" style="align-items:flex-end">
        <div class="field" style="flex:1;min-width:200px;margin:0"><label class="f" for="c">${esc(t('v_code'))}</label><input id="c" type="text" autocapitalize="characters" value="${esc(code || '')}"></div>
        <button class="btn btn-dark" type="submit">${esc(t('v_check'))}</button></form></section>`;
    app.querySelector('#f').onsubmit = (e) => { e.preventDefault(); const v = app.querySelector('#c').value.trim(); if (v) location.search = '?c=' + encodeURIComponent(v); };
  }
  async function check(code) {
    shell('<div class="empty"><span class="spinner"></span></div>', code);
    let r;
    try { r = await rpc('public_verify', { p_code: code }); }
    catch (e) { return shell(`<p class="note bad">${esc(e.message)}</p>`, code); }
    let html;
    if (r.type === 'ticket') {
      html = `<section class="card" style="border-left:6px solid ${r.valid ? 'var(--ok)' : 'var(--warn)'};border-radius:0 var(--r) var(--r) 0">
        <p class="pill ${r.valid ? 'ok' : 'warn'}">${esc(t(r.valid ? 'v_ticket_ok' : 'v_ticket_unpaid'))}</p>
        <dl class="kv" style="margin-top:12px"><dt>${esc(t('v_no'))}</dt><dd><span class="bib">${esc(r.athlete_no)}</span></dd>
          <dt>${esc(t('v_name'))}</dt><dd>${esc(r.name)}</dd><dt>${esc(t('v_club'))}</dt><dd>${esc(r.club)}</dd>
          <dt>${esc(t('v_disc'))}</dt><dd>${esc(DN[r.discipline] || r.discipline)}</dd>
          <dt>${esc(t('v_cat'))}</dt><dd>${(r.categories || []).map(esc).join('<br>')}</dd></dl></section>`;
    } else if (r.type === 'certificate' && r.valid) {
      const cat = JO.lang === 'en' ? r.category_name_en : r.category_name_id;
      html = `<section class="card" style="border-left:6px solid var(--ok);border-radius:0 var(--r) var(--r) 0">
        <p class="pill ok">${esc(t('v_cert_ok'))}</p>
        <dl class="kv" style="margin-top:12px"><dt>${esc(t('v_name'))}</dt><dd>${esc(r.name)}</dd>
          <dt>${esc(t('v_club'))}</dt><dd>${esc(r.club)}</dd><dt>${esc(t('v_cat'))}</dt><dd>${esc(cat)}</dd>
          <dt>${esc(t('v_result'))}</dt><dd>${r.rank ? esc(t('v_rank', { r: r.rank })) : '–'}${r.medal ? ` <span class="medal ${r.medal}"></span> ${esc(t('medal_' + r.medal))}` : ''}
          ${r.priangan_rank ? `<br>${esc(t('v_pri', { r: r.priangan_rank }))}${r.priangan_medal ? ` <span class="medal ${r.priangan_medal}"></span> ${esc(t('medal_' + r.priangan_medal))}` : ''}` : ''}</dd></dl></section>`;
    } else if (r.type === 'team_certificate' && r.valid) {
      html = `<section class="card" style="border-left:6px solid var(--ok);border-radius:0 var(--r) var(--r) 0">
        <p class="pill ok">${esc(t('v_team_ok'))}</p>
        <dl class="kv" style="margin-top:12px"><dt>${esc(t('v_name'))}</dt><dd>${esc(r.name)}</dd>
          <dt>${esc(t('v_team'))}</dt><dd>${esc(r.team)}</dd><dt>${esc(t('v_club'))}</dt><dd>${esc(r.club)}</dd>
          <dt>${esc(t('v_cat'))}</dt><dd>Beregu ${esc(DN[r.discipline] || r.discipline)} ${esc(r.level)}</dd>
          <dt>${esc(t('v_result'))}</dt><dd>${esc(t('v_team_rank', { r: r.rank }))} <span class="medal ${['emas', 'perak', 'perunggu'][r.rank - 1] || ''}"></span>${r.total != null ? ` <span class="muted num">(${Number(r.total).toFixed(3)})</span>` : ''}</dd></dl></section>`;
    } else if (r.type === 'team_certificate') {
      html = `<p class="note warn">${esc(t('v_team_wait'))}</p>`;
    } else if (r.type === 'certificate') {
      html = `<p class="note warn">${esc(t('v_cert_wait'))}</p>`;
    } else {
      html = `<p class="note bad">${esc(t('v_none'))}</p>`;
    }
    shell(html, code);
  }
  JO.header(''); JO.footer(); JO.applyI18n();
  const c = JO.qs('c');
  if (c) check(c.trim()); else shell('', '');
  JO.onLang(() => { if (c) check(c.trim()); else shell('', ''); });
})();
