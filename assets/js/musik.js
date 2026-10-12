/* Jabar Open 2026 — ganti / perbaiki tautan musik Ritmik */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    m_title: ['Musik Ritmik', 'Rhythmic music'],
    m_lead: ['Isi, perbaiki, atau ganti tautan musik atlet Ritmik. Masuk dengan kode pendaftaran dan email penanggung jawab.', 'Add, fix or change the music link for Rhythmic athletes. Sign in with the registration code and contact email.'],
    m_rules_t: ['Ketentuan musik', 'Music rules'],
    m_rule1: ['Satu folder Google Drive untuk setiap atlet, berisi semua file MP3 yang akan dipakai.', 'One Google Drive folder per athlete, holding every MP3 they will use.'],
    m_rule2: ['Atur akses folder ke "Siapa saja yang memiliki link" agar panitia bisa membukanya.', 'Set the folder access to "Anyone with the link" so the committee can open it.'],
    m_rule3: ['Musik bisa diganti satu kali per atlet, sampai start list kategorinya terbit. Perubahan berlaku langsung dan konfirmasi dikirim ke email penanggung jawab.', 'Music can be changed once per athlete, until the start list for its category is published. Changes apply at once and a confirmation goes to the contact email.'],
    m_rule4: ['Jika panitia menandai tautan "tidak bisa dibuka", perbaiki aksesnya lalu kirim lagi. Perbaikan ini tidak memakai kesempatan ganti.', 'If the committee marks a link "cannot be opened", fix the sharing and send it again. A fix does not use up the change.'],
    m_code: ['Kode pendaftaran', 'Registration code'], m_email: ['Email penanggung jawab', 'Contact email'],
    m_open: ['Buka', 'Open'], m_out: ['Keluar', 'Sign out'],
    m_err_input: ['Isi kode pendaftaran dan email yang valid.', 'Enter the registration code and a valid email.'],
    m_none: ['Tidak ada atlet Ritmik aktif di pendaftaran ini.', 'No active Rhythmic athletes in this registration.'],
    m_current: ['Tautan sekarang', 'Current link'], m_no_link: ['Belum ada tautan.', 'No link yet.'],
    m_updated: ['Diperbarui {d}', 'Updated {d}'],
    st_belum: ['Belum ada tautan', 'No link yet'], st_menunggu: ['Menunggu pemeriksaan panitia', 'Awaiting committee check'],
    st_ok: ['Sudah diperiksa, bisa dibuka', 'Checked, opens fine'], st_tidak_bisa: ['Tidak bisa dibuka', 'Cannot be opened'],
    m_note: ['Catatan panitia', 'Committee note'],
    m_new: ['Tautan folder Google Drive', 'Google Drive folder link'],
    m_fill: ['Simpan tautan', 'Save link'],
    m_fix: ['Kirim perbaikan', 'Send fix'],
    m_fix_hint: ['Periksa akses folder, lalu kirim lagi tautan yang sama atau tautan baru. Tidak memakai kesempatan ganti.', 'Check the folder access, then send the same link again or a new one. This does not use up the change.'],
    m_change_btn: ['Ganti musik (1 kali)', 'Change music (once)'],
    m_change_t: ['Ganti musik', 'Change music'],
    m_change_ok: ['Saya paham ini satu-satunya kesempatan ganti musik untuk atlet ini.', 'I understand this is the only music change for this athlete.'],
    m_change_go: ['Ganti sekarang', 'Change now'], m_cancel: ['Batal', 'Cancel'],
    m_used: ['Kesempatan ganti sudah dipakai.', 'The change has already been used.'],
    m_closed: ['Start list kategori ini sudah terbit, jadi musik tidak bisa diganti lewat halaman ini.', 'The start list for this category is published, so music can no longer be changed here.'],
    m_contact: ['Untuk keadaan khusus, hubungi narahubung Ritmik: {c}.', 'For special cases, contact the Rhythmic coordinator: {c}.'],
    m_err_url: ['Tautan harus dari Google Drive (diawali https://drive.google.com/).', 'The link must be a Google Drive link (starting with https://drive.google.com/).'],
    m_err_confirm: ['Centang pernyataan untuk melanjutkan.', 'Tick the statement to continue.'],
    m_saved: ['Tersimpan. Konfirmasi dikirim ke email penanggung jawab.', 'Saved. A confirmation was sent to the contact email.'],
    m_saving: ['Menyimpan…', 'Saving…'],
    m_status_link: ['Halaman status pendaftaran ada di tautan email konfirmasi.', 'The registration status page is linked in your confirmation email.'],
  });

  const app = document.getElementById('app');
  const validDrive = (u) => /^https:\/\/(drive|docs)\.google\.com\/\S+$/i.test((u || '').trim());
  const PILL = { belum: 'warn', menunggu: 'info', ok: 'ok', tidak_bisa: 'bad' };
  let CFG = null;
  let auth = { code: (JO.qs('k') || '').trim().toUpperCase(), email: '' };
  let D = null;

  function rgContact() {
    const d = CFG && CFG.disciplines.find((x) => x.code === 'RG');
    if (!d || !d.contact_name) return '';
    return d.contact_name + (d.contact_phone ? ` (${d.contact_phone})` : '');
  }
  function head() {
    return `<div class="page-head"><h1>${esc(t('m_title'))}</h1><p>${esc(t('m_lead'))}</p></div>
      <details class="note info m-rules" ${D ? '' : 'open'}><summary><b>${esc(t('m_rules_t'))}</b></summary>
        <ul>${['m_rule1', 'm_rule2', 'm_rule3', 'm_rule4'].map((k) => `<li>${esc(t(k))}</li>`).join('')}</ul></details>`;
  }

  function renderLogin(msg) {
    D = null;
    app.innerHTML = `${head()}
      <section class="card">
        <form id="f" class="grid-2" novalidate>
          <div class="field"><label class="f" for="fc">${esc(t('m_code'))}</label><input id="fc" type="text" placeholder="JO26-RG-0001" autocapitalize="characters" autocomplete="off" value="${esc(auth.code)}"></div>
          <div class="field"><label class="f" for="fe">${esc(t('m_email'))}</label><input id="fe" type="email" inputmode="email" autocomplete="email" value="${esc(auth.email)}"></div>
          <div><button class="btn btn-dark" type="submit">${esc(t('m_open'))}</button></div>
        </form>
        <div id="fmsg" style="margin-top:12px">${msg ? `<p class="note bad" role="alert">${esc(msg)}</p>` : ''}</div>
      </section>`;
    const f = app.querySelector('#f');
    f.onsubmit = async (e) => {
      e.preventDefault();
      const c = f.querySelector('#fc').value.trim().toUpperCase(), m = f.querySelector('#fe').value.trim();
      const out = app.querySelector('#fmsg');
      if (!c || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(m)) { out.innerHTML = `<p class="note bad" role="alert">${esc(t('m_err_input'))}</p>`; return; }
      const btn = f.querySelector('button'); btn.disabled = true;
      try {
        await JO.ensureSession();
        D = await rpc('public_music_lookup', { p_code: c, p_email: m });
        auth = { code: c, email: m };
        renderList();
      } catch (err) { out.innerHTML = `<p class="note bad" role="alert">${esc(err.message)}</p>`; }
      finally { btn.disabled = false; }
    };
  }

  function renderList() {
    const contact = rgContact();
    app.innerHTML = `${head()}
      <section class="card">
        <div class="row" style="justify-content:space-between;gap:10px;flex-wrap:wrap">
          <div><span class="code" style="font-size:1.2rem;font-weight:800;color:var(--ink)">${esc(D.code)}</span><br><span class="small muted">${esc(D.contact_name)}</span></div>
          <button type="button" class="btn btn-ghost btn-sm" id="out">${esc(t('m_out'))}</button>
        </div>
      </section>
      ${D.entries.length ? '' : `<p class="note warn">${esc(t('m_none'))}</p>`}
      <div id="list"></div>
      ${contact ? `<p class="small muted">${esc(t('m_contact', { c: contact }))}</p>` : ''}
      <p class="small muted">${esc(t('m_status_link'))}</p>`;
    app.querySelector('#out').onclick = () => { auth.email = ''; renderLogin(); };
    const list = app.querySelector('#list');
    D.entries.forEach((e) => list.appendChild(card(e)));
  }

  function card(e) {
    const el = document.createElement('section');
    el.className = 'ath';
    const cat = JO.lang === 'en' ? e.category_name_en : e.category_name_id;
    const st = e.music_url ? e.music_status : 'belum';
    el.innerHTML = `<div class="ath-head"><span class="bib">${esc(e.athlete_no || '')}</span><strong>${esc(e.athlete_name)}</strong></div>
      <div class="ath-body">
        <p class="small muted" style="margin:0 0 10px">${esc(cat)}</p>
        <p class="small" style="margin:0 0 6px"><span class="pill ${PILL[st] || ''}">${esc(t('st_' + st))}</span>
          ${e.music_updated_at ? ` <span class="muted">${esc(t('m_updated', { d: JO.fmtDateTime(e.music_updated_at) }))}</span>` : ''}</p>
        ${e.music_url ? `<p class="small" style="margin:0 0 6px"><strong>${esc(t('m_current'))}:</strong><br><a class="mono-link" href="${esc(e.music_url)}" target="_blank" rel="noopener">${esc(e.music_url)}</a></p>` : `<p class="small muted">${esc(t('m_no_link'))}</p>`}
        ${st === 'tidak_bisa' && e.music_note ? `<p class="note bad small" style="margin:8px 0">${esc(t('m_note'))}: ${esc(e.music_note)}</p>` : ''}
        <div class="m-act"></div>
      </div>`;
    const act = el.querySelector('.m-act');

    function form(kind) {
      const isChange = kind === 'change';
      act.innerHTML = `<div class="m-form">
          ${isChange ? `<h3 style="margin:12px 0 8px">${esc(t('m_change_t'))}</h3>` : ''}
          <div class="field music"><label class="f" for="u_${e.entry_id}">${esc(t('m_new'))}</label>
            <input id="u_${e.entry_id}" type="url" inputmode="url" autocomplete="off" spellcheck="false" placeholder="https://drive.google.com/drive/folders/…" value="${kind === 'fix' ? esc(e.music_url || '') : ''}">
            ${kind === 'fix' ? `<div class="f-hint">${esc(t('m_fix_hint'))}</div>` : ''}</div>
          ${isChange ? `<label class="check"><input type="checkbox" data-ok><span>${esc(t('m_change_ok'))}</span></label>` : ''}
          <div class="row" style="gap:8px;margin-top:6px">
            <button type="button" class="btn btn-primary btn-sm" data-go>${esc(t(kind === 'fill' ? 'm_fill' : kind === 'fix' ? 'm_fix' : 'm_change_go'))}</button>
            ${isChange ? `<button type="button" class="btn btn-ghost btn-sm" data-cancel>${esc(t('m_cancel'))}</button>` : ''}
          </div>
          <div data-err></div></div>`;
      const inp = act.querySelector('input[type=url]');
      const err = act.querySelector('[data-err]');
      const cancel = act.querySelector('[data-cancel]');
      if (cancel) cancel.onclick = () => draw();
      act.querySelector('[data-go]').onclick = async (ev) => {
        err.innerHTML = '';
        if (!validDrive(inp.value)) { err.innerHTML = `<p class="f-err">${esc(t('m_err_url'))}</p>`; inp.setAttribute('aria-invalid', 'true'); inp.focus(); return; }
        if (isChange && !act.querySelector('[data-ok]').checked) { err.innerHTML = `<p class="f-err">${esc(t('m_err_confirm'))}</p>`; return; }
        const b = ev.currentTarget; b.disabled = true; const old = b.textContent; b.textContent = t('m_saving');
        try {
          D = await rpc('public_music_set', { p_code: auth.code, p_email: auth.email, p_entry: e.entry_id, p_url: inp.value.trim() });
          renderList(); JO.toast(t('m_saved'));
        } catch (x) { err.innerHTML = `<p class="note bad small" role="alert" style="margin-top:8px">${esc(x.message)}</p>`; b.disabled = false; b.textContent = old; }
      };
      if (isChange) inp.focus();
    }
    function draw() {
      if (e.can_fill) return form('fill');
      if (e.can_fix) return form('fix');
      if (e.can_change) {
        act.innerHTML = `<button type="button" class="btn btn-ghost btn-sm" style="margin-top:8px" data-chg>${esc(t('m_change_btn'))}</button>`;
        act.querySelector('[data-chg]').onclick = () => form('change');
        return;
      }
      act.innerHTML = `<p class="small muted" style="margin:8px 0 0">${esc(t(e.startlist_published ? 'm_closed' : 'm_used'))}</p>`;
    }
    draw();
    return el;
  }

  async function init() {
    JO.header('musik.html'); JO.footer(); JO.applyI18n();
    try { CFG = await rpc('public_config'); } catch (e) { CFG = null; }
    renderLogin();
    JO.onLang(() => { if (D) renderList(); else renderLogin(); });
  }
  init();
})();
