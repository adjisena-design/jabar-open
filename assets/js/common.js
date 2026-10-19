/* =====================================================================
   Jabar Open 2026 — fungsi bersama untuk semua halaman aplikasi
   Butuh: assets/js/config.js, assets/vendor/supabase-*.js
   ===================================================================== */
(function () {
  'use strict';
  const C = window.JO_CONFIG || {};
  const sb = window.supabase.createClient(C.supabaseUrl, C.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'jo26-auth', detectSessionInUrl: false },
  });

  // ---------------- bahasa ----------------
  let lang = 'id';
  try { lang = localStorage.getItem('jo26-lang') || 'id'; } catch (e) {}
  const dict = { id: {}, en: {} };
  const langListeners = [];

  function addDict(d) {
    for (const k of Object.keys(d)) {
      dict.id[k] = d[k][0];
      dict.en[k] = d[k][1] !== undefined ? d[k][1] : d[k][0];
    }
  }
  function t(key, vars) {
    let s = (dict[lang] && dict[lang][key]) || dict.id[key] || key;
    if (vars) for (const v of Object.keys(vars)) s = s.split('{' + v + '}').join(vars[v]);
    return s;
  }
  function applyI18n(root) {
    (root || document).querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
    (root || document).querySelectorAll('[data-i18n-html]').forEach((el) => { el.innerHTML = t(el.dataset.i18nHtml); });
    (root || document).querySelectorAll('[data-i18n-ph]').forEach((el) => { el.placeholder = t(el.dataset.i18nPh); });
    document.documentElement.lang = lang;
    document.querySelectorAll('.lang button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.lang === lang)));
  }
  function setLang(l) {
    lang = l === 'en' ? 'en' : 'id';
    try { localStorage.setItem('jo26-lang', lang); } catch (e) {}
    applyI18n();
    langListeners.forEach((fn) => fn(lang));
  }
  function onLang(fn) { langListeners.push(fn); }

  addDict({
    nav_home: ['Beranda', 'Home'], nav_register: ['Daftar', 'Register'], nav_status: ['Cek status', 'Check status'],
    nav_startlist: ['Start list', 'Start list'], nav_results: ['Hasil', 'Results'], nav_faq: ['FAQ', 'FAQ'],
    menu: ['Menu', 'Menu'],
    footer_org: ['Diselenggarakan oleh Gimnastik Indonesia (GI) Jawa Barat', 'Organised by Gimnastik Indonesia (GI) West Java'],
    footer_contact: ['Pertanyaan pendaftaran', 'Registration questions'],
    footer_sec: ['Sekretariat KONI & GI Jawa Barat', 'KONI & GI West Java secretariat'],
    footer_jury: ['Pendaftaran juri', 'Judge application'], footer_verify: ['Verifikasi sertifikat', 'Verify a certificate'], footer_console: ['Konsol panitia', 'Committee console'],
    loading: ['Memuat…', 'Loading…'],
    err_network: ['Tidak bisa terhubung ke server. Periksa koneksi internet lalu coba lagi.', 'Cannot reach the server. Check your connection and try again.'],
    err_session: ['Sesi browser tidak bisa dibuat. Muat ulang halaman. Jika berulang, coba beberapa menit lagi.', 'Could not start a browser session. Reload the page; if it keeps happening, try again in a few minutes.'],
    status_menunggu_pembayaran: ['Menunggu pembayaran', 'Awaiting payment'],
    status_menunggu_verifikasi: ['Menunggu verifikasi', 'Awaiting verification'],
    status_lunas: ['Lunas', 'Paid'],
    status_perlu_perbaikan: ['Perlu perbaikan', 'Needs attention'],
    status_dibatalkan: ['Dibatalkan', 'Cancelled'],
    medal_emas: ['Emas', 'Gold'], medal_perak: ['Perak', 'Silver'], medal_perunggu: ['Perunggu', 'Bronze'],
    gender_M: ['Putra', 'Male'], gender_F: ['Putri', 'Female'],
  });

  // ---------------- format ----------------
  const fmtRp = (n) => 'Rp' + Number(n || 0).toLocaleString('id-ID');
  function fmtDate(d, opts) {
    if (!d) return '';
    const dt = typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d) ? new Date(d + 'T00:00:00') : new Date(d);
    return dt.toLocaleDateString(lang === 'en' ? 'en-GB' : 'id-ID', opts || { day: 'numeric', month: 'long', year: 'numeric' });
  }
  function fmtDateTime(d) {
    if (!d) return '';
    return new Date(d).toLocaleString(lang === 'en' ? 'en-GB' : 'id-ID', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  const statusClass = { menunggu_pembayaran: 'warn', menunggu_verifikasi: 'info', lunas: 'ok', perlu_perbaikan: 'bad', dibatalkan: '' };
  function statusPill(s) { return `<span class="pill ${statusClass[s] || ''}">${esc(t('status_' + s))}</span>`; }
  function amountHtml(total, uniqueCode) {
    const s = Number(total).toLocaleString('id-ID');
    if (!uniqueCode) return `<span class="amount">Rp${s}</span>`;
    const tail = s.slice(-3);
    return `<span class="amount">Rp${s.slice(0, -3)}<span class="uc">${tail}</span></span>`;
  }
  function compAge(birth, year) { return (year || 2026) - Number(String(birth).slice(0, 4)); }
  function isMinor(birth) {
    if (!birth) return false;
    const b = new Date(birth + 'T00:00:00'); const now = new Date();
    const eighteen = new Date(b.getFullYear() + 18, b.getMonth(), b.getDate());
    return eighteen > now;
  }

  // ---------------- server ----------------
  async function ensureSession() {
    const { data } = await sb.auth.getSession();
    if (data && data.session) return data.session.user.id;
    const res = await sb.auth.signInAnonymously();
    if (res.error) {
      const e = new Error(t('err_session') + ' (' + res.error.message + ')');
      e.cause = res.error; throw e;
    }
    return res.data.user.id;
  }
  async function rpc(fn, args) {
    let res;
    try { res = await sb.rpc(fn, args || {}); }
    catch (e) { throw new Error(t('err_network')); }
    if (res.error) {
      const msg = res.error.message || '';
      const e = new Error(/Failed to fetch|NetworkError|fetch failed/i.test(msg) ? t('err_network') : msg);
      e.hint = res.error.hint; e.code = res.error.code; throw e;
    }
    return res.data;
  }

  // ---------------- unggah berkas ----------------
  const MAX_BYTES = 5 * 1024 * 1024;
  function loadImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('img')); };
      img.src = url;
    });
  }
  async function compressImage(file, maxSide, quality) {
    const img = await loadImage(file);
    const scale = Math.min(1, (maxSide || 1600) / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.round(img.naturalWidth * scale), h = Math.round(img.naturalHeight * scale);
    const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
    const ctx = cv.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h); ctx.drawImage(img, 0, 0, w, h);
    return await new Promise((r) => cv.toBlob(r, 'image/jpeg', quality || 0.82));
  }
  // pas foto kecil 3:4 (dipotong di tengah) sebagai data URL JPEG, untuk kartu atlet
  async function photoThumb(file) {
    const img = await loadImage(file);
    const W = 240, H = 320, sw = img.naturalWidth, sh = img.naturalHeight;
    const r = Math.max(W / sw, H / sh), dw = sw * r, dh = sh * r;
    const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
    const ctx = cv.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
    ctx.drawImage(img, (W - dw) / 2, (H - dh) / 2, dw, dh);
    return cv.toDataURL('image/jpeg', 0.8);
  }
  addDict({
    up_type: ['Format berkas harus JPG, PNG, WEBP, atau PDF.', 'File must be JPG, PNG, WEBP or PDF.'],
    up_size: ['Ukuran berkas maksimal 5 MB.', 'Maximum file size is 5 MB.'],
    up_fail: ['Unggah gagal: {m}', 'Upload failed: {m}'],
  });
  async function uploadFile(bucket, file) {
    const uid = await ensureSession();
    let blob = file, type = file.type, ext;
    if (/^image\/(jpeg|png|webp|heic|heif)$/i.test(type) || /\.(jpe?g|png|webp|heic)$/i.test(file.name)) {
      try { blob = await compressImage(file, 1800, 0.82); type = 'image/jpeg'; ext = 'jpg'; }
      catch (e) { if (!/^image\/(jpeg|png|webp)$/.test(type)) throw new Error(t('up_type')); ext = type.split('/')[1].replace('jpeg', 'jpg'); }
    } else if (type === 'application/pdf' || /\.pdf$/i.test(file.name)) {
      type = 'application/pdf'; ext = 'pdf';
    } else {
      throw new Error(t('up_type'));
    }
    if (blob.size > MAX_BYTES) throw new Error(t('up_size'));
    const rand = Math.random().toString(36).slice(2, 8);
    const path = `${uid}/${Date.now().toString(36)}-${rand}.${ext}`;
    const buf = await blob.arrayBuffer();
    const { error } = await sb.storage.from(bucket).upload(path, buf, { contentType: type, upsert: false });
    if (error) throw new Error(t('up_fail', { m: error.message }));
    return { path, type, size: blob.size };
  }

  // ---------------- tampilan umum ----------------
  function toast(msg, kind) {
    const el = document.createElement('div');
    el.className = 'toast' + (kind === 'bad' ? ' bad' : '');
    el.setAttribute('role', kind === 'bad' ? 'alert' : 'status');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), kind === 'bad' ? 6000 : 3200);
  }
  function header(active) {
    const base = relRoot();
    const links = [['index.html', 'nav_home'], ['daftar.html', 'nav_register'], ['status.html', 'nav_status'], ['startlist.html', 'nav_startlist'], ['hasil.html', 'nav_results']];
    const h = document.createElement('header');
    h.className = 'topbar';
    h.innerHTML = `<div class="topbar-in">
      <a class="brand" href="${base}index.html"><img src="${base}assets/img/brand/jabar-open.webp" alt="" width="360" height="246"><span>Jabar Open 2026</span></a>
      <button class="menu-btn" type="button" aria-expanded="false" aria-controls="topnav" data-i18n="menu">Menu</button>
      <nav class="topnav" id="topnav">
        ${links.map(([href, key]) => `<a href="${base}${href}" data-i18n="${key}" ${active === href ? 'aria-current="page"' : ''}></a>`).join('')}
        <a href="${base}faq.html" data-i18n="nav_faq" data-faq-nav ${active === 'faq.html' ? 'aria-current="page"' : 'hidden'}></a>
        <span class="lang" role="group" aria-label="Bahasa / Language"><button type="button" data-lang="id">ID</button><button type="button" data-lang="en">EN</button></span>
      </nav></div>`;
    document.body.prepend(h);
    h.querySelector('.menu-btn').addEventListener('click', (e) => {
      const nav = h.querySelector('.topnav'); const open = nav.classList.toggle('open');
      e.currentTarget.setAttribute('aria-expanded', String(open));
    });
    h.querySelectorAll('.lang button').forEach((b) => b.addEventListener('click', () => setLang(b.dataset.lang)));
    // tautan FAQ hanya tampil bila sudah ada pertanyaan terbit
    if (active !== 'faq.html' && window.JOFaq) window.JOFaq.count().then((n) => { if (n > 0) h.querySelectorAll('[data-faq-nav]').forEach((a) => { a.hidden = false; }); }).catch(() => {});
  }
  function footer() {
    const base = relRoot();
    const f = document.createElement('footer');
    f.className = 'footer';
    f.innerHTML = `<div class="footer-in">
      <div class="logos"><img class="jo" src="${base}assets/img/brand/jabar-open.webp" alt="Jabar Open" width="360" height="246"><img src="${base}assets/img/logo-koni-gi.png" alt="KONI Jawa Barat dan Gimnastik Indonesia Jawa Barat" width="520" height="172"></div>
      <div><div data-i18n="footer_org"></div>
      <div><span data-i18n="footer_contact"></span>: <a href="mailto:jabaropen2026@gmail.com">jabaropen2026@gmail.com</a> · Instagram <a href="https://www.instagram.com/gimnastikjabar/" target="_blank" rel="noopener">@gimnastikjabar</a></div>
      <div><a href="${base}juri.html" data-i18n="footer_jury"></a> · <a href="${base}verifikasi.html" data-i18n="footer_verify"></a> · <a href="${base}panitia/" data-i18n="footer_console"></a></div>
      <address><span data-i18n="footer_sec"></span>: Jl. Padjajaran No. 37A, Pasir Kaliki, Kec. Cicendo, Kota Bandung 40171</address></div>
      </div>`;
    document.body.appendChild(f);
  }
  function relRoot() { return document.body.dataset.root || ''; }
  function qs(name) { return new URLSearchParams(location.search).get(name); }

  // ---------------- QR & PDF ----------------
  function siteUrl() { return (C.siteUrl || (location.origin + location.pathname.replace(/[^/]*$/, ''))).replace(/\/?$/, '/'); }
  function qrMatrix(text) {
    const q = window.qrcode(0, 'M'); q.addData(text); q.make();
    const n = q.getModuleCount(); const m = [];
    for (let r = 0; r < n; r++) { m.push([]); for (let c = 0; c < n; c++) m[r].push(q.isDark(r, c)); }
    return m;
  }
  function qrSvg(text, size) {
    const m = qrMatrix(text); const n = m.length; const q = 2; const s = size || 160;
    let rects = '';
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (m[r][c]) rects += `M${c + q},${r + q}h1v1h-1z`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n + 2 * q} ${n + 2 * q}" width="${s}" height="${s}" shape-rendering="crispEdges" role="img" aria-label="QR"><rect width="100%" height="100%" fill="#fff"/><path d="${rects}" fill="#13284a"/></svg>`;
  }
  function pdfQr(doc, text, x, y, size) {
    const m = qrMatrix(text); const n = m.length; const cell = size / n;
    doc.setFillColor(255, 255, 255); doc.rect(x - 1.5, y - 1.5, size + 3, size + 3, 'F');
    doc.setFillColor(19, 40, 74);
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (m[r][c]) doc.rect(x + c * cell, y + r * cell, cell + 0.02, cell + 0.02, 'F');
  }
  const imgCache = {};
  async function imgData(src) {
    if (imgCache[src]) return imgCache[src];
    const res = await fetch(src); const blob = await res.blob();
    const data = await new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(blob); });
    const dims = await new Promise((r) => { const i = new Image(); i.onload = () => r({ w: i.naturalWidth, h: i.naturalHeight }); i.src = data; });
    imgCache[src] = { data, ...dims };
    return imgCache[src];
  }
  const DISC_DATES = { MAG: '12–15 Desember 2026', WAG: '12–15 Desember 2026', RG: '16–18 Desember 2026', AER: '19–20 Desember 2026' };
  const DISC_NAME = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };

  // Athlete Identification Card (AIC) — kartu digital, ditunjukkan di venue (tidak perlu dicetak)
  async function ticketPdf(t_, docIn) {
    const { jsPDF } = window.jspdf;
    const doc = docIn || new jsPDF({ unit: 'mm', format: 'a5', orientation: 'portrait' });
    if (docIn) doc.addPage('a5', 'portrait');
    const W = 148;
    // logo putih langsung di atas pita navy (tanpa kotak putih): Jabar Open | GI Jawa Barat
    const logo = await imgData(relRoot() + 'assets/img/brand/jabar-open-white.png');
    const gi = await imgData(relRoot() + 'assets/img/brand/gi-jabar-white.png');
    doc.setFillColor(19, 40, 74); doc.rect(0, 0, W, 46, 'F');
    doc.setFillColor(228, 200, 125); doc.rect(0, 46, W, 2.2, 'F');
    const lh = 25, lw = lh * logo.w / logo.h; doc.addImage(logo.data, 'PNG', 11, 10.5, lw, lh, 'jo-logo-w', 'FAST');
    const dx = 11 + lw + 5; doc.setDrawColor(90, 115, 160); doc.setLineWidth(0.35); doc.line(dx, 12, dx, 34);
    const gw = 31, gh = gw * gi.h / gi.w; doc.addImage(gi.data, 'PNG', dx + 5, 23 - gh / 2, gw, gh, 'gi-logo-w', 'FAST');
    const tx = W - 10;
    doc.setTextColor(168, 191, 224); doc.setFont('helvetica', 'normal'); doc.setFontSize(7.6);
    doc.text('Athlete Identification Card (AIC)', tx, 15, { align: 'right' });
    doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(14);
    doc.text('Jabar Open 2026', tx, 22.5, { align: 'right' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.8);
    doc.text(DISC_NAME[t_.discipline] || t_.discipline, tx, 29, { align: 'right' });
    doc.text(DISC_DATES[t_.discipline] || '', tx, 34, { align: 'right' });

    // pas foto (3:4) di kanan
    const px = W - 12 - 33, py = 55, pw = 33, ph = 44;
    doc.setDrawColor(205, 214, 228); doc.setLineWidth(0.4); doc.rect(px - 0.6, py - 0.6, pw + 1.2, ph + 1.2);
    if (t_.photo) { try { doc.addImage(t_.photo, 'JPEG', px, py, pw, ph, undefined, 'FAST'); } catch (e) { /* lewati bila gagal */ } }
    else { doc.setFillColor(244, 246, 250); doc.rect(px, py, pw, ph, 'F'); doc.setFontSize(7); doc.setTextColor(140, 150, 170); doc.text('Pas foto', px + pw / 2, py + ph / 2, { align: 'center' }); }

    const tw = px - 12 - 6;
    doc.setTextColor(91, 107, 136); doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.text('Nomor atlet', 12, 60);
    doc.setTextColor(19, 40, 74); doc.setFont('helvetica', 'bold'); doc.setFontSize(34);
    doc.text(t_.athlete_no || '-', 12, 74);
    doc.setFontSize(14); const nameLines = doc.splitTextToSize(t_.name, tw); doc.text(nameLines, 12, 84);
    let y = 84 + nameLines.length * 6;
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.setTextColor(52, 71, 106);
    const clubL = doc.splitTextToSize(t_.club || 'Perorangan', tw); doc.text(clubL, 12, y); y = Math.max(y + clubL.length * 4.6 + 4, py + ph + 6);
    doc.setTextColor(91, 107, 136); doc.setFontSize(8.5); doc.text('Kategori', 12, y); y += 5;
    doc.setTextColor(19, 40, 74); doc.setFontSize(10.5);
    (t_.categories || []).forEach((c) => { const l = doc.splitTextToSize(c, W - 24); doc.text(l, 12, y); y += l.length * 5 + 1.5; });
    y += 2;
    if (t_.start) {
      doc.setTextColor(91, 107, 136); doc.setFontSize(8.5); doc.text('Jadwal tampil', 12, y); y += 5;
      doc.setTextColor(19, 40, 74); doc.setFontSize(10.5); doc.text(doc.splitTextToSize(t_.start, W - 24), 12, y);
    }
    // QR + status
    const qy = 144, qs_ = 34; pdfQr(doc, siteUrl() + 'verifikasi.html?c=' + t_.ticket_code, 12, qy, qs_);
    doc.setFillColor(230, 245, 236); doc.roundedRect(52, qy, 84, 13, 2, 2, 'F');
    doc.setTextColor(27, 127, 71); doc.setFont('helvetica', 'bold'); doc.setFontSize(12.5);
    doc.text('Lunas', 56, qy + 8.6);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(52, 71, 106);
    doc.text('Kode pendaftaran ' + t_.submission_code, 76, qy + 8.4);
    doc.setTextColor(91, 107, 136); doc.setFontSize(7.8);
    doc.text(doc.splitTextToSize('Kode verifikasi ' + t_.ticket_code + '. Panitia memindai QR ini; data dan pas foto atlet tampil di layar untuk dicocokkan.', 84), 52, qy + 19);
    doc.text(doc.splitTextToSize('Gymnasium Arcamanik, Jl. Pacuan Kuda No. 15b, Kota Bandung.', 84), 52, qy + 29);
    if (t_.bpjs_missing) {
      // tanda bagi panitia — BPJS Ketenagakerjaan belum diunggah saat pendaftaran
      doc.setFillColor(253, 243, 220); doc.setDrawColor(228, 200, 125); doc.roundedRect(12, 181, W - 24, 10, 2, 2, 'FD');
      doc.setTextColor(154, 98, 0); doc.setFont('helvetica', 'bold'); doc.setFontSize(8);
      doc.text('BPJS Ketenagakerjaan: BELUM DIUNGGAH', 15, 185.2);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(7.3);
      doc.text('Wajib dibawa ke meja panitia di venue sebelum bertanding.', 15, 188.8);
    }
    doc.setDrawColor(223, 228, 238); doc.setLineWidth(0.2); doc.line(12, 194, W - 12, 194);
    doc.setTextColor(91, 107, 136); doc.setFont('helvetica', 'normal'); doc.setFontSize(7.3);
    doc.text(doc.splitTextToSize('Tunjukkan AIC ini dalam bentuk digital (ponsel) di venue; tidak perlu dicetak. Tidak ada registrasi ulang; datang sesuai jadwal di Instagram @gimnastikjabar dan situs Jabar Open 2026.', W - 24), 12, 198);
    if (t_.registered_by) {
      doc.setFontSize(7); doc.setTextColor(120, 132, 155);
      doc.text('Didaftarkan oleh: ' + t_.registered_by, 12, 206);
    }
    return doc;
  }

  async function certificatePdf(c, docIn) {
    const { jsPDF } = window.jspdf;
    const doc = docIn || new jsPDF({ unit: 'mm', format: 'a4', orientation: 'landscape' });
    if (docIn) doc.addPage('a4', 'landscape');
    const W = 297, H = 210;
    const logo = await imgData(relRoot() + 'assets/img/logo-jabar-open.png');
    const org = await imgData(relRoot() + 'assets/img/logo-koni-gi.png');
    doc.setFillColor(19, 40, 74); doc.rect(0, 0, W, H, 'F');
    doc.setFillColor(255, 255, 255); doc.rect(9, 9, W - 18, H - 18, 'F');
    doc.setFillColor(228, 200, 125); doc.rect(9, 9, W - 18, 2.5, 'F');
    const lw = 46, lh = lw * logo.h / logo.w; doc.addImage(logo.data, 'PNG', 24, 22, lw, lh, 'jo-logo', 'FAST');
    const ow = 62, oh = ow * org.h / org.w; doc.addImage(org.data, 'PNG', W - 24 - ow, 26, ow, oh, 'jo-org', 'FAST');
    const winner = !!c.team || !!c.medal || !!c.mini || !!c.priangan_medal;
    doc.setTextColor(19, 40, 74); doc.setFont('helvetica', 'bold'); doc.setFontSize(34);
    doc.text('Sertifikat', W / 2, 62, { align: 'center' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(13); doc.setTextColor(91, 107, 136);
    doc.text(c.team ? 'Juara Beregu' : c.apparatus ? 'Juara Per Alat' : winner ? 'Pemenang' : 'Peserta', W / 2, 71, { align: 'center' });
    doc.setFontSize(11); doc.text('diberikan kepada', W / 2, 84, { align: 'center' });
    doc.setTextColor(19, 40, 74); doc.setFont('helvetica', 'bold'); doc.setFontSize(28);
    doc.text(c.name, W / 2, 98, { align: 'center' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(12); doc.setTextColor(52, 71, 106);
    doc.text(c.club || '', W / 2, 106, { align: 'center' });
    let line;
    const mName = { emas: 'Medali Emas', perak: 'Medali Perak', perunggu: 'Medali Perunggu' };
    const mRank = { emas: 1, perak: 2, perunggu: 3 };
    if (c.team) line = `sebagai Juara ${c.rank} Beregu`;
    else if (c.apparatus) line = `sebagai Juara ${mRank[c.medal]} ${c.apparatus} (${mName[c.medal]})`;
    else if (c.medal) line = `sebagai Juara ${c.rank} Serba Bisa (${mName[c.medal]})`;
    else if (c.mini) line = `meraih Peringkat ${c.rank} Serba Bisa`;
    else line = 'atas partisipasinya';
    doc.setFontSize(14); doc.setTextColor(19, 40, 74); doc.setFont('helvetica', 'bold');
    doc.text(line, W / 2, 119, { align: 'center' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(12); doc.setTextColor(52, 71, 106);
    doc.text(c.category, W / 2, 127, { align: 'center' });
    let yy = 134;
    if (c.priangan_rank) {
      const pl = c.priangan_medal ? `Kategori Priangan: Juara ${c.priangan_rank} (${mName[c.priangan_medal]})` : `Kategori Priangan: peringkat ${c.priangan_rank}`;
      doc.setTextColor(138, 106, 31); doc.text(pl, W / 2, yy, { align: 'center' }); yy += 7;
    }
    doc.setTextColor(91, 107, 136); doc.setFontSize(10.5);
    doc.text(`Jabar Open 2026, ${DISC_NAME[c.discipline] || ''}, Gymnasium Arcamanik Bandung, ${DISC_DATES[c.discipline] || 'Desember 2026'}`, W / 2, yy + 1, { align: 'center' });
    // tanda tangan
    const sig = c.signatories || [];
    const xs = [W / 2 - 62, W / 2 + 62];
    for (let i = 0; i < Math.min(2, sig.length); i++) {
      const s = sig[i];
      if (s.sig) {
        try {
          const im = await imgData(/^https?:/.test(s.sig) ? s.sig : relRoot() + s.sig);
          const sh = 24, sw = Math.min(56, sh * im.w / im.h);
          doc.addImage(im.data, 'PNG', xs[i] - sw / 2, 175 - sh, sw, sh, 'sig-' + i + '-' + s.sig.length, 'FAST');
        } catch (e) { /* tanda tangan gagal dimuat: lanjut tanpa gambar */ }
      }
      doc.setDrawColor(201, 209, 224); doc.line(xs[i] - 40, 176, xs[i] + 40, 176);
      doc.setTextColor(19, 40, 74); doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5);
      doc.text(s.name, xs[i], 182, { align: 'center' });
      doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(91, 107, 136);
      doc.text(s.title, xs[i], 187, { align: 'center' });
    }
    pdfQr(doc, siteUrl() + 'verifikasi.html?c=' + c.cert_code, 24, 160, 24);
    doc.setFontSize(7); doc.setTextColor(91, 107, 136);
    doc.text('Verifikasi: ' + c.cert_code, 24, 190);
    return doc;
  }

  // Nama orang, klub, tim: huruf pertama tiap kata kapital; huruf lain tetap seperti diketik
  // (kata kapital penuh seperti PPOP/DKI tidak berubah). Sama dengan jo.name_case di database.
  function nameCase(v) {
    return String(v || '').trim().replace(/\s+/g, ' ').replace(/(^|[\s\-(\/.])(\p{Ll})/gu, (m, a, b) => a + b.toUpperCase());
  }
  // pasang di formulir: rapikan saat kolom ditinggalkan
  function autoNameCase(root, sel) {
    root.addEventListener('focusout', (e) => {
      const el = e.target;
      if (!el.matches || !el.matches(sel)) return;
      const v = nameCase(el.value);
      if (v !== el.value) { el.value = v; el.dispatchEvent(new Event('input', { bubbles: true })); }
    });
  }
  window.JO = {
    nameCase, autoNameCase,
    sb, config: C, t, addDict, applyI18n, setLang, onLang, get lang() { return lang; },
    fmtRp, fmtDate, fmtDateTime, esc, statusPill, amountHtml, compAge, isMinor,
    ensureSession, rpc, uploadFile, photoThumb, toast, header, footer, qs, siteUrl, qrSvg, ticketPdf, certificatePdf,
    DISC_DATES, DISC_NAME,
  };
})();

// Data wilayah (dipakai formulir & konsol)
window.JO_REGIONS = {
  provinces: ['Aceh', 'Sumatera Utara', 'Sumatera Barat', 'Riau', 'Kepulauan Riau', 'Jambi', 'Sumatera Selatan', 'Kepulauan Bangka Belitung', 'Bengkulu', 'Lampung', 'DKI Jakarta', 'Banten', 'Jawa Barat', 'Jawa Tengah', 'DI Yogyakarta', 'Jawa Timur', 'Bali', 'Nusa Tenggara Barat', 'Nusa Tenggara Timur', 'Kalimantan Barat', 'Kalimantan Tengah', 'Kalimantan Selatan', 'Kalimantan Timur', 'Kalimantan Utara', 'Sulawesi Utara', 'Gorontalo', 'Sulawesi Tengah', 'Sulawesi Barat', 'Sulawesi Selatan', 'Sulawesi Tenggara', 'Maluku', 'Maluku Utara', 'Papua', 'Papua Barat', 'Papua Barat Daya', 'Papua Tengah', 'Papua Pegunungan', 'Papua Selatan'],
  jabar: ['Kabupaten Bandung', 'Kabupaten Bandung Barat', 'Kabupaten Bekasi', 'Kabupaten Bogor', 'Kabupaten Ciamis', 'Kabupaten Cianjur', 'Kabupaten Cirebon', 'Kabupaten Garut', 'Kabupaten Indramayu', 'Kabupaten Karawang', 'Kabupaten Kuningan', 'Kabupaten Majalengka', 'Kabupaten Pangandaran', 'Kabupaten Purwakarta', 'Kabupaten Subang', 'Kabupaten Sukabumi', 'Kabupaten Sumedang', 'Kabupaten Tasikmalaya', 'Kota Bandung', 'Kota Banjar', 'Kota Bekasi', 'Kota Bogor', 'Kota Cimahi', 'Kota Cirebon', 'Kota Depok', 'Kota Sukabumi', 'Kota Tasikmalaya'],
};
