/* =====================================================================
   Jabar Open 2026 — konsol panitia (owner, superadmin, admin, juri)
   ===================================================================== */
(function () {
  'use strict';
  const { esc, fmtRp, rpc } = JO;
  const root = document.getElementById('root');
  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };
  const DISCS = ['MAG', 'WAG', 'RG', 'AER'];
  const ROLE = { owner: 'Owner', superadmin: 'Superadmin', admin: 'Admin', juri: 'Juri' };
  const ST = { menunggu_pembayaran: 'Menunggu pembayaran', menunggu_verifikasi: 'Menunggu verifikasi', lunas: 'Lunas', perlu_perbaikan: 'Perlu perbaikan', dibatalkan: 'Dibatalkan' };
  let ME = null, CATS = null;
  const isSuper = () => ME && (ME.role === 'owner' || ME.role === 'superadmin');
  const isAdmin = () => ME && ME.role !== 'juri';
  const myDiscs = () => (ME && ME.discipline ? [ME.discipline] : DISCS);
  const num3 = (v) => (v == null || v === '' ? '–' : Number(v).toFixed(3));
  const dt = (d) => JO.fmtDateTime(d);
  const pill = (s) => JO.statusPill(s);
  const wa = (p) => { const d = String(p || '').replace(/\D/g, '').replace(/^0/, '62'); return d ? `https://wa.me/${d}` : '#'; };
  const catName = (id) => { const c = CATS && CATS.categories.find((x) => x.id === Number(id)); return c ? c.name_id : '#' + id; };
  const discApps = (code) => ((CATS && CATS.disciplines.find((d) => d.code === code)) || { apparatus: [] }).apparatus;
  const appName = (disc, code) => { const a = discApps(disc).find((x) => x.code === code); return a ? a.id : code; };

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
    root.innerHTML = `<div class="login"><div class="card">
      <img class="logo" src="../assets/img/logo-jabar-open.png" alt="Jabar Open 2026">
      <h1 style="font-size:1.5rem">Konsol panitia</h1>
      <p class="muted">Masukkan kode akses pribadi dari koordinator. Satu kode untuk satu orang; setiap tindakan tercatat atas nama pemegang kode.</p>
      ${msg ? `<p class="note warn">${esc(msg)}</p>` : ''}
      <form id="lf" novalidate><label class="f" for="code">Kode akses</label>
        <input id="code" class="codein" type="text" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="JO-XXXX-XXXX" required>
        <button class="btn btn-primary" style="width:100%;margin-top:12px" type="submit">Masuk</button></form>
      <div id="lmsg" style="margin-top:12px"></div>
      <p class="tiny muted" style="margin-top:18px">Kode hilang atau bocor? Minta superadmin menonaktifkan dan membuat kode baru.</p></div></div>`;
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
  const PAGES = [
    ['ringkasan', 'Ringkasan', () => isAdmin(), pageDashboard],
    ['pendaftaran', 'Pendaftaran', () => isAdmin(), pageSubmissions],
    ['atlet', 'Data atlet', () => isAdmin(), pageAthletes],
    ['kategori', 'Kategori', () => isAdmin(), pageCategories],
    ['startlist', 'Start list', () => isAdmin(), pageStartlist],
    ['nilai', 'Penilaian', () => true, pageScoring],
    ['hasil', 'Hasil & medali', () => isAdmin(), pageResults],
    ['ledger', 'Ledger', () => isSuper(), pageLedger],
    ['klub', 'Klub', () => isAdmin(), pageClubs],
    ['akses', 'Kode akses', () => isSuper(), pageAccess],
    ['pengaturan', 'Pengaturan', () => isSuper(), pageSettings],
    ['log', 'Log', () => isSuper(), pageLog],
  ];
  async function startApp() {
    await refreshCats();
    root.innerHTML = `<div class="shell"><aside class="side">
        <div class="who"><strong>${esc(ME.name)}</strong><span>${ROLE[ME.role]}${ME.discipline ? ' ' + DN[ME.discipline] : ''}</span></div>
        <nav id="nav">${PAGES.filter((p) => p[2]()).map(([k, l]) => `<a href="#/${k}" data-k="${k}">${esc(l)}</a>`).join('')}</nav>
        <div class="out"><button class="btn btn-ghost btn-sm" id="logout" type="button">Keluar</button></div>
      </aside><main class="main" id="view"></main></div>`;
    root.querySelector('#logout').onclick = async () => { try { await rpc('console_logout'); } catch (e) {} ME = null; location.hash = ''; showLogin('Anda sudah keluar.'); };
    window.onhashchange = route;
    if (!location.hash || location.hash === '#/' || location.hash === '#') location.hash = isAdmin() ? '#/ringkasan' : '#/nilai';
    else route();
  }
  function route() {
    if (!ME) return;
    const parts = location.hash.replace(/^#\/?/, '').split('?')[0].split('/');
    const page = PAGES.find((p) => p[0] === parts[0] && p[2]()) || PAGES.find((p) => p[2]());
    root.querySelectorAll('#nav a').forEach((a) => a.toggleAttribute('aria-current', a.dataset.k === page[0]));
    if (root.querySelector('#nav a[aria-current]')) root.querySelector('#nav a[aria-current]').setAttribute('aria-current', 'page');
    const v = root.querySelector('#view');
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
    v.innerHTML = `<h1>Ringkasan</h1><p class="muted">Halo, ${esc(ME.name)}. Angka di bawah diperbarui setiap halaman ini dibuka.</p>
      <div class="stats" style="margin-top:16px">${d.by_discipline.map((x) => `<div class="stat">
        <h3>${esc(x.name)} <a class="small" href="#/pendaftaran?d=${x.code}">Lihat</a></h3>
        <div class="big">${x.athletes}</div><div class="small muted">atlet terdaftar, ${x.athletes_paid} lunas</div>
        <ul>
          <li><a href="#/pendaftaran?d=${x.code}&s=menunggu_verifikasi">Menunggu verifikasi</a><strong>${x.to_verify}</strong></li>
          <li><a href="#/pendaftaran?d=${x.code}&s=menunggu_pembayaran">Belum bayar / perlu perbaikan</a><strong>${x.unpaid}</strong></li>
          <li><a href="#/pendaftaran?d=${x.code}&f=docs">Dokumen belum diperiksa</a><strong>${x.docs_pending}</strong></li>
          <li><a href="#/pendaftaran?d=${x.code}&f=priangan">Priangan menunggu</a><strong>${x.priangan_pending}</strong></li>
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
    v.innerHTML = `<h1>Pendaftaran</h1><p class="muted">Klik baris untuk memeriksa bukti bayar, dokumen identitas, dan kategori Priangan.</p>
      <div class="bar">${discSelect('fd', subFilter.discipline)}
        <div class="field"><label class="f" for="fs">Status</label><select id="fs"><option value="">Semua status</option>
          ${Object.entries(ST).map(([k, l]) => `<option value="${k}" ${subFilter.status === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
        <div class="field"><label class="f" for="ff">Perlu diperiksa</label><select id="ff"><option value="">Semua</option>
          <option value="docs" ${subFilter.flag === 'docs' ? 'selected' : ''}>Dokumen belum diperiksa</option>
          <option value="priangan" ${subFilter.flag === 'priangan' ? 'selected' : ''}>Priangan menunggu</option></select></div>
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
          <td>${esc(r.club || 'Perorangan')}<br><span class="tiny muted">${esc(r.contact_name)}, ${esc(r.region || '')}</span></td>
          <td class="small">${esc(r.athlete_names)}</td>
          <td class="r num">${fmtRp(r.total_amount)}${r.payment_method === 'manual' ? '<br><span class="pill warn">WNA</span>' : ''}</td>
          <td>${pill(r.status)}</td>
          <td class="small">${r.proof_uploaded_at ? '<span class="pill info">Bukti ada</span> ' : ''}${r.mutation_matched ? '<span class="pill ok">Mutasi cocok</span> ' : ''}
            ${r.docs_pending ? `<span class="pill">${r.docs_pending} dokumen</span> ` : ''}${r.priangan_pending ? `<span class="pill warn">${r.priangan_pending} Priangan</span>` : ''}</td></tr>`).join('')}
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
      <p class="muted">${esc(s.discipline_name)}, ${s.registrant_type === 'klub' ? 'pendaftaran klub' : 'perorangan'}, ${dt(s.created_at)}</p>
      <div class="split" style="margin-top:14px">
        <div>
          <section class="card"><h2>Pendaftar</h2><dl class="kv">
            <dt>Penanggung jawab</dt><dd>${esc(s.contact_name)}${s.contact_role ? ` <span class="tiny muted">(${esc(s.contact_role)})</span>` : ''}</dd>
            <dt>WhatsApp</dt><dd><a href="${wa(s.contact_phone)}" target="_blank" rel="noopener">${esc(s.contact_phone)}</a></dd>
            <dt>Email</dt><dd><a href="mailto:${esc(s.contact_email)}">${esc(s.contact_email)}</a></dd>
            <dt>Klub</dt><dd>${club}</dd>
            <dt>Bahasa</dt><dd>${s.lang === 'en' ? 'English' : 'Indonesia'}</dd></dl></section>
          <section class="card"><h2>Atlet & kategori</h2><div id="aths" class="stack"></div></section>
          <section class="card"><h2>Email</h2>
            ${D.emails.length ? `<ul class="small" style="padding-left:18px;margin:0 0 10px">${D.emails.map((e) => `<li>${esc(e.kind)} ke ${esc(e.to)}: <strong>${esc(e.status)}</strong> ${e.sent_at ? dt(e.sent_at) : ''}</li>`).join('')}</ul>` : '<p class="small muted">Belum ada email.</p>'}
            <div class="actions"><button class="btn btn-ghost btn-sm" data-mail="pendaftaran">Kirim ulang tagihan</button>
              ${s.status === 'lunas' ? '<button class="btn btn-ghost btn-sm" data-mail="lunas">Kirim ulang e-ticket</button>' : ''}
              <button class="btn btn-ghost btn-sm" data-mail="tautan">Kirim tautan status</button></div></section>
          <section class="card"><h2>Riwayat</h2>${D.history.length ? `<ul class="small" style="padding-left:18px;margin:0">${D.history.map((h) => `<li>${dt(h.at)}: <strong>${esc(h.action.replace(/_/g, ' '))}</strong>${h.staff ? ' oleh ' + esc(h.staff) : ''}${h.detail && (h.detail.note || h.detail.reason) ? ` <span class="muted">(${esc(h.detail.note || h.detail.reason)})</span>` : ''}</li>`).join('')}</ul>` : '<p class="small muted">Belum ada.</p>'}</section>
        </div>
        <div>
          <section class="card" style="position:sticky;top:12px"><h2>Pembayaran</h2>
            <table class="breakdown"><tbody>
              <tr><td>Biaya pendaftaran</td><td>${fmtRp(s.base_amount)}</td></tr>
              ${s.priangan_amount ? `<tr><td>Priangan</td><td>${fmtRp(s.priangan_amount)}</td></tr>` : ''}
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
        body: `<p>E-ticket ${D.athletes.length} atlet akan aktif dan email dikirim ke <strong>${esc(s.contact_email)}</strong>.</p>
          ${!s.proof_path && !matched.length && !manual ? '<p class="note warn">Belum ada bukti bayar maupun mutasi yang cocok. Hanya lanjutkan bila Anda sudah memastikan dana masuk.</p>' : ''}
          ${manual ? `<label class="f" for="amt">Nominal diterima (Rp)</label><input id="amt" type="number" min="1" value="${s.total_amount}">` : ''}
          <label class="f" for="note" style="margin-top:10px">Catatan (opsional)</label><textarea id="note" placeholder="Mis. cocok dengan mutasi GoBiz 13:42"></textarea>`,
        onOk: async (d) => {
          const args = { p_id: s.id, p_approve: true, p_note: d.querySelector('#note').value.trim() || null };
          if (manual) args.p_amount = Number(d.querySelector('#amt').value);
          await api('console_verify_payment', args); return true;
        } });
      if (r) { JO.toast('Ditandai lunas. Email e-ticket masuk antrean.'); reload(); }
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

    // atlet
    const box = v.querySelector('#aths');
    D.athletes.forEach((a) => {
      const ents = D.entries.filter((e) => e.athletes.some((x) => x.id === a.id));
      const el = document.createElement('div'); el.className = 'ath';
      el.innerHTML = `<div class="ath-head"><span class="bib">${esc(a.athlete_no || '')}</span><strong>${esc(a.full_name)}</strong><span class="spacer"></span>
          <button class="btn btn-ghost btn-sm" data-edit>Ubah data</button></div>
        <div class="ath-body">
          <dl class="kv"><dt>Jenis kelamin</dt><dd>${a.gender === 'M' ? 'Putra' : 'Putri'}</dd>
            <dt>Tanggal lahir</dt><dd>${JO.fmtDate(a.birth_date)} <span class="muted">(usia 2026: ${a.age})</span></dd>
            <dt>Asal</dt><dd>${a.nationality === 'WNA' ? 'WNA, ' + esc(a.country) : esc([a.kab_kota, a.province].filter(Boolean).join(', '))}</dd>
            ${a.minor ? `<dt>Orang tua/wali</dt><dd>${esc(a.guardian_name || '-')}${a.guardian_relation ? ` (${esc(a.guardian_relation)})` : ''}<br>
              <a href="${wa(a.guardian_phone)}" target="_blank" rel="noopener">${esc(a.guardian_phone || '')}</a><br>${esc(a.guardian_email || '')}</dd>` : ''}
          </dl>
          <div class="actions">
            <button class="btn btn-ghost btn-sm" data-doc>Lihat dokumen identitas</button>
            ${a.photo_path ? '<button class="btn btn-ghost btn-sm" data-photo>Lihat foto</button>' : ''}
            <span class="pill ${a.doc_status === 'valid' ? 'ok' : a.doc_status === 'tidak_valid' ? 'bad' : ''}">${a.doc_status === 'valid' ? 'Dokumen valid' : a.doc_status === 'tidak_valid' ? 'Dokumen tidak valid' : 'Dokumen belum diperiksa'}</span>
            ${a.doc_status !== 'valid' ? '<button class="btn btn-ok btn-sm" data-dv="1">Dokumen valid</button>' : ''}
            ${a.doc_status !== 'tidak_valid' ? '<button class="btn btn-bad btn-sm" data-dv="0">Tidak valid</button>' : ''}
          </div>
          ${a.doc_note ? `<p class="small muted">Catatan dokumen: ${esc(a.doc_note)}</p>` : ''}
          ${ents.map((e) => `<div style="border-top:1px solid var(--line);margin-top:12px;padding-top:10px" data-entry="${e.id}">
            <strong>${esc(e.category)}</strong> <span class="small muted">${fmtRp(e.fee)}</span>
            ${e.status !== 'aktif' ? ` <span class="pill bad">${esc(e.status)}</span>` : ''}
            ${e.athletes.length > 1 ? `<div class="small muted">Pasangan: ${esc(e.athletes.map((x) => x.name).join(' & '))}</div>` : ''}
            ${e.mismatch ? `<p class="note warn small" style="margin:6px 0">Tidak sesuai kategori: ${esc(e.mismatch)}</p>` : ''}
            ${e.priangan_requested ? `<div class="small" style="margin-top:6px">Priangan (${fmtRp(e.priangan_fee)}): <strong>${esc(e.priangan_status)}</strong>${e.priangan_note ? ` <span class="muted">(${esc(e.priangan_note)})</span>` : ''}
              ${e.priangan_status !== 'disetujui' ? ' <button class="btn btn-ok btn-sm" data-pri="1">Setujui</button>' : ''}${e.priangan_status !== 'ditolak' ? ' <button class="btn btn-bad btn-sm" data-pri="0">Tolak</button>' : ''}
              <div class="tiny muted">Syarat: WNI, alamat KTP/akte di Jawa Barat, klub di Jawa Barat.</div></div>` : ''}
            <div class="actions"><button class="btn btn-ghost btn-sm" data-move>Pindah kategori</button>
              ${e.status === 'aktif' ? '<button class="btn btn-ghost btn-sm" data-est="dns">Tidak tampil (DNS)</button>' : '<button class="btn btn-ghost btn-sm" data-est="aktif">Aktifkan lagi</button>'}</div>
          </div>`).join('')}
        </div>`;
      const q = (sel) => el.querySelector(sel);
      q('[data-doc]').onclick = () => preview('dokumen', a.id_doc_path, 'Dokumen identitas ' + a.full_name);
      if (q('[data-photo]')) q('[data-photo]').onclick = () => preview('dokumen', a.photo_path, 'Foto ' + a.full_name);
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
          if (!ok) { note = await askReason('Tolak Priangan', 'Alasan (mis. alamat di KTP luar Jawa Barat)'); if (!note) return; }
          act('console_set_priangan', { p_entry: e.id, p_approve: ok, p_note: note }, ok ? 'Priangan disetujui.' : 'Priangan ditolak.');
        });
        ee.querySelector('[data-move]').onclick = () => moveEntry(e, s.discipline, reload);
        ee.querySelectorAll('[data-est]').forEach((b) => b.onclick = async () => {
          const r = await askReason(b.dataset.est === 'dns' ? 'Tandai tidak tampil' : 'Aktifkan lagi', 'Alasan');
          if (r) act('console_set_entry_status', { p_entry: e.id, p_status: b.dataset.est, p_reason: r }, 'Status entri diubah.');
        });
      });
      box.appendChild(el);
    });
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
        <button class="btn btn-dark" id="ax" type="button">Unduh Excel</button></div><div id="list"></div>`;
    let rows = [];
    const load = async () => {
      const list = v.querySelector('#list'); loading(list);
      rows = await api('console_athletes', { p_filter: f });
      list.innerHTML = rows.length ? `<p class="small muted">${rows.length} atlet</p><div class="tbl-wrap"><table class="tbl"><thead><tr>
        <th>No.</th><th>Nama</th><th>L/P</th><th>Lahir</th><th>Klub</th><th>Asal</th><th>Kategori</th><th>Bayar</th><th>Dokumen</th></tr></thead><tbody>
        ${rows.map((r) => `<tr class="click" data-sub="${r.submission_id}"><td><span class="bib">${esc(r.athlete_no)}</span></td><td>${esc(r.full_name)}</td><td>${r.gender === 'M' ? 'L' : 'P'}</td>
          <td class="small">${esc(r.birth_date)}<br><span class="muted">usia ${r.age}</span></td><td>${esc(r.club)}</td>
          <td class="small">${esc(r.nationality === 'WNA' ? r.country : r.kab_kota || '')}</td><td class="small">${esc(r.categories || '')}</td>
          <td>${pill(r.payment_status)}</td><td class="small">${esc(r.doc_status)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Tidak ada atlet yang cocok.</p>';
      list.querySelectorAll('tr[data-sub]').forEach((tr) => tr.onclick = () => { location.hash = '#/pendaftaran/' + tr.dataset.sub; });
    };
    const ad = v.querySelector('#ad'); if (ad) ad.onchange = () => { f.discipline = ad.value; load(); };
    v.querySelector('#as').onchange = (e) => { f.status = e.target.value; load(); };
    let tm; v.querySelector('#aq').oninput = (e) => { clearTimeout(tm); tm = setTimeout(() => { f.q = e.target.value.trim(); load(); }, 300); };
    v.querySelector('#ax').onclick = () => exportXlsx(`atlet-jabar-open-2026-${new Date().toISOString().slice(0, 10)}.xlsx`, rows, [
      ['athlete_no', 'No. atlet'], ['full_name', 'Nama lengkap'], ['gender', 'L/P', (r) => (r.gender === 'M' ? 'L' : 'P')], ['birth_date', 'Tanggal lahir'], ['age', 'Usia 2026'],
      ['discipline', 'Disiplin', (r) => DN[r.discipline]], ['categories', 'Kategori'], ['club', 'Klub'], ['club_kab_kota', 'Kab/kota klub'],
      ['nationality', 'WNI/WNA'], ['country', 'Negara'], ['province', 'Provinsi (KTP)'], ['kab_kota', 'Kab/kota (KTP)'],
      ['submission_code', 'Kode pendaftaran'], ['payment_status', 'Status bayar', (r) => ST[r.payment_status]], ['doc_status', 'Dokumen'],
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
      v.innerHTML = `<h1>Kategori</h1><p class="muted">Dari Undangan Jabar Open 2026. Angka tahun lahir dihitung dari "usia pada tahun kompetisi" (2026).</p>
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
            <td><button class="btn btn-ghost btn-sm" data-edit="${c.id}">Ubah</button></td></tr>`;
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
          <label class="check"><input type="checkbox" data-b="allow_priangan" ${c.allow_priangan ? 'checked' : ''}>Membuka kategori Priangan</label>
          <label class="check"><input type="checkbox" data-b="active" ${c.active ? 'checked' : ''}>Aktif (tampil di formulir pendaftaran)</label>` : ''}
        <label class="check"><input type="checkbox" data-b="exhibition" ${c.exhibition ? 'checked' : ''}>Eksibisi (medali tidak dihitung di tabel perolehan)</label>
        <div class="field"><label class="f">Catatan internal</label><textarea data-k="note">${esc(c.note || '')}</textarea></div>
        ${!sup ? '<p class="small muted">Perubahan usia, biaya, dan alat hanya bisa dilakukan superadmin.</p>' : ''}`,
      onOk: async (d) => {
        const patch = {};
        d.querySelectorAll('[data-k]').forEach((i) => { const k = i.dataset.k; const old = c[k] == null ? '' : String(c[k]); if (i.value !== old) patch[k] = i.value; });
        d.querySelectorAll('[data-b]').forEach((i) => { if (i.checked !== c[i.dataset.b]) patch[i.dataset.b] = i.checked; });
        if (sup) { const apps2 = [...d.querySelectorAll('[data-app]:checked')].map((x) => x.dataset.app); if (apps2.join() !== c.apparatus.join()) patch.apparatus = apps2; }
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
    v.innerHTML = `<h1>Start list</h1><p class="muted">Atur sesi, grup, dan urutan tampil untuk atlet yang sudah lunas, lalu publikasikan. Start list yang dipublikasikan tampil di situs dan e-ticket.</p>
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
          <td class="r"><button class="btn btn-ghost btn-sm" data-se="${s.id}">Ubah</button> <button class="btn btn-bad btn-sm" data-sx="${s.id}">Hapus</button></td></tr>`).join('')}</tbody></table></div>` : '<p class="small muted">Belum ada sesi. Tambahkan sesi lomba (mis. "Sesi 1 Minggu pagi").</p>'}
        <button class="btn btn-ghost btn-sm" id="sadd" style="margin-top:10px">Tambah sesi</button>`;
      const edit = async (s) => {
        const r = await dialog({ title: s ? 'Ubah sesi' : 'Tambah sesi',
          body: `<div class="field"><label class="f">Nama sesi</label><input id="sn" value="${esc(s ? s.name : '')}" placeholder="Sesi 1"></div>
            <div class="grid-2"><div class="field"><label class="f">Hari</label><input id="sday" type="date" value="${esc(s ? s.day || '' : '')}"></div>
            <div class="field"><label class="f">Jam mulai</label><input id="st" type="time" value="${esc(s && s.start_time ? s.start_time.slice(0, 5) : '')}"></div></div>
            <div class="field"><label class="f">Urutan tampil sesi</label><input id="so" type="number" value="${s ? s.sort : sessions.length + 1}"></div>`,
          onOk: async (d) => { await api('console_save_session', { p: { id: s ? s.id : null, discipline: slState.disc, name: d.querySelector('#sn').value, day: d.querySelector('#sday').value, start_time: d.querySelector('#st').value, sort: Number(d.querySelector('#so').value || 0) } }); return true; } });
        if (r) { await drawSessions(); loadList(); }
      };
      box.querySelector('#sadd').onclick = () => edit(null);
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
          <div class="sticky-actions"><button class="btn btn-dark" id="save">Simpan</button>
            <button class="btn btn-ghost" id="draw" ${c.startlist_published ? 'disabled' : ''}>Undi urutan acak</button>
            <button class="btn btn-ghost" id="allsess">Isi semua dengan sesi pertama, grup 1</button>
            <button class="btn ${c.startlist_published ? 'btn-bad' : 'btn-primary'}" id="pub">${c.startlist_published ? 'Tarik dari situs' : 'Publikasikan'}</button></div>`
          : '<p class="empty">Belum ada atlet lunas di kategori ini.</p>'}</section>`;
      const rows = () => [...box.querySelectorAll('tr[data-e]')].map((tr) => ({ entry_id: tr.dataset.e,
        session_id: tr.querySelector('[data-f=session_id]').value, group_no: tr.querySelector('[data-f=group_no]').value, start_order: tr.querySelector('[data-f=start_order]').value }));
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
    const juri = ME.role === 'juri';
    v.innerHTML = `<h1>Penilaian</h1>
      <p class="muted">${juri ? `Masuk sebagai ${esc(ME.name)}${ME.components ? ', komponen ' + ME.components.join('/') : ''}${ME.apparatus ? ', alat ' + ME.apparatus.join('/') : ''}. Nilai tersimpan otomatis saat Anda pindah kolom.` : 'Nilai juri masuk langsung ke sini. Pencatat bisa mengisi nilai akhir per alat dari lembar juri. Setiap perubahan setelah dikunci tercatat di log koreksi.'}</p>
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
      box.innerHTML = `<section class="card">
        <div class="row" style="justify-content:space-between"><h2 style="margin:0">${esc(D.category.name_id)}</h2>
          <span>${D.locked ? '<span class="pill warn">Nilai dikunci</span>' : '<span class="pill ok">Terbuka untuk input</span>'}${D.category.results_published ? ' <span class="pill dark">Hasil dipublikasikan</span>' : ''}</span></div>
        <div class="tabs" style="margin-top:12px">${D.apparatus.map((a) => `<button data-app="${a.code}" aria-selected="${a.code === app}">${esc(a.id)}</button>`).join('')}</div>
        ${!juri ? `<div class="row" style="margin-bottom:10px"><div class="seg"><label><input type="radio" name="md" value="final" ${scState.mode === 'final' ? 'checked' : ''}>Isi nilai akhir</label><label><input type="radio" name="md" value="comp" ${scState.mode === 'comp' ? 'checked' : ''}>Isi per komponen</label></div>
          <span class="small muted">Nilai akhir menggantikan hitungan komponen untuk alat ini.</span></div>` : ''}
        ${D.entries.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">#</th><th>Atlet</th>
          ${showComps ? comps.map((c) => `<th class="r">${esc(c.code)}<br><span class="tiny">${esc(c.id.replace(/^Nilai /, ''))}</span></th>`).join('') : ''}
          ${!juri ? `${!showComps ? '<th>Nilai juri</th>' : ''}<th class="r">Nilai ${esc(app)}</th>${scState.mode === 'final' ? '<th class="r">Nilai akhir</th>' : ''}<th class="r">Total</th><th class="c">Per.</th>` : ''}</tr></thead><tbody>
          ${D.entries.map((e, i) => {
            const all = (e.all || []).filter((x) => x.apparatus === app);
            const res = e.result || {};
            const judgeTxt = ['D', 'A', 'E', 'PEN', 'FINAL'].map((c) => { const xs = all.filter((x) => x.component === c); return xs.length ? `${c}: ${xs.map((x) => `${num3(x.value)} <span class="muted">(${esc(x.staff)})</span>`).join(', ')}` : ''; }).filter(Boolean).join('<br>');
            return `<tr data-e="${e.entry_id}"><td class="c num">${e.start_order || i + 1}</td>
              <td>${e.athletes.map((a) => `<strong>${esc(a.name)}</strong> <span class="tiny muted">${esc(a.athlete_no)}</span>`).join('<br>')}<br><span class="tiny muted">${esc(e.club)}</span>${e.status === 'dns' ? ' <span class="pill bad">DNS</span>' : ''}</td>
              ${showComps ? comps.map((c) => `<td class="r"><input class="score-in" inputmode="decimal" data-c="${c.code}" value="${e.own[app + ':' + c.code] != null ? e.own[app + ':' + c.code] : ''}" aria-label="${esc(c.code)} ${esc(e.athletes[0].name)}" ${e.status === 'dns' ? 'disabled' : ''}></td>`).join('') : ''}
              ${!juri ? `${!showComps ? `<td class="judge-vals">${judgeTxt || '–'}</td>` : ''}
                <td class="r num"><strong data-score>${num3(res.scores ? res.scores[app] : null)}</strong></td>
                ${scState.mode === 'final' ? `<td class="r"><input class="score-in" inputmode="decimal" data-c="FINAL" value="${e.own[app + ':FINAL'] != null ? e.own[app + ':FINAL'] : ''}" aria-label="Nilai akhir ${esc(e.athletes[0].name)}" ${e.status === 'dns' ? 'disabled' : ''}></td>` : ''}
                <td class="r num">${num3(res.total)}</td><td class="c"><span class="rank">${res.rank || '–'}</span>${res.medal ? ` <span class="medal ${res.medal}"></span>` : ''}</td>` : ''}
            </tr>`;
          }).join('')}</tbody></table></div>` : '<p class="empty">Belum ada atlet lunas di kategori ini.</p>'}
        ${!juri ? `<div class="sticky-actions"><button class="btn btn-ghost" id="refresh">Muat ulang nilai</button>
          <button class="btn ${D.category.scores_locked ? 'btn-ghost' : 'btn-dark'}" id="lock" ${D.category.results_published ? 'disabled' : ''}>${D.category.scores_locked ? 'Buka kunci nilai' : 'Kunci nilai'}</button>
          <a class="btn btn-primary" href="#/hasil?c=${D.category.id}">Lihat hasil & publikasi</a></div>` : '<div class="sticky-actions"><button class="btn btn-ghost" id="refresh">Muat ulang</button></div>'}
      </section>`;
      box.querySelectorAll('[data-app]').forEach((b) => b.onclick = () => { scState.app = b.dataset.app; load(); });
      box.querySelectorAll('input[name=md]').forEach((r) => r.onchange = () => { scState.mode = r.value; load(); });
      box.querySelector('#refresh').onclick = load;
      const lk = box.querySelector('#lock');
      if (lk) lk.onclick = async () => { try { await api('console_lock_scores', { p_category: D.category.id, p_lock: !D.category.scores_locked }); load(); } catch (e) { JO.toast(e.message, 'bad'); } };
      const inputs = [...box.querySelectorAll('.score-in')];
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
    v.innerHTML = `<h1>Hasil & medali</h1><p class="muted">Publikasikan hasil per kategori setelah UPP. Publikasi mengunci nilai; sertifikat dan tabel medali di situs ikut diperbarui.</p>
      <div class="tabs"><button data-t="cat" aria-selected="true">Hasil kategori</button><button data-t="medal" aria-selected="false">Tabel medali</button></div><div id="rbox"></div>`;
    const rbox = v.querySelector('#rbox');
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = () => { v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b))); b.dataset.t === 'cat' ? catView() : medalView(); });
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
        <p class="small muted">Aturan medali sementara: peringkat 1–${(c.medal_rule && c.medal_rule.places) || 3} per kategori (serba bisa). Aturan khusus dari Undangan (persentase, ambang nilai, batas per klub) menyusul.${c.exhibition ? ' Kategori eksibisi: medali tidak dihitung.' : ''}</p>
        ${incomplete ? `<p class="note warn small">${incomplete} atlet belum punya nilai di semua alat.</p>` : ''}
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">Per.</th><th>Atlet</th><th>Klub</th>${apps.length > 1 ? apps.map((a) => `<th class="r">${esc(a.code)}</th>`).join('') : ''}<th class="r">Total</th><th>Medali</th>${anyPri ? '<th class="c">Priangan</th>' : ''}</tr></thead><tbody>
          ${D.results.map((r) => `<tr><td class="c"><span class="rank">${r.rank || '–'}</span></td>
            <td>${r.athletes.map((a) => `${esc(a.name)} <span class="tiny muted">${esc(a.athlete_no)}</span>`).join('<br>')}</td><td class="small">${esc(r.club)}<br><span class="muted">${esc(r.region)}</span></td>
            ${apps.length > 1 ? apps.map((a) => `<td class="r num">${num3(r.scores[a.code])}</td>`).join('') : ''}
            <td class="r num"><strong>${num3(r.total)}</strong></td><td>${r.medal ? `<span class="medal ${r.medal}"></span> ${esc(JO.t('medal_' + r.medal))}` : ''}</td>
            ${anyPri ? `<td class="c">${r.priangan_rank ? r.priangan_rank + (r.priangan_medal ? ` <span class="medal ${r.priangan_medal}"></span>` : '') : ''}</td>` : ''}</tr>`).join('')}
        </tbody></table></div>
        <div class="sticky-actions">
          <button class="btn ${c.results_published ? 'btn-bad' : 'btn-primary'}" id="pub" ${c.results_published && !isSuper() ? 'disabled' : ''}>${c.results_published ? 'Tarik hasil dari situs' : 'Publikasikan hasil'}</button>
          <button class="btn btn-ghost" id="certs">Unduh semua sertifikat (PDF)</button>
          <a class="btn btn-ghost" href="#/nilai?c=${c.id}">Ke penilaian</a></div></section>`;
      box.querySelector('#pub').onclick = async () => {
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
            for (const a of r.athletes) {
              const cert = D.certificates.find((x) => x.entry_id === r.entry_id && x.athlete_id === a.id);
              doc = await JO.certificatePdf({ name: a.name, club: r.club, discipline: c.discipline, category: c.name_id, rank: r.rank, medal: r.medal,
                priangan_rank: r.priangan_rank, priangan_medal: r.priangan_medal, cert_code: cert ? cert.cert_code : '-', signatories: D.signatories }, doc);
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
        <button class="btn btn-ghost btn-sm" id="mx">Unduh Excel</button></div><div id="mt"></div>`;
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
      const tot = D.summary.reduce((a, s) => ({ expected: a.expected + s.expected, paid: a.paid + s.paid, fees: a.fees + s.fees_paid, pri: a.pri + s.priangan_paid, uc: a.uc + s.unique_paid }), { expected: 0, paid: 0, fees: 0, pri: 0, uc: 0 });
      v.querySelector('#sum').innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Disiplin</th><th class="r">Tagihan aktif</th><th class="r">Lunas</th><th class="r">Biaya lomba (lunas)</th><th class="r">Priangan (lunas)</th><th class="r">Kode unik (lunas)</th><th class="r">Pendaftaran lunas / terbuka</th></tr></thead><tbody>
        ${D.summary.map((s) => `<tr><td>${esc(s.name)}</td><td class="r num">${fmtRp(s.expected)}</td><td class="r num"><strong>${fmtRp(s.paid)}</strong></td><td class="r num">${fmtRp(s.fees_paid)}</td><td class="r num">${fmtRp(s.priangan_paid)}</td><td class="r num">${fmtRp(s.unique_paid)}</td><td class="r num">${s.count_paid} / ${s.count_open}</td></tr>`).join('')}
        <tr><td><strong>Total</strong></td><td class="r num"><strong>${fmtRp(tot.expected)}</strong></td><td class="r num"><strong>${fmtRp(tot.paid)}</strong></td><td class="r num">${fmtRp(tot.fees)}</td><td class="r num">${fmtRp(tot.pri)}</td><td class="r num">${fmtRp(tot.uc)}</td><td></td></tr></tbody></table></div>`;
      v.querySelector('#rows').innerHTML = D.rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Kode</th><th>Disiplin</th><th>Klub / pendaftar</th><th class="r">Biaya</th><th class="r">Priangan</th><th class="r">Unik</th><th class="r">Total</th><th>Status</th><th>Diverifikasi</th><th>Mutasi</th></tr></thead><tbody>
        ${D.rows.map((r) => `<tr class="click" data-id="${r.id}"><td class="code small">${esc(r.code)}<br><span class="tiny muted">${dt(r.created_at)}</span></td><td>${r.discipline}</td><td class="small">${esc(r.club)}<br><span class="muted">${esc(r.contact_name)}</span></td>
          <td class="r num">${fmtRp(r.base_amount)}</td><td class="r num">${fmtRp(r.priangan_amount)}</td><td class="r num">${r.unique_code}</td><td class="r num"><strong>${fmtRp(r.total_amount)}</strong></td>
          <td>${pill(r.status)}</td><td class="small">${esc(r.verified_by || '')}<br><span class="muted">${r.verified_at ? dt(r.verified_at) : ''}</span></td>
          <td class="small">${(r.mutations || []).map((m) => `${fmtRp(m.amount)} <span class="muted">${esc(m.match_status)}</span>`).join('<br>')}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada tagihan.</p>';
      v.querySelectorAll('#rows tr[data-id]').forEach((tr) => tr.onclick = () => { location.hash = '#/pendaftaran/' + tr.dataset.id; });
      v.querySelector('#muts').innerHTML = D.mutations.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th class="r">Nominal</th><th>Referensi</th><th>Status</th><th>Pendaftaran</th><th></th></tr></thead><tbody>
        ${D.mutations.map((m) => `<tr><td class="small">${m.trx_time ? dt(m.trx_time) : '–'}<br><span class="tiny muted">impor ${esc(m.batch || '')}</span></td><td class="r num">${fmtRp(m.amount)}</td><td class="small">${esc(m.reference || '')}<br><span class="muted">${esc(m.description || '')}</span></td>
          <td><span class="pill ${m.match_status === 'belum' ? 'warn' : m.match_status === 'abaikan' ? '' : 'ok'}">${esc(m.match_status)}</span></td>
          <td class="small">${m.submission_code ? `<a href="#/pendaftaran/${m.submission_id}">${esc(m.submission_code)}</a> ${ST[m.submission_status] || ''}` : ''}</td>
          <td class="r">${m.match_status === 'belum' ? `<button class="btn btn-ghost btn-sm" data-mm="${m.id}">Cocokkan</button> <button class="btn btn-ghost btn-sm" data-mi="${m.id}">Abaikan</button>` : `<button class="btn btn-ghost btn-sm" data-mr="${m.id}">Lepas</button>`}</td></tr>`).join('')}</tbody></table></div>` : '<p class="empty">Belum ada mutasi diimpor.</p>';
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
      ['code', 'Kode'], ['created_at', 'Tanggal daftar', (r) => dt(r.created_at)], ['discipline', 'Disiplin'], ['club', 'Klub'], ['contact_name', 'Penanggung jawab'], ['contact_phone', 'WA'], ['contact_email', 'Email'],
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
    v.innerHTML = `<h1>Klub</h1><p class="muted">Klub baru dari formulir pendaftaran ditandai "belum diverifikasi". Rapikan nama dan wilayahnya, atau gabungkan bila satu klub terdaftar dengan dua nama, agar tabel medali per klub akurat.</p>
      <div class="bar"><div class="field" style="flex:1"><label class="f" for="kq">Cari</label><input id="kq" type="search"></div><button class="btn btn-dark" id="kadd">Tambah klub</button></div><div id="kl"></div>`;
    const draw = (q) => {
      const s = (q || '').toLowerCase();
      const list = rows.filter((k) => !s || (k.name + ' ' + (k.kab_kota || '')).toLowerCase().includes(s));
      v.querySelector('#kl').innerHTML = `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Jenis</th><th>Kab/kota</th><th>Provinsi</th><th class="r">Atlet</th><th></th></tr></thead><tbody>
        ${list.map((k) => `<tr><td>${esc(k.name)}${k.verified ? '' : ' <span class="pill warn">belum diverifikasi</span>'}${k.merged_into ? ` <span class="pill">digabung ke ${esc(k.merged_into_name)}</span>` : ''}</td><td class="small">${esc(k.kind)}</td>
          <td class="small">${esc(k.kab_kota || '')}</td><td class="small">${esc(k.province || k.country)}</td><td class="r">${k.athletes}</td>
          <td class="r">${k.merged_into ? '' : `<button class="btn btn-ghost btn-sm" data-ke="${k.id}">Ubah</button>${isSuper() ? ` <button class="btn btn-ghost btn-sm" data-km="${k.id}">Gabungkan</button>` : ''}`}</td></tr>`).join('')}</tbody></table></div>`;
      v.querySelectorAll('[data-ke]').forEach((b) => b.onclick = () => edit(rows.find((k) => k.id === b.dataset.ke)));
      v.querySelectorAll('[data-km]').forEach((b) => b.onclick = () => merge(rows.find((k) => k.id === b.dataset.km)));
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
  //  KODE AKSES
  // =====================================================================
  async function pageAccess(v) {
    const rows = await api('console_staff_list');
    v.innerHTML = `<h1>Kode akses</h1><p class="muted">Satu kode untuk satu orang. Kode hanya ditampilkan sekali saat dibuat; bila hilang, buat kode baru (kode lama otomatis tidak berlaku).</p>
      <div class="bar"><button class="btn btn-primary" id="new">Buat kode baru</button></div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Nama</th><th>Peran</th><th>Disiplin</th><th>Batasan juri</th><th>Kode</th><th>Terakhir masuk</th><th></th></tr></thead><tbody>
      ${rows.map((s) => `<tr><td>${esc(s.name)}${s.active ? '' : ' <span class="pill bad">nonaktif</span>'}${s.note ? `<br><span class="tiny muted">${esc(s.note)}</span>` : ''}</td>
        <td>${ROLE[s.role]}</td><td>${s.discipline ? DN[s.discipline] : 'Semua'}</td>
        <td class="small">${s.role === 'juri' ? `${s.apparatus ? 'Alat: ' + s.apparatus.join(', ') : 'Semua alat'}<br>${s.components ? 'Komponen: ' + s.components.join(', ') : 'Semua komponen'}` : ''}</td>
        <td class="code small">…${esc(s.code_hint || '')}</td><td class="small">${s.last_login_at ? dt(s.last_login_at) : 'Belum pernah'}</td>
        <td class="r">${s.role === 'owner' || (s.role === 'superadmin' && ME.role !== 'owner') ? '' : `
          <button class="btn btn-ghost btn-sm" data-edit="${s.id}">Ubah</button>
          <button class="btn btn-ghost btn-sm" data-rc="${s.id}">Kode baru</button>
          <button class="btn ${s.active ? 'btn-bad' : 'btn-ok'} btn-sm" data-act="${s.id}">${s.active ? 'Nonaktifkan' : 'Aktifkan'}</button>`}</td></tr>`).join('')}</tbody></table></div>`;
    const form = (s) => `<div class="field"><label class="f">Nama pemegang kode</label><input id="sn" value="${esc(s ? s.name : '')}" placeholder="Mis. Vicy Ayu"></div>
      ${s ? '' : `<div class="field"><label class="f">Peran</label><select id="sr">
        <option value="admin">Admin / verifikator (verifikasi bayar, dokumen, start list, hasil)</option>
        <option value="juri">Juri (input nilai saja)</option>
        ${ME.role === 'owner' ? '<option value="superadmin">Superadmin (semua, termasuk ledger)</option>' : ''}</select></div>`}
      <div class="field"><label class="f">Disiplin</label><select id="sd"><option value="">Semua disiplin</option>${DISCS.map((d) => `<option value="${d}" ${s && s.discipline === d ? 'selected' : ''}>${DN[d]}</option>`).join('')}</select></div>
      <div id="jopt"><div class="field"><span class="f">Batasi komponen (juri)</span><div class="row">${['D', 'E', 'A', 'PEN'].map((c) => `<label class="check" style="padding:2px 10px 2px 0"><input type="checkbox" data-comp="${c}" ${s && s.components && s.components.includes(c) ? 'checked' : ''}>${c}</label>`).join('')}</div><div class="f-hint">Kosongkan untuk semua komponen.</div></div>
        <div class="field"><label class="f">Batasi alat (juri, pisahkan dengan koma)</label><input id="sa" placeholder="Mis. VT, UB" value="${esc(s && s.apparatus ? s.apparatus.join(', ') : '')}"><div class="f-hint">Kode alat: MAG FX PH SR VT PB HB; WAG VT UB BB FX; Ritmik FH ROPE HOOP BALL CLUBS RIBBON; Aerobik RTN. Kosongkan untuk semua alat.</div></div></div>
      <div class="field"><label class="f">Catatan</label><input id="snote" value="${esc(s ? s.note || '' : '')}" placeholder="Mis. Juri E panel 1"></div>`;
    const collect = (d) => ({ name: d.querySelector('#sn').value, role: d.querySelector('#sr') ? d.querySelector('#sr').value : undefined, discipline: d.querySelector('#sd').value,
      components: [...d.querySelectorAll('[data-comp]:checked')].map((x) => x.dataset.comp), apparatus: d.querySelector('#sa').value.split(',').map((x) => x.trim().toUpperCase()).filter(Boolean), note: d.querySelector('#snote').value });
    const showCode = (name, code) => dialog({ title: 'Kode akses untuk ' + name, ok: null, cancel: 'Selesai',
      body: `<div class="codebox">${esc(code)}</div><p class="small" style="margin-top:12px">Salin dan kirim secara pribadi. Kode ini tidak bisa ditampilkan lagi.</p>
        <div class="actions"><button type="button" class="btn btn-dark btn-sm" id="cp">Salin kode</button>
        <a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(`Kode akses konsol panitia Jabar Open 2026 untuk ${name}: ${code}\nMasuk di ${JO.siteUrl()}panitia/\nJangan bagikan kode ini.`)}">Kirim lewat WhatsApp</a></div>` })
      .then(() => pageAccess(v)) && setTimeout(() => { const cp = document.getElementById('cp'); if (cp) cp.onclick = () => navigator.clipboard.writeText(code).then(() => JO.toast('Kode disalin.')); }, 50);
    v.querySelector('#new').onclick = async () => {
      const r = await dialog({ title: 'Buat kode baru', ok: 'Buat kode', body: form(null), onOk: async (d) => api('console_staff_create', { p: collect(d) }) });
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
    v.querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
      const s = rows.find((x) => x.id === b.dataset.act);
      try { await api('console_staff_update', { p_id: s.id, p: { active: !s.active } }); pageAccess(v); } catch (e) { JO.toast(e.message, 'bad'); }
    });
  }

  // =====================================================================
  //  PENGATURAN
  // =====================================================================
  async function pageSettings(v) {
    const D = await api('console_settings');
    const S = D.settings;
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
          <div class="pay" style="grid-template-columns:180px 1fr"><div class="qris">${S.qris_image_url ? `<img src="${esc(S.qris_image_url)}" alt="QRIS">` : '<p class="small muted" style="margin:8px">Belum ada</p>'}</div>
          <div><input type="file" id="qf" accept="image/png,image/jpeg,image/webp"><div class="field" style="margin-top:12px"><label class="f">Nama merchant</label><input data-s="qris_merchant" value="${esc(val('qris_merchant'))}"></div>
          <div class="field"><label class="f">Catatan pembayaran</label><textarea data-s="payment_note">${esc(val('payment_note'))}</textarea></div></div></div></section>
        <section class="card"><h2>Pendaftaran</h2>
          <label class="check"><input type="checkbox" data-sb="registration_open" ${S.registration_open ? 'checked' : ''}>Pendaftaran dibuka</label>
          <div class="grid-2"><div class="field"><label class="f">Batas pendaftaran (WIB)</label><input id="rd" type="datetime-local" value="${dlLocal}"></div>
          <div class="field"><label class="f">Teks batas pembayaran</label><input data-s="payment_deadline_label" value="${esc(val('payment_deadline_label'))}"></div>
          <div class="field"><label class="f">Biaya Priangan per entri (Rp)</label><input data-sn="priangan_fee" type="number" value="${val('priangan_fee')}"></div>
          <div class="field"><label class="f">Maks. atlet per pendaftaran</label><input data-sn="max_athletes" type="number" value="${val('max_athletes')}"></div>
          <div class="field"><label class="f">Batas nominal QRIS (Rp)</label><input data-sn="qris_cap" type="number" value="${val('qris_cap')}"></div>
          <div class="field"><label class="f">Email kontak publik</label><input data-s="contact_email" value="${esc(val('contact_email'))}"></div></div>
          <label class="check"><input type="checkbox" data-sb="email_guardians" ${S.email_guardians ? 'checked' : ''}>Kirim email e-ticket juga ke orang tua/wali</label></section>
        <section class="card"><h2>Penanda tangan sertifikat</h2>
          ${[0, 1].map((i) => `<div class="grid-2"><div class="field"><label class="f">Nama ${i + 1}</label><input data-sig="${i}" data-f="name" value="${esc(sig[i] ? sig[i].name : '')}"></div>
            <div class="field"><label class="f">Jabatan ${i + 1}</label><input data-sig="${i}" data-f="title" value="${esc(sig[i] ? sig[i].title : '')}"></div></div>`).join('')}</section>
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
      </div></div>`;
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
        const sg = [0, 1].map((i) => ({ name: v.querySelector(`[data-sig="${i}"][data-f=name]`).value.trim(), title: v.querySelector(`[data-sig="${i}"][data-f=title]`).value.trim() })).filter((x) => x.name);
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
