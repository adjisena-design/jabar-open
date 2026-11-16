/* =====================================================================
   Jabar Open 2026 — Public Live View
   live.html                 : daftar layar yang sedang tayang
   live.html?layar=ID        : satu layar (publik)
   live.html?layar=ID&k=KEY  : layar TV venue (prioritas; tetap jalan saat publik dijeda)
   &tv=1                     : tanpa bilah atas (layar penuh untuk TV)
   Pembaruan: sinyal Supabase Realtime "jo-live" + polling cadangan.
   ===================================================================== */
(function () {
  'use strict';
  const C = window.JO_CONFIG;
  const sb = window.supabase.createClient(C.supabaseUrl, C.supabaseKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const app = document.getElementById('app');
  const q = new URLSearchParams(location.search);
  const SCREEN = q.get('layar') ? Number(q.get('layar')) : null;
  const KEY = q.get('k') || null;
  const TV = q.get('tv') === '1';
  const VENUE = !!KEY;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const f3 = (v) => (v == null ? '–' : Number(v).toFixed(3));
  const f1 = (v) => (v == null ? '–' : (Math.round(Number(v) * 1000) / 1000).toFixed(Number(v) % 1 === 0 ? 1 : Math.min(3, String(Math.round(Number(v) * 1000) / 1000).split('.')[1].length)));
  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };
  const DUMMY_TXT = 'SIMULASI PANITIA SEDANG DILAKSANAKAN — BUKAN NILAI RESMI';

  async function rpc(fn, args) {
    const r = await sb.rpc(fn, args || {});
    if (r.error) throw new Error(r.error.message);
    return r.data;
  }

  // ---------------- sinyal realtime ----------------
  let onTick = () => {};
  sb.channel('jo-live', { config: { broadcast: { self: false } } })
    .on('broadcast', { event: 'tick' }, (m) => onTick(m && m.payload ? m.payload : {}))
    .subscribe();

  // =====================================================================
  //  INDEKS
  // =====================================================================
  async function index() {
    const draw = async () => {
      let D;
      try { D = await rpc('public_live_index'); } catch (e) { app.innerHTML = `<div class="lv-msg">Gagal memuat: ${esc(e.message)}</div>`; return; }
      const real = D.screens.filter((s) => s.mode === 'real');
      const dmy = D.screens.filter((s) => s.mode === 'dummy');
      const card = (s) => `<a class="lv-card ${s.mode}" href="?layar=${s.id}"><b>${esc(s.name)}</b><span>${esc(s.category || '')}${s.discipline ? ' · ' + esc(DN[s.discipline] || s.discipline) : ''}</span></a>`;
      app.innerHTML = `<div class="lv-idx">
        <div class="brand"><img src="assets/img/brand/jabar-open-white.webp" alt="Jabar Open 2026" width="600" height="409"></div>
        <h1>Public Live View</h1>
        <p>Nilai langsung dari Gymnasium Arcamanik, Bandung. Nilai live belum resmi; hasil resmi tampil di <a href="hasil.html">halaman Hasil</a> setelah dikonfirmasi Technical Delegate.</p>
        ${D.public_on ? '' : '<p class="lv-card" style="border-color:var(--gold)">Tayangan publik sedang dijeda sementara. Silakan coba lagi beberapa saat lagi.</p>'}
        <h2>Sedang tayang</h2>
        ${real.length ? `<div class="lv-cards">${real.map(card).join('')}</div>` : '<p>Belum ada pertandingan yang sedang tayang.</p>'}
        ${D.dummy_on && dmy.length ? `<h2 style="color:#ff8a80">DUMMY Simulation</h2><p>${DUMMY_TXT}. Nama atlet bertanda DUMMY TEST.</p><div class="lv-cards">${dmy.map(card).join('')}</div>` : ''}
        <p class="lv-note"><a href="index.html">Kembali ke situs Jabar Open 2026</a></p></div>`;
    };
    let t = null;
    onTick = () => { clearTimeout(t); t = setTimeout(draw, 500 + Math.random() * 2500); };
    await draw();
    setInterval(draw, 60000);
  }

  // =====================================================================
  //  SATU LAYAR
  // =====================================================================
  const ST = { feed: null, boards: [], bi: 0, pi: 0, flash: null, lastSeen: {}, okAt: 0, timer: null, photos: {} };

  function ranked(rows, board) {
    const pick = (r) => (board.kind === 'aa' ? r : r.apps && r.apps[board.code]);
    const L = rows.map((r) => ({ r, s: pick(r) })).filter((x) => x.s && x.s.total != null)
      .map((x) => ({ id: x.r.id, name: x.r.name, club: x.r.club, photo: x.r.photo, d: x.s.d, e: x.s.e, a: x.s.a, pen: x.s.pen, total: Number(x.s.total) }));
    L.sort((a, b) => b.total - a.total || String(a.name).localeCompare(String(b.name)));
    L.forEach((x, i) => { x.rank = i && x.total === L[i - 1].total ? L[i - 1].rank : i + 1; });
    return L;
  }
  function buildBoards() {
    const F = ST.feed; const s = F.screen; const apps = F.apparatus || [];
    if (apps.length <= 1) return [apps[0] ? { kind: 'app', code: apps[0].code, name: apps[0].name, single: true } : { kind: 'aa' }];
    if (s.view === 'app') { const a = apps.find((x) => x.code === s.apparatus) || apps[0]; return [{ kind: 'app', code: a.code, name: a.name }]; }
    if (s.view === 'rotate') {
      const scored = apps.filter((a) => F.rows.some((r) => r.apps && r.apps[a.code]));
      return [{ kind: 'aa' }, ...scored.map((a) => ({ kind: 'app', code: a.code, name: a.name }))];
    }
    return [{ kind: 'aa' }];
  }
  function pagesOf(n) {
    const s = ST.feed.screen;
    if (s.layout === 3) return [[0, Math.min(3, n)]];
    const out = [[0, Math.min(n, s.first_n)]]; let a = s.first_n;
    while (a < n) { out.push([a, Math.min(n, a + s.next_n)]); a += s.next_n; }
    return out;
  }
  function geom(layout) {
    if (layout === 2) return { x: 60, y: 186, w: 1020, h: 780, cam: [[1110, 186, 750, 780]] };
    if (layout === 3) return { x: 60, y: 650, w: 1800, h: 320, cam: [[60, 176, 890, 456], [970, 176, 890, 456]] };
    return { x: 60, y: 186, w: 1800, h: 780, cam: [] };
  }
  function embed(url) {
    if (!url) return '';
    let id = null;
    const m = url.match(/(?:youtu\.be\/|youtube\.com\/(?:live\/|watch\?v=|embed\/|shorts\/))([A-Za-z0-9_-]{6,})/);
    if (m) id = m[1];
    const src = id ? `https://www.youtube.com/embed/${id}?autoplay=1&mute=1&playsinline=1&controls=0&rel=0&modestbranding=1` : url;
    if (!/^https:\/\//.test(src)) return '';
    return `<iframe src="${esc(src)}" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>`;
  }

  // pas foto: tautan bertanda tangan, disimpan 50 menit
  async function photoUrls(paths) {
    const now = Date.now();
    const need = [...new Set(paths.filter(Boolean))].filter((p) => !ST.photos[p] || ST.photos[p].exp < now);
    if (!need.length) return;
    try {
      const { data } = await sb.storage.from('dokumen').createSignedUrls(need, 3600);
      (data || []).forEach((x) => { if (x.signedUrl) ST.photos[x.path] = { url: x.signedUrl, exp: now + 50 * 60000 }; else ST.photos[x.path] = { url: null, exp: now + 10 * 60000 }; });
    } catch (e) { need.forEach((p) => { ST.photos[p] = { url: null, exp: now + 5 * 60000 }; }); }
  }

  function shell() {
    app.innerHTML = `${TV ? '' : `<div class="lv-bar"><a href="live.html">← Semua layar</a><span class="sp"></span><span id="pubnote"></span><button type="button" id="fs">Layar penuh</button></div>`}
      <div class="lv-wrap ${TV ? '' : 'withbar'}" id="wrap"><div class="stage" id="stage"></div></div>`;
    const fit = () => { const w = document.getElementById('wrap'); const s = Math.min(w.clientWidth / 1920, w.clientHeight / 1080); document.getElementById('stage').style.transform = `scale(${s})`; };
    addEventListener('resize', fit); fit();
    const fs = document.getElementById('fs');
    if (fs) fs.onclick = () => { const el = document.documentElement; (el.requestFullscreen || el.webkitRequestFullscreen || (() => {})).call(el); };
    if (TV) document.addEventListener('dblclick', () => { const el = document.documentElement; if (!document.fullscreenElement && el.requestFullscreen) el.requestFullscreen(); });
  }

  let camKey = '';
  function renderStatic() {
    const F = ST.feed; const s = F.screen; const st = document.getElementById('stage');
    const g = geom(s.layout);
    const key = s.layout + '|' + (s.cam1 || '') + '|' + (s.cam2 || '');
    if (key !== camKey) {
      camKey = key;
      st.innerHTML = `<div class="hd"><img src="assets/img/brand/jabar-open-white.webp" alt="" width="600" height="409"><div><div class="t1">Jabar Open 2026 · Live Score</div><div class="t2" id="ttl"></div></div>
          <div class="right"><div class="pg" id="pg"></div><div class="live"><span class="dot" id="dot"></span>LIVE</div></div></div>
        ${s.mode === 'dummy' ? `<div class="dmy">${DUMMY_TXT}</div>` : ''}
        <div class="board" id="board" style="left:${g.x}px;top:${g.y}px;width:${g.w}px;height:${g.h}px"><div class="cols" id="cols"></div><div class="rows" id="rows"></div></div>
        ${g.cam.map((c, i) => `<div class="cam" style="left:${c[0]}px;top:${c[1]}px;width:${c[2]}px;height:${c[3]}px">${embed(i ? s.cam2 : s.cam1) || 'Kamera ' + (i + 1)}</div>`).join('')}
        <div class="prog" id="prog"></div><div class="foot" id="foot"></div>
        <div class="ticker" id="tkb"><div class="tk" id="tk"></div></div>`;
    }
    const tk = document.getElementById('tk');
    const txt = F.ticker || `Jabar Open 2026 · Gymnasium Arcamanik, Bandung · 12–20 Desember 2026 · Nilai live belum resmi; hasil resmi di gimnastikjabaropen2026.com/hasil.html`;
    if (tk.dataset.t !== txt) { tk.dataset.t = txt; tk.textContent = txt + '     ·     ' + txt; tk.parentNode.style.setProperty('--tk', Math.max(20, Math.round(txt.length / 4)) + 's'); }
  }

  function renderBoard(animate) {
    const F = ST.feed; const s = F.screen; const st = document.getElementById('stage');
    if (!ST.boards.length) ST.boards = buildBoards();
    if (ST.bi >= ST.boards.length) ST.bi = 0;
    const b = ST.boards[ST.bi];
    st.classList.toggle('app', b.kind === 'app' && !b.single);
    const L = ranked(F.rows, b);
    const P = pagesOf(L.length);
    if (ST.pi >= P.length) ST.pi = 0;
    const [from, to] = P[ST.pi] || [0, 0];
    const g = geom(s.layout);
    const per = s.layout === 3 ? 3 : (ST.pi === 0 ? s.first_n : s.next_n);
    const rowH = Math.min(150, Math.floor((g.h - 40) / per));
    const gap = Math.max(6, Math.round(rowH * 0.1));
    const fs = Math.round(rowH * 0.36), ph = Math.round(rowH * 0.8);
    const narrow = g.w < 1300;
    const withA = L.some((x) => x.a != null);
    const num = narrow ? '100px' : '150px';
    const tpl = `${Math.round(rowH * 0.8)}px ${Math.round(ph * 0.8) + 16}px 1fr ${num} ${narrow ? '120px' : '170px'}${withA ? ' ' + num : ''} ${narrow ? '120px' : '160px'} ${narrow ? '150px' : '210px'}`;
    const c = F.category || {};
    document.getElementById('ttl').innerHTML = `${esc(c.name || F.screen.name)} · <em>${b.kind === 'aa' ? 'Serba Bisa' : esc(b.name)}</em>`;
    document.getElementById('pg').textContent = L.length ? `(${to}/${c.competitors || L.length})` : '';
    document.getElementById('cols').style.gridTemplateColumns = tpl;
    document.getElementById('cols').style.fontSize = (narrow ? 16 : 20) + 'px';
    document.getElementById('cols').innerHTML = `<div>#</div><div></div><div>Atlet</div><div style="text-align:right">D</div><div style="text-align:right">${b.kind === 'aa' ? 'E' : 'E (rata²)'}</div>${withA ? '<div style="text-align:right">A</div>' : ''}<div style="text-align:right">Pen</div><div style="text-align:right">Total</div>`;
    const rowsEl = document.getElementById('rows');
    const before = {}; rowsEl.querySelectorAll('.row').forEach((r) => { before[r.dataset.id] = r.style.transform; });
    rowsEl.innerHTML = L.slice(from, to).map((x, i) => {
      const p = x.photo && ST.photos[x.photo] && ST.photos[x.photo].url;
      const ini = String(x.name).replace(/ – DUMMY TEST/g, '').split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
      return `<div class="row${x.rank === 1 ? ' r1' : ''}${ST.flash === x.id ? ' flash' : ''}" data-id="${x.id}" style="height:${rowH - gap}px;transform:translateY(${i * rowH}px);grid-template-columns:${tpl}">
        <div class="rk" style="font-size:${Math.round(fs * 1.15)}px">${x.rank}</div>
        <div class="ph" style="width:${Math.round(ph * 0.8)}px;height:${ph}px;font-size:${Math.round(fs * 0.6)}px;${p ? `background-image:url('${esc(p)}')` : ''}">${p ? '' : esc(ini)}</div>
        <div class="nm"><div class="n" style="font-size:${fs}px">${esc(x.name)}</div><div class="c" style="font-size:${Math.round(fs * 0.55)}px">${esc(x.club || '')}</div></div>
        <div class="sc" style="font-size:${Math.round(fs * 0.85)}px">${f3(x.d)}</div>
        <div class="sc" style="font-size:${Math.round(fs * 0.85)}px">${f3(x.e)}</div>
        ${withA ? `<div class="sc" style="font-size:${Math.round(fs * 0.85)}px">${f3(x.a)}</div>` : ''}
        <div class="sc" style="font-size:${Math.round(fs * 0.85)}px">${x.pen ? '-' + f3(x.pen) : '0.000'}</div>
        <div class="sc tot" style="font-size:${Math.round(fs * 1.05)}px">${f3(x.total)}</div></div>`;
    }).join('') || `<div class="empty-b">${F.rows.length ? 'Menunggu nilai alat ini' : 'Menunggu nilai pertama'}</div>`;
    if (animate) rowsEl.querySelectorAll('.row').forEach((r) => {
      const old = before[r.dataset.id];
      if (old && old !== r.style.transform) { const nu = r.style.transform; r.style.transition = 'none'; r.style.transform = old; void r.offsetHeight; r.style.transition = ''; r.style.transform = nu; }
      else if (!old) { r.style.opacity = 0; requestAnimationFrame(() => { r.style.opacity = 1; }); }
    });
    document.getElementById('foot').textContent = `${F.rows.length} dari ${c.competitors || '–'} atlet sudah dinilai${P.length > 1 ? ` · slide ${ST.pi + 1}/${P.length}` : ''}`;
    const pr = document.getElementById('prog'); pr.style.transition = 'none'; pr.style.width = '0';
    const multi = P.length > 1 || ST.boards.length > 1;
    if (multi) requestAnimationFrame(() => { pr.style.transition = `width ${s.page_secs}s linear`; pr.style.width = '100%'; });
    return { pages: P.length, list: L };
  }

  function schedulePage() {
    clearTimeout(ST.timer);
    ST.timer = setTimeout(() => {
      const r = renderBoardInfo();
      ST.flash = null;
      if (ST.pi + 1 < r.pages) ST.pi++;
      else { ST.pi = 0; ST.bi = (ST.bi + 1) % Math.max(1, ST.boards.length); }
      renderBoard(false); schedulePage();
    }, (ST.feed ? ST.feed.screen.page_secs : 8) * 1000);
  }
  function renderBoardInfo() { const b = ST.boards[ST.bi]; const L = ranked(ST.feed.rows, b); return { pages: pagesOf(L.length).length }; }

  // nilai baru terverifikasi: lompat ke papan & halaman atlet itu, lalu sorot
  function findNew(prev, F) {
    let best = null;
    F.rows.forEach((r) => Object.entries(r.apps || {}).forEach(([code, a]) => {
      const k = r.id + ':' + code; const at = Number(a.at || 0);
      if (prev && (!prev[k] || prev[k] < at) && (!best || at > best.at)) best = { id: r.id, code, at };
    }));
    return best;
  }

  async function screen() {
    shell();
    let first = true, fetching = false, again = false;
    const pull = async () => {
      if (fetching) { again = true; return; }
      fetching = true;
      try {
        const F = await rpc('public_live_feed', { p_screen: SCREEN, p_key: KEY });
        ST.okAt = Date.now();
        const st = document.getElementById('stage');
        if (F.missing || F.paused || F.off) {
          camKey = ''; clearTimeout(ST.timer); ST.feed = null;
          st.className = 'stage';
          st.innerHTML = `<div class="empty-b">${F.missing ? 'Layar tidak ditemukan.' : F.paused ? 'Tayangan publik sedang dijeda sementara.<br>Silakan coba lagi beberapa saat lagi.' : 'Layar ini sedang tidak tayang.'}</div>`;
          return;
        }
        const prev = ST.lastSeen;
        const seen = {}; F.rows.forEach((r) => Object.entries(r.apps || {}).forEach(([code, a]) => { seen[r.id + ':' + code] = Number(a.at || 0); }));
        const nw = first ? null : findNew(prev, F);
        ST.lastSeen = seen;
        const cfgChanged = !ST.feed || JSON.stringify(ST.feed.screen) !== JSON.stringify(F.screen) || JSON.stringify(ST.feed.apparatus) !== JSON.stringify(F.apparatus);
        ST.feed = F;
        const nb = buildBoards();
        if (cfgChanged || nb.length !== ST.boards.length) { ST.boards = nb; if (cfgChanged) { ST.bi = 0; ST.pi = 0; } }
        await photoUrls(F.rows.map((r) => r.photo));
        renderStatic();
        if (nw) {
          ST.flash = nw.id;
          const bi = ST.boards.findIndex((b) => (b.kind === 'app' && b.code === nw.code));
          if (ST.boards[ST.bi] && !(ST.boards[ST.bi].kind === 'aa' || ST.boards[ST.bi].code === nw.code)) ST.bi = bi >= 0 ? bi : 0;
          const L = ranked(F.rows, ST.boards[ST.bi]);
          const idx = L.findIndex((x) => x.id === nw.id);
          const P = pagesOf(L.length);
          const pi = P.findIndex(([a, b2]) => idx >= a && idx < b2);
          const samePage = pi === ST.pi;
          if (pi >= 0) ST.pi = pi;
          renderBoard(samePage); ST.flash = null; schedulePage();
        } else {
          renderBoard(!first); if (first || cfgChanged) schedulePage();
        }
        first = false;
      } catch (e) {
        if (first) { document.getElementById('stage').innerHTML = `<div class="empty-b">Gagal memuat: ${esc(e.message)}</div>`; }
      } finally {
        fetching = false;
        const dot = document.getElementById('dot'); if (dot) dot.classList.toggle('stale', Date.now() - ST.okAt > 30000);
        if (again) { again = false; pull(); }
      }
    };
    // venue: segera; publik: diberi jeda acak agar server tidak dibanjiri bersamaan
    let t = null;
    onTick = () => { clearTimeout(t); t = setTimeout(pull, VENUE ? 0 : 300 + Math.random() * 2200); };
    await pull();
    setInterval(pull, VENUE ? 10000 : 20000);
    setInterval(() => { const dot = document.getElementById('dot'); if (dot) dot.classList.toggle('stale', Date.now() - ST.okAt > 30000); }, 5000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) pull(); });
  }

  if (SCREEN) screen(); else index();
})();
