/* Jabar Open 2026 — formulir pendaftaran juri (publik) */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    j_title: ['Pendaftaran juri', 'Judge application'],
    j_lead: ['Untuk juri berbrevet yang ingin bertugas di Jabar Open 2026. Panitia memeriksa setiap pendaftaran dan menghubungi juri terpilih lewat WhatsApp.', 'For licensed judges who would like to officiate at Jabar Open 2026. The committee reviews every application and contacts selected judges on WhatsApp.'],
    j_ready: ['Siapkan foto KTP atau identitas lain, pas foto, dan (bila ada) sertifikat brevet. Berkas JPG, PNG, atau PDF, maks. 5 MB.', 'Have a photo of your ID card, a passport-style photo and, if you have one, your judging licence ready. JPG, PNG or PDF, up to 5 MB.'],
    j_s1: ['Data diri', 'Your details'],
    j_name: ['Nama lengkap (dengan gelar bila ada)', 'Full name (with titles, if any)'],
    j_phone: ['Nomor WhatsApp', 'WhatsApp number'], j_email: ['Email', 'Email'],
    j_city: ['Kota asal', 'Home city'], j_prov: ['Provinsi', 'Province'],
    j_s2: ['Disiplin dan brevet', 'Disciplines and licence'],
    j_s2_hint: ['Centang disiplin yang ingin Anda nilai, lalu pilih tingkat brevet tertinggi Anda untuk disiplin itu.', 'Tick each discipline you would like to judge, then choose your highest licence level for it.'],
    j_level: ['Tingkat brevet', 'Licence level'], j_level_ph: ['Pilih tingkat…', 'Choose a level…'],
    j_other: ['Sebutkan brevet Anda', 'Describe your licence'], j_year: ['Tahun brevet (opsional)', 'Licence year (optional)'],
    b_fig1: ['FIG Kategori 1', 'FIG Category 1'], b_fig2: ['FIG Kategori 2', 'FIG Category 2'], b_fig3: ['FIG Kategori 3', 'FIG Category 3'], b_fig4: ['FIG Kategori 4', 'FIG Category 4'],
    b_nas: ['Nasional', 'National'], b_prov: ['Provinsi/Daerah', 'Provincial/Regional'], b_none: ['Belum ada', 'None yet'], b_other: ['Lainnya', 'Other'],
    j_s3: ['Ketersediaan', 'Availability'],
    j_s3_hint: ['Centang hari Anda bisa hadir di Gymnasium Arcamanik (Desember 2026). Jadwal per disiplin ada di halaman utama.', 'Tick the days you can be at Gymnasium Arcamanik (December 2026). The schedule per discipline is on the home page.'],
    j_all: ['Pilih semua', 'Select all'],
    j_s4: ['Dokumen', 'Documents'],
    j_ktp: ['KTP atau identitas lain', 'ID card or other identity document'], j_photo: ['Pas foto', 'Passport-style photo'], j_cert: ['Sertifikat brevet (opsional)', 'Judging licence certificate (optional)'],
    j_up: ['Unggah', 'Upload'], j_replace: ['Ganti', 'Replace'], j_uploading: ['Mengunggah…', 'Uploading…'], j_uploaded: ['Terunggah', 'Uploaded'],
    j_note: ['Catatan untuk panitia (opsional)', 'Note for the committee (optional)'],
    j_note_ph: ['Mis. pengalaman menjadi juri, kejuaraan terakhir yang dinilai', 'E.g. judging experience, the last competitions you judged'],
    j_consent: ['Saya menyetujui panitia mengolah data dan dokumen ini hanya untuk seleksi dan penugasan juri Jabar Open 2026, sesuai UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi. Dokumen tidak dipublikasikan.', 'I agree the committee may process this data and these documents only to select and assign judges for Jabar Open 2026, under Indonesian Law No. 27 of 2022 on Personal Data Protection. Documents are not published.'],
    j_submit: ['Kirim pendaftaran', 'Submit application'], j_sending: ['Mengirim…', 'Sending…'],
    j_done_t: ['Pendaftaran terkirim', 'Application sent'],
    j_done: ['Terima kasih, {n}. Panitia akan memeriksa data Anda dan menghubungi lewat WhatsApp {p}. Konfirmasi juga dikirim ke email Anda.', 'Thank you, {n}. The committee will review your details and contact you on WhatsApp at {p}. A confirmation has also been sent to your email.'],
    j_home: ['Kembali ke beranda', 'Back to home'],
    e_name: ['Isi nama lengkap.', 'Enter your full name.'], e_phone: ['Isi nomor WhatsApp yang valid.', 'Enter a valid WhatsApp number.'],
    e_email: ['Isi email yang valid.', 'Enter a valid email address.'], e_disc: ['Pilih minimal satu disiplin.', 'Choose at least one discipline.'],
    e_level: ['Pilih tingkat brevet.', 'Choose a licence level.'], e_other: ['Sebutkan brevet Anda.', 'Describe your licence.'],
    e_days: ['Pilih minimal satu hari.', 'Choose at least one day.'], e_ktp: ['Unggah KTP atau identitas.', 'Upload your ID.'], e_photo: ['Unggah pas foto.', 'Upload a photo.'],
    e_wait: ['Tunggu unggahan selesai.', 'Wait for the upload to finish.'], e_consent: ['Centang persetujuan pengolahan data.', 'Tick the data processing consent.'],
    e_fix: ['Periksa kembali isian yang ditandai.', 'Please check the highlighted fields.'],
  });
  const app = document.getElementById('app');
  const DISC = [['MAG', 'Artistik Putra', "Men's Artistic"], ['WAG', 'Artistik Putri', "Women's Artistic"], ['RG', 'Ritmik', 'Rhythmic'], ['AER', 'Aerobik', 'Aerobic']];
  const LEVELS = [['FIG Kategori 1', 'b_fig1'], ['FIG Kategori 2', 'b_fig2'], ['FIG Kategori 3', 'b_fig3'], ['FIG Kategori 4', 'b_fig4'], ['Nasional', 'b_nas'], ['Provinsi/Daerah', 'b_prov'], ['Belum ada', 'b_none'], ['Lainnya', 'b_other']];
  const DAYS = ['2026-12-12', '2026-12-13', '2026-12-14', '2026-12-15', '2026-12-16', '2026-12-17', '2026-12-18', '2026-12-19', '2026-12-20'];
  const S = { full_name: '', phone: '', email: '', city: '', province: 'Jawa Barat', disciplines: [], brevet: {}, availability: [], note: '', consent: false,
    files: { ktp: null, photo: null, cert: null }, uploading: 0, done: false };
  const dname = (code) => { const d = DISC.find((x) => x[0] === code); return d ? (JO.lang === 'en' ? d[2] : d[1]) : code; };
  const dayLabel = (d) => JO.fmtDate(d, { weekday: 'short', day: 'numeric' });

  function render() {
    if (S.done) return renderDone();
    const R = window.JO_REGIONS;
    app.innerHTML = `<p class="note info">${esc(t('j_ready'))}</p>
      <form id="jf" novalidate>
      <section class="card"><h2>${esc(t('j_s1'))}</h2>
        <div class="grid-2">
          <div class="field"><label class="f" for="full_name">${esc(t('j_name'))}</label><input id="full_name" data-k="full_name" type="text" autocomplete="name" value="${esc(S.full_name)}"></div>
          <div class="field"><label class="f" for="phone">${esc(t('j_phone'))}</label><input id="phone" data-k="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="08xx-xxxx-xxxx" value="${esc(S.phone)}"></div>
          <div class="field"><label class="f" for="email">${esc(t('j_email'))}</label><input id="email" data-k="email" type="email" inputmode="email" autocomplete="email" value="${esc(S.email)}"></div>
          <div class="field"><label class="f" for="city">${esc(t('j_city'))}</label><input id="city" data-k="city" type="text" value="${esc(S.city)}"></div>
          <div class="field"><label class="f" for="province">${esc(t('j_prov'))}</label><select id="province" data-k="province">${R.provinces.map((p) => `<option ${S.province === p ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
        </div></section>
      <section class="card"><h2>${esc(t('j_s2'))}</h2><p class="muted small">${esc(t('j_s2_hint'))}</p>
        <div id="discs">${DISC.map(([code]) => {
          const on = S.disciplines.includes(code); const b = S.brevet[code] || {};
          return `<div class="jd ${on ? 'on' : ''}" data-d="${code}"><label class="check"><input type="checkbox" data-disc="${code}" ${on ? 'checked' : ''}><span><b>${esc(dname(code))}</b></span></label>
            ${on ? `<div class="grid-3 jd-body">
              <div class="field"><label class="f" for="lv_${code}">${esc(t('j_level'))}</label><select id="lv_${code}" data-lv="${code}"><option value="">${esc(t('j_level_ph'))}</option>${LEVELS.map(([v, k]) => `<option value="${esc(v)}" ${b.level === v ? 'selected' : ''}>${esc(t(k))}</option>`).join('')}</select></div>
              ${b.level === 'Lainnya' ? `<div class="field"><label class="f" for="ot_${code}">${esc(t('j_other'))}</label><input id="ot_${code}" data-ot="${code}" type="text" value="${esc(b.other || '')}"></div>` : ''}
              ${b.level && b.level !== 'Belum ada' ? `<div class="field"><label class="f" for="yr_${code}">${esc(t('j_year'))}</label><input id="yr_${code}" data-yr="${code}" type="number" inputmode="numeric" min="1980" max="2026" value="${esc(b.year || '')}"></div>` : ''}
            </div>` : ''}</div>`;
        }).join('')}</div></section>
      <section class="card"><h2>${esc(t('j_s3'))}</h2><p class="muted small">${esc(t('j_s3_hint'))}</p>
        <div class="days" id="days">${DAYS.map((d) => `<label class="day"><input type="checkbox" data-day="${d}" ${S.availability.includes(d) ? 'checked' : ''}><span>${esc(dayLabel(d))}</span></label>`).join('')}</div>
        <button type="button" class="btn btn-ghost btn-sm" id="alldays" style="margin-top:10px">${esc(t('j_all'))}</button></section>
      <section class="card"><h2>${esc(t('j_s4'))}</h2>
        <div class="grid-3">${[['ktp', 'j_ktp', 'image/*,application/pdf'], ['photo', 'j_photo', 'image/*'], ['cert', 'j_cert', 'image/*,application/pdf']].map(([k, l, acc]) => `<div class="field" data-slotwrap="${k}"><span class="f">${esc(t(l))}</span>
          <div class="upload ${S.files[k] ? 'done' : ''}" data-slot="${k}">${S.files[k] ? `<span class="small"><strong>${esc(t('j_uploaded'))}:</strong> ${esc(S.files[k].name)}</span>` : ''}
            <label class="btn btn-ghost btn-sm" style="position:relative;overflow:hidden">${esc(t(S.files[k] ? 'j_replace' : 'j_up'))}<input type="file" accept="${acc}" style="position:absolute;inset:0;opacity:0;cursor:pointer"></label>
            <span class="small muted" data-st></span></div></div>`).join('')}</div>
        <div class="field"><label class="f" for="note">${esc(t('j_note'))}</label><textarea id="note" data-k="note" rows="3" placeholder="${esc(t('j_note_ph'))}">${esc(S.note)}</textarea></div>
        <label class="check"><input type="checkbox" id="consent" ${S.consent ? 'checked' : ''}><span>${esc(t('j_consent'))}</span></label></section>
      <div id="err"></div>
      <div class="row" style="margin-top:14px"><button class="btn btn-primary" type="submit" id="send">${esc(t('j_submit'))}</button></div>
      </form>`;
    const f = app.querySelector('#jf');
    f.querySelectorAll('[data-k]').forEach((i) => i.addEventListener('input', () => { S[i.dataset.k] = i.value; }));
    f.querySelectorAll('[data-disc]').forEach((c) => c.onchange = () => {
      const d = c.dataset.disc;
      S.disciplines = c.checked ? S.disciplines.concat(d) : S.disciplines.filter((x) => x !== d);
      if (c.checked && !S.brevet[d]) S.brevet[d] = {};
      render(); const el = app.querySelector(`#lv_${d}`); if (el) el.focus();
    });
    f.querySelectorAll('[data-lv]').forEach((s) => s.onchange = () => { S.brevet[s.dataset.lv].level = s.value; render(); const el = app.querySelector(`#ot_${s.dataset.lv}`) || app.querySelector(`#lv_${s.dataset.lv}`); if (el) el.focus(); });
    f.querySelectorAll('[data-ot]').forEach((i) => i.oninput = () => { S.brevet[i.dataset.ot].other = i.value; });
    f.querySelectorAll('[data-yr]').forEach((i) => i.oninput = () => { S.brevet[i.dataset.yr].year = i.value; });
    f.querySelectorAll('[data-day]').forEach((c) => c.onchange = () => { S.availability = [...f.querySelectorAll('[data-day]:checked')].map((x) => x.dataset.day); });
    f.querySelector('#alldays').onclick = () => { S.availability = DAYS.slice(); f.querySelectorAll('[data-day]').forEach((c) => { c.checked = true; }); };
    f.querySelector('#consent').onchange = (e) => { S.consent = e.target.checked; };
    f.querySelectorAll('[data-slot]').forEach((slot) => {
      const k = slot.dataset.slot;
      slot.querySelector('input').onchange = async (e) => {
        const file = e.target.files[0]; if (!file) return;
        const st = slot.querySelector('[data-st]'); st.innerHTML = `<span class="spinner"></span> ${esc(t('j_uploading'))}`; st.style.color = '';
        S.uploading++;
        try { const r = await JO.uploadFile('dokumen', file); S.files[k] = { path: r.path, name: file.name }; S.uploading--; render(); }
        catch (err) { S.uploading--; st.textContent = err.message; st.style.color = 'var(--bad)'; }
      };
    });
    f.onsubmit = submit;
  }

  function fieldErr(el, msg) {
    if (!el) return;
    const wrap = el.closest('.field') || el.closest('section') || el;
    if (wrap.querySelector(':scope > .f-err')) return;
    wrap.insertAdjacentHTML('beforeend', `<p class="f-err">${esc(msg)}</p>`);
  }
  async function submit(e) {
    e.preventDefault();
    const f = app.querySelector('#jf');
    f.querySelectorAll('.f-err').forEach((x) => x.remove());
    const errBox = app.querySelector('#err'); errBox.innerHTML = '';
    const bad = [];
    const chk = (cond, sel, msg) => { if (!cond) { const el = f.querySelector(sel); fieldErr(el, t(msg)); bad.push(el); } };
    chk(S.full_name.trim().length >= 3, '#full_name', 'e_name');
    chk(S.phone.replace(/\D/g, '').length >= 9, '#phone', 'e_phone');
    chk(/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(S.email.trim()), '#email', 'e_email');
    chk(S.disciplines.length > 0, '#discs', 'e_disc');
    S.disciplines.forEach((d) => {
      const b = S.brevet[d] || {};
      chk(!!b.level, `#lv_${d}`, 'e_level');
      if (b.level === 'Lainnya') chk((b.other || '').trim().length >= 2, `#ot_${d}`, 'e_other');
    });
    chk(S.availability.length > 0, '#days', 'e_days');
    chk(!!S.files.ktp, '[data-slotwrap=ktp] .upload', 'e_ktp');
    chk(!!S.files.photo, '[data-slotwrap=photo] .upload', 'e_photo');
    chk(S.consent, '#consent', 'e_consent');
    if (S.uploading) { errBox.innerHTML = `<p class="note warn">${esc(t('e_wait'))}</p>`; return; }
    if (bad.length) { errBox.innerHTML = `<p class="note bad">${esc(t('e_fix'))}</p>`; const el = bad.find(Boolean); if (el) { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); if (el.focus) el.focus({ preventScroll: true }); } return; }
    const btn = app.querySelector('#send'); btn.disabled = true; btn.textContent = t('j_sending');
    const brevet = {};
    S.disciplines.forEach((d) => { const b = S.brevet[d]; brevet[d] = { level: b.level }; if (b.level === 'Lainnya') brevet[d].other = b.other.trim(); if (b.year) brevet[d].year = String(b.year); });
    try {
      await JO.ensureSession();
      await rpc('public_jury_apply', { p: { full_name: S.full_name.trim(), phone: S.phone.trim(), email: S.email.trim(), city: S.city.trim(), province: S.province,
        disciplines: S.disciplines, brevet, availability: S.availability.slice().sort(), note: S.note.trim(),
        ktp_path: S.files.ktp.path, photo_path: S.files.photo.path, cert_path: S.files.cert ? S.files.cert.path : null, consent: true } });
      S.done = true; renderDone();
    } catch (err) {
      errBox.innerHTML = `<p class="note bad">${esc(err.message)}</p>`;
      btn.disabled = false; btn.textContent = t('j_submit');
    }
  }
  function renderDone() {
    app.innerHTML = `<section class="card"><h2>${esc(t('j_done_t'))}</h2><p>${esc(t('j_done', { n: S.full_name.trim(), p: S.phone.trim() }))}</p>
      <p><a class="btn btn-ghost" href="index.html">${esc(t('j_home'))}</a></p></section>`;
    window.scrollTo(0, 0);
  }

  JO.header(''); JO.footer(); JO.applyI18n();
  JO.ensureSession().catch(() => {});
  render();
  JO.onLang(render);
})();
