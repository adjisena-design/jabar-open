/* =====================================================================
   Jabar Open 2026 — konsol panitia (owner, superadmin, admin, TD, juri)
   ===================================================================== */
(function () {
  'use strict';
  const { esc, fmtRp, rpc } = JO;
  const root = document.getElementById('root');
  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };
  const DISCS = ['MAG', 'WAG', 'RG', 'AER'];
  const ROLE_CLUB = { pemilik: 'pemilik klub', admin: 'admin klub', pelatih: 'pelatih', manajer: 'manajer/official', lainnya: 'lainnya', atlet: 'atlet', ortu: 'orang tua/wali' };
  const ROLE = { owner: 'Owner', superadmin: 'Superadmin', admin: 'Admin', td: 'TD', juri: 'Juri', pemantau: 'Pemantau' };
  const ST = { menunggu_pembayaran: 'Menunggu pembayaran', menunggu_verifikasi: 'Menunggu verifikasi', lunas: 'Lunas', perlu_perbaikan: 'Perlu perbaikan', dibatalkan: 'Dibatalkan' };
  let ME = null, CATS = null;
  const isSuper = () => ME && (ME.role === 'owner' || ME.role === 'superadmin');
  const isAdmin = () => ME && ['owner', 'superadmin', 'admin'].includes(ME.role);
  const isTD = () => ME && (ME.role === 'td' || ME.role === 'pemantau');   // hanya baca di halaman pertandingan
  const isViewer = () => ME && ME.role === 'pemantau';                        // pemantau: halaman pertandingan saja
  const canSee = () => isAdmin() || isTD();   // halaman pertandingan: admin ke atas, TD & pemantau hanya baca
  const roMode = () => (ME && ME.role === 'pemantau' ? 'Mode pemantau' : 'Mode TD');
  let pageTimer = null;                        // polling halaman aktif (chat), dihentikan saat pindah halaman
  const setPageTimer = (fn, ms) => { clearInterval(pageTimer); pageTimer = setInterval(fn, ms); };
  const myDiscs = () => (ME && ME.discipline ? [ME.discipline] : DISCS);
  // Tabel di ponsel tampil sebagai kartu: setiap sel diberi label dari judul kolomnya,
  // isinya dibungkus agar label dan nilai bisa berdampingan. Node dipindahkan (bukan
  // disalin) sehingga pendengar klik tetap menempel.
  function labelTables(scope) {
    (scope || document).querySelectorAll('table.tbl').forEach((tb) => {
      const heads = [];
      const hr = tb.tHead && tb.tHead.rows[tb.tHead.rows.length - 1];
      if (hr) [...hr.cells].forEach((th) => { const sub = th.querySelector('.tiny'); const c = th.cloneNode(true); c.querySelectorAll('br').forEach((x) => x.replaceWith(' ')); const lab = (sub ? sub.textContent : c.textContent).replace(/\s+/g, ' ').trim(); for (let k = 0; k < (th.colSpan || 1); k++) heads.push(lab); });
      tb.classList.toggle('tbl-nohead', !hr);
      [...tb.tBodies].forEach((tbd) => [...tbd.rows].forEach((tr) => {
        let col = 0;
        [...tr.cells].forEach((td) => {
          if (td.tagName === 'TD') {
            const lab = td.colSpan > 1 ? '' : (heads[col] || '');
            if (td.dataset.label !== lab) td.dataset.label = lab;
            const only = td.childNodes.length === 1 && td.firstChild.nodeType === 1 && td.firstChild.classList.contains('tdv');
            if (!only && td.childNodes.length) {
              const w = document.createElement('div'); w.className = 'tdv';
              while (td.firstChild) w.appendChild(td.firstChild);
              td.appendChild(w);
            }
          }
          col += td.colSpan || 1;
        });
      }));
    });
  }
  let labelQueued = false;
  new MutationObserver(() => {
    if (labelQueued) return; labelQueued = true;
    requestAnimationFrame(() => { labelQueued = false; labelTables(document); });
  }).observe(document.body, { childList: true, subtree: true });

  const num3 = (v) => (v == null || v === '' ? '–' : Number(v).toFixed(3));
  const dt = (d) => JO.fmtDateTime(d);
  const pill = (s) => JO.statusPill(s);
  const wa = (p) => { const d = String(p || '').replace(/\D/g, '').replace(/^0/, '62'); return d ? `https://wa.me/${d}` : '#'; };
  const catName = (id) => { const c = CATS && CATS.categories.find((x) => x.id === Number(id)); return c ? c.name_id : '#' + id; };
  const discApps = (code) => ((CATS && CATS.disciplines.find((d) => d.code === code)) || { apparatus: [] }).apparatus;
  const appName = (disc, code) => { const a = discApps(disc).find((x) => x.code === code); return a ? a.id : code; };
  const DOCS = [['akte_path', 'Akte'], ['ktp_path', 'KTP'], ['ijazah_path', 'Ijazah'], ['passport_path', 'Paspor'], ['bpjs_path', 'BPJS TK'], ['photo_path', 'Pas foto']];
  // hapus berkas di penyimpanan setelah data dihapus (owner/superadmin), lalu catat di Log
  async function removeFiles(files, ctx) {
    const by = {}; (files || []).forEach((f) => { (by[f.bucket] = by[f.bucket] || []).push(f.path); });
    let n = 0;
    for (const [b, paths] of Object.entries(by)) {
      const { data, error } = await JO.sb.storage.from(b).remove(paths);
      if (error) { JO.toast('Data terhapus, tetapi berkas gagal dihapus: ' + error.message, 'bad'); continue; }
      n += (data || []).length;
    }
    if (n) { try { await api('console_log_files_removed', { p_count: n, p_context: ctx }); } catch (e) {} }
    return n;
  }

  // ---------------- dasar ----------------
  async function api(fn, args) {
    try { return await rpc(fn, args || {}); }
    catch (e) {
      if (e.hint === 'ERR_SESSION' && fn !== 'console_login') { ME = null; showLogin('Sesi panitia berakhir. Masuk lagi dengan kode akses.'); }
      throw e;
    }
  }
  const dlg = document.getElementById('dlg');
  function dialog({ title, body, ok = 'Simpan', okClass = 'btn-primary', cancel = 'Batal', onOk, wide }) {
    dlg.style.maxWidth = wide ? 'min(900px, calc(100% - 24px))' : '';
    dlg.innerHTML = `<form method="dialog" novalidate><div class="dlg-head"><h2 style="margin:0;font-size:1.15rem">${esc(title)}</h2></div>
      <div class="dlg-body">${body}<div data-err></div></div>
      <div class="dlg-foot">${cancel ? `<button type="button" class="btn btn-ghost" data-x>${esc(cancel)}</button>` : ''}${ok ? `<button type="submit" class="btn ${okClass}" data-ok>${esc(ok)}</button>` : ''}</div></form>`;
    dlg.showModal();
    return new Promise((resolve) => {
      const x = dlg.querySelector('[data-x]');
      if (x) x.onclick = () => { dlg.close(); resolve(null); };
      dlg.onclose = () => resolve(null);
      dlg.querySelector('form').onsubmit = async (e) => {
        e.preventDefault();
        const btn = dlg.querySelector('[data-ok]'); if (btn) btn.disabled = true;
        dlg.querySelector('[data-err]').innerHTML = '';
        try {
          const r = onOk ? await onOk(dlg) : true;
          if (r === false) { if (btn) btn.disabled = false; return; }
          dlg.onclose = null; dlg.close(); resolve(r);
        } catch (err) {
          dlg.querySelector('[data-err]').innerHTML = `<p class="note bad" style="margin-top:12px">${esc(err.message)}</p>`;
          if (btn) btn.disabled = false;
        }
      };
    });
  }
  function askReason(title, label, opts) {
    opts = opts || {};
    return dialog({ title, ok: opts.ok || 'Lanjut', okClass: opts.okClass || 'btn-primary',
      body: `${opts.intro ? `<p>${opts.intro}</p>` : ''}<label class="f" for="rsn">${esc(label)}</label><textarea id="rsn" ${opts.required === false ? '' : 'required'}>${esc(opts.value || '')}</textarea>`,
      onOk: (d) => {
        const v = d.querySelector('#rsn').value.trim();
        if (opts.required !== false && v.length < (opts.min || 3)) throw new Error('Tulis alasan yang jelas.');
        return v || '';
      } });
  }
  async function signed(bucket, path) {
    const { data, error } = await JO.sb.storage.from(bucket).createSignedUrl(path, 900);
    if (error) throw new Error('Berkas tidak bisa dibuka: ' + error.message);
    return data.signedUrl;
  }
  async function preview(bucket, path, title) {
    let url;
    try { url = await signed(bucket, path); } catch (e) { return JO.toast(e.message, 'bad'); }
    const pdf = /\.pdf$/i.test(path);
    dialog({ title, ok: null, cancel: 'Tutup', wide: true,
      body: `<div class="doc-prev">${pdf ? `<iframe src="${esc(url)}" title="${esc(title)}"></iframe>` : `<a href="${esc(url)}" target="_blank" rel="noopener"><img src="${esc(url)}" alt="${esc(title)}"></a>`}</div>
        <p class="small" style="margin-top:8px"><a href="${esc(url)}" target="_blank" rel="noopener">Buka di tab baru</a> (tautan berlaku 15 menit)</p>` });
  }
  function exportXlsx(filename, rows, cols) {
    const data = rows.map((r) => Object.fromEntries(cols.map(([k, label, fn]) => [label, fn ? fn(r) : (r[k] == null ? '' : r[k])])));
    const ws = XLSX.utils.json_to_sheet(data);
    ws['!cols'] = cols.map(([, label]) => ({ wch: Math.max(10, Math.min(40, label.length + 4)) }));
    const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, 'Data');
    XLSX.writeFile(wb, filename);
  }
  const discSelect = (id, val, allLabel) => `<div class="field"><label class="f" for="${id}">Disiplin</label><select id="${id}">
    ${ME.discipline ? '' : `<option value="">${esc(allLabel || 'Semua disiplin')}</option>`}
    ${myDiscs().map((d) => `<option value="${d}" ${val === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>`;
  function catSelect(id, disc, val, filterFn) {
    const list = CATS.categories.filter((c) => (!disc || c.discipline === disc) && (!filterFn || filterFn(c)));
    return `<div class="field" style="min-width:260px;flex:1"><label class="f" for="${id}">Kategori</label><select id="${id}"><option value="">Pilih kategori…</option>
      ${list.map((c) => `<option value="${c.id}" ${Number(val) === c.id ? 'selected' : ''}>${esc(c.name_id)} (${c.paid}/${c.registered})</option>`).join('')}</select></div>`;
  }
  async function refreshCats() { CATS = await api('console_categories', { p_discipline: null }); }
  function loading(v) { v.innerHTML = '<div class="empty"><span class="spinner"></span></div>'; }
  function fail(v, e) { v.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; }
  function parseScore(s) { const v = String(s).trim().replace(',', '.'); if (v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; }

  // ---------------- masuk ----------------
  function showLogin(msg) {
    root.innerHTML = `<div class="login">
      <section class="lg-hero" aria-hidden="false">
        <img class="lg-star s1" src="../assets/img/deco/star-red.webp" alt="" width="420" height="420">
        <img class="lg-star s2" src="../assets/img/deco/star-white.webp" alt="" width="420" height="420">
        <img class="lg-star s3" src="../assets/img/deco/star-gold.webp" alt="" width="420" height="420">
        <div class="lg-brand"><img src="../assets/img/brand/jabar-open-white.webp" alt="Jabar Open 2026" width="600" height="409"><span class="lg-div"></span><img class="gi" src="../assets/img/brand/gi-jabar-white.webp" alt="Gimnastik Indonesia Jawa Barat" width="700" height="335"></div>
        <div class="lg-text">
          <p class="lg-eyebrow">Khusus panitia &amp; juri</p>
          <h1 class="lg-title">Konsol <em>Panitia</em></h1>
          <p class="lg-sub"><span>Jabar Open 2026 · Gymnasium Arcamanik</span><span class="lg-date">12–20 Desember 2026</span></p>
        </div>
        <div class="lg-stage">
          <img class="lg-athletes" src="../assets/img/hero/athletes.webp" srcset="../assets/img/hero/athletes-800.webp 800w, ../assets/img/hero/athletes.webp 1570w" sizes="(max-width:900px) 110vw, 50vw" alt="" width="1570" height="1290">
          <img class="lg-strip" src="../assets/img/hero/strip.webp" srcset="../assets/img/hero/strip-1280.webp 1280w, ../assets/img/hero/strip.webp 2560w" sizes="(max-width:900px) 160vw, 60vw" alt="" width="2560" height="455">
        </div>
      </section>
      <section class="lg-panel"><div class="card">
      <span class="lg-badge">Konsol, bukan halaman publik</span>
      <h2 style="font-size:1.45rem;margin:14px 0 6px">Masuk</h2>
      <p class="muted">Masukkan kode akses pribadi dari koordinator. Satu kode untuk satu orang; setiap tindakan tercatat atas nama pemegang kode.</p>
      ${msg ? `<p class="note warn">${esc(msg)}</p>` : ''}
      <form id="lf" novalidate><label class="f" for="code">Kode akses</label>
        <input id="code" class="codein" type="text" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="JO-XXXX-XXXX" required>
        <button class="btn btn-primary" style="width:100%;margin-top:12px" type="submit">Masuk</button></form>
      <div id="lmsg" style="margin-top:12px"></div>
      <p class="tiny muted" style="margin-top:18px">Kode hilang atau bocor? Minta superadmin menonaktifkan dan membuat kode baru.</p></div>
      <a class="lg-public" href="../index.html">Ke situs publik Jabar Open 2026</a></section></div>`;
    const f = root.querySelector('#lf');
    f.querySelector('#code').focus();
    f.onsubmit = async (e) => {
      e.preventDefault();
      const code = f.querySelector('#code').value.trim();
      if (!code) return;
      const btn = f.querySelector('button'); btn.disabled = true; btn.textContent = 'Memeriksa…';
      try {
        await JO.ensureSession();
        const r = await rpc('console_login', { p_code: code });
        if (!r.ok) { root.querySelector('#lmsg').innerHTML = `<p class="note bad">${esc(r.message)}</p>`; return; }
        ME = r.staff; await startApp();
      } catch (err) { root.querySelector('#lmsg').innerHTML = `<p class="note bad">${esc(err.message)}</p>`; }
      finally { btn.disabled = false; btn.textContent = 'Masuk'; }
    };
  }

  // ---------------- kerangka ----------------
  // ikon garis sederhana (24x24)
  const IC = {
    chev: '<path d="M9 6l6 6-6 6"/>',
    home: '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
    inbox: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 13h5l2 3h4l2-3h5"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-5.5 6.5-5.5s5.9 1.9 6.5 5.5"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14.8c1.7.8 2.8 2.6 3 5.2"/>',
    music: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    tag: '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.5"/>',
    list: '<path d="M9 6h12M9 12h12M9 18h12"/><path d="M4 5h1v3M4 11.5c1-1 2-.5 2 .3 0 .9-2 1.6-2 2.7h2M4 17h2l-1 1.5c1 0 1.2 1.6 0 1.7-.6 0-1-.3-1-.6"/>',
    pen: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
    trophy: '<path d="M8 4h8v5a4 4 0 0 1-8 0z"/><path d="M8 6H4v1a4 4 0 0 0 4 4M16 6h4v1a4 4 0 0 1-4 4"/><path d="M12 13v4M8 21h8M9 21v-1.5c0-1 1.3-2.5 3-2.5s3 1.5 3 2.5V21"/>',
    wallet: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18M16 15h2"/><path d="M6 6V5a2 2 0 0 1 2-2h9"/>',
    flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M15 8l2 2"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
    log: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
    out: '<path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h11"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    dots: '<circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>',
    chat: '<path d="M4 5h16v11H9l-5 4z"/><path d="M8 9h8M8 12h5"/>',
    bug: '<path d="M12 3l9 16H3z"/><path d="M12 9v4M12 16v.5"/>',
    phone: '<path d="M5 3h4l2 5-2.5 1.5a11 11 0 0 0 6 6L16 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 5a2 2 0 0 1 2-2z"/>',
    whistle: '<circle cx="8" cy="14" r="5"/><path d="M12 11l9-4v5l-8 1"/><path d="M8 4v3M4.5 5.5l1.5 2"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.6 9.3a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.2-2.4 3.8M12 17v.5"/>',
    check: '<path d="M4 12l5 5L20 6"/>', clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', alert: '<path d="M12 3l10 18H2z"/><path d="M12 10v4M12 17.5v.5"/>',
  };
  const icon = (k) => `<svg viewBox="0 0 24 24" aria-hidden="true">${IC[k] || ''}</svg>`;

  // menu aksi baris: tombol utama opsional + "…" berisi aksi lain
  // items: [{ label, act, danger, sep }]; tombol berisi data-rm-act="<act>"
  function rowMenu(primary, items) {
    const list = items.filter(Boolean);
    return `<span class="rm">${primary || ''}${list.length ? `<button type="button" class="rm-btn" aria-label="Aksi lain" aria-haspopup="true">${icon('dots')}</button>
      <span class="rm-pop" role="menu">${list.map((x) => x.sep ? '<hr>' : `<button type="button" role="menuitem" class="${x.danger ? 'danger' : ''}" ${x.attr || ''}>${esc(x.label)}</button>`).join('')}</span>` : ''}</span>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('.rm-btn');
    document.querySelectorAll('.rm.open').forEach((m) => { if (!b || m !== b.parentElement) m.classList.remove('open'); });
    if (b) {
      const m = b.parentElement; m.classList.toggle('open'); e.stopPropagation();
      if (m.classList.contains('open')) {
        const pop = m.querySelector('.rm-pop'); const r = b.getBoundingClientRect();
        pop.style.position = 'fixed'; pop.style.right = 'auto';
        const w = Math.max(pop.offsetWidth, 170), h = pop.offsetHeight;
        pop.style.left = Math.max(8, Math.min(window.innerWidth - w - 8, r.right - w)) + 'px';
        pop.style.top = (r.bottom + 4 + h > window.innerHeight ? Math.max(8, r.top - h - 4) : r.bottom + 4) + 'px';
      }
    }
    else if (e.target.closest('.rm-pop button')) document.querySelectorAll('.rm.open').forEach((m) => m.classList.remove('open'));
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') document.querySelectorAll('.rm.open').forEach((m) => m.classList.remove('open')); });
  window.addEventListener('scroll', () => document.querySelectorAll('.rm.open').forEach((m) => m.classList.remove('open')), true);

  // ---------- jam tugas juri (WIB) ----------
  const BLN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  const winDay = (d) => { const [y, m, dd] = String(d).split('-').map(Number); return `${dd} ${BLN[m - 1]} ${y}`; };
  const winLabel = (w) => (w ? `${winDay(w.date)}, ${String(w.from).replace(':', '.')}–${String(w.to).replace(':', '.')}` : '');
  const winRow = (w) => `<div class="win-row"><input type="date" data-wd value="${esc(w.date || '')}" min="2026-12-01" max="2026-12-31" aria-label="Tanggal">
      <input type="time" data-wf value="${esc(w.from || '07:00')}" step="900" aria-label="Mulai"><span class="muted">–</span><input type="time" data-wt value="${esc(w.to || '17:00')}" step="900" aria-label="Selesai">
      <button type="button" class="btn btn-ghost btn-sm" data-wdel aria-label="Hapus baris">Hapus</button></div>`;
  const winEditor = (list) => `<div class="field win-ed"><span class="f">Jam tugas (WIB)</span>
      <div class="f-hint" style="margin:0 0 8px">Tambahkan hari dan rentang jam bertugas. Di luar jam ini juri tetap bisa masuk dan melihat, tetapi tidak bisa mengisi nilai. Kosongkan bila juri boleh mengisi nilai kapan saja.</div>
      <div class="win-rows">${(list || []).map(winRow).join('')}</div>
      <button type="button" class="btn btn-ghost btn-sm" data-wadd>+ Tambah hari</button></div>`;
  const readWindows = (scope) => [...scope.querySelectorAll('.win-row')].map((r) => ({ date: r.querySelector('[data-wd]').value, from: r.querySelector('[data-wf]').value, to: r.querySelector('[data-wt]').value }))
    .filter((w) => w.date || w.from !== '07:00' || w.to !== '17:00');
  document.addEventListener('click', (e) => {
    const add = e.target.closest('[data-wadd]');
    if (add) {
      const box = add.closest('.win-ed').querySelector('.win-rows');
      const last = [...box.querySelectorAll('.win-row')].pop();
      let date = '2026-12-12', from = '07:00', to = '17:00';
      if (last) {
        const d = last.querySelector('[data-wd]').value;
        if (d) { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + 1); date = x.toISOString().slice(0, 10); }
        from = last.querySelector('[data-wf]').value || from; to = last.querySelector('[data-wt]').value || to;
      }
      box.insertAdjacentHTML('beforeend', winRow({ date, from, to }));
    }
    const del = e.target.closest('[data-wdel]');
    if (del) del.closest('.win-row').remove();
  });
  const winSummary = (s) => {
    if (s.role !== 'juri') return '';
    const ws = s.access_windows || [];
    if (!ws.length) return '<br>Jam tugas: kapan saja';
    const st = s.window || {};
    return `<br>Jam tugas: ${ws.map((w) => esc(winLabel(w))).join('; ')}<br><span class="pill ${st.open ? 'ok' : ''}">${st.open ? 'sedang bertugas' : 'di luar jam: hanya lihat'}</span>`;
  };

  const PAGES = [
    ['ringkasan', 'Ringkasan', () => isAdmin(), pageDashboard, 'home', 'Utama'],
    ['chat', 'Chat panitia', () => !isViewer(), pageChat, 'chat', 'Komunikasi'],
    ['laporan', 'Laporan masalah', () => !isViewer(), pageIssues, 'bug', 'Komunikasi'],
    ['kontak', 'Kontak', () => !isViewer(), pageContacts, 'phone', 'Komunikasi'],
    ['faq', 'FAQ situs', () => isAdmin(), pageFaq, 'help', 'Komunikasi'],
    ['pendaftaran', 'Pendaftaran', () => isAdmin(), pageSubmissions, 'inbox', 'Peserta'],
    ['atlet', 'Data atlet', () => isAdmin(), pageAthletes, 'users', 'Peserta'],
    ['musik', 'Musik Ritmik', () => isAdmin() && (!ME.discipline || ME.discipline === 'RG'), pageMusic, 'music', 'Peserta'],
    ['klub', 'Klub', () => isAdmin(), pageClubs, 'flag', 'Peserta'],
    ['kategori', 'Kategori', () => canSee(), pageCategories, 'tag', 'Pertandingan'],
    ['startlist', 'Start list', () => canSee(), pageStartlist, 'list', 'Pertandingan'],
    ['nilai', 'Penilaian', () => true, pageScoring, 'pen', 'Pertandingan'],
    ['hasil', 'Hasil & medali', () => canSee(), pageResults, 'trophy', 'Pertandingan'],
    ['juri', 'Pendaftaran juri', () => isAdmin(), pageJury, 'whistle', 'Pertandingan'],
    ['ledger', 'Ledger', () => isSuper(), pageLedger, 'wallet', 'Keuangan'],
    ['akses', 'Kode akses', () => isSuper(), pageAccess, 'key', 'Sistem'],
    ['pengaturan', 'Pengaturan', () => isSuper(), pageSettings, 'gear', 'Sistem'],
    ['log', 'Log', () => isSuper(), pageLog, 'log', 'Sistem'],
  ];
  async function startApp() {
    await refreshCats();
    let grp = '';
    const nav = PAGES.filter((p) => p[2]()).map(([k, l, , , ic, g]) => {
      const head = g !== grp ? `<div class="grp">${esc(g)}</div>` : ''; grp = g;
      return `${head}<a href="#/${k}" data-k="${k}">${icon(ic)}<span>${esc(l)}</span><em class="badge" data-badge="${k}" hidden></em></a>`;
    }).join('');
    const initials = ME.name.split(/\s+/).map((x) => x[0]).slice(0, 2).join('').toUpperCase();
    root.innerHTML = `<div class="shell"><aside class="side" id="side">
        <div class="brandbox"><img src="../assets/img/brand/jabar-open.webp" alt="" width="360" height="246"><div><small>Konsol panitia</small><b>Jabar Open 2026</b></div></div>
        <nav id="nav">${nav}</nav>
        <div class="foot">${ROLE[ME.role]}${ME.discipline ? ' ' + DN[ME.discipline] : ''} · setiap tindakan tercatat atas nama Anda</div>
      </aside>
      <div class="mainwrap">
        <header class="topline">
          <button type="button" class="btn btn-ghost btn-sm menu-tg" id="menu-tg" aria-label="Menu">${icon('menu')}</button>
          <div class="ttl"><b>Konsol Panitia</b><small>Jabar Open 2026 · Gymnasium Arcamanik · 12–20 Desember</small></div>
          <div class="me"><button type="button" class="avatar" id="mebtn" title="Nomor WhatsApp saya">${esc(initials)}</button><span class="who"><b>${esc(ME.name)}</b><small>${ROLE[ME.role]}${ME.discipline ? ' ' + DN[ME.discipline] : ''}</small></span>
            <button class="btn btn-ghost btn-sm" id="logout" type="button" title="Keluar">${icon('out')}<span>Keluar</span></button></div>
        </header>
        <main class="main" id="view"></main></div></div>`;
    const side = root.querySelector('#side');
    const closeSide = () => { side.classList.remove('open'); const sc = document.querySelector('.scrim'); if (sc) sc.remove(); };
    root.querySelector('#menu-tg').onclick = () => {
      side.classList.add('open');
      const sc = document.createElement('div'); sc.className = 'scrim'; sc.onclick = closeSide; document.body.appendChild(sc);
    };
    side.querySelectorAll('nav a').forEach((a) => a.addEventListener('click', closeSide));
    root.querySelector('#logout').onclick = async () => { clearInterval(window.__joUnread); clearInterval(pageTimer); try { await rpc('console_logout'); } catch (e) {} ME = null; location.hash = ''; showLogin('Anda sudah keluar.'); };
    root.querySelector('#mebtn').onclick = () => editMyPhone();
    window.onhashchange = route;
    pollUnread(); clearInterval(window.__joUnread); window.__joUnread = setInterval(pollUnread, 30000);
    if (!location.hash || location.hash === '#/' || location.hash === '#') location.hash = isAdmin() ? '#/ringkasan' : isTD() ? '#/hasil' : '#/nilai';
    else route();
  }
  function route() {
    if (!ME) return;
    const parts = location.hash.replace(/^#\/?/, '').split('?')[0].split('/');
    const page = PAGES.find((p) => p[0] === parts[0] && p[2]()) || PAGES.find((p) => p[2]());
    root.querySelectorAll('#nav a').forEach((a) => a.toggleAttribute('aria-current', a.dataset.k === page[0]));
    if (root.querySelector('#nav a[aria-current]')) root.querySelector('#nav a[aria-current]').setAttribute('aria-current', 'page');
    const v = root.querySelector('#view');
    clearInterval(pageTimer); pageTimer = null;
    loading(v);
    window.scrollTo(0, 0);
    Promise.resolve(page[3](v, parts.slice(1))).catch((e) => { if (e.hint !== 'ERR_SESSION') fail(v, e); });
  }

  // =====================================================================
  //  RINGKASAN
  // =====================================================================
  async function pageDashboard(v) {
    const d = await api('console_dashboard');
    const emailOk = d.email && d.email.last_poll && (Date.now() - new Date(d.email.last_poll).getTime() < 30 * 60 * 1000);
    const sum = (k) => d.by_discipline.reduce((a, x) => a + (Number(x[k]) || 0), 0);
    const A = await api('console_actions').catch(() => null);
    const one = (x) => (ME.discipline ? `&d=${ME.discipline}` : '') + x;
    const acts = A ? [
      [Number(A.to_verify), `Verifikasi pembayaran`, `${A.to_verify} pendaftaran, ${A.to_verify_athletes} atlet`, `#/pendaftaran?s=menunggu_verifikasi${one('')}`],
      [Number(A.docs_pending), 'Periksa dokumen atlet', `${A.docs_pending} atlet`, `#/pendaftaran?f=docs${one('')}`],
      [Number(A.priangan_pending), 'Cek syarat Priangan', `${A.priangan_pending} nomor Ritmik`, `#/pendaftaran?f=priangan${one('')}`],
      [Number(A.music_pending), 'Periksa tautan musik', `${A.music_pending} nomor Ritmik`, '#/musik'],
    ].filter((x) => x[0] > 0) : [];
    v.innerHTML = `<h1>Ringkasan</h1><p class="muted">Halo, ${esc(ME.name)}. Angka diperbarui setiap halaman ini dibuka.</p>
      <section class="todo ${acts.length ? 'has' : 'none'}" aria-live="polite">
        <h2>${acts.length ? '<span class="rdot" aria-hidden="true"></span>Perlu tindakan' : 'Tidak ada yang perlu ditindaklanjuti'}</h2>
        ${acts.length ? `<div class="todo-list">${acts.map((x) => `<a class="todo-item" href="${x[3]}"><span class="rdot" aria-hidden="true"></span><span><b>${esc(x[1])}</b><small>${esc(x[2])}</small></span><strong>${x[0]}</strong>${icon('chev')}</a>`).join('')}</div>`
          : '<p class="small muted" style="margin:0">Semua pembayaran dan dokumen yang masuk sudah diperiksa.</p>'}
      </section>
      <div class="kpis">
        <div class="kpi"><div><small>Atlet terdaftar</small><b>${sum('athletes')}</b><small>dalam ${sum('submissions')} pendaftaran</small></div><i>${icon('users')}</i></div>
        <div class="kpi ok"><div><small>Atlet lunas</small><b>${sum('athletes_paid')}</b><small>atlet</small></div><i>${icon('check')}</i></div>
        <div class="kpi warn"><div><small>Pembayaran menunggu verifikasi</small><b>${sum('to_verify')}</b><small>pendaftaran${A ? `, ${A.to_verify_athletes} atlet` : ''}</small></div><i>${icon('clock')}</i></div>
        <div class="kpi bad"><div><small>Dokumen belum diperiksa</small><b>${sum('docs_pending')}</b><small>atlet</small></div><i>${icon('alert')}</i></div>
      </div>
      <div class="stats">${d.by_discipline.map((x) => `<div class="stat">
        <h3>${esc(x.name)} <a class="small" href="#/pendaftaran?d=${x.code}">Lihat</a></h3>
        <div class="big">${x.athletes}</div><div class="small muted">atlet terdaftar dalam ${x.submissions} pendaftaran, ${x.athletes_paid} atlet lunas</div>
        <ul>
          <li><a href="#/pendaftaran?d=${x.code}&s=menunggu_verifikasi">Pendaftaran menunggu verifikasi</a><strong>${x.to_verify}</strong></li>
          <li><a href="#/pendaftaran?d=${x.code}&s=menunggu_pembayaran">Pendaftaran belum bayar / perlu perbaikan</a><strong>${x.unpaid}</strong></li>
          <li><a href="#/pendaftaran?d=${x.code}&f=docs">Atlet: dokumen belum diperiksa</a><strong>${x.docs_pending}</strong></li>
          ${x.code === 'RG' ? `<li><a href="#/pendaftaran?d=${x.code}&f=priangan">Priangan: cek syarat Jawa Barat</a><strong>${x.priangan_pending}</strong></li>` : ''}
          ${x.code === 'MAG' || x.code === 'WAG' ? `<li><a href="#/pendaftaran?d=${x.code}&f=beregu">Tim beregu (lunas / terdaftar)</a><strong>${x.teams_paid || 0} / ${x.teams || 0}</strong></li>` : ''}
          ${x.code === 'RG' ? `<li><a href="#/musik">Musik perlu diperiksa</a><strong>${x.music_pending || 0}</strong></li>` : ''}
        </ul></div>`).join('')}
        ${d.money ? `<div class="stat"><h3>Keuangan <a class="small" href="#/ledger">Ledger</a></h3>
          <div class="big">${fmtRp(d.money.paid)}</div><div class="small muted">sudah lunas</div>
          <ul><li><span>Total tagihan</span><strong>${fmtRp(d.money.expected)}</strong></li>
          <li><span>Belum lunas</span><strong>${fmtRp(d.money.outstanding)}</strong></li>
          <li><span>Mutasi belum cocok</span><strong>${d.money.mutations_unmatched}</strong></li></ul></div>` : ''}
        ${d.email ? `<div class="stat"><h3>Email otomatis <a class="small" href="#/pengaturan">Atur</a></h3>
          <div class="big" style="font-size:1.2rem;color:${emailOk ? 'var(--ok)' : 'var(--bad)'}">${emailOk ? 'Berjalan' : 'Belum aktif / berhenti'}</div>
          <div class="small muted">${d.email.last_poll ? 'Terakhir aktif ' + dt(d.email.last_poll) : 'Pengirim email belum pernah terhubung'}</div>
          <ul><li><span>Antre</span><strong>${d.email.pending}</strong></li><li><span>Terkirim</span><strong>${d.email.sent}</strong></li><li><span>Gagal</span><strong>${d.email.error}</strong></li></ul></div>` : ''}
      </div>
      ${d.low_categories.length ? `<section class="card" style="margin-top:16px"><h2>Kategori dengan peserta kurang dari 3</h2>
        <p class="small muted">Sesuai Undangan, kategori artistik dengan kurang dari 3 peserta digabung ke kategori di atas atau di bawahnya. Pindahkan peserta dari halaman detail pendaftaran.</p>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Kategori</th><th class="r">Terdaftar</th><th class="r">Lunas</th></tr></thead><tbody>
        ${d.low_categories.map((c) => `<tr><td>${esc(c.name)}</td><td class="r">${c.registered}</td><td class="r">${c.paid}</td></tr>`).join('')}</tbody></table></div></section>` : ''}
      <section class="card" style="margin-top:16px"><h2>Pendaftaran terbaru</h2>
        ${d.recent.length ? `<div class="tbl-wrap"><table class="tbl"><tbody>${d.recent.map((r) => `<tr class="click" data-id="${r.id}">
          <td><span class="code">${esc(r.code)}</span><br><span class="tiny muted">${dt(r.created_at)}</span></td>
          <td>${esc(r.club || r.contact_name)}<br><span class="tiny muted">${r.n_athletes} atlet</span></td>
          <td class="r num">${fmtRp(r.total_amount)}</td><td>${pill(r.status)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada pendaftaran.</p>'}</section>`;
    v.querySelectorAll('tr[data-id]').forEach((tr) => tr.onclick = () => { location.hash = '#/pendaftaran/' + tr.dataset.id; });
  }

  // =====================================================================
  //  PENDAFTARAN
  // =====================================================================
  const subFilter = { discipline: '', status: '', flag: '', q: '' };
  function hashParams() { const i = location.hash.indexOf('?'); return new URLSearchParams(i >= 0 ? location.hash.slice(i + 1) : ''); }
  async function pageSubmissions(v, rest) {
    const id = (rest[0] || '').split('?')[0];
    if (id) return pageSubmission(v, id);
    const hp = hashParams();
    if (hp.has('d') || hp.has('s') || hp.has('f')) { subFilter.discipline = hp.get('d') || ''; subFilter.status = hp.get('s') || ''; subFilter.flag = hp.get('f') || ''; }
    v.innerHTML = `<h1>Pendaftaran</h1><p class="muted">Klik baris untuk memeriksa bukti bayar, dokumen, dan syarat Priangan (Ritmik). Pendaftaran QRIS tanpa bukti bayar dihapus otomatis 15 menit setelah dikirim.</p>
      <div class="bar">${discSelect('fd', subFilter.discipline)}
        <div class="field"><label class="f" for="fs">Status</label><select id="fs"><option value="">Semua status</option>
          ${Object.entries(ST).map(([k, l]) => `<option value="${k}" ${subFilter.status === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
        <div class="field"><label class="f" for="ff">Perlu diperiksa</label><select id="ff"><option value="">Semua</option>
          <option value="docs" ${subFilter.flag === 'docs' ? 'selected' : ''}>Dokumen belum diperiksa</option>
          <option value="priangan" ${subFilter.flag === 'priangan' ? 'selected' : ''}>Priangan: cek syarat</option>
          <option value="beregu" ${subFilter.flag === 'beregu' ? 'selected' : ''}>Pendaftaran beregu</option>
          <option value="musik" ${subFilter.flag === 'musik' ? 'selected' : ''}>Musik Ritmik belum beres</option></select></div>
        <div class="field" style="flex:1;min-width:200px"><label class="f" for="fq">Cari</label><input id="fq" type="search" placeholder="Kode, nama atlet, klub, email, nominal" value="${esc(subFilter.q)}"></div>
      </div><div id="list"><div class="empty"><span class="spinner"></span></div></div>`;
    const load = async () => {
      const list = v.querySelector('#list');
      const rows = await api('console_submissions', { p_filter: subFilter });
      if (!rows.length) { list.innerHTML = '<p class="empty">Tidak ada pendaftaran yang cocok dengan filter.</p>'; return; }
      list.innerHTML = `<p class="small muted">${rows.length} pendaftaran</p><div class="tbl-wrap"><table class="tbl"><thead><tr>
        <th>Kode</th><th>Pendaftar</th><th>Atlet</th><th class="r">Total</th><th>Status</th><th>Periksa</th></tr></thead><tbody>
        ${rows.map((r) => `<tr class="click" data-id="${r.id}">
          <td><span class="code">${esc(r.code)}</span><br><span class="tiny muted">${dt(r.created_at)}</span></td>
          <td>${esc(r.club || '–')}<br><span class="tiny muted">${esc(r.contact_name)}, ${esc(r.region || '')}</span></td>
          <td class="small">${r.team_name ? `<strong>Tim ${esc(r.team_name)}</strong><br>` : ''}${esc(r.athlete_names || '')}</td>
          <td class="r num">${fmtRp(r.total_amount)}${r.payment_method === 'manual' ? '<br><span class="pill warn">WNA</span>' : ''}</td>
          <td>${pill(r.status)}</td>
          <td class="small">${r.proof_uploaded_at ? '<span class="pill info">Bukti ada</span> ' : ''}${r.mutation_matched ? '<span class="pill ok">Mutasi cocok</span> ' : ''}
            ${r.expires_at ? `<span class="pill warn">hapus otomatis ${esc(new Date(r.expires_at).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }))}</span> ` : ''}${r.docs_pending ? `<span class="pill">${r.docs_pending} dokumen</span> ` : ''}${r.priangan_pending ? `<span class="pill warn">${r.priangan_pending} cek Priangan</span> ` : ''}${r.music_pending ? `<span class="pill warn">${r.music_pending} musik</span>` : ''}</td></tr>`).join('')}
        </tbody></table></div>`;
      list.querySelectorAll('tr[data-id]').forEach((tr) => tr.onclick = () => { location.hash = '#/pendaftaran/' + tr.dataset.id; });
    };
    const bind = (sel, key, ev) => { const el = v.querySelector(sel); if (el) el.addEventListener(ev || 'change', () => { subFilter[key] = el.value; load().catch((e) => fail(v.querySelector('#list'), e)); }); };
    bind('#fd', 'discipline'); bind('#fs', 'status'); bind('#ff', 'flag');
    let tm; v.querySelector('#fq').addEventListener('input', (e) => { clearTimeout(tm); tm = setTimeout(() => { subFilter.q = e.target.value.trim(); load(); }, 300); });
    await load();
  }

  async function pageSubmission(v, id) {
    const D = await api('console_submission', { p_id: id });
    const s = D.submission;
    const open = ['menunggu_pembayaran', 'menunggu_verifikasi', 'perlu_perbaikan'].includes(s.status);
    const matched = D.mutations.filter((m) => m.match_status === 'otomatis' || m.match_status === 'manual');
    const club = D.club ? `${esc(D.club.name)}<br><span class="tiny muted">${esc([D.club.kab_kota, D.club.province, D.club.country !== 'Indonesia' ? D.club.country : ''].filter(Boolean).join(', '))}${D.club.verified ? '' : ', klub baru belum diverifikasi'}</span>` : 'Perorangan (tanpa klub)';
    v.innerHTML = `<p><a href="#/pendaftaran">Kembali ke daftar</a></p>
      <div class="row" style="justify-content:space-between"><h1 class="code">${esc(s.code)}</h1>${pill(s.status)}</div>
      <p class="muted">${esc(s.discipline_name)}, ${s.registrant_type === 'klub' ? 'pendaftaran klub' : s.registrant_type === 'beregu' ? 'pendaftaran beregu (format lama)' : 'perorangan (format lama)'}${D.teams.length ? `, ${D.teams.length} tim beregu` : ''}, ${dt(s.created_at)}</p>
      <div class="split" style="margin-top:14px">
        <div>
          <section class="card"><h2>Pendaftar</h2><dl class="kv">
            <dt>Penanggung jawab</dt><dd>${esc(s.contact_name)}${s.contact_role ? ` <span class="tiny muted">(${esc(ROLE_CLUB[s.contact_role] || s.contact_role)})</span>` : ''}</dd>
            <dt>WhatsApp</dt><dd><a href="${wa(s.contact_phone)}" target="_blank" rel="noopener">${esc(s.contact_phone)}</a></dd>
            <dt>Email</dt><dd><a href="mailto:${esc(s.contact_email)}">${esc(s.contact_email)}</a></dd>
            <dt>Klub</dt><dd>${club}</dd>
            <dt>Bahasa</dt><dd>${s.lang === 'en' ? 'English' : 'Indonesia'}</dd></dl></section>
          ${D.teams.map((T) => teamCardConsole(T, s)).join('')}
          <section class="card"><h2>Atlet & kategori</h2>${D.teams.length && !D.athletes.length ? '<p class="small muted">Semua anggota tim didaftarkan perorangan lewat pendaftaran klub sebelumnya; data dan dokumen mereka ada di sana.</p>' : ''}<div id="aths" class="stack"></div></section>
          <section class="card"><h2>Email</h2>
            ${D.emails.length ? `<ul class="small" style="padding-left:18px;margin:0 0 10px">${D.emails.map((e) => `<li>${esc(e.kind)} ke ${esc(e.to)}: <strong>${esc(e.status)}</strong> ${e.sent_at ? dt(e.sent_at) : ''}</li>`).join('')}</ul>` : '<p class="small muted">Belum ada email.</p>'}
            <div class="actions"><button class="btn btn-ghost btn-sm" data-mail="pendaftaran">Kirim ulang tagihan</button>
              ${s.status === 'lunas' ? '<button class="btn btn-ghost btn-sm" data-mail="lunas">Kirim ulang AIC</button>' : ''}
              <button class="btn btn-ghost btn-sm" data-mail="tautan">Kirim tautan status</button></div></section>
          <section class="card"><h2>Riwayat</h2>${D.history.length ? `<ul class="small" style="padding-left:18px;margin:0">${D.history.map((h) => `<li>${dt(h.at)}: <strong>${esc(h.action.replace(/_/g, ' '))}</strong>${h.staff ? ' oleh ' + esc(h.staff) : ''}${h.detail && (h.detail.note || h.detail.reason) ? ` <span class="muted">(${esc(h.detail.note || h.detail.reason)})</span>` : ''}</li>`).join('')}</ul>` : '<p class="small muted">Belum ada.</p>'}</section>
        </div>
        <div>
          <section class="card" style="position:sticky;top:12px"><h2>Pembayaran</h2>
            <table class="breakdown"><tbody>
              ${s.base_amount - (s.team_amount || 0) ? `<tr><td>Biaya pendaftaran</td><td>${fmtRp(s.base_amount - (s.team_amount || 0))}</td></tr>` : ''}
              ${s.team_amount ? `<tr><td>Biaya beregu (${D.teams.length} tim)</td><td>${fmtRp(s.team_amount)}</td></tr>` : ''}
                <tr><td>Kode unik</td><td>${fmtRp(s.unique_code)}</td></tr>
              <tr class="total"><td>Total</td><td>${fmtRp(s.total_amount)}</td></tr></tbody></table>
            ${s.payment_method === 'manual' ? '<p class="note warn" style="margin-top:12px">Atlet internasional: pembayaran terpisah. Hubungi pendaftar, lalu superadmin menandai lunas dengan nominal yang diterima.</p>' : ''}
            ${s.status === 'lunas' ? `<p class="note ok" style="margin-top:12px">Lunas ${fmtRp(s.paid_amount)} pada ${dt(s.paid_at)}${s.verified_by_name ? ', diverifikasi ' + esc(s.verified_by_name) : ''}.${s.verify_note ? '<br>Catatan: ' + esc(s.verify_note) : ''}</p>` : ''}
            ${s.status === 'perlu_perbaikan' ? `<p class="note bad" style="margin-top:12px">Ditolak: ${esc(s.verify_note || '')}</p>` : ''}
            ${s.status === 'dibatalkan' ? `<p class="note bad" style="margin-top:12px">Dibatalkan: ${esc(s.cancel_reason || '')}</p>` : ''}
            <h3 style="margin-top:16px">Bukti bayar</h3>
            ${s.proof_path ? `<div class="doc-prev" id="proof"><span class="spinner"></span></div><p class="tiny muted">Diunggah ${dt(s.proof_uploaded_at)}</p>` : '<p class="small muted">Belum ada bukti bayar.</p>'}
            <h3 style="margin-top:16px">Mutasi GoBiz / bank</h3>
            ${matched.length ? matched.map((m) => `<p class="note ok small">Cocok: ${fmtRp(m.amount)} pada ${dt(m.trx_time)}${m.reference ? ', ref ' + esc(m.reference) : ''}</p>`).join('')
              : D.candidate_mutations.length ? `<p class="note info small">Ada ${D.candidate_mutations.length} mutasi belum dicocokkan dengan nominal yang sama. Cocokkan di Ledger.</p>` : '<p class="small muted">Belum ada mutasi yang cocok. Impor laporan GoBiz di Ledger.</p>'}
            <div class="actions" style="margin-top:14px">
              ${open ? `<button class="btn btn-ok" id="approve">Tandai lunas</button>` : ''}
              ${open || (s.status === 'lunas' && isSuper()) ? `<button class="btn btn-bad" id="reject">${s.status === 'lunas' ? 'Batalkan status lunas' : 'Tolak bukti'}</button>` : ''}
              ${s.status !== 'dibatalkan' && (s.status !== 'lunas' || isSuper()) ? `<button class="btn btn-ghost" id="cancel">Batalkan pendaftaran</button>` : ''}
            </div>
            ${s.expires_at ? `<p class="note warn small" style="margin-top:12px">Belum ada bukti bayar. Pendaftaran ini dihapus otomatis pukul ${esc(new Date(s.expires_at).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }))} bila bukti tidak diunggah.</p>` : ''}
            ${isSuper() ? `<div class="actions" style="margin-top:10px;border-top:1px solid var(--line);padding-top:10px"><button class="btn btn-bad btn-sm" id="purge">Hapus pendaftaran permanen</button></div>` : ''}
          </section>
        </div>
      </div>`;
    if (s.proof_path) {
      signed('bukti', s.proof_path).then((url) => {
        const box = v.querySelector('#proof');
        box.innerHTML = /\.pdf$/i.test(s.proof_path) ? `<iframe src="${esc(url)}" title="Bukti bayar"></iframe>` : `<a href="${esc(url)}" target="_blank" rel="noopener"><img src="${esc(url)}" alt="Bukti bayar"></a>`;
      }).catch((e) => { v.querySelector('#proof').innerHTML = `<p class="small" style="color:var(--bad)">${esc(e.message)}</p>`; });
    }
    const reload = () => pageSubmission(v, id);
    const act = async (fn, args, msg) => { try { await api(fn, args); JO.toast(msg); reload(); } catch (e) { JO.toast(e.message, 'bad'); } };
    const ap = v.querySelector('#approve');
    if (ap) ap.onclick = async () => {
      const manual = s.payment_method === 'manual';
      const r = await dialog({ title: 'Tandai lunas', ok: 'Tandai lunas', okClass: 'btn-ok',
        body: `<p>${D.athletes.length ? `AIC ${D.athletes.length} atlet akan aktif dan email` : 'Tim ditandai lunas dan email konfirmasi'} dikirim ke <strong>${esc(s.contact_email)}</strong>.</p>
          ${!s.proof_path && !matched.length && !manual ? '<p class="note warn">Belum ada bukti bayar maupun mutasi yang cocok. Hanya lanjutkan bila Anda sudah memastikan dana masuk.</p>' : ''}
          ${manual ? `<label class="f" for="amt">Nominal diterima (Rp)</label><input id="amt" type="number" min="1" value="${s.total_amount}">` : ''}
          <label class="f" for="note" style="margin-top:10px">Catatan (opsional)</label><textarea id="note" placeholder="Mis. cocok dengan mutasi GoBiz 13:42"></textarea>`,
        onOk: async (d) => {
          const args = { p_id: s.id, p_approve: true, p_note: d.querySelector('#note').value.trim() || null };
          if (manual) args.p_amount = Number(d.querySelector('#amt').value);
          await api('console_verify_payment', args); return true;
        } });
      if (r) { JO.toast('Ditandai lunas. Email AIC masuk antrean.'); reload(); }
    };
    const rj = v.querySelector('#reject');
    if (rj) rj.onclick = async () => {
      const note = await askReason(s.status === 'lunas' ? 'Batalkan status lunas' : 'Tolak bukti bayar', 'Alasan (dikirim ke pendaftar lewat email)',
        { min: 5, ok: 'Kirim penolakan', okClass: 'btn-bad', intro: 'Contoh: "Nominal yang masuk Rp1.650.000, kurang Rp172 kode unik." Pendaftar bisa mengunggah ulang bukti dari halaman status.' });
      if (note) act('console_verify_payment', { p_id: s.id, p_approve: false, p_note: note }, 'Penolakan tersimpan dan email dikirim.');
    };
    const cn = v.querySelector('#cancel');
    if (cn) cn.onclick = async () => {
      const note = await askReason('Batalkan pendaftaran', 'Alasan pembatalan', { min: 5, ok: 'Batalkan', okClass: 'btn-bad', intro: 'Semua entri di pendaftaran ini ikut dibatalkan. Tindakan ini tercatat di log.' });
      if (note) act('console_cancel_submission', { p_id: s.id, p_reason: note }, 'Pendaftaran dibatalkan.');
    };
    v.querySelectorAll('[data-mail]').forEach((b) => b.onclick = () => act('console_resend_email', { p_id: s.id, p_kind: b.dataset.mail }, 'Email masuk antrean.'));
    const pg = v.querySelector('#purge');
    if (pg) pg.onclick = async () => {
      const reason = await askReason('Hapus ' + s.code + ' permanen?', 'Alasan penghapusan (masuk Log)', { min: 3, ok: 'Hapus permanen', okClass: 'btn-bad',
        intro: `Pendaftaran, ${D.athletes.length} atlet, entri, nilai, dan semua berkasnya (dokumen, pas foto, bukti bayar) dihapus dan tidak bisa dikembalikan. Ringkasannya tetap tercatat di Log (hanya owner dan superadmin).` });
      if (!reason) return;
      try { const r = await api('console_delete_submission', { p_id: s.id, p_reason: reason }); await removeFiles(r.files, s.code); JO.toast('Pendaftaran dihapus.'); location.hash = '#/pendaftaran'; }
      catch (e) { JO.toast(e.message, 'bad'); }
    };

    // atlet
    const box = v.querySelector('#aths');
    D.athletes.forEach((a) => {
      const ents = D.entries.filter((e) => e.athletes.some((x) => x.id === a.id));
      const el = document.createElement('div'); el.className = 'ath';
      el.innerHTML = `<div class="ath-head"><span class="bib">${esc(a.athlete_no || '')}</span><strong>${esc(a.full_name)}</strong><span class="spacer"></span>
          ${isSuper() && D.athletes.length > 1 ? rowMenu('<button class="btn btn-ghost btn-sm" data-edit>Ubah data</button>', [{ label: 'Hapus atlet', attr: 'data-delath', danger: true }]) : '<button class="btn btn-ghost btn-sm" data-edit>Ubah data</button>'}</div>
        <div class="ath-body">
          <dl class="kv"><dt>Jenis kelamin</dt><dd>${a.gender === 'M' ? 'Putra' : 'Putri'}</dd>
            <dt>Tanggal lahir</dt><dd>${JO.fmtDate(a.birth_date)} <span class="muted">(usia 2026: ${a.age})</span></dd>
            <dt>Asal</dt><dd>${a.nationality === 'WNA' ? 'WNA, ' + esc(a.country) : esc([a.kab_kota, a.province].filter(Boolean).join(', ') || 'WNI')}</dd>
            ${a.minor ? `<dt>Orang tua/wali</dt><dd>${esc(a.guardian_name || '-')}${a.guardian_relation ? ` (${esc(a.guardian_relation)})` : ''}<br>
              <a href="${wa(a.guardian_phone)}" target="_blank" rel="noopener">${esc(a.guardian_phone || '')}</a><br>${esc(a.guardian_email || '')}</dd>` : ''}
          </dl>
          <div class="ath-docs">${a.photo_thumb ? `<img class="ath-thumb" src="${esc(a.photo_thumb)}" alt="Pas foto ${esc(a.full_name)}" width="60" height="80">` : ''}
            <div class="actions" style="margin:0">${DOCS.filter(([k]) => a[k]).map(([k, l]) => `<button class="btn btn-ghost btn-sm" data-docp="${k}">${l}</button>`).join('')}
              ${!a.akte_path && !a.passport_path && a.id_doc_path ? '<button class="btn btn-ghost btn-sm" data-docp="id_doc_path">Dokumen identitas</button>' : ''}
              ${a.nationality === 'WNI' && !a.bpjs_path ? '<span class="pill warn">BPJS TK belum diunggah: bawa ke venue</span>' : ''}</div></div>
          <div class="actions">
            <span class="pill ${a.doc_status === 'valid' ? 'ok' : a.doc_status === 'tidak_valid' ? 'bad' : ''}">${a.doc_status === 'valid' ? 'Dokumen valid' : a.doc_status === 'tidak_valid' ? 'Dokumen tidak valid' : 'Dokumen belum diperiksa'}</span>
            ${a.doc_status !== 'valid' ? '<button class="btn btn-ok btn-sm" data-dv="1">Dokumen valid</button>' : ''}
            ${a.doc_status !== 'tidak_valid' ? '<button class="btn btn-bad btn-sm" data-dv="0">Tidak valid</button>' : ''}
          </div>
          ${a.doc_note ? `<p class="small muted">Catatan dokumen: ${esc(a.doc_note)}</p>` : ''}
          ${ents.map((e) => `<div style="border-top:1px solid var(--line);margin-top:12px;padding-top:10px" data-entry="${e.id}">
            <strong>${esc(e.category)}</strong> <span class="small muted">${e.team_only ? 'termasuk biaya beregu' : fmtRp(e.fee)}</span>
            ${e.team_only ? ' <span class="pill gold">khusus beregu</span>' : ''}
            ${e.status !== 'aktif' ? ` <span class="pill bad">${esc(e.status)}</span>` : ''}
            ${e.in_team && e.in_team.submission_id !== s.id ? `<div class="small">Anggota tim <a href="#/pendaftaran/${e.in_team.submission_id}">${esc(e.in_team.team)} (${esc(e.in_team.code)})</a></div>` : ''}
            ${e.discipline === 'RG' ? musicBlock(e) : ''}
            ${e.athletes.length > 1 ? `<div class="small muted">Pasangan: ${esc(e.athletes.map((x) => x.name).join(' & '))}</div>` : ''}
            ${e.mismatch ? `<p class="note warn small" style="margin:6px 0">Tidak sesuai kategori: ${esc(e.mismatch)}</p>` : ''}
            ${e.priangan_requested ? `<div class="small" style="margin-top:6px">Cek syarat Priangan (Jawa Barat): <strong>${esc(e.priangan_status)}</strong>${e.priangan_note ? ` <span class="muted">(${esc(e.priangan_note)})</span>` : ''}
              ${e.priangan_status !== 'disetujui' ? ' <button class="btn btn-ok btn-sm" data-pri="1">Memenuhi</button>' : ''}${e.priangan_status !== 'ditolak' ? ' <button class="btn btn-bad btn-sm" data-pri="0">Tidak memenuhi</button>' : ''}
              <div class="tiny muted">Syarat: WNI, alamat pada identitas di Jawa Barat, klub di Jawa Barat. Bila tidak memenuhi, pindahkan ke kategori Amatir.</div></div>` : ''}
            <div class="actions"><button class="btn btn-ghost btn-sm" data-move>Pindah kategori</button>
              ${e.status === 'aktif' ? '<button class="btn btn-ghost btn-sm" data-est="dns">Tidak tampil (DNS)</button>' : '<button class="btn btn-ghost btn-sm" data-est="aktif">Aktifkan lagi</button>'}</div>
          </div>`).join('')}
        </div>`;
      const q = (sel) => el.querySelector(sel);
      el.querySelectorAll('[data-docp]').forEach((b) => b.onclick = () => preview('dokumen', a[b.dataset.docp], b.textContent + ' ' + a.full_name));
      const da = q('[data-delath]');
      if (da) da.onclick = async () => {
        const reason = await askReason('Hapus atlet ' + a.full_name + '?', 'Alasan penghapusan (masuk Log)', { min: 3, ok: 'Hapus atlet', okClass: 'btn-bad',
          intro: 'Atlet, kategorinya (termasuk pasangan), nilai, dan berkasnya dihapus permanen. Tagihan dihitung ulang bila belum lunas.' });
        if (!reason) return;
        try { const r = await api('console_delete_athlete', { p_athlete: a.id, p_reason: reason }); await removeFiles(r.files, s.code + ' ' + a.full_name); JO.toast('Atlet dihapus.'); reload(); }
        catch (e) { JO.toast(e.message, 'bad'); }
      };
      el.querySelectorAll('[data-dv]').forEach((b) => b.onclick = async () => {
        const ok = b.dataset.dv === '1';
        let note = null;
        if (!ok) { note = await askReason('Dokumen tidak valid', 'Apa yang salah? (mis. tanggal lahir di akte berbeda)'); if (!note) return; }
        act('console_verify_doc', { p_athlete: a.id, p_valid: ok, p_note: note }, ok ? 'Dokumen ditandai valid.' : 'Dokumen ditandai tidak valid.');
      });
      q('[data-edit]').onclick = () => editAthlete(a, reload);
      el.querySelectorAll('[data-entry]').forEach((ee) => {
        const e = ents.find((x) => x.id === ee.dataset.entry);
        ee.querySelectorAll('[data-pri]').forEach((b) => b.onclick = async () => {
          const ok = b.dataset.pri === '1'; let note = null;
          if (!ok) { note = await askReason('Tidak memenuhi syarat Priangan', 'Alasan (mis. alamat di akte luar Jawa Barat)'); if (!note) return; }
          act('console_set_priangan', { p_entry: e.id, p_approve: ok, p_note: note }, ok ? 'Syarat Priangan terpenuhi.' : 'Ditandai tidak memenuhi syarat Priangan.');
        });
        ee.querySelector('[data-move]').onclick = () => moveEntry(e, s.discipline, reload);
        ee.querySelectorAll('[data-mc]').forEach((b) => b.onclick = () => musicCheck(e, b.dataset.mc === '1', reload));
        ee.querySelectorAll('[data-est]').forEach((b) => b.onclick = async () => {
          const r = await askReason(b.dataset.est === 'dns' ? 'Tandai tidak tampil' : 'Aktifkan lagi', 'Alasan');
          if (r) act('console_set_entry_status', { p_entry: e.id, p_status: b.dataset.est, p_reason: r }, 'Status entri diubah.');
        });
      });
      box.appendChild(el);
    });
  }
  const MUSIC_ST = { belum: ['Belum ada tautan', 'warn'], menunggu: ['Menunggu diperiksa', 'info'], ok: ['Bisa dibuka', 'ok'], tidak_bisa: ['Tidak bisa dibuka', 'bad'], tidak_perlu: ['Tidak perlu', ''] };
  const musicPill = (st) => { const m = MUSIC_ST[st] || [st, '']; return `<span class="pill ${m[1]}">${esc(m[0])}</span>`; };
  const MUSIC_ACT = { daftar: 'diisi saat daftar', isi: 'diisi', ganti: 'diganti (jatah terpakai)', perbaiki: 'diperbaiki', ok: 'ditandai bisa dibuka', tidak_bisa: 'ditandai tidak bisa dibuka' };
  function musicLinks(e) {
    const m = e.music || {};
    return (e.apparatus || Object.keys(m)).map((ap) => `<div class="small"><strong>${esc(appName('RG', ap))}:</strong> ${m[ap] ? `<a class="mono-link" href="${esc(m[ap])}" target="_blank" rel="noopener">${esc(m[ap])}</a>` : '<span class="muted">belum ada</span>'}</div>`).join('');
  }
  function musicBlock(e) {
    return `<div class="music-box"><div class="small"><strong>Musik</strong> ${musicPill(e.music_status)}${e.music_changes ? ' <span class="pill">ganti sudah dipakai</span>' : ''}</div>
      ${musicLinks(e)}
      ${e.music_note ? `<div class="small" style="color:var(--bad)">Catatan: ${esc(e.music_note)}</div>` : ''}
      ${e.music_checked_by ? `<div class="tiny muted">Diperiksa ${esc(e.music_checked_by)}, ${dt(e.music_checked_at)}</div>` : ''}
      ${Object.keys(e.music || {}).length ? `<div class="actions">${e.music_status !== 'ok' ? '<button class="btn btn-ok btn-sm" data-mc="1">Bisa dibuka</button>' : ''}${e.music_status !== 'tidak_bisa' ? '<button class="btn btn-bad btn-sm" data-mc="0">Tidak bisa dibuka</button>' : ''}</div>` : ''}
      ${(e.music_log || []).length ? `<details class="small" style="margin-top:6px"><summary>Riwayat musik (${e.music_log.length})</summary><ul style="padding-left:18px;margin:6px 0 0">
        ${e.music_log.map((l) => `<li>${dt(l.at)}: ${esc(MUSIC_ACT[l.action] || l.action)}${l.apparatus ? ' ' + esc(appName('RG', l.apparatus)) : ''}${l.staff ? ' oleh ' + esc(l.staff) : ''}${l.new_url && ['daftar', 'isi', 'ganti', 'perbaiki'].includes(l.action) ? `<br><span class="mono-link">${esc(l.new_url)}</span>` : ''}${l.note ? ` <span class="muted">(${esc(l.note)})</span>` : ''}</li>`).join('')}</ul></details>` : ''}</div>`;
  }
  async function musicCheck(e, ok, done) {
    let note = null;
    if (!ok) {
      note = await askReason('Tautan musik tidak bisa dibuka', 'Apa masalahnya? (dikirim ke pendaftar lewat email)',
        { min: 5, ok: 'Kirim ke pendaftar', okClass: 'btn-bad', value: 'Folder belum dibagikan. Ubah akses ke "Siapa saja yang memiliki link", lalu kirim ulang lewat halaman Musik Ritmik.',
          intro: 'Pendaftar diminta memperbaiki akses lewat halaman Musik Ritmik. Perbaikan tidak memakai kesempatan ganti musik.' });
      if (!note) return;
    }
    try { await api('console_music_check', { p_entry: e.id || e.entry_id, p_ok: ok, p_note: note }); JO.toast(ok ? 'Ditandai bisa dibuka.' : 'Ditandai tidak bisa dibuka. Email ke pendaftar masuk antrean.'); done(); }
    catch (err) { JO.toast(err.message, 'bad'); }
  }
  function teamCardConsole(T, s) {
    return `<section class="card"><h2>Tim ${esc(T.name)}</h2><p class="small muted" style="margin-top:-6px">${esc(s.discipline_name)} ${esc(T.level)}, ${T.members.length} pesenam. Peringkat dan publikasi di Hasil &amp; medali, tab Beregu.</p>
      <div class="tbl-wrap"><table class="tbl"><tbody>${T.members.map((m) => `<tr>
        <td><span class="bib">${esc(m.athlete_no || '')}</span> <strong>${esc(m.name)}</strong><br><span class="small muted">${esc(m.category)}</span></td>
        <td>${m.team_only ? '<span class="pill gold">khusus beregu</span>' : '<span class="pill info">juga perorangan</span>'}${m.entry_status !== 'aktif' ? ` <span class="pill bad">${esc(m.entry_status)}</span>` : ''}</td>
        <td class="small">${m.submission_id !== s.id ? `<a href="#/pendaftaran/${m.submission_id}">${esc(m.submission_code)}</a><br>${pill(m.submission_status)}` : '<span class="muted">pendaftaran ini</span>'}</td></tr>`).join('')}
      </tbody></table></div></section>`;
  }

  // =====================================================================
  //  MUSIK RITMIK
  // =====================================================================
  const muFilter = { status: 'perlu', q: '' };
  async function pageMusic(v) {
    v.innerHTML = `<h1>Musik Ritmik</h1><p class="muted">Buka setiap tautan Google Drive dan pastikan folder bisa diakses dan berisi MP3. Tandai "Bisa dibuka", atau "Tidak bisa dibuka" untuk meminta pendaftar memperbaiki akses lewat email.</p>
      <div class="bar"><div class="field"><label class="f" for="ms">Status</label><select id="ms">
        ${[['perlu', 'Perlu tindakan'], ['', 'Semua'], ['menunggu', 'Menunggu diperiksa'], ['tidak_bisa', 'Tidak bisa dibuka'], ['belum', 'Belum ada tautan'], ['ok', 'Bisa dibuka']].map(([k, l]) => `<option value="${k}" ${muFilter.status === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
        <div class="field" style="flex:1;min-width:200px"><label class="f" for="mq">Cari</label><input id="mq" type="search" placeholder="Nama atlet, klub, kode" value="${esc(muFilter.q)}"></div>
        <button class="btn btn-dark" id="mx">Unduh Excel</button></div><div id="list"></div>`;
    let rows = [];
    const load = async () => {
      const list = v.querySelector('#list'); loading(list);
      rows = await api('console_music', { p_filter: muFilter });
      if (!rows.length) { list.innerHTML = '<p class="empty">Tidak ada entri yang cocok.</p>'; return; }
      list.innerHTML = `<p class="small muted">${rows.length} atlet</p><div class="tbl-wrap"><table class="tbl"><thead><tr><th>Atlet</th><th>Kategori</th><th>Tautan</th><th>Status</th><th></th></tr></thead><tbody>
        ${rows.map((r) => `<tr data-e="${r.entry_id}"><td><span class="bib">${esc(r.athlete_no || '')}</span> <strong>${esc(r.full_name)}</strong><br>
            <span class="small muted">${esc(r.club)}, <a href="#/pendaftaran/${r.submission_id}">${esc(r.code)}</a></span>${r.payment_status !== 'lunas' ? ` ${pill(r.payment_status)}` : ''}</td>
          <td class="small">${esc(r.category)}${r.startlist_published ? '<br><span class="pill">start list terbit</span>' : ''}</td>
          <td class="small">${Object.keys(r.music || {}).length ? musicLinks(r) : '<span class="muted">–</span>'}
            ${r.music_updated_at ? `<br><span class="tiny muted">diperbarui ${dt(r.music_updated_at)}${r.music_changes ? ', ganti sudah dipakai' : ''}</span>` : ''}</td>
          <td class="small">${musicPill(r.music_status)}${r.music_note ? `<br><span style="color:var(--bad)">${esc(r.music_note)}</span>` : ''}${r.checked_by ? `<br><span class="tiny muted">${esc(r.checked_by)}, ${dt(r.music_checked_at)}</span>` : ''}</td>
          <td class="r" style="white-space:nowrap">${Object.keys(r.music || {}).length ? `${r.music_status !== 'ok' ? '<button class="btn btn-ok btn-sm" data-mc="1">Bisa dibuka</button> ' : ''}${r.music_status !== 'tidak_bisa' ? '<button class="btn btn-bad btn-sm" data-mc="0">Tidak bisa</button>' : ''}` : `<a class="btn btn-ghost btn-sm" href="${wa(r.contact_phone)}" target="_blank" rel="noopener">WA pendaftar</a>`}</td></tr>`).join('')}
        </tbody></table></div>`;
      list.querySelectorAll('[data-mc]').forEach((b) => b.onclick = () => {
        const r = rows.find((x) => x.entry_id === b.closest('tr').dataset.e);
        musicCheck(r, b.dataset.mc === '1', load);
      });
    };
    v.querySelector('#ms').onchange = (e) => { muFilter.status = e.target.value; load(); };
    let tm; v.querySelector('#mq').addEventListener('input', (e) => { clearTimeout(tm); tm = setTimeout(() => { muFilter.q = e.target.value.trim(); load(); }, 300); });
    v.querySelector('#mx').onclick = () => exportXlsx(`musik-ritmik-${new Date().toISOString().slice(0, 10)}.xlsx`, rows, [
      ['athlete_no', 'No. atlet'], ['full_name', 'Nama'], ['club', 'Klub'], ['category', 'Kategori'], ['apparatus', 'Alat', (r) => (r.apparatus || []).join(', ')],
      ['music', 'Tautan musik', (r) => (r.apparatus || []).map((ap) => appName('RG', ap) + ': ' + ((r.music || {})[ap] || '-')).join('\n')], ['music_status', 'Status', (r) => (MUSIC_ST[r.music_status] || [r.music_status])[0]], ['music_note', 'Catatan'],
      ['music_changes', 'Ganti dipakai'], ['music_updated_at', 'Diperbarui', (r) => (r.music_updated_at ? dt(r.music_updated_at) : '')],
      ['code', 'Kode pendaftaran'], ['payment_status', 'Pembayaran', (r) => ST[r.payment_status]], ['contact_name', 'Penanggung jawab'], ['contact_phone', 'WA'], ['contact_email', 'Email']]);
    await load();
  }

  async function editAthlete(a, done) {
    const R = window.JO_REGIONS;
    const r = await dialog({ title: 'Ubah data ' + a.full_name, ok: 'Simpan perubahan',
      body: `<div class="grid-2">
        <div class="field"><label class="f">Nama lengkap</label><input data-k="full_name" value="${esc(a.full_name)}"></div>
        <div class="field"><label class="f">Tanggal lahir</label><input data-k="birth_date" type="date" value="${esc(a.birth_date)}"></div>
        <div class="field"><label class="f">Jenis kelamin</label><select data-k="gender"><option value="M" ${a.gender === 'M' ? 'selected' : ''}>Putra</option><option value="F" ${a.gender === 'F' ? 'selected' : ''}>Putri</option></select></div>
        <div class="field"><label class="f">Kewarganegaraan</label><select data-k="nationality"><option ${a.nationality === 'WNI' ? 'selected' : ''}>WNI</option><option ${a.nationality === 'WNA' ? 'selected' : ''}>WNA</option></select></div>
        <div class="field"><label class="f">Provinsi</label><select data-k="province"><option value=""></option>${R.provinces.map((p) => `<option ${p === a.province ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
        <div class="field"><label class="f">Kabupaten/kota</label><input data-k="kab_kota" value="${esc(a.kab_kota || '')}" list="kabs"><datalist id="kabs">${R.jabar.map((k) => `<option>${esc(k)}</option>`).join('')}</datalist></div>
        <div class="field"><label class="f">Negara</label><input data-k="country" value="${esc(a.country || '')}"></div>
        <div class="field"><label class="f">Nama orang tua/wali</label><input data-k="guardian_name" value="${esc(a.guardian_name || '')}"></div>
        <div class="field"><label class="f">WhatsApp orang tua/wali</label><input data-k="guardian_phone" value="${esc(a.guardian_phone || '')}"></div>
        <div class="field"><label class="f">Email orang tua/wali</label><input data-k="guardian_email" value="${esc(a.guardian_email || '')}"></div></div>
        <label class="f" for="why">Alasan perubahan (tercatat di log)</label><textarea id="why"></textarea>`,
      onOk: async (d) => {
        const patch = {};
        d.querySelectorAll('[data-k]').forEach((i) => { const k = i.dataset.k; const old = a[k] == null ? '' : String(a[k]); if (i.value !== old) patch[k] = i.value; });
        if (!Object.keys(patch).length) return true;
        await api('console_update_athlete', { p_athlete: a.id, p_patch: patch, p_reason: d.querySelector('#why').value.trim() });
        return true;
      } });
    if (r) { JO.toast('Data atlet disimpan.'); done(); }
  }
  async function moveEntry(e, disc, done) {
    const cur = CATS.categories.find((c) => c.id === e.category_id);
    const list = CATS.categories.filter((c) => c.discipline === disc && c.entry_type === cur.entry_type && c.id !== cur.id);
    const r = await dialog({ title: 'Pindah kategori', ok: 'Pindahkan',
      body: `<p class="small">Dari <strong>${esc(cur.name_id)}</strong>. Gunakan untuk penggabungan kategori dengan kurang dari 3 peserta, atau koreksi kesalahan pilih kategori.</p>
        <label class="f" for="tc">Ke kategori</label><select id="tc">${list.map((c) => `<option value="${c.id}">${esc(c.name_id)} (${c.registered} terdaftar)</option>`).join('')}</select>
        <label class="f" for="why" style="margin-top:10px">Alasan</label><textarea id="why" placeholder="Mis. digabung karena peserta kurang dari 3"></textarea>`,
      onOk: async (d) => { await api('console_move_entry', { p_entry: e.id, p_category: Number(d.querySelector('#tc').value), p_reason: d.querySelector('#why').value.trim() }); return true; } });
    if (r) { JO.toast('Entri dipindahkan.'); await refreshCats(); done(); }
  }

  // =====================================================================
  //  DATA ATLET
  // =====================================================================
  async function pageAthletes(v) {
    const f = { discipline: '', status: '', q: '' };
    v.innerHTML = `<h1>Data atlet</h1><p class="muted">Seluruh atlet dari pendaftaran yang tidak dibatalkan. Unduh ke Excel untuk rekap panitia.</p>
      <div class="bar">${discSelect('ad', '')}
        <div class="field"><label class="f" for="as">Pembayaran</label><select id="as"><option value="">Semua</option>${Object.entries(ST).filter(([k]) => k !== 'dibatalkan').map(([k, l]) => `<option value="${k}">${l}</option>`).join('')}</select></div>
        <div class="field" style="flex:1;min-width:200px"><label class="f" for="aq">Cari</label><input id="aq" type="search" placeholder="Nama, nomor atlet, klub, kota"></div>
        <button class="btn btn-dark" id="ax" type="button">Unduh Excel</button>
        ${myDiscs().some((d) => d === 'MAG' || d === 'WAG') ? '<button class="btn btn-ghost" id="anom" type="button">Nominative Form</button>' : ''}</div><div id="list"></div>`;
    const nb = v.querySelector('#anom'); if (nb) nb.onclick = () => nominativeDialog();
    let rows = [];
    const load = async () => {
      const list = v.querySelector('#list'); loading(list);
      rows = await api('console_athletes', { p_filter: f });
      list.innerHTML = rows.length ? `<p class="small muted">${rows.length} atlet</p><div class="tbl-wrap"><table class="tbl"><thead><tr>
        <th>No.</th><th>Nama</th><th>L/P</th><th>Lahir</th><th>Klub</th><th>Asal</th><th>Kategori</th><th>Bayar</th><th>Dokumen</th><th></th></tr></thead><tbody>
        ${rows.map((r) => `<tr class="click" data-sub="${r.submission_id}"><td><span class="bib">${esc(r.athlete_no)}</span></td><td>${esc(r.full_name)}</td><td>${r.gender === 'M' ? 'L' : 'P'}</td>
          <td class="small">${esc(r.birth_date)}<br><span class="muted">usia ${r.age}</span></td><td>${esc(r.club)}</td>
          <td class="small">${esc(r.nationality === 'WNA' ? r.country : r.kab_kota || '')}</td><td class="small">${esc(r.categories || '')}</td>
          <td>${pill(r.payment_status)}</td><td class="small">${esc(r.doc_status)}${r.nationality === 'WNI' && !r.has_bpjs ? '<br><span class="pill warn">tanpa BPJS TK</span>' : ''}</td>
          <td class="r">${isSuper() ? rowMenu('', [{ label: 'Buka pendaftaran', attr: `data-open="${r.submission_id}"` }, { sep: true }, { label: 'Hapus atlet', attr: `data-delath="${r.id}"`, danger: true }]) : ''}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Tidak ada atlet yang cocok.</p>';
      list.querySelectorAll('tr[data-sub]').forEach((tr) => tr.onclick = (ev) => { if (ev.target.closest('.rm')) return; location.hash = '#/pendaftaran/' + tr.dataset.sub; });
      list.querySelectorAll('[data-open]').forEach((b) => b.onclick = () => { location.hash = '#/pendaftaran/' + b.dataset.open; });
      list.querySelectorAll('[data-delath]').forEach((b) => b.onclick = async () => {
        const r = rows.find((x) => x.id === b.dataset.delath);
        const reason = await askReason('Hapus atlet ' + r.full_name + '?', 'Alasan penghapusan (masuk Log)', { min: 3, ok: 'Hapus atlet', okClass: 'btn-bad',
          intro: `Dari pendaftaran ${esc(r.submission_code)}. Atlet, kategori, nilai, dan berkasnya dihapus permanen. Bila ini satu-satunya atlet, hapus pendaftarannya dari halaman pendaftaran.` });
        if (!reason) return;
        try { const x = await api('console_delete_athlete', { p_athlete: r.id, p_reason: reason }); await removeFiles(x.files, r.submission_code + ' ' + r.full_name); JO.toast('Atlet dihapus.'); load(); }
        catch (e) { JO.toast(e.message, 'bad'); }
      });
    };
    const ad = v.querySelector('#ad'); if (ad) ad.onchange = () => { f.discipline = ad.value; load(); };
    v.querySelector('#as').onchange = (e) => { f.status = e.target.value; load(); };
    let tm; v.querySelector('#aq').oninput = (e) => { clearTimeout(tm); tm = setTimeout(() => { f.q = e.target.value.trim(); load(); }, 300); };
    v.querySelector('#ax').onclick = () => exportXlsx(`atlet-jabar-open-2026-${new Date().toISOString().slice(0, 10)}.xlsx`, rows, [
      ['athlete_no', 'No. atlet'], ['full_name', 'Nama lengkap'], ['gender', 'L/P', (r) => (r.gender === 'M' ? 'L' : 'P')], ['birth_date', 'Tanggal lahir'], ['age', 'Usia 2026'],
      ['discipline', 'Disiplin', (r) => DN[r.discipline]], ['categories', 'Kategori'], ['club', 'Klub'], ['club_kab_kota', 'Kab/kota klub'],
      ['nationality', 'WNI/WNA'], ['country', 'Negara'], ['province', 'Provinsi (KTP)'], ['kab_kota', 'Kab/kota (KTP)'],
      ['submission_code', 'Kode pendaftaran'], ['payment_status', 'Status bayar', (r) => ST[r.payment_status]], ['doc_status', 'Dokumen'],
      ['has_bpjs', 'BPJS TK diunggah', (r) => (r.nationality === 'WNA' ? '-' : r.has_bpjs ? 'Ya' : 'Belum (bawa ke venue)')],
      ['guardian_name', 'Orang tua/wali'], ['guardian_phone', 'WA orang tua/wali'], ['guardian_email', 'Email orang tua/wali'],
      ['contact_name', 'Penanggung jawab'], ['contact_phone', 'WA penanggung jawab'], ['contact_email', 'Email penanggung jawab']]);
    await load();
  }

  // =====================================================================
  //  KATEGORI
  // =====================================================================
  async function pageCategories(v) {
    await refreshCats();
    let disc = myDiscs()[0];
    const draw = () => {
      const d = CATS.disciplines.find((x) => x.code === disc);
      const list = CATS.categories.filter((c) => c.discipline === disc);
      v.innerHTML = `<h1>Kategori</h1><p class="muted">Dari Undangan Jabar Open 2026. Angka tahun lahir dihitung dari "usia pada tahun kompetisi" (2026).${isTD() ? ' ' + roMode() + ': hanya baca.' : ''}</p>
        <div class="tabs">${myDiscs().map((k) => `<button data-d="${k}" aria-selected="${k === disc}">${DN[k]}</button>`).join('')}</div>
        ${d ? `<div class="row" style="margin-bottom:12px"><span>Pendaftaran ${DN[disc]}: <strong>${d.registration_open ? 'dibuka' : 'ditutup'}</strong></span>
          ${isSuper() ? `<button class="btn btn-ghost btn-sm" id="dtoggle">${d.registration_open ? 'Tutup pendaftaran disiplin ini' : 'Buka pendaftaran'}</button>` : ''}
          <span class="small muted">Kontak: ${esc(d.contact_name || '-')} ${esc(d.contact_phone || '')}</span></div>` : ''}
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Kategori</th><th>Tahun lahir</th><th>Alat</th><th class="r">Biaya</th><th class="r">Terdaftar</th><th class="r">Lunas</th><th class="r">Priangan</th><th>Catatan</th><th></th></tr></thead><tbody>
        ${list.map((c) => {
          const warn = [];
          if (c.registered > 0 && c.registered < 3 && disc !== 'AER') warn.push('Kurang dari 3: gabungkan');
          if (disc === 'AER' && c.registered > 0 && (c.registered < 4 || c.delegations < 3)) warn.push('Aturan eksibisi: <4 peserta atau <3 delegasi');
          if (c.exhibition) warn.push('Eksibisi');
          if (!c.active) warn.push('Nonaktif');
          return `<tr><td><strong>${esc(c.name_id)}</strong><br><span class="tiny muted code">${esc(c.code)}</span></td>
            <td class="small num">${c.birth_year_min || '…'}–${c.birth_year_max || '…'}</td><td class="small">${esc((c.apparatus || []).join(', '))}</td>
            <td class="r num">${fmtRp(c.fee)}</td><td class="r num">${c.registered}</td><td class="r num">${c.paid}</td><td class="r num">${c.priangan}</td>
            <td class="small">${warn.map((w) => `<span class="pill warn">${esc(w)}</span>`).join(' ')}${c.note ? `<br>${esc(c.note)}` : ''}</td>
            <td>${isAdmin() ? `<button class="btn btn-ghost btn-sm" data-edit="${c.id}">Ubah</button>` : ''}</td></tr>`;
        }).join('')}</tbody></table></div>`;
      v.querySelectorAll('[data-d]').forEach((b) => b.onclick = () => { disc = b.dataset.d; draw(); });
      const dt_ = v.querySelector('#dtoggle');
      if (dt_) dt_.onclick = async () => { try { await api('console_update_discipline', { p_code: disc, p_patch: { registration_open: !d.registration_open } }); await refreshCats(); draw(); } catch (e) { JO.toast(e.message, 'bad'); } };
      v.querySelectorAll('[data-edit]').forEach((b) => b.onclick = () => editCategory(CATS.categories.find((c) => c.id === Number(b.dataset.edit)), draw));
    };
    draw();
  }
  async function editCategory(c, done) {
    const sup = isSuper();
    const apps = discApps(c.discipline);
    const r = await dialog({ title: 'Ubah kategori', ok: 'Simpan', wide: true,
      body: `<p><strong>${esc(c.name_id)}</strong></p>
        ${sup ? `<div class="grid-2">
          <div class="field"><label class="f">Nama (Indonesia)</label><input data-k="name_id" value="${esc(c.name_id)}"></div>
          <div class="field"><label class="f">Nama (English)</label><input data-k="name_en" value="${esc(c.name_en)}"></div>
          <div class="field"><label class="f">Lahir paling awal (tahun)</label><input data-k="birth_year_min" type="number" value="${c.birth_year_min || ''}"><div class="f-hint">Kosongkan bila tanpa batas</div></div>
          <div class="field"><label class="f">Lahir paling akhir (tahun)</label><input data-k="birth_year_max" type="number" value="${c.birth_year_max || ''}"></div>
          <div class="field"><label class="f">Biaya (Rp)</label><input data-k="fee" type="number" value="${c.fee}"><div class="f-hint">Hanya berlaku untuk pendaftaran baru</div></div>
          <div class="field"><label class="f">Maks. peserta per klub</label><input data-k="max_per_club" type="number" value="${c.max_per_club || ''}"></div></div>
          <div class="field"><span class="f">Alat</span><div class="row">${apps.map((a) => `<label class="check" style="padding:2px 8px 2px 0"><input type="checkbox" data-app="${a.code}" ${c.apparatus.includes(a.code) ? 'checked' : ''}>${esc(a.id)}</label>`).join('')}</div></div>
          <div class="grid-3">
            <div class="field"><label class="f">Medali serba bisa s.d. peringkat</label><input id="mr_places" type="number" min="1" max="10" value="${(c.medal_rule && c.medal_rule.places) || 3}"></div>
            <div class="field"><label class="f">Penghargaan serba bisa s.d. peringkat</label><input id="mr_aa" type="number" min="1" max="10" value="${(c.medal_rule && (c.medal_rule.aa_places || c.medal_rule.places)) || 3}"><div class="f-hint">Mis. 6 = peringkat 4–6 medali mini</div></div>
            <div class="field"><label class="f">Maks. pesenam per klub per penghargaan</label><input id="mr_cap" type="number" min="0" max="10" value="${(c.medal_rule && c.medal_rule.club_cap) || ''}"><div class="f-hint">Kosongkan bila tanpa batas</div></div></div>
          <label class="check"><input type="checkbox" id="mr_app" ${c.medal_rule && c.medal_rule.apparatus_medals ? 'checked' : ''}>Medali per alat (peringkat 1–3 setiap alat)</label>
          <label class="check"><input type="checkbox" data-b="active" ${c.active ? 'checked' : ''}>Aktif (tampil di formulir pendaftaran)</label>` : ''}
        <label class="check"><input type="checkbox" data-b="exhibition" ${c.exhibition ? 'checked' : ''}>Eksibisi (medali tidak dihitung di tabel perolehan)</label>
        <div class="field"><label class="f">Catatan internal</label><textarea data-k="note">${esc(c.note || '')}</textarea></div>
        ${!sup ? '<p class="small muted">Perubahan usia, biaya, dan alat hanya bisa dilakukan superadmin.</p>' : ''}`,
      onOk: async (d) => {
        const patch = {};
        d.querySelectorAll('[data-k]').forEach((i) => { const k = i.dataset.k; const old = c[k] == null ? '' : String(c[k]); if (i.value !== old) patch[k] = i.value; });
        d.querySelectorAll('[data-b]').forEach((i) => { if (i.checked !== c[i.dataset.b]) patch[i.dataset.b] = i.checked; });
        if (sup) {
          const apps2 = [...d.querySelectorAll('[data-app]:checked')].map((x) => x.dataset.app); if (apps2.join() !== c.apparatus.join()) patch.apparatus = apps2;
          const mr = { type: 'rank', places: Number(d.querySelector('#mr_places').value) || 3 };
          const aa = Number(d.querySelector('#mr_aa').value) || mr.places; if (aa > mr.places) mr.aa_places = aa;
          if (d.querySelector('#mr_app').checked) mr.apparatus_medals = true;
          const cap = Number(d.querySelector('#mr_cap').value); if (cap > 0) mr.club_cap = cap;
          const o = c.medal_rule || {};
          const norm = (x) => JSON.stringify({ p: x.places || 3, a: x.aa_places || x.places || 3, m: !!x.apparatus_medals, c: x.club_cap || 0 });
          if (norm(mr) !== norm(o)) patch.medal_rule = mr;
        }
        if (!Object.keys(patch).length) return true;
        CATS = await api('console_update_category', { p_id: c.id, p_patch: patch }).then(() => api('console_categories', { p_discipline: null }));
        return true;
      } });
    if (r) { JO.toast('Kategori disimpan.'); done(); }
  }

  // =====================================================================
  //  START LIST
  // =====================================================================
  const slState = { disc: '', cat: '' };
  async function pageStartlist(v) {
    await refreshCats();
    if (!slState.disc) slState.disc = myDiscs()[0];
    v.innerHTML = `<h1>Start list</h1><p class="muted">Atur sesi, grup, dan urutan tampil untuk atlet yang sudah lunas, lalu publikasikan. Start list yang dipublikasikan tampil di situs dan AIC.</p>
      <div class="bar"><div class="field"><label class="f" for="sd">Disiplin</label><select id="sd">${myDiscs().map((d) => `<option value="${d}" ${slState.disc === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>
        <div id="catslot" style="flex:1;display:flex"></div></div>
      <section class="card" id="sess"></section><div id="sl" style="margin-top:16px"></div>`;
    const drawCat = () => {
      v.querySelector('#catslot').innerHTML = catSelect('sc', slState.disc, slState.cat);
      v.querySelector('#sc').onchange = (e) => { slState.cat = e.target.value; loadList(); };
    };
    let sessions = [];
    const drawSessions = async () => {
      sessions = await api('console_sessions', { p_discipline: slState.disc });
      const box = v.querySelector('#sess');
      box.innerHTML = `<h2>Sesi ${DN[slState.disc]}</h2>
        ${sessions.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama sesi</th><th>Hari</th><th>Mulai</th><th></th></tr></thead><tbody>
        ${sessions.map((s) => `<tr><td>${esc(s.name)}</td><td>${s.day ? JO.fmtDate(s.day, { weekday: 'long', day: 'numeric', month: 'long' }) : '–'}</td><td>${s.start_time ? s.start_time.slice(0, 5) : '–'}</td>
          <td class="r">${isTD() ? '' : rowMenu(`<button class="btn btn-ghost btn-sm" data-se="${s.id}">Ubah</button>`, [{ label: 'Hapus sesi', attr: `data-sx="${s.id}"`, danger: true }])}</td></tr>`).join('')}</tbody></table></div>` : `<p class="small muted">Belum ada sesi.${isTD() ? '' : ' Tambahkan sesi lomba (mis. "Sesi 1 Minggu pagi").'}</p>`}
        ${isTD() ? '' : '<button class="btn btn-ghost btn-sm" id="sadd" style="margin-top:10px">Tambah sesi</button>'}`;
      const edit = async (s) => {
        const r = await dialog({ title: s ? 'Ubah sesi' : 'Tambah sesi',
          body: `<div class="field"><label class="f">Nama sesi</label><input id="sn" value="${esc(s ? s.name : '')}" placeholder="Sesi 1"></div>
            <div class="grid-2"><div class="field"><label class="f">Hari</label><input id="sday" type="date" value="${esc(s ? s.day || '' : '')}"></div>
            <div class="field"><label class="f">Jam mulai</label><input id="st" type="time" value="${esc(s && s.start_time ? s.start_time.slice(0, 5) : '')}"></div></div>
            <div class="field"><label class="f">Urutan tampil sesi</label><input id="so" type="number" value="${s ? s.sort : sessions.length + 1}"></div>`,
          onOk: async (d) => { await api('console_save_session', { p: { id: s ? s.id : null, discipline: slState.disc, name: d.querySelector('#sn').value, day: d.querySelector('#sday').value, start_time: d.querySelector('#st').value, sort: Number(d.querySelector('#so').value || 0) } }); return true; } });
        if (r) { await drawSessions(); loadList(); }
      };
      if (box.querySelector('#sadd')) box.querySelector('#sadd').onclick = () => edit(null);
      box.querySelectorAll('[data-se]').forEach((b) => b.onclick = () => edit(sessions.find((x) => x.id === Number(b.dataset.se))));
      box.querySelectorAll('[data-sx]').forEach((b) => b.onclick = async () => {
        if (!(await dialog({ title: 'Hapus sesi?', ok: 'Hapus', okClass: 'btn-bad', body: '<p>Atlet di sesi ini akan kehilangan penempatan sesinya (grup dan urutan tetap).</p>' }))) return;
        try { await api('console_delete_session', { p_id: Number(b.dataset.sx) }); await drawSessions(); loadList(); } catch (e) { JO.toast(e.message, 'bad'); }
      });
    };
    const loadList = async () => {
      const box = v.querySelector('#sl');
      if (!slState.cat) { box.innerHTML = '<p class="empty">Pilih kategori untuk mengatur urutan.</p>'; return; }
      loading(box);
      const D = await api('console_startlist', { p_category: Number(slState.cat) });
      const c = D.category;
      box.innerHTML = `<section class="card"><div class="row" style="justify-content:space-between"><h2 style="margin:0">${esc(c.name_id)}</h2>
          ${c.startlist_published ? '<span class="pill ok">Dipublikasikan</span>' : '<span class="pill">Belum dipublikasikan</span>'}</div>
        ${D.unpaid ? `<p class="note warn small" style="margin-top:10px">${D.unpaid} entri belum lunas dan tidak masuk start list.</p>` : ''}
        ${D.entries.length ? `<div class="tbl-wrap" style="margin-top:12px"><table class="tbl"><thead><tr><th>Atlet</th><th>Klub</th><th>Sesi</th><th>Grup</th><th>Urutan</th></tr></thead><tbody>
          ${D.entries.map((e) => `<tr data-e="${e.entry_id}"><td>${e.athletes.map((a) => `${esc(a.name)} <span class="tiny muted">${esc(a.athlete_no)}</span>`).join('<br>')}${e.status === 'dns' ? ' <span class="pill bad">DNS</span>' : ''}${e.priangan_status === 'disetujui' ? ' <span class="pill info">P</span>' : ''}</td>
            <td class="small">${esc(e.club)}</td>
            <td><select data-f="session_id"><option value="">–</option>${D.sessions.map((s) => `<option value="${s.id}" ${e.session_id === s.id ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select></td>
            <td><input data-f="group_no" type="number" min="1" style="width:70px" value="${e.group_no || ''}"></td>
            <td><input data-f="start_order" type="number" min="1" style="width:80px" value="${e.start_order || ''}"></td></tr>`).join('')}</tbody></table></div>
          ${isTD() ? '' : `<div class="sticky-actions"><button class="btn btn-dark" id="save">Simpan</button>
            <button class="btn btn-ghost" id="draw" ${c.startlist_published ? 'disabled' : ''}>Undi urutan acak</button>
            <button class="btn btn-ghost" id="allsess">Isi semua dengan sesi pertama, grup 1</button>
            <button class="btn ${c.startlist_published ? 'btn-bad' : 'btn-primary'}" id="pub">${c.startlist_published ? 'Tarik dari situs' : 'Publikasikan'}</button></div>`}`
          : '<p class="empty">Belum ada atlet lunas di kategori ini.</p>'}</section>`;
      const rows = () => [...box.querySelectorAll('tr[data-e]')].map((tr) => ({ entry_id: tr.dataset.e,
        session_id: tr.querySelector('[data-f=session_id]').value, group_no: tr.querySelector('[data-f=group_no]').value, start_order: tr.querySelector('[data-f=start_order]').value }));
      if (isTD()) box.querySelectorAll('tr[data-e] select, tr[data-e] input').forEach((x) => { x.disabled = true; });
      const sv = box.querySelector('#save');
      if (!sv) return;
      sv.onclick = async () => { try { await api('console_save_startlist', { p_category: c.id, p_rows: rows() }); JO.toast('Start list disimpan.'); loadList(); } catch (e) { JO.toast(e.message, 'bad'); } };
      box.querySelector('#draw').onclick = async () => { try { await api('console_save_startlist', { p_category: c.id, p_rows: rows() }); await api('console_draw_order', { p_category: c.id }); JO.toast('Urutan diundi per grup.'); loadList(); } catch (e) { JO.toast(e.message, 'bad'); } };
      box.querySelector('#allsess').onclick = () => { box.querySelectorAll('tr[data-e]').forEach((tr) => { const s = tr.querySelector('[data-f=session_id]'); if (s.options[1]) s.value = s.options[1].value; tr.querySelector('[data-f=group_no]').value = tr.querySelector('[data-f=group_no]').value || 1; }); };
      box.querySelector('#pub').onclick = async () => {
        try { await api('console_save_startlist', { p_category: c.id, p_rows: rows() }); await api('console_publish_startlist', { p_category: c.id, p_publish: !c.startlist_published }); JO.toast(c.startlist_published ? 'Start list ditarik.' : 'Start list dipublikasikan.'); loadList(); }
        catch (e) { JO.toast(e.message, 'bad'); }
      };
    };
    v.querySelector('#sd').onchange = async (e) => { slState.disc = e.target.value; slState.cat = ''; drawCat(); await drawSessions(); loadList(); };
    drawCat(); await drawSessions(); await loadList();
  }

  // =====================================================================
  //  PENILAIAN
  // =====================================================================
  const scState = { disc: '', cat: '', app: '', mode: 'final' };
  async function pageScoring(v) {
    await refreshCats();
    if (!scState.disc) scState.disc = myDiscs()[0];
    const juri = ME.role === 'juri', ro = isTD();
    if (ro) scState.mode = 'final';
    v.innerHTML = `<h1>Penilaian</h1>
      <p class="muted">${juri ? `Masuk sebagai ${esc(ME.name)}${ME.components ? ', komponen ' + ME.components.join('/') : ''}${ME.apparatus ? ', alat ' + ME.apparatus.join('/') : ''}. Nilai tersimpan otomatis saat Anda pindah kolom.` : ro ? roMode() + ': memantau nilai yang masuk dari juri dan pencatat. Hanya baca; muat ulang untuk melihat nilai terbaru.' : 'Nilai juri masuk langsung ke sini. Pencatat bisa mengisi nilai akhir per alat dari lembar juri. Setiap perubahan setelah dikunci tercatat di log koreksi.'}</p>
      <div class="bar">${myDiscs().length > 1 ? `<div class="field"><label class="f" for="nd">Disiplin</label><select id="nd">${myDiscs().map((d) => `<option value="${d}" ${scState.disc === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>` : ''}
        <div id="catslot" style="flex:1;display:flex"></div></div><div id="sheet"></div>`;
    const drawCat = () => {
      v.querySelector('#catslot').innerHTML = catSelect('nc', scState.disc, scState.cat, (c) => c.paid > 0 || Number(scState.cat) === c.id);
      v.querySelector('#nc').onchange = (e) => { scState.cat = e.target.value; scState.app = ''; load(); };
    };
    const nd = v.querySelector('#nd'); if (nd) nd.onchange = (e) => { scState.disc = e.target.value; scState.cat = ''; drawCat(); load(); };
    const load = async () => {
      const box = v.querySelector('#sheet');
      if (!scState.cat) { box.innerHTML = '<p class="empty">Pilih kategori. Hanya kategori dengan atlet lunas yang muncul.</p>'; return; }
      loading(box);
      const D = await api('console_score_sheet', { p_category: Number(scState.cat) });
      if (!D.apparatus.length) { box.innerHTML = '<p class="note warn">Kode akses Anda tidak mencakup alat di kategori ini.</p>'; return; }
      if (!scState.app || !D.apparatus.some((a) => a.code === scState.app)) scState.app = D.apparatus[0].code;
      const app = scState.app;
      const comps = D.components;
      const showComps = juri || scState.mode === 'comp';
      const W = D.window || { open: true };
      const offHours = juri && W.limited && !W.open;
      box.innerHTML = `<section class="card">
        <div class="row" style="justify-content:space-between"><h2 style="margin:0">${esc(D.category.name_id)}</h2>
          <span>${D.locked ? '<span class="pill warn">Nilai dikunci</span>' : offHours ? '<span class="pill warn">Di luar jam tugas</span>' : '<span class="pill ok">Terbuka untuk input</span>'}${D.category.results_published ? ' <span class="pill dark">Hasil dipublikasikan</span>' : ''}</span></div>
        ${juri && W.limited ? `<p class="note ${offHours ? 'warn' : 'ok'}" style="margin:10px 0 0">${offHours
          ? `Di luar jam tugas Anda: nilai hanya bisa dilihat, tidak bisa diisi.${W.next ? ` Jam tugas berikutnya ${esc(winLabel(W.next))} WIB.` : ' Tidak ada jam tugas lagi; hubungi admin bila perlu.'}`
          : `Jam tugas Anda sekarang: ${esc(winLabel(W.current))} WIB.`}</p>` : ''}
        <div class="tabs" style="margin-top:12px">${D.apparatus.map((a) => `<button data-app="${a.code}" aria-selected="${a.code === app}">${esc(a.id)}</button>`).join('')}</div>
        ${!juri && !ro ? `<div class="row" style="margin-bottom:10px"><div class="seg"><label><input type="radio" name="md" value="final" ${scState.mode === 'final' ? 'checked' : ''}>Isi nilai akhir</label><label><input type="radio" name="md" value="comp" ${scState.mode === 'comp' ? 'checked' : ''}>Isi per komponen</label></div>
          <span class="small muted">Nilai akhir menggantikan hitungan komponen untuk alat ini.</span></div>` : ''}
        ${D.entries.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">#</th><th>Atlet</th>
          ${showComps ? comps.map((c) => `<th class="r">${esc(c.code)}<br><span class="tiny">${esc(c.id.replace(/^Nilai /, ''))}</span></th>`).join('') : ''}
          ${!juri ? `${!showComps ? '<th>Nilai juri</th>' : ''}<th class="r">Nilai ${esc(app)}</th>${scState.mode === 'final' && !ro ? '<th class="r">Nilai akhir</th>' : ''}<th class="r">Total</th><th class="c">Per.</th>` : ''}</tr></thead><tbody>
          ${D.entries.map((e, i) => {
            const all = (e.all || []).filter((x) => x.apparatus === app);
            const res = e.result || {};
            const judgeTxt = ['D', 'A', 'E', 'PEN', 'FINAL'].map((c) => { const xs = all.filter((x) => x.component === c); return xs.length ? `${c}: ${xs.map((x) => `${num3(x.value)} <span class="muted">(${esc(x.staff)})</span>`).join(', ')}` : ''; }).filter(Boolean).join('<br>');
            return `<tr data-e="${e.entry_id}"><td class="c num">${e.start_order || i + 1}</td>
              <td>${e.athletes.map((a) => `<strong>${esc(a.name)}</strong> <span class="tiny muted">${esc(a.athlete_no)}</span>`).join('<br>')}<br><span class="tiny muted">${esc(e.club)}</span>${e.status === 'dns' ? ' <span class="pill bad">DNS</span>' : ''}</td>
              ${showComps ? comps.map((c) => `<td class="r"><input class="score-in" inputmode="decimal" data-c="${c.code}" value="${e.own[app + ':' + c.code] != null ? e.own[app + ':' + c.code] : ''}" aria-label="${esc(c.code)} ${esc(e.athletes[0].name)}" ${e.status === 'dns' ? 'disabled' : ''}></td>`).join('') : ''}
              ${!juri ? `${!showComps ? `<td class="judge-vals">${judgeTxt || '–'}</td>` : ''}
                <td class="r num"><strong data-score>${num3(res.scores ? res.scores[app] : null)}</strong></td>
                ${scState.mode === 'final' && !ro ? `<td class="r"><input class="score-in" inputmode="decimal" data-c="FINAL" value="${e.own[app + ':FINAL'] != null ? e.own[app + ':FINAL'] : ''}" aria-label="Nilai akhir ${esc(e.athletes[0].name)}" ${e.status === 'dns' ? 'disabled' : ''}></td>` : ''}
                <td class="r num">${num3(res.total)}</td><td class="c"><span class="rank">${res.rank || '–'}</span>${res.medal ? ` <span class="medal ${res.medal}"></span>` : ''}</td>` : ''}
            </tr>`;
          }).join('')}</tbody></table></div>` : '<p class="empty">Belum ada atlet lunas di kategori ini.</p>'}
        ${ro ? `<div class="sticky-actions"><button class="btn btn-ghost" id="refresh">Muat ulang nilai</button><a class="btn btn-primary" href="#/hasil?c=${D.category.id}">Lihat hasil</a></div>`
          : !juri ? `<div class="sticky-actions"><button class="btn btn-ghost" id="refresh">Muat ulang nilai</button>
          <button class="btn ${D.category.scores_locked ? 'btn-ghost' : 'btn-dark'}" id="lock" ${D.category.results_published ? 'disabled' : ''}>${D.category.scores_locked ? 'Buka kunci nilai' : 'Kunci nilai'}</button>
          <a class="btn btn-primary" href="#/hasil?c=${D.category.id}">Lihat hasil & publikasi</a></div>` : '<div class="sticky-actions"><button class="btn btn-ghost" id="refresh">Muat ulang</button></div>'}
      </section>`;
      box.querySelectorAll('[data-app]').forEach((b) => b.onclick = () => { scState.app = b.dataset.app; load(); });
      box.querySelectorAll('input[name=md]').forEach((r) => r.onchange = () => { scState.mode = r.value; load(); });
      box.querySelector('#refresh').onclick = load;
      const lk = box.querySelector('#lock');
      if (lk) lk.onclick = async () => { try { await api('console_lock_scores', { p_category: D.category.id, p_lock: !D.category.scores_locked }); load(); } catch (e) { JO.toast(e.message, 'bad'); } };
      const inputs = [...box.querySelectorAll('.score-in')];
      if (offHours) inputs.forEach((x) => { x.disabled = true; });
      inputs.forEach((inp, idx) => {
        inp.dataset.orig = inp.value;
        inp.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); if (inputs[idx + 1]) inputs[idx + 1].focus(); else inp.blur(); } });
        inp.addEventListener('change', async () => {
          const tr = inp.closest('tr');
          const val = parseScore(inp.value);
          if (Number.isNaN(val)) { inp.classList.add('err'); JO.toast('Nilai harus angka, mis. 8.350', 'bad'); return; }
          let reason = null;
          if (D.locked && !juri) { reason = await askReason('Koreksi nilai terkunci', 'Alasan koreksi (masuk log koreksi)'); if (!reason) { inp.value = inp.dataset.orig; return; } }
          inp.classList.remove('saved', 'err'); inp.classList.add('saving');
          try {
            if (val === null) await api('console_delete_score', { p_entry: tr.dataset.e, p_apparatus: app, p_component: inp.dataset.c, p_reason: reason });
            else {
              const r = await api('console_save_score', { p_entry: tr.dataset.e, p_apparatus: app, p_component: inp.dataset.c, p_value: val, p_reason: reason });
              const sc = tr.querySelector('[data-score]'); if (sc && r.apparatus_score != null) sc.textContent = num3(r.apparatus_score);
            }
            inp.dataset.orig = inp.value; inp.classList.remove('saving'); inp.classList.add('saved');
          } catch (e) { inp.classList.remove('saving'); inp.classList.add('err'); JO.toast(e.message, 'bad'); }
        });
      });
    };
    const hp = hashParams(); if (hp.get('c')) { scState.cat = hp.get('c'); const c = CATS.categories.find((x) => x.id === Number(scState.cat)); if (c) scState.disc = c.discipline; }
    drawCat(); await load();
  }

  // =====================================================================
  //  HASIL & MEDALI
  // =====================================================================
  const reState = { disc: '', cat: '' };
  async function pageResults(v) {
    await refreshCats();
    if (!reState.disc) reState.disc = myDiscs()[0];
    const hp = hashParams(); if (hp.get('c')) { reState.cat = hp.get('c'); const c = CATS.categories.find((x) => x.id === Number(reState.cat)); if (c) reState.disc = c.discipline; }
    v.innerHTML = `<h1>Hasil & medali</h1><p class="muted">${isTD() ? roMode() + ': hanya baca. ' : ''}Publikasikan hasil per kategori setelah UPP. Publikasi mengunci nilai; sertifikat dan tabel medali di situs ikut diperbarui.</p>
      <div class="tabs"><button data-t="cat" aria-selected="true">Hasil kategori</button>${teamDiscs().length ? '<button data-t="team" aria-selected="false">Beregu</button>' : ''}<button data-t="medal" aria-selected="false">Tabel medali</button></div><div id="rbox"></div>`;
    const rbox = v.querySelector('#rbox');
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = () => { v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b))); b.dataset.t === 'cat' ? catView() : b.dataset.t === 'team' ? teamView(rbox) : medalView(); });
    const catView = () => {
      rbox.innerHTML = `<div class="bar"><div class="field"><label class="f" for="rd">Disiplin</label><select id="rd">${myDiscs().map((d) => `<option value="${d}" ${reState.disc === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>
        <div id="catslot" style="flex:1;display:flex"></div></div><div id="res"></div>`;
      const drawCat = () => { rbox.querySelector('#catslot').innerHTML = catSelect('rc', reState.disc, reState.cat, (c) => c.paid > 0); rbox.querySelector('#rc').onchange = (e) => { reState.cat = e.target.value; loadRes(); }; };
      rbox.querySelector('#rd').onchange = (e) => { reState.disc = e.target.value; reState.cat = ''; drawCat(); loadRes(); };
      drawCat(); loadRes();
    };
    const loadRes = async () => {
      const box = rbox.querySelector('#res');
      if (!reState.cat) { box.innerHTML = '<p class="empty">Pilih kategori.</p>'; return; }
      loading(box);
      const D = await api('console_results', { p_category: Number(reState.cat) });
      const c = D.category; const apps = D.apparatus; const anyPri = D.results.some((r) => r.priangan);
      const incomplete = D.results.filter((r) => r.n_scored < apps.length).length;
      box.innerHTML = `<section class="card"><div class="row" style="justify-content:space-between"><h2 style="margin:0">${esc(c.name_id)}</h2>
          ${c.results_published ? `<span class="pill ok">Dipublikasikan ${dt(c.results_published_at)}</span>` : '<span class="pill">Belum dipublikasikan</span>'}</div>
        <p class="small muted">${ruleText(c.medal_rule)}${c.exhibition ? ' Kategori eksibisi: medali tidak dihitung.' : ''}</p>
        ${incomplete ? `<p class="note warn small">${incomplete} atlet belum punya nilai di semua alat.</p>` : ''}
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">Per.</th><th>Atlet</th><th>Klub</th>${apps.length > 1 ? apps.map((a) => `<th class="r">${esc(a.code)}</th>`).join('') : ''}<th class="r">Total</th><th>Medali</th>${anyPri ? '<th class="c">Priangan</th>' : ''}</tr></thead><tbody>
          ${D.results.map((r) => `<tr><td class="c"><span class="rank">${r.rank || '–'}</span></td>
            <td>${r.athletes.map((a) => `${esc(a.name)} <span class="tiny muted">${esc(a.athlete_no)}</span>`).join('<br>')}</td><td class="small">${esc(r.club)}<br><span class="muted">${esc(r.region)}</span></td>
            ${apps.length > 1 ? apps.map((a) => `<td class="r num">${num3(r.scores[a.code])}${r.app_medals && r.app_medals[a.code] ? ` <span class="medal ${r.app_medals[a.code]}"></span>` : ''}</td>`).join('') : ''}
            <td class="r num"><strong>${num3(r.total)}</strong></td><td>${r.medal ? `<span class="medal ${r.medal}"></span> ${esc(JO.t('medal_' + r.medal))}` : r.mini ? `<span class="pill">Mini ${r.award_rank}</span>` : ''}${r.capped ? ' <span class="pill warn" title="Maks. 2 pesenam per klub; penghargaan turun ke pesenam berikutnya">batas klub</span>' : ''}${r.team_only ? ' <span class="pill gold">khusus beregu</span>' : ''}</td>
            ${anyPri ? `<td class="c">${r.priangan_rank ? r.priangan_rank + (r.priangan_medal ? ` <span class="medal ${r.priangan_medal}"></span>` : '') : ''}</td>` : ''}</tr>`).join('')}
        </tbody></table></div>
        <div class="sticky-actions">
          ${isTD() ? '' : `<button class="btn ${c.results_published ? 'btn-bad' : 'btn-primary'}" id="pub" ${c.results_published && !isSuper() ? 'disabled' : ''}>${c.results_published ? 'Tarik hasil dari situs' : 'Publikasikan hasil'}</button>`}
          <button class="btn btn-ghost" id="certs">Unduh semua sertifikat (PDF)</button>
          <a class="btn btn-ghost" href="#/nilai?c=${c.id}">Ke penilaian</a></div></section>`;
      if (box.querySelector('#pub')) box.querySelector('#pub').onclick = async () => {
        const go = await dialog({ title: c.results_published ? 'Tarik hasil?' : 'Publikasikan hasil?', ok: c.results_published ? 'Tarik' : 'Publikasikan', okClass: c.results_published ? 'btn-bad' : 'btn-primary',
          body: c.results_published ? '<p>Hasil dan sertifikat kategori ini tidak lagi tampil di situs. Nilai tetap terkunci.</p>' : `<p>Hasil tampil di situs, sertifikat bisa diunduh peserta, dan nilai dikunci. ${incomplete ? '<strong>Masih ada atlet tanpa nilai lengkap.</strong>' : ''}</p>` });
        if (!go) return;
        try { await api('console_publish_results', { p_category: c.id, p_publish: !c.results_published }); JO.toast(c.results_published ? 'Hasil ditarik.' : 'Hasil dipublikasikan.'); loadRes(); } catch (e) { JO.toast(e.message, 'bad'); }
      };
      box.querySelector('#certs').onclick = async (ev) => {
        const btn = ev.currentTarget; btn.disabled = true; btn.textContent = 'Membuat PDF…';
        try {
          let doc = null;
          for (const r of D.results) {
            if (r.team_only) continue;
            for (const a of r.athletes) {
              const cert = D.certificates.find((x) => x.entry_id === r.entry_id && x.athlete_id === a.id);
              const code = cert ? cert.cert_code : '-';
              doc = await JO.certificatePdf({ name: a.name, club: r.club, discipline: c.discipline, category: c.name_id, rank: r.award_rank, medal: r.medal, mini: r.mini,
                priangan_rank: r.priangan_rank, priangan_medal: r.priangan_medal, cert_code: code, signatories: D.signatories }, doc);
              for (const [ap, m] of Object.entries(r.app_medals || {})) {
                const an = (apps.find((x) => x.code === ap) || {}).id || ap;
                doc = await JO.certificatePdf({ name: a.name, club: r.club, discipline: c.discipline, category: c.name_id, apparatus: an, medal: m,
                  cert_code: code + '-' + ap, signatories: D.signatories }, doc);
              }
            }
          }
          if (doc) doc.save(`sertifikat-${c.code}.pdf`); else JO.toast('Belum ada hasil.', 'bad');
        } catch (e) { JO.toast(e.message, 'bad'); }
        finally { btn.disabled = false; btn.textContent = 'Unduh semua sertifikat (PDF)'; }
      };
    };
    const medalView = async () => {
      rbox.innerHTML = `<div class="bar"><div class="seg"><label><input type="radio" name="mk" value="0" checked>Jabar Open</label><label><input type="radio" name="mk" value="1">Priangan</label></div>
        <label class="check" style="padding:0"><input type="checkbox" id="mu">Sertakan kategori yang belum dipublikasikan (pratinjau)</label>
        <button class="btn btn-ghost btn-sm" id="mx">Unduh Excel</button>
        <button class="btn btn-ghost btn-sm" id="mo" ${isTD() ? 'hidden' : ''} title="Jumlah medali & piala yang perlu dipesan, dihitung dari pendaftaran">Kebutuhan medali (Excel)</button></div><div id="mt"></div>`;
      rbox.querySelector('#mo').onclick = () => medalOrderReport().catch((e) => JO.toast(e.message, 'bad'));
      let data;
      const draw = async () => {
        const box = rbox.querySelector('#mt'); loading(box);
        data = await api('console_medal_table', { p_priangan: rbox.querySelector('input[name=mk]:checked').value === '1', p_published_only: !rbox.querySelector('#mu').checked });
        const tbl = (rows, label) => rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>#</th><th>${label}</th><th class="c">Emas</th><th class="c">Perak</th><th class="c">Perunggu</th><th class="c">Total</th></tr></thead><tbody>
          ${rows.map((r, i) => `<tr><td>${i + 1}</td><td>${esc(r.label)}</td><td class="c">${r.emas}</td><td class="c">${r.perak}</td><td class="c">${r.perunggu}</td><td class="c"><strong>${r.total}</strong></td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada medali.</p>';
        box.innerHTML = `<div class="grid-2" style="align-items:start"><div><h2>Per kabupaten/kota</h2>${tbl(data.by_region, 'Kab/kota')}</div><div><h2>Per klub</h2>${tbl(data.by_club, 'Klub')}</div></div>`;
      };
      rbox.querySelectorAll('input[name=mk]').forEach((r) => r.onchange = draw);
      rbox.querySelector('#mu').onchange = draw;
      rbox.querySelector('#mx').onclick = () => {
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(data.by_region), 'Per kab-kota');
        XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(data.by_club), 'Per klub');
        XLSX.writeFile(wb, 'tabel-medali-jabar-open-2026.xlsx');
      };
      draw();
    };
    catView();
  }

  const teamDiscs = () => myDiscs().filter((d) => d === 'WAG');
  function ruleText(r) {
    r = r || {};
    const p = r.places || 3, aa = r.aa_places || p;
    const parts = [`Medali serba bisa peringkat 1–${p}`];
    if (aa > p) parts.push(`medali mini peringkat ${p + 1}–${aa}`);
    if (r.apparatus_medals) parts.push('medali per alat peringkat 1–3');
    let txt = parts.join(', ') + '.';
    if (r.club_cap) txt += ` Maks. ${r.club_cap} pesenam per klub untuk setiap penghargaan; pesenam berikutnya dari klub yang sama dilewati.`;
    return txt + ' Setiap atlet mendapat sertifikat peserta.';
  }
  const teState = { disc: '' };
  async function teamView(rbox) {
    if (!teState.disc) teState.disc = teamDiscs()[0];
    rbox.innerHTML = `<div class="bar"><div class="field"><label class="f" for="td">Disiplin</label><select id="td">${teamDiscs().map((d) => `<option value="${d}" ${teState.disc === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div></div>
      <p class="small muted">Nilai tim = jumlah 4 nilai serba bisa terbaik dari anggotanya (hanya tim lunas dan anggota aktif yang lunas). Nilai anggota diambil dari halaman Penilaian kategori masing-masing. Sertifikat Juara Beregu untuk setiap anggota tim peringkat 1–3.</p><div id="tl"></div>`;
    rbox.querySelector('#td').onchange = (e) => { teState.disc = e.target.value; load(); };
    const load = async () => {
      const box = rbox.querySelector('#tl'); loading(box);
      const L = await api('console_teams', { p_discipline: teState.disc });
      if (!L.length) { box.innerHTML = '<p class="empty">Belum ada tim beregu di disiplin ini.</p>'; return; }
      box.innerHTML = L.map((lv, i) => `<section class="card" data-i="${i}"><div class="row" style="justify-content:space-between"><h2 style="margin:0">Beregu ${esc(DN[teState.disc])} ${esc(lv.level)}</h2>
          ${lv.published ? `<span class="pill ok">Dipublikasikan ${dt(lv.published_at)}</span>` : '<span class="pill">Belum dipublikasikan</span>'}</div>
        ${lv.results.length ? `<div class="tbl-wrap" style="margin-top:12px"><table class="tbl"><thead><tr><th class="c">Per.</th><th>Tim</th><th>Anggota (nilai serba bisa)</th><th class="r">Nilai tim</th></tr></thead><tbody>
          ${lv.results.map((r) => `<tr><td class="c"><span class="rank">${r.rank || '–'}</span>${r.trophy ? ` <span class="medal ${['emas', 'perak', 'perunggu'][r.rank - 1]}"></span>` : ''}</td>
            <td><strong>${esc(r.name)}</strong><br><span class="small muted">${esc(r.club)}</span><br>${isAdmin() ? `<a class="small" href="#/pendaftaran/${r.submission_id}">${esc(r.code)}</a>` : `<span class="small code">${esc(r.code)}</span>`}</td>
            <td class="small">${r.members.map((m) => `${esc(m.name)}${m.team_only ? ' <span class="tiny muted">(khusus beregu)</span>' : ''}: <span class="num">${m.counted ? `<strong>${num3(m.total)}</strong>` : num3(m.total)}</span>`).join('<br>')}
              ${r.n_scored < r.n_members ? `<br><span class="pill warn">${r.n_members - r.n_scored} anggota belum bernilai</span>` : ''}</td>
            <td class="r num"><strong>${num3(r.total)}</strong></td></tr>`).join('')}</tbody></table></div>` : '<p class="small muted" style="margin-top:10px">Belum ada tim lunas di level ini.</p>'}
        ${lv.pending.length ? `<p class="small muted">Belum lunas (tidak ikut peringkat): ${lv.pending.map((x) => isAdmin() ? `<a href="#/pendaftaran/${x.id}">${esc(x.name)}</a>` : esc(x.name)).join(', ')}</p>` : ''}
        <div class="sticky-actions">
          <button class="btn ${lv.published ? 'btn-bad' : 'btn-primary'}" ${isTD() ? 'hidden' : ''} data-pub ${lv.published && !isSuper() ? 'disabled' : ''}>${lv.published ? 'Tarik hasil beregu' : 'Publikasikan hasil beregu'}</button>
          <button class="btn btn-ghost" data-certs ${lv.results.some((r) => r.trophy) ? '' : 'disabled'}>Unduh sertifikat Juara Beregu (PDF)</button></div></section>`).join('');
      box.querySelectorAll('section[data-i]').forEach((sec) => {
        const lv = L[Number(sec.dataset.i)];
        sec.querySelector('[data-pub]').onclick = async () => {
          const go = await dialog({ title: lv.published ? 'Tarik hasil beregu?' : 'Publikasikan hasil beregu?', ok: lv.published ? 'Tarik' : 'Publikasikan', okClass: lv.published ? 'btn-bad' : 'btn-primary',
            body: lv.published ? '<p>Peringkat beregu level ini tidak lagi tampil di situs dan sertifikat Juara Beregu tidak bisa diunduh peserta.</p>'
              : `<p>Peringkat beregu ${esc(lv.level)} tampil di halaman Hasil, dan anggota tim peringkat 1–3 bisa mengunduh sertifikat Juara Beregu dari halaman status. Pastikan nilai semua kategori di level ini sudah final.</p>${lv.results.some((r) => r.n_scored < r.n_members) ? '<p class="note warn">Masih ada anggota tanpa nilai lengkap.</p>' : ''}` });
          if (!go) return;
          try { await api('console_team_publish', { p_discipline: teState.disc, p_level: lv.level, p_publish: !lv.published }); JO.toast(lv.published ? 'Hasil beregu ditarik.' : 'Hasil beregu dipublikasikan.'); load(); }
          catch (e) { JO.toast(e.message, 'bad'); }
        };
        sec.querySelector('[data-certs]').onclick = async (ev) => {
          const btn = ev.currentTarget; const old = btn.textContent; btn.disabled = true; btn.textContent = 'Membuat PDF…';
          try {
            const sig = lv.signatories;
            let doc = null;
            for (const r of lv.results.filter((x) => x.trophy)) {
              for (const m of r.members) {
                doc = await JO.certificatePdf({ team: true, name: m.name, club: r.club, discipline: teState.disc,
                  category: `Beregu ${DN[teState.disc]} ${lv.level}, tim ${r.name}`, rank: r.rank, cert_code: m.cert_code || '-', signatories: sig }, doc);
              }
            }
            if (doc) doc.save(`sertifikat-beregu-${teState.disc}-${lv.level.replace(/\s+/g, '-')}.pdf`);
          } catch (e) { JO.toast(e.message, 'bad'); }
          finally { btn.disabled = false; btn.textContent = old; }
        };
      });
    };
    await load();
  }

  // =====================================================================
  //  EKSPOR: Nominative Form & kebutuhan medali (format lampiran panitia)
  // =====================================================================
  const fmtDMY = (d) => (d ? d.slice(8, 10) + '/' + d.slice(5, 7) + '/' + d.slice(0, 4) : '');
  async function nominativeDialog() {
    const discs = myDiscs().filter((d) => d === 'MAG' || d === 'WAG');
    let clubs = [];
    try { clubs = (await api('console_clubs')).filter((k) => !k.merged_into); } catch (e) { clubs = []; }
    const r = await dialog({ title: 'Unduh Nominative Form', ok: 'Unduh Excel',
      body: `<p class="small muted">Format sama dengan lampiran panitia: lembar Gymnasts List (perorangan) dan Team (beregu). Pendaftaran yang dibatalkan tidak ikut.</p>
        <div class="grid-2"><div class="field"><label class="f" for="nd2">Disiplin</label><select id="nd2">${discs.map((d) => `<option value="${d}">${DN[d]}</option>`).join('')}</select></div>
        <div class="field"><label class="f" for="nc2">Klub</label><select id="nc2"><option value="">Semua klub</option>${clubs.map((k) => `<option value="${k.id}">${esc(k.name)}</option>`).join('')}</select></div></div>`,
      onOk: async (d) => ({ disc: d.querySelector('#nd2').value, club: d.querySelector('#nc2').value || null,
        clubName: d.querySelector('#nc2').selectedOptions[0].textContent }) });
    if (!r) return;
    const D = await api('console_nominative', { p_discipline: r.disc, p_club: r.club });
    const g = [['JABAR OPEN 2026 - ARTISTIC GYMNASTICS'], [' Form Nominative'], ['', '', '', '', '', '', 'Deadline : 12 November 2026'],
      ['NO', 'KLUB', 'NAMA', 'TANGGAL LAHIR', 'UMUR', 'MAG / WAG', 'LEVEL', 'KATEGORI', 'NO. ATLET', 'KODE PENDAFTARAN', 'STATUS'],
      ['', '', '', '(dd/mm/yyyy)']];
    D.gymnasts.forEach((x, i) => g.push([i + 1, x.club, x.name, fmtDMY(x.birth_date), x.age, x.discipline, x.level, x.category + (x.priangan ? ' + Priangan' : ''), x.athlete_no || '', x.code, ST[x.status] || x.status]));
    const wsG = XLSX.utils.aoa_to_sheet(g);
    wsG['!cols'] = [6, 26, 30, 14, 7, 10, 12, 22, 11, 18, 20].map((w) => ({ wch: w }));
    wsG['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: 7 } }, { s: { r: 1, c: 0 }, e: { r: 1, c: 7 } }];
    const t = [['JABAR OPEN 2026 - ARTISTIC GYMNASTICS'], [' Form Nominative - Tim'], ['NO', 'KLUB', 'MAG / WAG', 'LEVEL', 'NAMA TIM', 'NO.', 'NAMA PESENAM', 'KETERANGAN', 'KODE PENDAFTARAN', 'STATUS']];
    const merges = [{ s: { r: 0, c: 0 }, e: { r: 0, c: 6 } }, { s: { r: 1, c: 0 }, e: { r: 1, c: 6 } }];
    D.teams.forEach((tm, i) => {
      const r0 = t.length;
      const n = Math.max(6, tm.members.length);
      for (let j = 0; j < n; j++) {
        const m = tm.members[j];
        t.push(j === 0 ? [i + 1, tm.club, tm.discipline, tm.level, tm.name, 1, m ? m.name : '', m ? (m.team_only ? 'khusus beregu' : 'juga perorangan') : '', tm.code, ST[tm.status] || tm.status]
          : ['', '', '', '', '', j + 1, m ? m.name : '', m ? (m.team_only ? 'khusus beregu' : 'juga perorangan') : '', '', '']);
      }
      [0, 1, 2, 3, 4, 8, 9].forEach((c) => merges.push({ s: { r: r0, c }, e: { r: r0 + n - 1, c } }));
    });
    const wsT = XLSX.utils.aoa_to_sheet(t);
    wsT['!cols'] = [5, 26, 10, 10, 20, 5, 30, 16, 18, 20].map((w) => ({ wch: w }));
    wsT['!merges'] = merges;
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, wsG, 'Gymnasts List');
    XLSX.utils.book_append_sheet(wb, wsT, 'Team');
    const tag = r.club ? r.clubName.replace(/[^a-z0-9]+/gi, '-') : 'Semua-klub';
    XLSX.writeFile(wb, `JBO 2026 - Nominative Form ${r.disc} - ${tag}.xlsx`);
    JO.toast(`${D.gymnasts.length} pesenam, ${D.teams.length} tim.`);
  }

  async function medalOrderReport() {
    await refreshCats();
    const cats = CATS.categories.filter((c) => c.active);
    const teamLv = (CATS.team_levels || { WAG: ['Level 1', 'Level 2', 'Level 3', 'Level 4', 'Level 5', 'Level 6'] });
    const wb = XLSX.utils.book_new();
    // --- Artistik ---
    const A = [['JABAR OPEN GYMNASTICS 2026 - MEDALI & PIALA ARTISTIK'],
      ['DISIPLIN', '', 'LEVEL', 'NO', 'KATEGORI', 'PESERTA (N)', 'MEDALI ACHIEVEMENT & PARTICIPANT', 'MEDALI KOMPETISI (1-3)', '', '', '', '', 'MEDALI MINI (4-6)', '', '', '', '', 'PIALA BEREGU', '', ''],
      ['', '', '', '', '', 'TERDAFTAR / LUNAS', 'EMAS', 'EMAS', 'PERAK', 'PERUNGGU', 'SET', 'KEPING', 'IV', 'V', 'VI', 'SET', 'KEPING', 'JUARA I', 'JUARA II', 'JUARA III']];
    const sumRows = [];
    for (const disc of ['MAG', 'WAG']) {
      const list = cats.filter((c) => c.discipline === disc);
      if (!list.length) continue;
      const first = A.length;
      const seenLv = new Set();
      list.forEach((c, i) => {
        const r = c.medal_rule || {};
        const sets = 1 + (r.apparatus_medals ? c.apparatus.length : 0);
        const mini = Math.max(0, (r.aa_places || r.places || 3) - (r.places || 3));
        const lvFirst = !seenLv.has(c.level); seenLv.add(c.level);
        const trophy = lvFirst && (teamLv[disc] || []).includes(c.level) ? 1 : '';
        A.push([i === 0 ? (disc === 'MAG' ? 'ARTISTIK PUTRA' : 'ARTISTIK PUTRI') : '', '', lvFirst ? `${disc} ${c.level.toUpperCase()}` : '', i + 1, c.name_id,
          `${c.registered} / ${c.paid}`, c.registered, sets, sets, sets, sets, sets * 3,
          mini >= 1 ? 1 : '', mini >= 2 ? 1 : '', mini >= 3 ? 1 : '', mini ? 1 : '', mini || '', trophy, trophy, trophy]);
      });
      const last = A.length;
      A.push(['', '', '', '', 'Cadangan :']);
      const cad = A.length;
      const col = (n) => XLSX.utils.encode_col(n);
      A.push(['', '', '', '', 'Jumlah :', '', ...[6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19].map((n) => ({ f: `SUM(${col(n)}${first + 1}:${col(n)}${cad})` }))]);
      sumRows.push(A.length);
      A.push([]);
    }
    if (sumRows.length) A.push(['', 'TOTAL MEDALI ARTISTIK PUTRA & PUTRI :', '', '', '', '', ...[6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19].map((n) => ({ f: sumRows.map((r) => XLSX.utils.encode_col(n) + r).join('+') }))]);
    A.push([]);
    A.push(['Catatan: N = jumlah peserta terdaftar (belum dibatalkan). Isi baris Cadangan sesuai kebutuhan; baris Jumlah menghitung otomatis.']);
    const wsA = XLSX.utils.aoa_to_sheet(A);
    wsA['!cols'] = [16, 2, 16, 5, 44, 14, 12, 8, 8, 10, 6, 8, 5, 5, 5, 6, 8, 9, 9, 10].map((w) => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, wsA, 'ARTISTIK');
    // --- Aerobik ---
    const aer = cats.filter((c) => c.discipline === 'AER');
    if (aer.length) {
      const E = [['JABAR OPEN GYMNASTICS 2026 - MEDALI AEROBIK'], ['DISIPLIN', '', 'NO', 'KATEGORI', 'PESERTA (N)', 'MEDALI KOMPETISI (1-3)'], ['', '', '', '', 'TERDAFTAR / LUNAS', 'EMAS', 'PERAK', 'PERUNGGU', 'SET', 'KEPING']];
      const f0 = E.length;
      aer.forEach((c, i) => { const k = c.entry_type === 'pair' ? 2 : 1; E.push([i === 0 ? 'AEROBIK' : '', '', i + 1, c.name_id, `${c.registered} / ${c.paid}`, k, k, k, k, k * 3]); });
      E.push(['', '', '', 'Cadangan :']);
      const cad = E.length;
      E.push(['', '', '', 'Jumlah :', '', ...[5, 6, 7, 8, 9].map((n) => ({ f: `SUM(${XLSX.utils.encode_col(n)}${f0 + 1}:${XLSX.utils.encode_col(n)}${cad})` }))]);
      const wsE = XLSX.utils.aoa_to_sheet(E);
      wsE['!cols'] = [12, 2, 5, 44, 14, 8, 8, 10, 6, 8].map((w) => ({ wch: w }));
      XLSX.utils.book_append_sheet(wb, wsE, 'AEROBIK');
    }
    XLSX.writeFile(wb, `JBO 2026 - Kebutuhan Medali ${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  // =====================================================================
  //  LEDGER (superadmin)
  // =====================================================================
  function parseAmount(v) {
    if (typeof v === 'number') return Math.round(v);
    let s = String(v == null ? '' : v).replace(/[^0-9,.-]/g, '');
    if (!s) return null;
    if (/^-?\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) s = s.replace(/\./g, '').replace(',', '.');
    else if (/^-?\d{1,3}(,\d{3})+(\.\d+)?$/.test(s)) s = s.replace(/,/g, '');
    else s = s.replace(',', '.');
    const n = Number(s); return Number.isFinite(n) ? Math.round(n) : null;
  }
  function parseWhen(v) {
    if (v instanceof Date) return isNaN(v) ? null : v.toISOString();
    const s = String(v == null ? '' : v).trim(); if (!s) return null;
    let m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?:[ T,]+(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?)?/);
    if (m) return new Date(`${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}T${(m[4] || '00').padStart(2, '0')}:${m[5] || '00'}:${m[6] || '00'}+07:00`).toISOString();
    m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/);
    if (m) return new Date(`${m[1]}-${m[2]}-${m[3]}T${m[4] || '00'}:${m[5] || '00'}:${m[6] || '00'}+07:00`).toISOString();
    const d = new Date(s); return isNaN(d) ? null : d.toISOString();
  }
  async function readTable(file) {
    if (/\.csv$/i.test(file.name) || file.type === 'text/csv') {
      const text = await file.text();
      return Papa.parse(text, { header: true, skipEmptyLines: true }).data;
    }
    const wb = XLSX.read(await file.arrayBuffer(), { cellDates: true });
    const ws = wb.Sheets[wb.SheetNames[0]];
    // cari baris header: baris pertama yang punya >= 3 sel terisi
    const aoa = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: '' });
    const hi = aoa.findIndex((r) => r.filter((x) => String(x).trim()).length >= 3);
    const head = (aoa[hi] || []).map((h, i) => String(h || 'Kolom ' + (i + 1)).trim());
    return aoa.slice(hi + 1).filter((r) => r.some((x) => String(x).trim())).map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
  }
  async function pageLedger(v) {
    const f = { discipline: '', status: '' };
    v.innerHTML = `<h1>Ledger</h1><p class="muted">Semua tagihan, pembayaran, kode unik, dan verifikator. Impor laporan transaksi GoBiz untuk mencocokkan dana masuk secara otomatis berdasarkan nominal.</p>
      <div id="sum"></div>
      <section class="card" style="margin-top:16px"><h2>Impor mutasi GoBiz / bank</h2>
        <p class="small muted">Unduh laporan transaksi dari GoBiz (Excel atau CSV), lalu unggah di sini. Mutasi dicocokkan otomatis bila nominalnya sama persis dengan satu tagihan. Impor ulang file yang sama aman: duplikat dilewati.</p>
        <input type="file" id="mf" accept=".csv,.xlsx,.xls,text/csv"><div id="map"></div></section>
      <div class="bar">${discSelect('ld', '')}<div class="field"><label class="f" for="ls">Status</label><select id="ls"><option value="">Semua</option>${Object.entries(ST).map(([k, l]) => `<option value="${k}">${l}</option>`).join('')}</select></div>
        <button class="btn btn-dark" id="lx">Unduh Excel</button></div>
      <div id="rows"></div><h2 style="margin-top:22px">Mutasi masuk</h2><div id="muts"></div>`;
    let D;
    const load = async () => {
      D = await api('console_ledger', { p_filter: f });
      const tot = D.summary.reduce((a, s) => ({ expected: a.expected + s.expected, paid: a.paid + s.paid, fees: a.fees + s.fees_paid, team: a.team + (s.team_paid || 0), teams: a.teams + (s.teams_paid || 0), pri: a.pri + s.priangan_paid, uc: a.uc + s.unique_paid }), { expected: 0, paid: 0, fees: 0, team: 0, teams: 0, pri: 0, uc: 0 });
      v.querySelector('#sum').innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Disiplin</th><th class="r">Tagihan aktif</th><th class="r">Lunas</th><th class="r">Biaya perorangan (lunas)</th><th class="r">Beregu (lunas)</th><th class="r">Priangan (lunas)</th><th class="r">Kode unik (lunas)</th><th class="r">Pendaftaran lunas / terbuka</th></tr></thead><tbody>
        ${D.summary.map((s) => `<tr><td>${esc(s.name)}</td><td class="r num">${fmtRp(s.expected)}</td><td class="r num"><strong>${fmtRp(s.paid)}</strong></td><td class="r num">${fmtRp(s.fees_paid)}</td><td class="r num">${s.discipline === 'MAG' || s.discipline === 'WAG' ? `${fmtRp(s.team_paid || 0)}<br><span class="tiny muted">${s.teams_paid || 0} tim</span>` : '–'}</td><td class="r num">${fmtRp(s.priangan_paid)}</td><td class="r num">${fmtRp(s.unique_paid)}</td><td class="r num">${s.count_paid} / ${s.count_open}</td></tr>`).join('')}
        <tr><td><strong>Total</strong></td><td class="r num"><strong>${fmtRp(tot.expected)}</strong></td><td class="r num"><strong>${fmtRp(tot.paid)}</strong></td><td class="r num">${fmtRp(tot.fees)}</td><td class="r num">${fmtRp(tot.team)}<br><span class="tiny muted">${tot.teams} tim</span></td><td class="r num">${fmtRp(tot.pri)}</td><td class="r num">${fmtRp(tot.uc)}</td><td></td></tr></tbody></table></div>`;
      v.querySelector('#rows').innerHTML = D.rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Kode</th><th>Disiplin</th><th>Klub / pendaftar</th><th class="r">Biaya</th><th class="r">Priangan</th><th class="r">Unik</th><th class="r">Total</th><th>Status</th><th>Diverifikasi</th><th>Mutasi</th></tr></thead><tbody>
        ${D.rows.map((r) => `<tr class="click" data-id="${r.id}"><td class="code small">${esc(r.code)}<br><span class="tiny muted">${dt(r.created_at)}</span></td><td>${r.discipline}</td><td class="small">${esc(r.club)}${r.team_name ? `<br><span class="pill gold">Beregu</span> ${esc(r.team_name)}` : ''}<br><span class="muted">${esc(r.contact_name)}</span></td>
          <td class="r num">${fmtRp(r.base_amount)}</td><td class="r num">${fmtRp(r.priangan_amount)}</td><td class="r num">${r.unique_code}</td><td class="r num"><strong>${fmtRp(r.total_amount)}</strong></td>
          <td>${pill(r.status)}</td><td class="small">${esc(r.verified_by || '')}<br><span class="muted">${r.verified_at ? dt(r.verified_at) : ''}</span></td>
          <td class="small">${(r.mutations || []).map((m) => `${fmtRp(m.amount)} <span class="muted">${esc(m.match_status)}</span>`).join('<br>')}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada tagihan.</p>';
      v.querySelectorAll('#rows tr[data-id]').forEach((tr) => tr.onclick = () => { location.hash = '#/pendaftaran/' + tr.dataset.id; });
      v.querySelector('#muts').innerHTML = D.mutations.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th class="r">Nominal</th><th>Referensi</th><th>Status</th><th>Pendaftaran</th><th></th></tr></thead><tbody>
        ${D.mutations.map((m) => `<tr><td class="small">${m.trx_time ? dt(m.trx_time) : '–'}<br><span class="tiny muted">impor ${esc(m.batch || '')}</span></td><td class="r num">${fmtRp(m.amount)}</td><td class="small">${esc(m.reference || '')}<br><span class="muted">${esc(m.description || '')}</span></td>
          <td><span class="pill ${m.match_status === 'belum' ? 'warn' : m.match_status === 'abaikan' ? '' : 'ok'}">${esc(m.match_status)}</span></td>
          <td class="small">${m.submission_code ? `<a href="#/pendaftaran/${m.submission_id}">${esc(m.submission_code)}</a> ${ST[m.submission_status] || ''}` : ''}</td>
          <td class="r">${m.match_status === 'belum' ? rowMenu(`<button class="btn btn-ghost btn-sm" data-mm="${m.id}">Cocokkan</button>`, [{ label: 'Abaikan mutasi', attr: `data-mi="${m.id}"` }]) : rowMenu('', [{ label: 'Lepas pencocokan', attr: `data-mr="${m.id}"` }])}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada mutasi diimpor.</p>';
      v.querySelectorAll('[data-mm]').forEach((b) => b.onclick = async () => {
        const m = D.mutations.find((x) => x.id === Number(b.dataset.mm));
        const r = await dialog({ title: 'Cocokkan mutasi ' + fmtRp(m.amount), ok: 'Cocokkan',
          body: `<label class="f" for="mc">Kode pendaftaran</label><input id="mc" placeholder="JO26-WAG-0001" list="opencodes">
            <datalist id="opencodes">${D.rows.filter((r) => r.status !== 'dibatalkan').map((r) => `<option value="${esc(r.code)}">${fmtRp(r.total_amount)} ${esc(r.club)}</option>`).join('')}</datalist>
            <p class="small muted">Mutasi tidak otomatis mengubah status lunas. Setelah dicocokkan, verifikator menandai lunas dari halaman pendaftaran.</p>`,
          onOk: async (d) => { const code = d.querySelector('#mc').value.trim().toUpperCase(); const row = D.rows.find((x) => x.code === code); if (!row) throw new Error('Kode pendaftaran tidak ditemukan.');
            await api('console_match_mutation', { p_mutation: m.id, p_submission: row.id, p_status: 'manual' }); return true; } });
        if (r) load();
      });
      v.querySelectorAll('[data-mi]').forEach((b) => b.onclick = async () => { await api('console_match_mutation', { p_mutation: Number(b.dataset.mi), p_submission: null, p_status: 'abaikan' }); load(); });
      v.querySelectorAll('[data-mr]').forEach((b) => b.onclick = async () => { await api('console_match_mutation', { p_mutation: Number(b.dataset.mr), p_submission: null, p_status: 'belum' }); load(); });
    };
    const ld = v.querySelector('#ld'); if (ld) ld.onchange = () => { f.discipline = ld.value; load(); };
    v.querySelector('#ls').onchange = (e) => { f.status = e.target.value; load(); };
    v.querySelector('#lx').onclick = () => exportXlsx(`ledger-jabar-open-2026-${new Date().toISOString().slice(0, 10)}.xlsx`, D.rows, [
      ['code', 'Kode'], ['created_at', 'Tanggal daftar', (r) => dt(r.created_at)], ['discipline', 'Disiplin'], ['registrant_type', 'Jenis'], ['team_name', 'Tim beregu'], ['club', 'Klub'], ['contact_name', 'Penanggung jawab'], ['contact_phone', 'WA'], ['contact_email', 'Email'],
      ['n_athletes', 'Jumlah atlet'], ['n_entries', 'Jumlah entri'], ['base_amount', 'Biaya lomba'], ['priangan_amount', 'Priangan'], ['unique_code', 'Kode unik'], ['total_amount', 'Total tagihan'],
      ['status', 'Status', (r) => ST[r.status]], ['payment_method', 'Metode'], ['paid_amount', 'Diterima'], ['paid_at', 'Tanggal lunas', (r) => (r.paid_at ? dt(r.paid_at) : '')],
      ['verified_by', 'Diverifikasi oleh'], ['verify_note', 'Catatan'], ['mutations', 'Mutasi', (r) => (r.mutations || []).map((m) => `${m.amount} ${m.reference || ''} ${m.match_status}`).join('; ')]]);
    v.querySelector('#mf').onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      const map = v.querySelector('#map');
      let rows;
      try { rows = await readTable(file); } catch (err) { map.innerHTML = `<p class="note bad">File tidak terbaca: ${esc(err.message)}</p>`; return; }
      if (!rows.length) { map.innerHTML = '<p class="note bad">Tidak ada baris data.</p>'; return; }
      const cols = Object.keys(rows[0]);
      const guess = (re) => cols.find((c) => re.test(c.toLowerCase())) || '';
      const g = { time: guess(/waktu|tanggal|date|time/), amount: guess(/nominal|amount|jumlah|gross|total|nilai/), ref: guess(/ref|id transaksi|transaction id|order|no\.? transaksi|id/), desc: guess(/keterangan|desc|status|metode|payment/) };
      const sel = (k, label) => `<div class="field"><label class="f">${label}</label><select data-m="${k}"><option value="">–</option>${cols.map((c) => `<option ${g[k] === c ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select></div>`;
      map.innerHTML = `<p class="small" style="margin-top:12px">${rows.length} baris terbaca dari <strong>${esc(file.name)}</strong>. Periksa kolom berikut:</p>
        <div class="grid-2">${sel('time', 'Waktu transaksi')}${sel('amount', 'Nominal')}${sel('ref', 'ID / referensi transaksi')}${sel('desc', 'Keterangan (opsional)')}</div>
        <div id="pv"></div><button class="btn btn-primary" id="imp">Impor dan cocokkan</button>`;
      const build = () => {
        const m = Object.fromEntries([...map.querySelectorAll('[data-m]')].map((s) => [s.dataset.m, s.value]));
        return rows.map((r) => ({ trx_time: m.time ? parseWhen(r[m.time]) : null, amount: m.amount ? parseAmount(r[m.amount]) : null,
          reference: m.ref ? String(r[m.ref] == null ? '' : r[m.ref]) : null, description: m.desc ? String(r[m.desc] == null ? '' : r[m.desc]) : null, raw: r })).filter((x) => x.amount && x.amount > 0);
      };
      const pv = () => { const b = build(); map.querySelector('#pv').innerHTML = `<p class="small muted">${b.length} baris bernominal positif akan diimpor. Contoh: ${b.slice(0, 3).map((x) => `${fmtRp(x.amount)} ${x.trx_time ? dt(x.trx_time) : ''}`).join('; ')}</p>`; };
      map.querySelectorAll('[data-m]').forEach((s) => s.onchange = pv); pv();
      map.querySelector('#imp').onclick = async (ev) => {
        ev.currentTarget.disabled = true;
        try { const r = await api('console_import_mutations', { p_rows: build(), p_batch: file.name }); map.innerHTML = `<p class="note ok">${r.inserted} mutasi baru, ${r.duplicates} duplikat dilewati, ${r.matched} cocok otomatis, ${r.unmatched} perlu dicek manual.</p>`; e.target.value = ''; load(); }
        catch (err) { JO.toast(err.message, 'bad'); ev.currentTarget.disabled = false; }
      };
    };
    await load();
  }

  // =====================================================================
  //  KLUB
  // =====================================================================
  async function pageClubs(v) {
    const R = window.JO_REGIONS;
    const rows = await api('console_clubs');
    v.innerHTML = `<h1>Klub</h1><p class="muted">Klub baru dari formulir pendaftaran ditandai "belum diverifikasi". Rapikan nama dan wilayahnya. Bila satu klub terdaftar dengan dua nama (mis. salah ketik), pakai <em>Gabungkan</em> dari menu "…" agar tabel medali per klub akurat. Klub yang belum dipakai pendaftaran bisa dihapus.</p>
      <div class="bar"><div class="field" style="flex:1"><label class="f" for="kq">Cari</label><input id="kq" type="search"></div><button class="btn btn-dark" id="kadd">Tambah klub</button></div><div id="kl"></div>`;
    const draw = (q) => {
      const s = (q || '').toLowerCase();
      const list = rows.filter((k) => !s || (k.name + ' ' + (k.kab_kota || '') + ' ' + (k.province || '')).toLowerCase().includes(s));
      v.querySelector('#kl').innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Jenis</th><th>Kab/kota</th><th>Provinsi</th><th class="r">Atlet</th><th></th></tr></thead><tbody>
        ${list.map((k) => `<tr><td>${esc(k.name)}${k.verified ? '' : ' <span class="pill warn">belum diverifikasi</span>'}${k.merged_into ? ` <span class="pill">digabung ke ${esc(k.merged_into_name)}</span>` : ''}</td><td class="small">${esc(k.kind)}</td>
          <td class="small">${esc(k.kab_kota || '')}</td><td class="small">${esc(k.province || k.country)}</td><td class="r">${k.athletes}</td>
          <td class="r">${k.merged_into ? '' : rowMenu(`<button class="btn btn-ghost btn-sm" data-ke="${k.id}">Ubah</button>`,
            [{ label: 'Gabungkan ke klub lain', attr: `data-km="${k.id}"` }, k.athletes ? null : { sep: true }, k.athletes ? null : { label: 'Hapus klub', attr: `data-kx="${k.id}"`, danger: true }])}</td></tr>`).join('')}</tbody></table></div>`;
      v.querySelectorAll('[data-ke]').forEach((b) => b.onclick = () => edit(rows.find((k) => k.id === b.dataset.ke)));
      v.querySelectorAll('[data-km]').forEach((b) => b.onclick = () => merge(rows.find((k) => k.id === b.dataset.km)));
      v.querySelectorAll('[data-kx]').forEach((b) => b.onclick = () => del(rows.find((k) => k.id === b.dataset.kx)));
    };
    const del = async (k) => {
      const r = await dialog({ title: 'Hapus ' + k.name + '?', ok: 'Hapus klub', okClass: 'btn-bad',
        body: `<p>Klub <strong>${esc(k.name)}</strong> dihapus dari daftar pilihan formulir. Hanya bisa untuk klub yang belum dipakai pendaftaran mana pun; bila sudah dipakai, gunakan <em>Gabungkan</em>. Penghapusan tercatat di Log.</p>`,
        onOk: async () => { await api('console_delete_club', { p_id: k.id }); return true; } });
      if (r) { JO.toast('Klub dihapus.'); pageClubs(v); }
    };
    const edit = async (k) => {
      const r = await dialog({ title: k ? 'Ubah klub' : 'Tambah klub',
        body: `<div class="field"><label class="f">Nama</label><input id="kn" value="${esc(k ? k.name : '')}"></div>
          <div class="grid-2"><div class="field"><label class="f">Jenis</label><select id="kk">${['klub', 'sekolah', 'pengkab', 'lainnya'].map((x) => `<option ${k && k.kind === x ? 'selected' : ''}>${x}</option>`).join('')}</select></div>
          <div class="field"><label class="f">Negara</label><input id="kc" value="${esc(k ? k.country : 'Indonesia')}"></div>
          <div class="field"><label class="f">Provinsi</label><select id="kp"><option value=""></option>${R.provinces.map((p) => `<option ${k && k.province === p ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
          <div class="field"><label class="f">Kab/kota</label><input id="kb" list="kabs2" value="${esc(k ? k.kab_kota || '' : '')}"><datalist id="kabs2">${R.jabar.map((x) => `<option>${esc(x)}</option>`).join('')}</datalist></div></div>
          <label class="check"><input type="checkbox" id="kv" ${!k || k.verified ? 'checked' : ''}>Sudah diverifikasi</label>`,
        onOk: async (d) => { await api('console_save_club', { p: { id: k ? k.id : null, name: d.querySelector('#kn').value, kind: d.querySelector('#kk').value, country: d.querySelector('#kc').value, province: d.querySelector('#kp').value, kab_kota: d.querySelector('#kb').value, verified: d.querySelector('#kv').checked } }); return true; } });
      if (r) pageClubs(v);
    };
    const merge = async (k) => {
      const r = await dialog({ title: 'Gabungkan ' + k.name, ok: 'Gabungkan', okClass: 'btn-bad',
        body: `<p class="small">Semua pendaftaran dari <strong>${esc(k.name)}</strong> dipindahkan ke klub tujuan. Nama ini tidak lagi muncul di formulir.</p>
          <label class="f" for="mi">Gabungkan ke</label><select id="mi">${rows.filter((x) => x.id !== k.id && !x.merged_into).map((x) => `<option value="${x.id}">${esc(x.name)} (${esc(x.kab_kota || x.country)})</option>`).join('')}</select>`,
        onOk: async (d) => { await api('console_merge_club', { p_from: k.id, p_into: d.querySelector('#mi').value }); return true; } });
      if (r) pageClubs(v);
    };
    v.querySelector('#kq').oninput = (e) => draw(e.target.value);
    v.querySelector('#kadd').onclick = () => edit(null);
    draw('');
  }

  // =====================================================================
  //  FAQ SITUS — owner, superadmin, admin. Tidak ada hapus permanen: arsipkan.
  // =====================================================================
  const FAQ_ST = { terbit: ['Terbit', 'ok'], draf: ['Draf', 'warn'], arsip: ['Arsip', ''] };
  async function pageFaq(v) {
    let D = await api('console_faq');
    const F = { q: '', st: 'aktif', cat: '' };
    const siteFaq = (JO.config.siteUrl || '../').replace(/\/?$/, '/') + 'faq.html';
    const catName = (k) => (D.categories.find((c) => c.key === k) || {}).name_id || k;
    const shell = () => {
      const n = (st) => D.items.filter((i) => i.status === st).length;
      const noEn = D.items.filter((i) => i.status !== 'arsip' && !i.q_en).length;
      v.innerHTML = `<h1>FAQ situs</h1>
        <p class="muted">Pertanyaan berstatus <em>Terbit</em> tampil di beranda dan halaman <a href="${esc(siteFaq)}" target="_blank" rel="noopener">FAQ</a>; <em>Draf</em> hanya terlihat di sini. Butir yang tidak dipakai lagi diarsipkan (bisa dipulihkan), tidak dihapus. Bagian FAQ di situs baru muncul setelah ada minimal satu pertanyaan terbit. Pengunjung yang sudah membuka situs melihat menu FAQ setelah membuka tab baru.</p>
        <div class="kpis">
          <div class="kpi ok"><div><small>Terbit</small><b>${n('terbit')}</b></div><i>${icon('check')}</i></div>
          <div class="kpi warn"><div><small>Draf</small><b>${n('draf')}</b></div><i>${icon('pen')}</i></div>
          <div class="kpi"><div><small>Arsip</small><b>${n('arsip')}</b></div><i>${icon('log')}</i></div>
          <div class="kpi ${noEn ? 'bad' : ''}"><div><small>Belum ada versi Inggris</small><b>${noEn}</b></div><i>${icon('alert')}</i></div>
        </div>
        <div class="bar" style="margin-top:16px">
          <div class="field" style="flex:1;min-width:180px"><label class="f" for="fq">Cari</label><input id="fq" type="search" value="${esc(F.q)}"></div>
          <div class="field"><label class="f" for="fs">Status</label><select id="fs">
            ${[['aktif', 'Terbit + draf'], ['terbit', 'Terbit'], ['draf', 'Draf'], ['arsip', 'Arsip'], ['semua', 'Semua']].map(([k, l]) => `<option value="${k}" ${F.st === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
          <div class="field"><label class="f" for="fc">Kategori</label><select id="fc"><option value="">Semua kategori</option>
            ${D.categories.map((c) => `<option value="${esc(c.key)}" ${F.cat === c.key ? 'selected' : ''}>${esc(c.name_id)}${c.active ? '' : ' (nonaktif)'}</option>`).join('')}</select></div>
          <button class="btn btn-ghost" id="fcat" type="button">Kelola kategori</button>
          <button class="btn btn-dark" id="fadd" type="button">Tambah pertanyaan</button>
        </div>
        <div id="fl"></div>`;
      v.querySelector('#fq').oninput = (e) => { F.q = e.target.value; list(); };
      v.querySelector('#fs').onchange = (e) => { F.st = e.target.value; list(); };
      v.querySelector('#fc').onchange = (e) => { F.cat = e.target.value; list(); };
      v.querySelector('#fadd').onclick = () => edit(null);
      v.querySelector('#fcat').onclick = () => cats();
      list();
    };
    const list = () => {
      const s = F.q.trim().toLowerCase();
      const rows = D.items.filter((i) => (F.st === 'semua' || (F.st === 'aktif' ? i.status !== 'arsip' : i.status === F.st))
        && (!F.cat || i.category === F.cat)
        && (!s || [i.q_id, i.a_id, i.q_en, i.a_en, i.slug].join(' ').toLowerCase().includes(s)));
      const groups = D.categories.filter((c) => rows.some((i) => i.category === c.key));
      v.querySelector('#fl').innerHTML = rows.length ? groups.map((c) => {
        const its = rows.filter((i) => i.category === c.key);
        return `<section class="card" style="margin-top:16px"><h2 style="font-size:1.05rem">${esc(c.name_id)}${c.active ? '' : ' <span class="pill">nonaktif, tidak tampil di situs</span>'}</h2>
          <div class="tbl-wrap"><table class="tbl"><tbody>${its.map((i, n) => `<tr>
            <td style="width:64px;white-space:nowrap">${s ? '' : `<button class="btn btn-ghost btn-sm" data-up="${i.id}" ${n === 0 ? 'disabled' : ''} aria-label="Naikkan">&uarr;</button><button class="btn btn-ghost btn-sm" data-dn="${i.id}" ${n === its.length - 1 ? 'disabled' : ''} aria-label="Turunkan">&darr;</button>`}</td>
            <td><strong>${esc(i.q_id)}</strong>${i.q_en ? '' : ' <span class="pill bad">EN belum ada</span>'}
              <br><span class="tiny muted">faq.html#${esc(i.slug)} · diubah ${esc(i.updated_by || '-')}, ${dt(i.updated_at)}</span></td>
            <td style="width:84px"><span class="pill ${FAQ_ST[i.status][1]}">${FAQ_ST[i.status][0]}</span></td>
            <td class="r" style="width:110px">${rowMenu(`<button class="btn btn-ghost btn-sm" data-fe="${i.id}">Ubah</button>`, [
              i.status !== 'terbit' && i.status !== 'arsip' ? { label: 'Terbitkan', attr: `data-fs="${i.id}" data-to="terbit"` } : null,
              i.status === 'terbit' ? { label: 'Jadikan draf (sembunyikan)', attr: `data-fs="${i.id}" data-to="draf"` } : null,
              i.status === 'arsip' ? { label: 'Pulihkan sebagai draf', attr: `data-fs="${i.id}" data-to="draf"` } : null,
              { label: 'Salin tautan', attr: `data-fl="${i.id}"` },
              i.status !== 'arsip' ? { sep: true } : null,
              i.status !== 'arsip' ? { label: 'Arsipkan', attr: `data-fs="${i.id}" data-to="arsip"`, danger: true } : null,
            ])}</td></tr>`).join('')}</tbody></table></div></section>`;
      }).join('') : '<p class="empty">Tidak ada pertanyaan yang cocok.</p>';
      const by = (id) => D.items.find((i) => i.id === id);
      v.querySelectorAll('[data-fe]').forEach((b) => b.onclick = () => edit(by(b.dataset.fe)));
      v.querySelectorAll('[data-up],[data-dn]').forEach((b) => b.onclick = async () => {
        b.disabled = true;
        try { D = await api('console_faq_move', { p_id: b.dataset.up || b.dataset.dn, p_dir: b.dataset.up ? -1 : 1 }); list(); } catch (e) { JO.toast(e.message, 'bad'); b.disabled = false; }
      });
      v.querySelectorAll('[data-fs]').forEach((b) => b.onclick = async () => {
        const it = by(b.dataset.fs); const to = b.dataset.to;
        if (to === 'arsip') {
          const ok = await dialog({ title: 'Arsipkan pertanyaan?', ok: 'Arsipkan', okClass: 'btn-bad',
            body: `<p><strong>${esc(it.q_id)}</strong></p><p class="small">Pertanyaan hilang dari situs dan pindah ke status Arsip. Bisa dipulihkan kapan saja dari filter Status: Arsip.</p>`, onOk: () => true });
          if (!ok) return;
        }
        try { D = await api('console_faq_set_status', { p_id: it.id, p_status: to }); JO.toast(to === 'terbit' ? 'Diterbitkan.' : to === 'arsip' ? 'Diarsipkan.' : 'Disimpan sebagai draf.'); shell(); }
        catch (e) { JO.toast(e.message, 'bad'); }
      });
      v.querySelectorAll('[data-fl]').forEach((b) => b.onclick = async () => {
        const url = siteFaq + '#' + by(b.dataset.fl).slug;
        try { await navigator.clipboard.writeText(url); JO.toast('Tautan disalin: ' + url); } catch (e) { JO.toast(url); }
      });
    };
    const edit = async (it) => {
      const cat0 = it ? it.category : (F.cat || (D.categories.find((c) => c.active) || {}).key);
      const pr = dialog({ title: it ? 'Ubah pertanyaan' : 'Tambah pertanyaan', wide: true, ok: 'Simpan',
        body: `<div class="grid-2">
            <div class="field"><label class="f" for="ec">Kategori</label><select id="ec">${D.categories.map((c) => `<option value="${esc(c.key)}" ${cat0 === c.key ? 'selected' : ''}>${esc(c.name_id)}${c.active ? '' : ' (nonaktif)'}</option>`).join('')}</select></div>
            <div class="field"><label class="f" for="es">Status</label><select id="es">${['draf', 'terbit', 'arsip'].map((k) => `<option value="${k}" ${(it ? it.status : 'draf') === k ? 'selected' : ''}>${FAQ_ST[k][0]}</option>`).join('')}</select></div></div>
          <p class="note info small" style="margin:4px 0 14px">Format jawaban: baris kosong untuk paragraf baru; awali baris dengan "- " untuk daftar; <code>**tebal**</code>; tautan <code>[teks](daftar.html)</code> atau <code>[teks](https://…)</code>.</p>
          <div class="grid-2">
            <div><h3 style="font-size:.95rem;margin:0 0 8px">Bahasa Indonesia (wajib)</h3>
              <div class="field"><label class="f" for="eqi">Pertanyaan</label><input id="eqi" maxlength="300" value="${esc(it ? it.q_id : '')}"></div>
              <div class="field"><label class="f" for="eai">Jawaban</label><textarea id="eai" rows="9" maxlength="4000">${esc(it ? it.a_id : '')}</textarea></div></div>
            <div><h3 style="font-size:.95rem;margin:0 0 8px">English (boleh menyusul)</h3>
              <div class="field"><label class="f" for="eqe">Question</label><input id="eqe" maxlength="300" value="${esc(it ? it.q_en || '' : '')}"></div>
              <div class="field"><label class="f" for="eae">Answer</label><textarea id="eae" rows="9" maxlength="4000">${esc(it ? it.a_en || '' : '')}</textarea></div></div></div>
          <p class="small muted" style="margin:-4px 0 12px">Bila versi Inggris kosong, pengunjung berbahasa Inggris melihat teks Indonesia.</p>
          <div class="field"><label class="f" for="esl">Tautan pertanyaan</label>
            <div class="row" style="gap:6px;align-items:center;flex-wrap:nowrap"><span class="small muted" style="white-space:nowrap">faq.html#</span><input id="esl" value="${esc(it ? it.slug : '')}" placeholder="dibuat otomatis dari pertanyaan" pattern="[a-z0-9-]{2,60}"></div>
            <p class="small muted" style="margin:4px 0 0">Huruf kecil, angka, tanda hubung. Mengubahnya membuat tautan lama yang sudah dibagikan tidak lagi membuka pertanyaan ini.</p></div>
          <h3 style="font-size:.95rem;margin:14px 0 6px">Pratinjau</h3>
          <div class="faq-preview" id="epv"></div>`,
        onOk: async (d) => {
          const val = (id) => d.querySelector(id).value;
          D = await api('console_faq_save', { p: { id: it ? it.id : null, category: val('#ec'), status: val('#es'),
            q_id: val('#eqi'), a_id: val('#eai'), q_en: val('#eqe'), a_en: val('#eae'), slug: val('#esl').trim() } });
          return true;
        } });
      // pratinjau langsung
      const d = document.querySelector('dialog[open]');
      const onIn = () => paint(d);
      if (d) { paint(d); d.addEventListener('input', onIn); }
      const r = await pr;
      if (d) d.removeEventListener('input', onIn);
      if (r) { JO.toast('Pertanyaan disimpan.'); shell(); }
    };
    function paint(d) {
      const pv = d.querySelector('#epv'); if (!pv) return;
      const qi = d.querySelector('#eqi').value, ai = d.querySelector('#eai').value, qe = d.querySelector('#eqe').value, ae = d.querySelector('#eae').value;
      const one = (q, a, tag) => `<details class="faq-item" open><summary><span class="faq-q"><span class="pill" style="margin-right:6px">${tag}</span>${esc(q || '…')}</span></summary><div class="faq-a">${window.JOFaq.render(a || '…')}</div></details>`;
      pv.innerHTML = one(qi, ai, 'ID') + (qe || ae ? one(qe, ae, 'EN') : '');
    }
    const cats = async () => {
      const pr = dialog({ title: 'Kategori FAQ', wide: true, ok: 'Selesai', cancel: '',
        body: `<p class="small muted">Urutan di sini menjadi urutan tab di situs. Kategori nonaktif beserta pertanyaannya tidak tampil di situs. Kategori tanpa pertanyaan terbit otomatis tidak tampil.</p>
          <div id="cl"></div>
          <h3 style="font-size:.95rem;margin:16px 0 6px">Tambah kategori</h3>
          <div class="grid-2"><div class="field"><label class="f" for="cni">Nama (Indonesia)</label><input id="cni"></div>
          <div class="field"><label class="f" for="cne">Nama (English)</label><input id="cne"></div></div>
          <button type="button" class="btn btn-ghost btn-sm" id="cadd">Tambah</button>`,
        onOk: () => true });
      const d = document.querySelector('dialog[open]');
      const onClick = (e) => catClicks(e, d);
      if (d) { drawCats(d); d.addEventListener('click', onClick); }
      await pr;
      if (d) d.removeEventListener('click', onClick);
      shell();
    };
    function drawCats(d) {
      const box = d.querySelector('#cl'); if (!box) return;
      box.innerHTML = `<div class="tbl-wrap"><table class="tbl"><tbody>${D.categories.map((c, n) => `<tr>
        <td style="width:64px;white-space:nowrap"><button type="button" class="btn btn-ghost btn-sm" data-cu="${esc(c.key)}" ${n === 0 ? 'disabled' : ''} aria-label="Naikkan">&uarr;</button><button type="button" class="btn btn-ghost btn-sm" data-cd="${esc(c.key)}" ${n === D.categories.length - 1 ? 'disabled' : ''} aria-label="Turunkan">&darr;</button></td>
        <td><input data-cid="${esc(c.key)}" value="${esc(c.name_id)}" aria-label="Nama Indonesia"></td>
        <td><input data-cen="${esc(c.key)}" value="${esc(c.name_en || '')}" aria-label="Nama Inggris" placeholder="English"></td>
        <td><label class="check" style="margin:0"><input type="checkbox" data-cac="${esc(c.key)}" ${c.active ? 'checked' : ''}>Aktif</label></td>
        <td class="r"><button type="button" class="btn btn-ghost btn-sm" data-cs="${esc(c.key)}">Simpan</button></td></tr>`).join('')}</tbody></table></div>`;
    }
    async function catClicks(e, d) {
      const b = e.target.closest('button'); if (!b) return;
      try {
        if (b.dataset.cu || b.dataset.cd) { D = await api('console_faq_category_move', { p_key: b.dataset.cu || b.dataset.cd, p_dir: b.dataset.cu ? -1 : 1 }); drawCats(d); }
        else if (b.dataset.cs) {
          const k = b.dataset.cs;
          D = await api('console_faq_category_save', { p: { key: k, name_id: d.querySelector(`[data-cid="${k}"]`).value, name_en: d.querySelector(`[data-cen="${k}"]`).value, active: d.querySelector(`[data-cac="${k}"]`).checked } });
          drawCats(d); JO.toast('Kategori disimpan.');
        } else if (b.id === 'cadd') {
          D = await api('console_faq_category_save', { p: { name_id: d.querySelector('#cni').value, name_en: d.querySelector('#cne').value } });
          d.querySelector('#cni').value = ''; d.querySelector('#cne').value = ''; drawCats(d); JO.toast('Kategori ditambahkan.');
        }
      } catch (err) { JO.toast(err.message, 'bad'); }
    }
    shell();
  }

  // =====================================================================
  //  KOMUNIKASI: lencana, nomor WA sendiri, chat, laporan masalah, kontak
  // =====================================================================
  const roleLabel = (r, d) => (ROLE[r] || r) + (d ? ' ' + DN[d] : '');
  const multiline = (s) => esc(s || '').replace(/\n/g, '<br>');
  const ago = (d) => {
    const s = (Date.now() - new Date(d).getTime()) / 1000;
    if (s < 60) return 'baru saja';
    if (s < 3600) return Math.floor(s / 60) + ' mnt lalu';
    if (s < 86400 && new Date(d).toDateString() === new Date().toDateString()) return new Date(d).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' });
    return dt(d);
  };
  const waText = (p, text) => { const u = wa(p); return u === '#' ? '#' : u + (text ? '?text=' + encodeURIComponent(text) : ''); };

  const BASE_TITLE = document.title;
  async function pollActions() {
    if (!ME || !isAdmin()) return;
    let a;
    try { a = await api('console_actions'); } catch (e) { return; }
    const n = (k) => Number(a[k]) || 0;
    const reg = n('to_verify') + n('docs_pending') + n('priangan_pending');
    const total = reg + n('music_pending');
    const dot = (k, on, t) => { const el = root.querySelector(`[data-k="${k}"]`); if (!el) return; el.classList.toggle('has-action', !!on); if (t) el.title = on ? t : ''; };
    dot('ringkasan', total, total + ' hal perlu tindakan');
    dot('pendaftaran', reg, `${n('to_verify')} pembayaran, ${n('docs_pending')} dokumen atlet${n('priangan_pending') ? ', ' + n('priangan_pending') + ' Priangan' : ''}`);
    dot('musik', n('music_pending'), n('music_pending') + ' musik perlu diperiksa');
    const mt = root.querySelector('#menu-tg'); if (mt) mt.classList.toggle('has-action', !!total);
    document.title = total ? `(${total}) ${BASE_TITLE}` : BASE_TITLE;
  }
  async function pollUnread() {
    if (!ME || isViewer()) return;
    pollActions();
    let u;
    try { u = await api('console_unread'); } catch (e) { return; }
    const set = (k, n) => { const b = root.querySelector(`[data-badge="${k}"]`); if (b) { b.hidden = !n; b.textContent = n > 99 ? '99+' : String(n || ''); } };
    set('chat', Number(u.chat)); set('laporan', Number(u.issues)); set('juri', Number(u.jury));
    const me = root.querySelector('.topline .me');
    let nag = root.querySelector('#phone-nag');
    if (u.phone_missing && me && !nag) {
      me.insertAdjacentHTML('afterbegin', `<button type="button" class="btn btn-ghost btn-sm nag" id="phone-nag">${icon('phone')}<span>Lengkapi nomor WA</span></button>`);
      root.querySelector('#phone-nag').onclick = () => editMyPhone();
    } else if (!u.phone_missing && nag) nag.remove();
  }
  async function editMyPhone() {
    const r = await dialog({ title: 'Nomor WhatsApp saya', ok: 'Simpan',
      body: `<p class="small">Nomor ini tampil di halaman Kontak agar sesama panitia dan juri bisa menghubungi Anda lewat WhatsApp. Tidak tampil di situs publik.</p>
        <div class="field"><label class="f" for="myph">Nomor WhatsApp</label><input id="myph" inputmode="tel" value="${esc(ME.phone || '')}" placeholder="08xx-xxxx-xxxx"></div>`,
      onOk: async (d) => api('console_me_update', { p: { phone: d.querySelector('#myph').value } }) });
    if (r) { ME = Object.assign(ME, { phone: r.phone }); JO.toast('Nomor WhatsApp disimpan.'); pollUnread(); }
    return r;
  }

  // ---------------- chat ----------------
  async function pageChat(v, rest) {
    let room = rest && rest[0] ? decodeURIComponent(rest[0]) : '';
    let R = await api('console_chat_rooms');
    let lastId = 0, busy = false;
    v.innerHTML = `<h1>Chat panitia</h1><p class="muted">Ruang bersama, ruang per disiplin, dan pesan pribadi antarpemegang kode. Untuk masalah teknis yang perlu ditindaklanjuti admin, pakai <a href="#/laporan">Laporan masalah</a> agar statusnya terpantau.</p>
      <div class="chat ${room ? 'has-room' : ''}" id="chat"><aside class="chat-rooms" id="rooms"></aside><section class="chat-thread" id="thread"></section></div>`;
    const drawRooms = () => {
      const groups = R.rooms.filter((r) => r.kind === 'group'), dms = R.rooms.filter((r) => r.kind === 'dm');
      const item = (r) => `<a href="#/chat/${encodeURIComponent(r.room)}" class="${r.room === room ? 'on' : ''}"><b>${esc(r.label)}</b>${Number(r.unread) ? `<em class="badge">${r.unread}</em>` : ''}
        <small>${r.last ? esc((r.last.sender_name || '') + ': ' + r.last.body) : 'Belum ada pesan'}</small></a>`;
      v.querySelector('#rooms').innerHTML = `<div class="grp">Ruang</div>${groups.map(item).join('')}
        <div class="grp">Pesan pribadi</div>${dms.map(item).join('') || '<p class="tiny muted" style="padding:0 10px">Belum ada.</p>'}
        <div class="field" style="padding:8px 10px 0"><label class="f" for="dmto">Mulai pesan pribadi</label><select id="dmto"><option value="">Pilih orang…</option>
          ${R.people.map((p) => `<option value="${esc(p.room)}">${esc(p.name)} (${esc(roleLabel(p.role, p.discipline))})</option>`).join('')}</select></div>`;
      v.querySelector('#dmto').onchange = (e) => { if (e.target.value) location.hash = '#/chat/' + encodeURIComponent(e.target.value); };
    };
    drawRooms();
    const th = v.querySelector('#thread');
    if (!room) { th.innerHTML = '<p class="empty">Pilih ruang di sebelah kiri.</p>'; setPageTimer(async () => { try { R = await api('console_chat_rooms'); drawRooms(); } catch (e) {} }, 10000); return; }
    const known = R.rooms.find((r) => r.room === room) || R.people.find((p) => p.room === room);
    th.innerHTML = `<header class="chat-head"><a href="#/chat" class="btn btn-ghost btn-sm chat-back">Kembali</a><b id="rlabel">${esc(known ? (known.label || known.name) : 'Percakapan')}</b></header>
      <div class="chat-msgs" id="msgs"><div class="empty"><span class="spinner"></span></div></div>
      <form class="chat-form" id="cf"><textarea id="cm" rows="2" maxlength="4000" placeholder="Tulis pesan. Enter untuk kirim, Shift+Enter untuk baris baru." required></textarea><button class="btn btn-primary" type="submit">Kirim</button></form>`;
    const box = th.querySelector('#msgs');
    const bubble = (m) => `<div class="msg ${m.sender === R.me ? 'mine' : ''}" data-id="${m.id}"><div class="meta"><b>${esc(m.sender_name || 'Kode terhapus')}</b>${m.role ? ` <span>${esc(ROLE[m.role] || m.role)}</span>` : ''} · <time title="${esc(dt(m.at))}">${esc(ago(m.at))}</time>${isSuper() ? ` <button type="button" class="msg-del" data-mdel="${m.id}" title="Hapus pesan">Hapus</button>` : ''}</div><div class="body">${multiline(m.body)}</div></div>`;
    box.addEventListener('click', async (ev) => {
      const b = ev.target.closest('[data-mdel]'); if (!b) return;
      if (!(await dialog({ title: 'Hapus pesan ini?', ok: 'Hapus', okClass: 'btn-bad', body: '<p>Pesan dihapus untuk semua orang. Isinya tetap tercatat di Log (hanya owner dan superadmin).</p>' }))) return;
      try { await api('console_delete_chat_message', { p_id: Number(b.dataset.mdel) }); b.closest('.msg').remove(); JO.toast('Pesan dihapus.'); }
      catch (e) { JO.toast(e.message, 'bad'); }
    });
    const load = async (first) => {
      if (busy) return; busy = true;
      try {
        const r = await api('console_chat_messages', { p_room: room, p_after: lastId });
        if (first) { box.innerHTML = r.messages.length ? '' : '<p class="empty chat-none">Belum ada pesan. Mulai percakapan.</p>'; th.querySelector('#rlabel').textContent = r.label; }
        if (r.messages.length) {
          const none = box.querySelector('.chat-none'); if (none) none.remove();
          const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
          box.insertAdjacentHTML('beforeend', r.messages.filter((m) => !box.querySelector(`[data-id="${m.id}"]`)).map(bubble).join(''));
          lastId = r.messages[r.messages.length - 1].id;
          if (first || atBottom) box.scrollTop = box.scrollHeight;
        }
      } catch (e) { if (first) box.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; }
      finally { busy = false; }
    };
    await load(true);
    let tick = 0;
    setPageTimer(async () => {
      if (document.hidden) return;
      await load(false);
      if (++tick % 3 === 0) { try { R = await api('console_chat_rooms'); drawRooms(); } catch (e) {} }
    }, 4000);
    const f = th.querySelector('#cf'), ta = th.querySelector('#cm');
    ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); f.requestSubmit(); } });
    f.onsubmit = async (e) => {
      e.preventDefault();
      const body = ta.value.trim(); if (!body) return;
      const btn = f.querySelector('button'); btn.disabled = true;
      try { await api('console_chat_send', { p_room: room, p_body: body }); ta.value = ''; await load(false); box.scrollTop = box.scrollHeight; pollUnread(); }
      catch (err) { JO.toast(err.message, 'bad'); }
      finally { btn.disabled = false; ta.focus(); }
    };
    ta.focus();
    pollUnread();
  }

  // ---------------- laporan masalah ----------------
  const ISS = { baru: ['Baru', 'warn'], diproses: ['Diproses', 'info'], selesai: ['Selesai', 'ok'] };
  const issPill = (s) => `<span class="pill ${ISS[s][1]}">${ISS[s][0]}</span>`;
  const issFilter = { f: 'terbuka' };
  async function pageIssues(v, rest) {
    if (rest && rest[0]) return pageIssue(v, Number(rest[0]));
    const filt = issFilter.f === 'mine' ? { mine: true } : issFilter.f === 'semua' ? {} : { status: 'terbuka' };
    const rows = await api('console_issues', { p_filter: filt });
    v.innerHTML = `<div class="row" style="justify-content:space-between;align-items:flex-end"><div><h1>Laporan masalah</h1>
        <p class="muted">Laporkan kendala (mis. tidak bisa input nilai, data atlet salah, dokumen perlu dicek). Admin menindaklanjuti dan mengubah statusnya; Anda mendapat lencana saat ada tanggapan.</p></div>
        <button class="btn btn-primary" id="inew">Laporkan masalah</button></div>
      <div class="tabs" style="margin-top:12px">${[['terbuka', 'Belum selesai'], ['mine', 'Laporan saya'], ['semua', 'Semua']].map(([k, l]) => `<button data-f="${k}" aria-selected="${issFilter.f === k}">${l}</button>`).join('')}</div>
      ${rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Masalah</th><th>Pelapor</th><th>Disiplin</th><th>Status</th><th>Diperbarui</th></tr></thead><tbody>
        ${rows.map((i) => `<tr class="click" data-id="${i.id}"><td>${i.unread ? '<span class="dot" title="Ada pembaruan"></span>' : ''}<strong>${esc(i.title)}</strong>${i.comments ? ` <span class="tiny muted">${i.comments} tanggapan</span>` : ''}${i.shot_path ? ' <span class="tiny muted">· tangkapan layar</span>' : ''}</td>
          <td class="small">${esc(i.reporter_name || '-')}<br><span class="tiny muted">${esc(ROLE[i.reporter_role] || '')}</span></td><td class="small">${i.discipline ? DN[i.discipline] : 'Umum'}</td>
          <td>${issPill(i.status)}</td><td class="small">${esc(ago(i.updated_at))}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Tidak ada laporan di sini.</p>'}`;
    v.querySelectorAll('[data-f]').forEach((b) => b.onclick = () => { issFilter.f = b.dataset.f; pageIssues(v); });
    v.querySelectorAll('tr[data-id]').forEach((tr) => tr.onclick = () => { location.hash = '#/laporan/' + tr.dataset.id; });
    v.querySelector('#inew').onclick = async () => {
      const r = await dialog({ title: 'Laporkan masalah', ok: 'Kirim laporan',
        body: `<div class="field"><label class="f" for="it">Judul singkat</label><input id="it" maxlength="140" placeholder="Mis. Tidak bisa input nilai E di Balok"></div>
          <div class="field"><label class="f" for="idc">Disiplin</label><select id="idc">${ME.discipline ? '' : '<option value="">Umum / semua disiplin</option>'}${myDiscs().map((d) => `<option value="${d}">${DN[d]}</option>`).join('')}</select></div>
          <div class="field"><label class="f" for="ib">Penjelasan</label><textarea id="ib" rows="4" placeholder="Apa yang terjadi, di halaman mana, dan apa yang Anda harapkan."></textarea></div>
          <div class="field"><label class="f" for="is">Tangkapan layar (opsional)</label><input id="is" type="file" accept="image/*,application/pdf"><div class="f-hint">JPG, PNG, atau PDF, maks. 5 MB. Hanya pelapor dan admin yang bisa membukanya.</div></div>`,
        onOk: async (d) => {
          const file = d.querySelector('#is').files[0];
          let shot = null;
          if (file) shot = (await JO.uploadFile('dokumen', file)).path;
          return api('console_issue_create', { p: { title: d.querySelector('#it').value, discipline: d.querySelector('#idc').value, body: d.querySelector('#ib').value, shot_path: shot } });
        } });
      if (r) { JO.toast('Laporan terkirim.'); location.hash = '#/laporan/' + r.id; }
    };
  }
  async function pageIssue(v, id) {
    const I = await api('console_issue', { p_id: id });
    const mine = I.reporter === ME.id;
    v.innerHTML = `<p><a href="#/laporan">Semua laporan</a></p>
      <div class="row" style="justify-content:space-between;align-items:flex-start"><div><h1>${esc(I.title)}</h1>
        <p class="muted">Dari ${esc(I.reporter_name || '-')} (${esc(ROLE[I.reporter_role] || '-')}) · ${I.discipline ? DN[I.discipline] : 'Umum'} · ${esc(dt(I.created_at))}</p></div>${issPill(I.status)}</div>
      <section class="card" style="margin-top:12px">${I.body ? `<p style="margin:0">${multiline(I.body)}</p>` : '<p class="muted" style="margin:0">Tanpa penjelasan.</p>'}
        ${I.shot_path && (mine || I.can_manage) ? '<div class="actions"><button class="btn btn-ghost btn-sm" id="shot">Lihat tangkapan layar</button></div>' : ''}
        ${I.status === 'selesai' && I.handled_by ? `<p class="small muted" style="margin:10px 0 0">Diselesaikan oleh ${esc(I.handled_by)}, ${esc(dt(I.resolved_at))}</p>` : ''}</section>
      <section class="card"><h2>Tanggapan</h2><div class="thread">${I.thread.length ? I.thread.map((c) => `<div class="msg"><div class="meta"><b>${esc(c.staff_name || 'Kode terhapus')}</b>${c.role ? ` <span>${esc(ROLE[c.role] || c.role)}</span>` : ''} · <time>${esc(dt(c.at))}</time></div><div class="body">${multiline(c.body)}</div></div>`).join('') : '<p class="small muted">Belum ada tanggapan.</p>'}</div>
        <form id="icf" style="margin-top:12px"><label class="f" for="icb">Tulis tanggapan</label><textarea id="icb" rows="3" required></textarea>
          <div class="actions"><button class="btn btn-dark btn-sm" type="submit">Kirim tanggapan</button>
          ${I.can_manage ? `${I.status !== 'diproses' ? '<button type="button" class="btn btn-ghost btn-sm" data-st="diproses">Tandai diproses</button>' : ''}
            ${I.status !== 'selesai' ? '<button type="button" class="btn btn-ok btn-sm" data-st="selesai">Tandai selesai</button>' : '<button type="button" class="btn btn-ghost btn-sm" data-st="baru">Buka lagi</button>'}` : ''}
          ${isSuper() ? '<button type="button" class="btn btn-bad btn-sm" id="idel" style="margin-left:auto">Hapus laporan</button>' : ''}</div></form></section>`;
    const sh = v.querySelector('#shot'); if (sh) sh.onclick = () => preview('dokumen', I.shot_path, 'Tangkapan layar');
    const idel = v.querySelector('#idel');
    if (idel) idel.onclick = async () => {
      if (!(await dialog({ title: 'Hapus laporan ini?', ok: 'Hapus', okClass: 'btn-bad', body: '<p>Laporan, tanggapan, dan tangkapan layarnya dihapus permanen. Tercatat di Log.</p>' }))) return;
      try { const r = await api('console_delete_issue', { p_id: id }); await removeFiles(r.files, 'laporan ' + id); JO.toast('Laporan dihapus.'); location.hash = '#/laporan'; }
      catch (e) { JO.toast(e.message, 'bad'); }
    };
    v.querySelector('#icf').onsubmit = async (e) => {
      e.preventDefault();
      const t = v.querySelector('#icb').value.trim(); if (!t) return;
      try { await api('console_issue_comment', { p_id: id, p_body: t }); pageIssue(v, id); } catch (err) { JO.toast(err.message, 'bad'); }
    };
    v.querySelectorAll('[data-st]').forEach((b) => b.onclick = async () => {
      const t = v.querySelector('#icb').value.trim();
      try {
        if (t) await api('console_issue_comment', { p_id: id, p_body: t });
        await api('console_issue_status', { p_id: id, p_status: b.dataset.st }); JO.toast('Status diperbarui.'); pageIssue(v, id);
      } catch (err) { JO.toast(err.message, 'bad'); }
    });
    pollUnread();
  }

  // ---------------- kontak ----------------
  const ctState = { tab: 'panitia', q: '' };
  async function pageContacts(v) {
    const C = await api('console_contacts');
    if (!C.can_registrants) ctState.tab = 'panitia';
    v.innerHTML = `<h1>Kontak</h1><p class="muted">Hubungi lewat WhatsApp atau kirim pesan di konsol. ${C.can_registrants ? 'Kontak pendaftar (pelatih, manajer, orang tua) hanya terlihat oleh admin ke atas dan TD; gunakan hanya untuk urusan Jabar Open 2026.' : ''}</p>
      ${ME.phone ? '' : '<p class="note warn small">Nomor WhatsApp Anda belum tercatat. <button type="button" class="btn btn-ghost btn-sm" id="setph">Isi sekarang</button></p>'}
      <div class="tabs">${[['panitia', 'Panitia & juri'], C.can_registrants ? ['pendaftar', 'Pendaftar'] : null].filter(Boolean).map(([k, l]) => `<button data-t="${k}" aria-selected="${ctState.tab === k}">${l}</button>`).join('')}</div>
      <div class="bar"><div class="field" style="flex:1"><label class="f" for="cq">Cari</label><input id="cq" type="search" value="${esc(ctState.q)}" placeholder="Nama, klub, disiplin, nomor"></div><span id="cx"></span></div><div id="cl"></div>`;
    const sp = v.querySelector('#setph'); if (sp) sp.onclick = async () => { if (await editMyPhone()) pageContacts(v); };
    const match = (txt) => !ctState.q || txt.toLowerCase().includes(ctState.q.toLowerCase());
    const waBtn = (p, text) => p ? `<a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="${esc(waText(p, text))}">WhatsApp</a>` : '<span class="tiny muted">Belum ada nomor</span>';
    const draw = () => {
      const cl = v.querySelector('#cl'), cx = v.querySelector('#cx');
      cx.innerHTML = '';
      if (ctState.tab === 'panitia') {
        const list = C.staff.filter((s) => match([s.name, ROLE[s.role], s.discipline ? DN[s.discipline] : 'semua', s.phone, s.note].join(' ')));
        cl.innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Peran</th><th>WhatsApp</th><th></th></tr></thead><tbody>
          ${list.map((s) => `<tr><td><strong>${esc(s.name)}</strong>${s.id === C.me ? ' <span class="pill">Anda</span>' : ''}${s.note ? `<br><span class="tiny muted">${esc(s.note)}</span>` : ''}</td>
            <td class="small">${esc(roleLabel(s.role, s.discipline))}${s.discipline ? '' : '<br><span class="tiny muted">semua disiplin</span>'}</td><td class="small num">${esc(s.phone || '')}</td>
            <td class="r"><span class="rm">${s.id === C.me ? '' : `${waBtn(s.phone)} <a class="btn btn-dark btn-sm" href="#/chat/${encodeURIComponent(s.room)}">Chat</a>`}</span></td></tr>`).join('')}</tbody></table></div>
          ${C.coordinators.length ? `<section class="card" style="margin-top:14px"><h2>Narahubung disiplin (tercantum di situs)</h2><div class="tbl-wrap"><table class="tbl"><tbody>
            ${C.coordinators.map((c) => `<tr><td>${DN[c.discipline] || esc(c.discipline)}</td><td><strong>${esc(c.name)}</strong></td><td class="small num">${esc(c.phone || '')}</td><td class="r">${waBtn(c.phone)}</td></tr>`).join('')}</tbody></table></div></section>` : ''}`;
      } else {
        const list = C.registrants.filter((r) => match([r.club, r.name, r.role, r.code, r.phone, r.email, DN[r.discipline]].join(' ')));
        cx.innerHTML = '<button class="btn btn-ghost btn-sm" id="cxl">Unduh Excel</button>';
        cx.querySelector('#cxl').onclick = () => exportXlsx('kontak-pendaftar-jabar-open-2026.xlsx', list, [['club', 'Klub'], ['name', 'Kontak'], ['role', 'Peran'], ['phone', 'WhatsApp'], ['email', 'Email'], ['discipline', 'Disiplin', (r) => DN[r.discipline]], ['code', 'Kode'], ['status', 'Status', (r) => ST[r.status] || r.status], ['athletes', 'Atlet']]);
        cl.innerHTML = list.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Klub / pendaftar</th><th>Kontak</th><th>Disiplin</th><th>Status</th><th></th></tr></thead><tbody>
          ${list.map((r) => `<tr><td><strong>${esc(r.club)}</strong><br>${isAdmin() ? `<a class="tiny code" href="#/pendaftaran/${r.submission_id}">${esc(r.code)}</a>` : `<span class="tiny code">${esc(r.code)}</span>`} <span class="tiny muted">${r.athletes} atlet</span></td>
            <td class="small">${esc(r.name)}${r.role ? ` <span class="muted">(${esc(r.role)})</span>` : ''}<br><span class="num">${esc(r.phone)}</span> · <a href="mailto:${esc(r.email)}">${esc(r.email)}</a></td>
            <td class="small">${DN[r.discipline] || esc(r.discipline)}</td><td>${pill(r.status)}</td>
            <td class="r">${waBtn(r.phone, `Halo ${r.name}, kami dari panitia Jabar Open 2026 terkait pendaftaran ${r.code} (${r.club}).`)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Tidak ada pendaftar.</p>';
      }
    };
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = () => { ctState.tab = b.dataset.t; v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b))); draw(); });
    v.querySelector('#cq').oninput = (e) => { ctState.q = e.target.value; draw(); };
    draw();
  }

  // =====================================================================
  //  PENDAFTARAN JURI
  // =====================================================================
  const BREVET = ['FIG Kategori 1', 'FIG Kategori 2', 'FIG Kategori 3', 'FIG Kategori 4', 'Nasional', 'Provinsi/Daerah', 'Belum ada', 'Lainnya'];
  const JDAYS = ['2026-12-12', '2026-12-13', '2026-12-14', '2026-12-15', '2026-12-16', '2026-12-17', '2026-12-18', '2026-12-19', '2026-12-20'];
  const JST = { baru: ['Baru', 'warn'], disetujui: ['Disetujui', 'ok'], ditolak: ['Ditolak', 'bad'] };
  const brevetText = (b) => (b ? (b.level === 'Lainnya' ? b.other || 'Lainnya' : b.level) + (b.year ? ' (' + b.year + ')' : '') : '–');
  const daysText = (a) => (a && a.length ? a.map((d) => Number(d.slice(8, 10))).join(', ') + ' Des' : '–');
  const juState = { status: 'baru', disc: '' };
  async function pageJury(v) {
    const rows = await api('console_jury_list', { p_filter: { status: juState.status, discipline: juState.disc } });
    const link = JO.siteUrl() + 'juri.html';
    v.innerHTML = `<div class="row" style="justify-content:space-between;align-items:flex-end"><div><h1>Pendaftaran juri</h1>
        <p class="muted">Calon juri mendaftar lewat <a href="${esc(link)}" target="_blank" rel="noopener">formulir juri</a> di situs, atau ditambahkan admin di sini. Menyetujui pendaftar membuat kode akses juri; kirim kodenya secara pribadi lewat WhatsApp.</p></div>
        <span class="rm"><button class="btn btn-ghost" id="jlink">Salin tautan formulir</button><button class="btn btn-primary" id="jadd">Tambah juri</button></span></div>
      <div class="bar"><div class="field"><label class="f" for="jst">Status</label><select id="jst">${[['baru', 'Baru'], ['disetujui', 'Disetujui'], ['ditolak', 'Ditolak'], ['', 'Semua']].map(([k, l]) => `<option value="${k}" ${juState.status === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
        ${ME.discipline ? '' : discSelect('jd', juState.disc)}</div>
      ${rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Disiplin & brevet</th><th>Dokumen</th><th>Status</th><th></th></tr></thead><tbody>
        ${rows.map((j) => `<tr><td><strong>${esc(j.full_name)}</strong><br><span class="tiny muted">${esc([j.city, j.province].filter(Boolean).join(', '))}${j.source === 'konsol' ? ' · ditambah admin' : ''} · ${esc(dt(j.created_at))}</span>
            <br><span class="small num">${esc(j.phone)}</span>${j.email ? ` · <a class="small" href="mailto:${esc(j.email)}">${esc(j.email)}</a>` : ''}${j.note ? `<br><span class="tiny">${esc(j.note)}</span>` : ''}</td>
          <td class="small">${j.disciplines.map((d) => `<div><b>${DN[d] || esc(d)}</b>: ${esc(brevetText(j.brevet && j.brevet[d]))}</div>`).join('')}</td>
          <td class="small"><span class="rm">${[['ktp_path', 'KTP'], ['photo_path', 'Foto'], ['bpjs_path', 'BPJS TK'], ['cert_path', 'Sertifikat']].map(([k, l]) => j[k] ? `<button class="btn btn-ghost btn-sm" data-doc="${esc(j[k])}" data-dl="${l} ${esc(j.full_name)}">${l}</button>` : '').join('') || '<span class="muted">–</span>'}</span></td>
          <td><span class="pill ${JST[j.status][1]}">${JST[j.status][0]}</span>${j.staff_name ? `<br><span class="tiny muted">Kode: ${esc(j.staff_name)}${j.staff_active === false ? ' (nonaktif)' : ''}</span>` : ''}${j.reviewed_by_name ? `<br><span class="tiny muted">oleh ${esc(j.reviewed_by_name)}</span>` : ''}${j.review_note && j.status === 'ditolak' ? `<br><span class="tiny">${esc(j.review_note)}</span>` : ''}</td>
          <td class="r">${rowMenu(j.status !== 'disetujui' ? `<button class="btn btn-ok btn-sm" data-ok="${j.id}">Setujui</button>` : '',
            [{ label: 'WhatsApp', attr: `data-wa="${j.id}"` }, j.status === 'baru' ? { label: 'Tolak', attr: `data-no="${j.id}"`, danger: true } : null,
             isSuper() ? { sep: true } : null, isSuper() ? { label: 'Hapus permanen', attr: `data-jdel="${j.id}"`, danger: true } : null])}</td></tr>`).join('')}</tbody></table></div>`
        : '<p class="empty">Tidak ada pendaftar juri di sini.</p>'}`;
    v.querySelector('#jst').onchange = (e) => { juState.status = e.target.value; pageJury(v); };
    const jd = v.querySelector('#jd'); if (jd) jd.onchange = (e) => { juState.disc = e.target.value; pageJury(v); };
    v.querySelector('#jlink').onclick = () => navigator.clipboard.writeText(link).then(() => JO.toast('Tautan formulir juri disalin.'));
    v.querySelector('#jadd').onclick = () => juryForm(v);
    v.querySelectorAll('[data-doc]').forEach((b) => b.onclick = () => preview('dokumen', b.dataset.doc, b.dataset.dl));
    v.querySelectorAll('[data-wa]').forEach((b) => b.onclick = () => { const j = rows.find((x) => x.id === b.dataset.wa); window.open(waText(j.phone, `Halo ${j.full_name}, kami dari panitia Jabar Open 2026 terkait pendaftaran juri Anda.`), '_blank', 'noopener'); });
    v.querySelectorAll('[data-no]').forEach((b) => b.onclick = async () => {
      const j = rows.find((x) => x.id === b.dataset.no);
      const note = await askReason('Tolak ' + j.full_name + '?', 'Pesan untuk pendaftar (opsional, ikut di email)', { ok: 'Tolak', okClass: 'btn-bad', required: false });
      if (note === null) return;
      try { await api('console_jury_reject', { p_id: j.id, p_note: note }); JO.toast('Pendaftar ditolak.'); pageJury(v); pollUnread(); } catch (e) { JO.toast(e.message, 'bad'); }
    });
    v.querySelectorAll('[data-ok]').forEach((b) => b.onclick = () => juryApprove(v, rows.find((x) => x.id === b.dataset.ok)));
    v.querySelectorAll('[data-jdel]').forEach((b) => b.onclick = async () => {
      const j = rows.find((x) => x.id === b.dataset.jdel);
      const reason = await askReason('Hapus pendaftar juri ' + j.full_name + '?', 'Alasan (masuk Log)', { required: false, ok: 'Hapus permanen', okClass: 'btn-bad',
        intro: 'Data dan berkas pendaftar dihapus permanen.' + (j.staff_id ? ' Kode akses juri yang sudah dibuat tidak ikut terhapus; nonaktifkan di Kode akses bila perlu.' : '') });
      if (reason === null) return;
      try { const r = await api('console_delete_jury', { p_id: j.id, p_reason: reason }); await removeFiles(r.files, 'juri ' + j.full_name); JO.toast('Pendaftar juri dihapus.'); pageJury(v); pollUnread(); }
      catch (e) { JO.toast(e.message, 'bad'); }
    });
  }
  async function juryApprove(v, j) {
    const discs = j.disciplines.filter((d) => myDiscs().includes(d));
    if (!discs.length) return JO.toast('Pendaftar ini tidak mendaftar untuk disiplin Anda.', 'bad');
    const r = await dialog({ title: 'Setujui ' + j.full_name, ok: 'Setujui & buat kode',
      body: `<p class="small">Membuat kode akses <b>juri</b> atas nama ${esc(j.full_name)} (WA ${esc(j.phone)}). Satu kode untuk satu disiplin; bila juri bertugas di dua disiplin, buat kode kedua dari Kode akses.</p>
        <div class="field"><label class="f" for="ad">Disiplin</label><select id="ad">${discs.map((d) => `<option value="${d}">${DN[d]} (brevet: ${esc(brevetText(j.brevet && j.brevet[d]))})</option>`).join('')}</select></div>
        <div class="field"><span class="f">Batasi komponen</span><div class="row">${['D', 'E', 'A', 'PEN'].map((c) => `<label class="check" style="padding:2px 10px 2px 0"><input type="checkbox" data-comp="${c}">${c}</label>`).join('')}</div><div class="f-hint">Kosongkan untuk semua komponen. Bisa diubah nanti di Kode akses.</div></div>
        <div class="field"><label class="f" for="aa">Batasi alat (pisahkan dengan koma)</label><input id="aa" placeholder="Mis. VT, UB"><div class="f-hint">Kosongkan untuk semua alat.</div></div>
        ${winEditor([])}
        <div class="field"><label class="f" for="an">Catatan internal</label><input id="an" placeholder="Mis. Juri E panel 1"></div>
        <div class="field"><label class="f" for="am">Pesan untuk juri (ikut di email persetujuan, opsional)</label><textarea id="am" rows="2" placeholder="Mis. Rapat juri 11 Desember pukul 15.00 di Arcamanik."></textarea><div class="f-hint">Email tidak memuat kode akses. Kode hanya dikirim lewat WhatsApp.</div></div>`,
      onOk: async (d) => api('console_jury_approve', { p_id: j.id, p: { discipline: d.querySelector('#ad').value,
        components: [...d.querySelectorAll('[data-comp]:checked')].map((x) => x.dataset.comp),
        apparatus: d.querySelector('#aa').value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean),
        note: d.querySelector('#an').value, message: d.querySelector('#am').value, access_windows: readWindows(d) } }) });
    if (!r) return;
    const msg = `Halo ${r.name}, Anda disetujui sebagai juri Jabar Open 2026.\nKode akses konsol penilaian: ${r.code}\nMasuk di ${JO.siteUrl()}panitia/\nKode ini pribadi, jangan dibagikan.`;
    dialog({ title: 'Kode akses untuk ' + r.name, ok: null, cancel: 'Selesai',
      body: `<div class="codebox">${esc(r.code)}</div><p class="small" style="margin-top:12px">Kirim secara pribadi ke ${esc(r.name)}. Kode ini tidak bisa ditampilkan lagi; bila hilang, buat kode baru dari Kode akses.</p>
        <div class="actions"><button type="button" class="btn btn-dark btn-sm" id="cp">Salin kode</button>
        <a class="btn btn-ok btn-sm" target="_blank" rel="noopener" href="${esc(waText(r.phone, msg))}">Kirim ke WhatsApp ${esc(r.phone)}</a></div>` }).then(() => { pageJury(v); pollUnread(); });
    setTimeout(() => { const cp = document.getElementById('cp'); if (cp) cp.onclick = () => navigator.clipboard.writeText(r.code).then(() => JO.toast('Kode disalin.')); }, 50);
  }
  async function juryForm(v) {
    const r = await dialog({ title: 'Tambah juri', ok: 'Simpan', wide: true,
      body: `<p class="small muted">Untuk juri yang dihubungi langsung oleh panitia. Setelah disimpan, setujui untuk membuat kode aksesnya.</p>
        <div class="grid-2"><div class="field"><label class="f" for="jn">Nama lengkap (dengan gelar bila ada)</label><input id="jn"></div>
          <div class="field"><label class="f" for="jp">Nomor WhatsApp</label><input id="jp" inputmode="tel" placeholder="08xx-xxxx-xxxx"></div>
          <div class="field"><label class="f" for="je">Email (opsional)</label><input id="je" type="email"></div>
          <div class="field"><label class="f" for="jc">Kota asal</label><input id="jc"></div></div>
        <div class="field"><span class="f">Disiplin (satu) dan brevet</span>${myDiscs().filter((d) => d !== 'AER').map((d) => `<div class="brv-row"><label class="check"><input type="radio" name="jdisc" data-jd="${d}">${DN[d]}</label>
          <select data-bl="${d}" disabled><option value="">Tingkat brevet…</option>${BREVET.map((b) => `<option>${b}</option>`).join('')}</select><input data-bo="${d}" placeholder="Sebutkan brevet" hidden></div>`).join('')}</div>
        <div class="grid-2"><div class="field"><label class="f" for="fk">KTP (opsional)</label><input id="fk" type="file" accept="image/*,application/pdf"></div>
          <div class="field"><label class="f" for="ff">Pas foto (opsional)</label><input id="ff" type="file" accept="image/*"></div>
          <div class="field"><label class="f" for="fb">BPJS Ketenagakerjaan (opsional di sini)</label><input id="fb" type="file" accept="image/*,application/pdf"></div>
          <div class="field"><label class="f" for="fc">Sertifikat brevet (opsional)</label><input id="fc" type="file" accept="image/*,application/pdf"></div></div>
        <div class="field"><label class="f" for="jnote">Catatan</label><input id="jnote"></div>`,
      onOk: async (d) => {
        const discs = [...d.querySelectorAll('[data-jd]:checked')].map((x) => x.dataset.jd);
        const brevet = {}; discs.forEach((k) => { brevet[k] = { level: d.querySelector(`[data-bl="${k}"]`).value }; if (brevet[k].level === 'Lainnya') brevet[k].other = d.querySelector(`[data-bo="${k}"]`).value; });
        const up = async (sel) => { const f = d.querySelector(sel).files[0]; return f ? (await JO.uploadFile('dokumen', f)).path : null; };
        const p = { full_name: d.querySelector('#jn').value, phone: d.querySelector('#jp').value, email: d.querySelector('#je').value, city: d.querySelector('#jc').value,
          disciplines: discs, brevet, note: d.querySelector('#jnote').value,
          ktp_path: await up('#fk'), photo_path: await up('#ff'), bpjs_path: await up('#fb'), cert_path: await up('#fc') };
        return api('console_jury_add', { p });
      },
      });
    if (r) { JO.toast('Juri ditambahkan. Setujui untuk membuat kodenya.'); juState.status = 'baru'; pageJury(v); }
  }
  // brevet: aktifkan pilihan saat disiplin dicentang (dipakai di dialog Tambah juri)
  document.addEventListener('change', (e) => {
    const t = e.target;
    if (t.matches && t.matches('[data-jd]')) {
      t.closest('.field').querySelectorAll('.brv-row').forEach((row) => { const on = row.contains(t) && t.checked; const s2 = row.querySelector('select'); s2.disabled = !on; if (!on) s2.value = ''; });
    }
    if (t.matches && t.matches('.brv-row select')) { const o = t.closest('.brv-row').querySelector('input[data-bo]'); o.hidden = t.value !== 'Lainnya'; }
  });

  // =====================================================================
  //  KODE AKSES
  // =====================================================================
  async function pageAccess(v) {
    const rows = await api('console_staff_list');
    v.innerHTML = `<div class="row page-act" style="justify-content:space-between;align-items:center;gap:12px 20px"><div><h1>Kode akses</h1><p class="muted">Satu kode untuk satu orang. Kode hanya ditampilkan sekali; bila hilang, buat kode baru (kode lama otomatis tidak berlaku).</p></div>
      <button class="btn btn-primary" id="new">+ Buat kode baru</button></div><div style="height:14px"></div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Peran</th><th>Disiplin</th><th>Batasan juri</th><th>Kode</th><th>Terakhir masuk</th><th></th></tr></thead><tbody>
      ${rows.map((s) => `<tr><td>${esc(s.name)}${s.active ? '' : ' <span class="pill bad">nonaktif</span>'}${s.note || s.phone ? `<br><span class="tiny muted">${esc([s.phone, s.note].filter(Boolean).join(' · '))}</span>` : ''}</td>
        <td>${ROLE[s.role]}</td><td>${s.discipline ? DN[s.discipline] : 'Semua'}</td>
        <td class="small">${s.role === 'juri' ? `${s.apparatus ? 'Alat: ' + s.apparatus.join(', ') : 'Semua alat'}<br>${s.components ? 'Komponen: ' + s.components.join(', ') : 'Semua komponen'}${winSummary(s)}` : ''}</td>
        <td class="code small">…${esc(s.code_hint || '')}</td><td class="small">${s.last_login_at ? dt(s.last_login_at) : 'Belum pernah'}</td>
        <td class="r">${s.role === 'owner' || (s.role === 'superadmin' && ME.role !== 'owner') ? '' : rowMenu(
          s.active ? `<button class="btn btn-ghost btn-sm" data-rc="${s.id}">Kode baru</button>` : `<button class="btn btn-ok btn-sm" data-act="${s.id}">Aktifkan</button>`,
          [{ label: 'Ubah', attr: `data-edit="${s.id}"` },
           s.active ? null : { label: 'Kode baru', attr: `data-rc="${s.id}"` },
           s.active ? { label: 'Nonaktifkan', attr: `data-act="${s.id}"`, danger: true } : null,
           s.active || s.id === ME.id ? null : { sep: true },
           s.active || s.id === ME.id ? null : { label: 'Hapus permanen', attr: `data-del="${s.id}"`, danger: true }])}</td></tr>`).join('')}</tbody></table></div>
      <p class="tiny muted" style="margin-top:10px">Hapus hanya muncul untuk kode nonaktif. Kode yang pernah memverifikasi atau memberi nilai tidak bisa dihapus, agar namanya tetap tercatat di riwayat; cukup biarkan nonaktif.</p>`;
    const form = (s) => `<div class="field"><label class="f">Nama pemegang kode</label><input id="sn" value="${esc(s ? s.name : '')}" placeholder="Mis. Vici Ayu"></div>
      ${s ? '' : `<div class="field"><label class="f">Peran</label><select id="sr">
        <option value="admin">Admin / verifikator (verifikasi bayar, dokumen, start list, hasil)</option>
        <option value="td">TD / Technical Director (pantau kategori, start list, nilai, hasil; hanya baca)</option>
        <option value="juri">Juri (input nilai saja; bisa dibatasi jam tugas)</option>
        <option value="pemantau">Pemantau (hanya lihat: kategori, start list, nilai, hasil)</option>
        ${ME.role === 'owner' ? '<option value="superadmin">Superadmin (semua, termasuk ledger)</option>' : ''}</select></div>`}
      <div class="field"><label class="f">Disiplin</label><select id="sd"><option value="">Semua disiplin</option>${DISCS.map((d) => `<option value="${d}" ${s && s.discipline === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>
      <div id="jopt" ${!s || s.role !== 'juri' ? 'hidden' : ''}><div class="field"><span class="f">Batasi komponen (juri)</span><div class="row">${['D', 'E', 'A', 'PEN'].map((c) => `<label class="check" style="padding:2px 10px 2px 0"><input type="checkbox" data-comp="${c}" ${s && s.components && s.components.includes(c) ? 'checked' : ''}>${c}</label>`).join('')}</div><div class="f-hint">Kosongkan untuk semua komponen.</div></div>
        <div class="field"><label class="f">Batasi alat (juri, pisahkan dengan koma)</label><input id="sa" placeholder="Mis. VT, UB" value="${esc(s && s.apparatus ? s.apparatus.join(', ') : '')}"><div class="f-hint">Kode alat: MAG FX PH SR VT PB HB; WAG VT UB BB FX; Ritmik FH ROPE HOOP BALL CLUBS RIBBON; Aerobik RTN. Kosongkan untuk semua alat.</div></div>${winEditor(s ? s.access_windows : [])}</div>
      <div class="field"><label class="f">Nomor WhatsApp</label><input id="sph" inputmode="tel" value="${esc(s ? s.phone || '' : '')}" placeholder="08xx-xxxx-xxxx"><div class="f-hint">Tampil di halaman Kontak untuk sesama panitia dan juri.</div></div>
      <div class="field"><label class="f">Catatan</label><input id="snote" value="${esc(s ? s.note || '' : '')}" placeholder="Mis. Juri E panel 1"></div>`;
    const collect = (d) => ({ name: d.querySelector('#sn').value, role: d.querySelector('#sr') ? d.querySelector('#sr').value : undefined, discipline: d.querySelector('#sd').value,
      components: [...d.querySelectorAll('[data-comp]:checked')].map((x) => x.dataset.comp), apparatus: d.querySelector('#sa').value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean), note: d.querySelector('#snote').value, phone: d.querySelector('#sph').value,
      access_windows: readWindows(d) });
    const wireRole = () => { const d = document.getElementById('dlg'); const sr = d && d.querySelector('#sr'); if (sr) sr.onchange = () => { d.querySelector('#jopt').hidden = sr.value !== 'juri'; }; };
    const showCode = (name, code) => dialog({ title: 'Kode akses untuk ' + name, ok: null, cancel: 'Selesai',
      body: `<div class="codebox">${esc(code)}</div><p class="small" style="margin-top:12px">Salin dan kirim secara pribadi. Kode ini tidak bisa ditampilkan lagi.</p>
        <div class="actions"><button type="button" class="btn btn-dark btn-sm" id="cp">Salin kode</button>
        <a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(`Kode akses konsol panitia Jabar Open 2026 untuk ${name}: ${code}\nMasuk di ${JO.siteUrl()}panitia/\nJangan bagikan kode ini.`)}">Kirim lewat WhatsApp</a></div>` })
      .then(() => pageAccess(v)) && setTimeout(() => { const cp = document.getElementById('cp'); if (cp) cp.onclick = () => navigator.clipboard.writeText(code).then(() => JO.toast('Kode disalin.')); }, 50);
    v.querySelector('#new').onclick = async () => {
      const pr = dialog({ title: 'Buat kode baru', ok: 'Buat kode', body: form(null), onOk: async (d) => api('console_staff_create', { p: collect(d) }) });
      wireRole(); const r = await pr;
      if (r) showCode(r.staff.name, r.code);
    };
    v.querySelectorAll('[data-edit]').forEach((b) => b.onclick = async () => {
      const s = rows.find((x) => x.id === b.dataset.edit);
      const r = await dialog({ title: 'Ubah ' + s.name, body: form(s), onOk: async (d) => { const p = collect(d); delete p.role; await api('console_staff_update', { p_id: s.id, p: p }); return true; } });
      if (r) pageAccess(v);
    });
    v.querySelectorAll('[data-rc]').forEach((b) => b.onclick = async () => {
      const s = rows.find((x) => x.id === b.dataset.rc);
      if (!(await dialog({ title: 'Buat kode baru untuk ' + s.name + '?', ok: 'Buat kode baru', body: '<p>Kode lama langsung tidak berlaku dan sesi yang sedang masuk akan keluar.</p>' }))) return;
      try { const r = await api('console_staff_new_code', { p_id: s.id }); showCode(s.name, r.code); } catch (e) { JO.toast(e.message, 'bad'); }
    });
    v.querySelectorAll('[data-del]').forEach((b) => b.onclick = async () => {
      const s = rows.find((x) => x.id === b.dataset.del);
      const r = await dialog({ title: 'Hapus kode ' + s.name + '?', ok: 'Hapus permanen', okClass: 'btn-bad',
        body: `<p>Kode <strong>${esc(s.name)}</strong> (${ROLE[s.role]}${s.discipline ? ' ' + DN[s.discipline] : ''}) dihapus dari daftar dan tidak bisa dikembalikan. Penghapusan ini tercatat di Log.</p>`,
        onOk: async () => { await api('console_staff_delete', { p_id: s.id }); return true; } });
      if (r) { JO.toast('Kode dihapus.'); pageAccess(v); }
    });
    v.querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
      const s = rows.find((x) => x.id === b.dataset.act);
      try { await api('console_staff_update', { p_id: s.id, p: { active: !s.active } }); pageAccess(v); } catch (e) { JO.toast(e.message, 'bad'); }
    });
  }

  // =====================================================================
  //  PENGATURAN
  // =====================================================================
  // Gambar tanda tangan: latar terang -> transparan, dipotong ke goresan, maks. 700 px
  async function transparentPng(file) {
    const url = URL.createObjectURL(file);
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('Gambar tidak terbaca')); i.src = url; });
    URL.revokeObjectURL(url);
    const sc = Math.min(1, 1400 / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.round(img.naturalWidth * sc), h = Math.round(img.naturalHeight * sc);
    const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
    const ctx = cv.getContext('2d'); ctx.drawImage(img, 0, 0, w, h);
    const d = ctx.getImageData(0, 0, w, h); const p = d.data;
    let x0 = w, y0 = h, x1 = 0, y1 = 0;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const k = (y * w + x) * 4; const lum = (p[k] + p[k + 1] + p[k + 2]) / 3;
      const a = Math.min(p[k + 3], Math.max(0, Math.round((235 - lum) * 255 / 120)));
      p[k + 3] = a;
      if (a > 20) { if (x < x0) x0 = x; if (y < y0) y0 = y; if (x > x1) x1 = x; if (y > y1) y1 = y; }
    }
    if (x1 <= x0) throw new Error('Goresan tanda tangan tidak terdeteksi.');
    ctx.putImageData(d, 0, 0);
    const pad = 8; x0 = Math.max(0, x0 - pad); y0 = Math.max(0, y0 - pad); x1 = Math.min(w - 1, x1 + pad); y1 = Math.min(h - 1, y1 + pad);
    const cw = x1 - x0 + 1, ch = y1 - y0 + 1, s2 = Math.min(1, 700 / Math.max(cw, ch));
    const out = document.createElement('canvas'); out.width = Math.round(cw * s2); out.height = Math.round(ch * s2);
    out.getContext('2d').drawImage(cv, x0, y0, cw, ch, 0, 0, out.width, out.height);
    return await new Promise((r) => out.toBlob(r, 'image/png'));
  }

  // Notifikasi WhatsApp ke admin pendaftaran (dikirim Apps Script lewat gateway)
  async function drawWa(card) {
    if (!card) return;
    let W;
    try { W = await api('console_wa'); } catch (e) { card.innerHTML = `<h2>Notifikasi WhatsApp</h2><p class="note bad small">${esc(e.message)}</p>`; return; }
    const live = W.last_poll && (Date.now() - new Date(W.last_poll).getTime() < 30 * 60 * 1000);
    const dn = (c) => (c ? DN[c] || c : 'Semua disiplin');
    card.innerHTML = `<h2>Notifikasi WhatsApp</h2>
      <p class="small">Setiap ${W.interval_min} menit sistem memeriksa bukti bayar baru. Bila ada, penerima di bawah mendapat ringkasan berisi kode pendaftaran, klub, jumlah atlet, total yang menunggu, dan tautan ke konsol. Tidak ada pesan bila tidak ada yang baru.</p>
      <p class="small">${live ? `<span class="pill ok">Terhubung</span> Terakhir diperiksa ${dt(W.last_poll)}` : '<span class="pill warn">Belum terhubung</span> Isi FONNTE_TOKEN di Apps Script (lihat panduan).'}</p>
      <div class="row" style="gap:10px;align-items:end;flex-wrap:wrap">
        <label class="check" style="margin:0"><input type="checkbox" id="wa_on" ${W.enabled ? 'checked' : ''}><span>Kirim notifikasi</span></label>
        <div class="field" style="margin:0;width:150px"><label class="f" for="wa_int">Interval (menit)</label><input id="wa_int" type="number" min="5" max="240" value="${W.interval_min}"></div>
        <button class="btn btn-ghost btn-sm" id="wa_set">Simpan</button>
      </div>
      <h3 style="margin-top:16px">Penerima</h3>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Nomor</th><th>Disiplin</th><th></th></tr></thead><tbody>
        ${W.recipients.map((r) => `<tr class="${r.active ? '' : 'muted'}"><td><strong>${esc(r.name)}</strong>${r.active ? '' : ' <span class="pill">nonaktif</span>'}</td><td class="small">${esc(r.phone)}</td><td class="small">${esc(dn(r.discipline))}</td>
          <td class="r"><button class="btn btn-ghost btn-sm" data-wae="${r.id}">Ubah</button> ${r.active ? `<button class="btn btn-ghost btn-sm" data-wat="${r.id}">Kirim tes</button>` : ''}</td></tr>`).join('')
          || '<tr><td colspan="4" class="muted">Belum ada penerima. Tambahkan admin pendaftaran.</td></tr>'}
      </tbody></table></div>
      <button class="btn btn-primary btn-sm" id="wa_add" style="margin-top:10px">Tambah penerima</button>
      <h3 style="margin-top:16px">Pesan terakhir</h3>
      <div class="tbl-wrap" style="max-height:320px;overflow:auto"><table class="tbl"><tbody>
        ${W.recent.map((o) => `<tr><td class="small"><strong>${esc(o.name || o.to)}</strong> · ${o.kind === 'tes' ? 'tes' : 'ringkasan'}<br><span class="muted">${dt(o.created_at)}</span>${o.error ? `<br><span style="color:var(--bad)">${esc(o.error)}</span>` : ''}</td>
          <td><span class="pill ${o.status === 'sent' ? 'ok' : o.status === 'error' ? 'bad' : 'warn'}">${esc(o.status === 'sent' ? 'terkirim' : o.status === 'error' ? 'gagal' : 'antre')}</span></td></tr>`).join('') || '<tr><td class="muted">Belum ada pesan.</td></tr>'}
      </tbody></table></div>`;
    const edit = async (r) => {
      r = r || { name: '', phone: '', discipline: '', active: true };
      const res = await dialog({ title: r.id ? 'Ubah penerima' : 'Tambah penerima', ok: 'Simpan',
        body: `<div class="field"><label class="f" for="wn">Nama</label><input id="wn" value="${esc(r.name)}" placeholder="mis. Vici (admin WAG)"></div>
          <div class="field"><label class="f" for="wp">Nomor WhatsApp</label><input id="wp" inputmode="tel" value="${esc(r.phone)}" placeholder="08xx-xxxx-xxxx"></div>
          <div class="field"><label class="f" for="wd">Disiplin</label><select id="wd"><option value="">Semua disiplin</option>
            ${Object.keys(DN).map((c) => `<option value="${c}" ${r.discipline === c ? 'selected' : ''}>${esc(DN[c])}</option>`).join('')}</select>
            <div class="tiny muted">Penerima satu disiplin hanya mendapat pendaftaran disiplin itu.</div></div>
          ${r.id ? `<label class="check"><input type="checkbox" id="wa_act" ${r.active ? 'checked' : ''}><span>Aktif</span></label>` : ''}`,
        onOk: async (d) => api('console_wa_save', { p: { id: r.id || null, name: d.querySelector('#wn').value, phone: d.querySelector('#wp').value,
          discipline: d.querySelector('#wd').value, active: r.id ? d.querySelector('#wa_act').checked : true } }) });
      if (res) { JO.toast('Penerima disimpan.'); drawWa(card); }
    };
    card.querySelector('#wa_add').onclick = () => edit(null);
    card.querySelectorAll('[data-wae]').forEach((b) => b.onclick = () => edit(W.recipients.find((x) => x.id === b.dataset.wae)));
    card.querySelectorAll('[data-wat]').forEach((b) => b.onclick = async () => {
      try { await api('console_wa_test', { p_id: b.dataset.wat }); JO.toast('Pesan tes masuk antrean; terkirim dalam 1 menit bila Apps Script terhubung.'); drawWa(card); }
      catch (e) { JO.toast(e.message, 'bad'); }
    });
    card.querySelector('#wa_set').onclick = async () => {
      try { await api('console_wa_settings', { p: { enabled: card.querySelector('#wa_on').checked, interval_min: Number(card.querySelector('#wa_int').value) } }); JO.toast('Pengaturan notifikasi disimpan.'); drawWa(card); }
      catch (e) { JO.toast(e.message, 'bad'); }
    };
  }
  async function pageSettings(v) {
    const D = await api('console_settings');
    const S = D.settings;
    setTimeout(() => {
      const ob2 = v.querySelector('#orph'); if (!ob2) return;
      ob2.onclick = async () => {
        const box = v.querySelector('#orphres'); loading(box);
        try {
          const files = await api('console_orphan_files');
          if (!files.length) { box.innerHTML = '<p class="note ok small">Tidak ada berkas tak terpakai.</p>'; return; }
          const kb = Math.round(files.reduce((a, f) => a + (f.size || 0), 0) / 1024);
          box.innerHTML = `<p class="small">${files.length} berkas (${kb} KB) tidak dipakai data mana pun.</p><button type="button" class="btn btn-bad btn-sm" id="orphdel">Hapus ${files.length} berkas</button>`;
          box.querySelector('#orphdel').onclick = async () => {
            if (!(await dialog({ title: 'Hapus ' + files.length + ' berkas?', ok: 'Hapus permanen', okClass: 'btn-bad', body: '<p>Berkas dihapus dari penyimpanan dan tidak bisa dikembalikan.</p>' }))) return;
            const n = await removeFiles(files, 'berkas tak terpakai');
            box.innerHTML = `<p class="note ok small">${n} berkas dihapus.</p>`;
          };
        } catch (e) { box.innerHTML = `<p class="note bad small">${esc(e.message)}</p>`; }
      };
    }, 0);
    const ob = await api('console_outbox');
    const sig = S.signatories || [];
    const val = (k) => (S[k] == null ? '' : S[k]);
    const dl = S.registration_deadline ? new Date(S.registration_deadline) : null;
    const dlLocal = dl ? new Date(dl.getTime() + 7 * 3600 * 1000).toISOString().slice(0, 16) : '';
    v.innerHTML = `<h1>Pengaturan</h1>
      <div class="split">
      <div>
        <section class="card"><h2>QRIS pembayaran</h2>
          <p class="small muted">Unggah gambar QRIS dari GoPay Merchant / GoBiz (PNG atau JPG). Gambar tampil di halaman tagihan dan status.</p>
          <div class="pay pay-set"><div class="qris">${S.qris_image_url ? `<img src="${esc(S.qris_image_url)}" alt="QRIS">` : '<p class="small muted" style="margin:8px">Belum ada</p>'}</div>
          <div><input type="file" id="qf" accept="image/png,image/jpeg,image/webp"><div class="field" style="margin-top:12px"><label class="f">Nama merchant</label><input data-s="qris_merchant" value="${esc(val('qris_merchant'))}"></div>
          <div class="field"><label class="f">Catatan pembayaran</label><textarea data-s="payment_note">${esc(val('payment_note'))}</textarea></div></div></div></section>
        <section class="card"><h2>Pendaftaran</h2>
          <label class="check"><input type="checkbox" data-sb="registration_open" ${S.registration_open ? 'checked' : ''}>Pendaftaran dibuka</label>
          <div class="grid-2"><div class="field"><label class="f">Batas pendaftaran (WIB)</label><input id="rd" type="datetime-local" value="${dlLocal}"></div>
          <div class="field"><label class="f">Teks batas pembayaran</label><input data-s="payment_deadline_label" value="${esc(val('payment_deadline_label'))}"></div>
          <div class="field"><label class="f">Maks. atlet per pendaftaran</label><input data-sn="max_athletes" type="number" value="${val('max_athletes')}"></div>
          <div class="field"><label class="f">Batas nominal QRIS (Rp)</label><input data-sn="qris_cap" type="number" value="${val('qris_cap')}"></div>
          <div class="field"><label class="f">Email kontak publik</label><input data-s="contact_email" value="${esc(val('contact_email'))}"></div></div>
          <label class="check"><input type="checkbox" data-sb="email_guardians" ${S.email_guardians ? 'checked' : ''}>Kirim email AIC juga ke orang tua/wali</label></section>
        <section class="card"><h2>Berkas tak terpakai</h2>
          <p class="small muted">Dokumen, pas foto, dan bukti bayar yang tidak lagi dipakai data mana pun (mis. dari pendaftaran yang kedaluwarsa 15 menit atau data uji). Penghapusan permanen dan tercatat di Log.</p>
          <div class="actions"><button type="button" class="btn btn-ghost btn-sm" id="orph">Periksa berkas tak terpakai</button></div><div id="orphres"></div></section>
        <section class="card"><h2>Penanda tangan sertifikat</h2>
          <p class="small muted">Gambar tanda tangan tampil di atas nama pada semua sertifikat. Pakai PNG berlatar transparan atau putih polos; latar putih dibuat transparan otomatis.</p>
          ${[0, 1].map((i) => `<div class="sig-row"><div class="sig-prev" data-sigprev="${i}"></div><div style="flex:1;min-width:0"><div class="grid-2"><div class="field"><label class="f">Nama ${i + 1}</label><input data-sig="${i}" data-f="name" value="${esc(sig[i] ? sig[i].name : '')}"></div>
            <div class="field"><label class="f">Jabatan ${i + 1}</label><input data-sig="${i}" data-f="title" value="${esc(sig[i] ? sig[i].title : '')}"></div></div>
            <div class="row" style="gap:8px"><label class="btn btn-ghost btn-sm" style="position:relative;overflow:hidden">Unggah tanda tangan<input type="file" accept="image/png,image/jpeg" data-sigfile="${i}" style="position:absolute;inset:0;opacity:0;cursor:pointer"></label>
            <button type="button" class="btn btn-ghost btn-sm" data-sigdel="${i}">Hapus gambar</button></div></div></div>`).join('')}</section>
        ${ME.role === 'owner' ? `<section class="card"><h2>Alamat situs</h2><div class="field"><label class="f">URL publik (untuk tautan email & QR)</label><input data-s="site_url" value="${esc(val('site_url'))}"></div></section>` : ''}
        <div class="sticky-actions"><button class="btn btn-primary" id="save">Simpan pengaturan</button></div>
      </div>
      <div>
        <section class="card"><h2>Pengirim email (Gmail)</h2>
          <p class="small">${ob.last_poll ? 'Terakhir terhubung ' + dt(ob.last_poll) : '<strong>Belum pernah terhubung.</strong> Pasang Google Apps Script sesuai panduan.'}</p>
          ${ME.role === 'owner' ? '<button class="btn btn-ghost btn-sm" id="sec">Buat secret email baru</button><p class="tiny muted">Secret lama langsung tidak berlaku; perbarui juga di Apps Script.</p>' : ''}
          <div class="tbl-wrap" style="margin-top:12px;max-height:520px;overflow:auto"><table class="tbl"><thead><tr><th>Email</th><th>Status</th><th></th></tr></thead><tbody>
          ${ob.rows.map((o) => `<tr><td class="small"><strong>${esc(o.subject)}</strong><br>${esc(o.to)}${o.cc ? ' cc ' + esc(o.cc) : ''}<br><span class="muted">${dt(o.created_at)}</span>${o.last_error ? `<br><span style="color:var(--bad)">${esc(o.last_error)}</span>` : ''}</td>
            <td><span class="pill ${o.status === 'sent' ? 'ok' : o.status === 'error' ? 'bad' : 'warn'}">${esc(o.status)}</span></td>
            <td>${o.status === 'error' || o.status === 'sending' ? `<button class="btn btn-ghost btn-sm" data-retry="${o.id}">Ulangi</button>` : ''}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Belum ada email.</td></tr>'}</tbody></table></div></section>
        <section class="card" id="wa-card"></section>
      </div></div>`;
    drawWa(v.querySelector('#wa-card'));
    const sigImg = [0, 1].map((i) => (sig[i] && sig[i].sig) || '');
    const drawSig = (i) => {
      const box = v.querySelector(`[data-sigprev="${i}"]`); const u = sigImg[i];
      box.innerHTML = u ? `<img src="${esc(/^https?:/.test(u) ? u : '../' + u)}" alt="Tanda tangan ${i + 1}">` : '<span class="tiny muted">Belum ada tanda tangan</span>';
    };
    [0, 1].forEach(drawSig);
    v.querySelectorAll('[data-sigdel]').forEach((b) => b.onclick = () => { sigImg[b.dataset.sigdel] = ''; drawSig(Number(b.dataset.sigdel)); JO.toast('Klik Simpan pengaturan untuk menerapkan.'); });
    v.querySelectorAll('[data-sigfile]').forEach((inp) => inp.onchange = async (e) => {
      const i = Number(inp.dataset.sigfile); const file = e.target.files[0]; if (!file) return;
      try {
        await JO.ensureSession();
        const blob = await transparentPng(file);
        const path = `ttd/ttd-${i + 1}-${Date.now()}.png`;
        const { error } = await JO.sb.storage.from('publik').upload(path, await blob.arrayBuffer(), { contentType: 'image/png', upsert: false });
        if (error) throw new Error(error.message);
        sigImg[i] = JO.sb.storage.from('publik').getPublicUrl(path).data.publicUrl;
        drawSig(i); JO.toast('Tanda tangan diunggah. Klik Simpan pengaturan untuk menerapkan.');
      } catch (err) { JO.toast('Unggah tanda tangan gagal: ' + err.message, 'bad'); }
    });
    v.querySelector('#qf').onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      try {
        await JO.ensureSession();
        const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
        const path = `qris/qris-${Date.now()}.${ext}`;
        const { error } = await JO.sb.storage.from('publik').upload(path, await file.arrayBuffer(), { contentType: file.type, upsert: false });
        if (error) throw new Error(error.message);
        const url = JO.sb.storage.from('publik').getPublicUrl(path).data.publicUrl;
        await api('console_save_setting', { p_key: 'qris_image_url', p_value: url });
        JO.toast('QRIS diperbarui.'); pageSettings(v);
      } catch (err) { JO.toast('Unggah QRIS gagal: ' + err.message, 'bad'); }
    };
    v.querySelector('#save').onclick = async (ev) => {
      const btn = ev.currentTarget; btn.disabled = true;
      try {
        const ch = [];
        v.querySelectorAll('[data-s]').forEach((i) => { if (i.value !== String(val(i.dataset.s))) ch.push([i.dataset.s, i.value]); });
        v.querySelectorAll('[data-sn]').forEach((i) => { if (i.value !== String(val(i.dataset.sn))) ch.push([i.dataset.sn, Number(i.value)]); });
        v.querySelectorAll('[data-sb]').forEach((i) => { if (i.checked !== !!S[i.dataset.sb]) ch.push([i.dataset.sb, i.checked]); });
        const rd = v.querySelector('#rd').value; if (rd && rd !== dlLocal) ch.push(['registration_deadline', rd + ':59+07:00']);
        const sg = [0, 1].map((i) => Object.assign({ name: v.querySelector(`[data-sig="${i}"][data-f=name]`).value.trim(), title: v.querySelector(`[data-sig="${i}"][data-f=title]`).value.trim() },
          sigImg[i] ? { sig: sigImg[i] } : {})).filter((x) => x.name);
        if (JSON.stringify(sg) !== JSON.stringify(sig)) ch.push(['signatories', sg]);
        for (const [k, val_] of ch) await api('console_save_setting', { p_key: k, p_value: val_ });
        JO.toast(ch.length ? `${ch.length} pengaturan disimpan.` : 'Tidak ada perubahan.');
        if (ch.length) pageSettings(v);
      } catch (e) { JO.toast(e.message, 'bad'); }
      finally { btn.disabled = false; }
    };
    const sec = v.querySelector('#sec');
    if (sec) sec.onclick = async () => {
      if (!(await dialog({ title: 'Buat secret email baru?', ok: 'Buat', body: '<p>Pengirim email berhenti sampai secret baru dipasang di Apps Script (Project Settings → Script properties → SECRET).</p>' }))) return;
      const r = await api('console_new_email_secret');
      dialog({ title: 'Secret email baru', ok: null, cancel: 'Selesai', body: `<div class="codebox" style="font-size:1rem;word-break:break-all">${esc(r.secret)}</div><p class="small">Tempel di Apps Script sebagai Script property <span class="kbd">SECRET</span>. Tidak ditampilkan lagi.</p>` });
    };
    v.querySelectorAll('[data-retry]').forEach((b) => b.onclick = async () => { await api('console_outbox_retry', { p_id: Number(b.dataset.retry) }); pageSettings(v); });
  }

  // =====================================================================
  //  LOG
  // =====================================================================
  async function pageLog(v) {
    v.innerHTML = `<h1>Log</h1><p class="muted">Semua tindakan panitia tercatat dengan nama pemegang kode. Log koreksi nilai menyimpan nilai lama, nilai baru, dan alasannya.</p>
      <div class="tabs"><button data-t="a" aria-selected="true">Aktivitas</button><button data-t="s" aria-selected="false">Koreksi nilai</button></div><div id="lb"></div>`;
    const lb = v.querySelector('#lb');
    const act = async () => {
      loading(lb);
      const rows = await api('console_audit', { p_filter: { limit: 500 } });
      lb.innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th>Oleh</th><th>Tindakan</th><th>Detail</th></tr></thead><tbody>
        ${rows.map((r) => `<tr><td class="small">${dt(r.at)}</td><td>${esc(r.staff || 'Pendaftar')}</td><td>${esc(r.action.replace(/_/g, ' '))}</td><td class="small muted" style="max-width:420px;word-break:break-word">${esc(JSON.stringify(r.detail))}</td></tr>`).join('')}</tbody></table></div>`;
    };
    const sco = async () => {
      loading(lb);
      const rows = await api('console_score_log', { p_filter: {} });
      lb.innerHTML = rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th>Kategori</th><th>Atlet</th><th>Alat</th><th>Komp.</th><th class="r">Lama</th><th class="r">Baru</th><th>Juri</th><th>Diubah oleh</th><th>Alasan</th></tr></thead><tbody>
        ${rows.map((r) => `<tr><td class="small">${dt(r.at)}</td><td class="small">${esc(r.category || '')}</td><td class="small">${esc((r.athletes || []).map((a) => a.name).join(' & '))}</td>
          <td>${esc(r.apparatus || '')}</td><td>${esc(r.component || '')}</td><td class="r num">${num3(r.old_value)}</td><td class="r num">${num3(r.new_value)}</td>
          <td class="small">${esc(r.judge || '')}</td><td class="small">${esc(r.changed_by || '')}</td><td class="small">${esc(r.reason || '')}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada koreksi nilai.</p>';
    };
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = () => { v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b))); b.dataset.t === 'a' ? act() : sco(); });
    await act();
  }

  // ---------------- mulai ----------------
  (async function boot() {
    try { await JO.ensureSession(); }
    catch (e) { root.innerHTML = `<div class="login"><div class="card"><p class="note bad">${esc(e.message)}</p><button class="btn btn-ghost" onclick="location.reload()">Muat ulang</button></div></div>`; return; }
    try { ME = await rpc('console_me'); } catch (e) { ME = null; }
    if (!ME) return showLogin();
    try { await startApp(); } catch (e) { showLogin(e.message); }
  })();
})();
