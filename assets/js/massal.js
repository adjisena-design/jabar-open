/* Jabar Open 2026 — Pendaftaran Massal (min. 30 atlet per klub, maks. 250 per kode akses)
 * Alur: kode akses dari Inda -> data pemilik & kolaborator -> lembar atlet (tersimpan otomatis di server)
 * -> kirim batch -> transfer BCA (boleh dipecah) + unggah bukti -> diverifikasi Inda -> AIC.
 */
(function () {
  'use strict';
  const { esc, fmtRp, rpc } = JO;
  const R = window.JO_REGIONS;
  const LS = 'jo_massal';
  const app = document.getElementById('app');

  let CFG = null, INFO = null, CODE = '', PERSON = '', ACC = null, BATCHES = [], LOG = [], LAST_SYNC = null;
  const ROWS = new Map();        // no -> { no, data, has_photo, batch_id, updated_by, updated_at, saved }
  const DIRTY = new Set();
  const THUMB = new Map();       // no -> data URL pas foto yang belum tersimpan
  const SEL = new Set();         // baris dipilih untuk batch
  let saveTimer = null, saving = false, saveErr = '', lastSaved = null, pollTimer = null, clockTimer = null;
  let TAB = 'sheet', FILTER = 'all', Q = '', EXTRA_ROWS = 0;

  const DOCS = { akte: 'Akte', ktp: 'KTP', ijazah: 'Ijazah', bpjs: 'BPJS', passport: 'Paspor', photo: 'Foto' };
  const ROLES = [['pemilik', 'Pemilik klub'], ['admin', 'Admin klub'], ['pelatih', 'Pelatih'], ['manajer', 'Manajer / official'], ['lainnya', 'Lainnya']];
  const PASTE = ['full_name', 'gender', 'birth_date', 'nationality', 'region', 'kab_kota', 'discipline', 'category', 'extra',
    'g_name', 'g_relation', 'g_phone', 'g_email', 'music1', 'music2', 'music3'];
  const DRIVE = /^https:\/\/(drive|docs)\.google\.com\/\S+$/i;
  const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

  // ---------------- utilitas ----------------
  const pad3 = (n) => String(n).padStart(3, '0');
  const digits = (v) => String(v || '').replace(/\D/g, '');
  const cleanEmail = (v) => String(v || '').replace(/[\s​-‍﻿]/g, '').toLowerCase();
  const catById = (id) => (id == null || id === '' ? null : CFG.categories.find((c) => String(c.id) === String(id)));
  const discName = (code) => { const d = CFG.disciplines.find((x) => x.code === code); return d ? d.name_id : code; };
  const appName = (disc, code) => { const d = CFG.disciplines.find((x) => x.code === disc); const a = d && (d.apparatus || []).find((x) => x.code === code); return a ? a.id : code; };
  const teamLevels = (disc) => ((CFG.registration.team_levels || {})[disc] || []);
  const minAth = () => INFO.min || 30, maxAth = () => INFO.max || 250;
  function fmtDT(d) {
    if (!d) return '';
    return new Date(d).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) + ' WIB';
  }
  function fmtD(d) { return d ? new Date(d + 'T00:00:00').toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' }) : ''; }
  function leftText(ms) {
    if (ms <= 0) return 'berakhir';
    const h = Math.floor(ms / 3600000), d = Math.floor(h / 24);
    if (d >= 1) return `${d} hari ${h % 24} jam`;
    const m = Math.floor((ms % 3600000) / 60000);
    return `${h} jam ${m} menit`;
  }
  function waLink(text) { return `https://wa.me/${INFO.wa}?text=${encodeURIComponent(text)}`; }
  function loadLS() { try { return JSON.parse(localStorage.getItem(LS) || '{}'); } catch (e) { return {}; } }
  function saveLS() { try { localStorage.setItem(LS, JSON.stringify({ code: CODE, person: PERSON })); } catch (e) { /* abaikan */ } }
  function personName() { const p = (ACC && ACC.people || []).find((x) => x.id === PERSON); return p ? p.name : ''; }
  function clubName() { return (ACC && ACC.club && ACC.club.name) || (ACC && ACC.label) || ''; }
  function clubProvince() { return (ACC && ACC.club && ACC.club.province) || ''; }
  function modal(html, wide) {
    const m = document.createElement('div'); m.className = 'ms-modal';
    m.innerHTML = `<div class="box ${wide ? 'wide' : ''}" role="dialog" aria-modal="true">${html}</div>`;
    document.body.appendChild(m);
    m.addEventListener('click', (e) => { if (e.target === m && !m.dataset.busy) m.remove(); });
    return m;
  }
  function errMsg(e) { return (e && e.message) || 'Terjadi kesalahan. Coba lagi.'; }

  // ---------------- aturan kategori (sama dengan jo.category_mismatch) ----------------
  function mism(c, g, bd) {
    if (!c) return null;
    if ((c.gender === 'M' || c.gender === 'F') && g && c.gender !== g) return c.gender === 'M' ? 'khusus putra' : 'khusus putri';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(bd || '')) return null;
    const y = Number(bd.slice(0, 4));
    if (c.birth_year_min && y < c.birth_year_min) return `untuk kelahiran ${c.birth_year_min} ke atas`;
    if (c.birth_year_max && y > c.birth_year_max) return `untuk kelahiran ${c.birth_year_max} ke bawah`;
    return null;
  }
  function priOk(d) { return d.nationality !== 'WNA' && d.province === 'Jawa Barat' && clubProvince() === 'Jawa Barat'; }
  function catOptions(d) {
    if (!d.discipline) return [];
    return CFG.categories.filter((c) => c.discipline === d.discipline && c.entry_type === 'individual'
      && (String(c.id) === String(d.category_id) || !mism(c, d.gender, d.birth_date)));
  }
  const DISC_NAME = (code) => ((CFG.disciplines || []).find((x) => x.code === code) || {}).name_id || code;
  const FAQ_CAT = 'faq.html#kategori-tidak-muncul';
  function noCatMsg(d) {
    const y = (d.birth_date || '').slice(0, 4);
    const g = d.gender === 'M' ? 'putra ' : d.gender === 'F' ? 'putri ' : '';
    return `Tidak ada kategori ${DISC_NAME(d.discipline)} untuk ${g}kelahiran ${y}`;
  }
  function pairOptions(d) {
    return CFG.categories.filter((c) => c.discipline === d.discipline && c.entry_type === 'pair'
      && (String(c.id) === String(d.pair_category_id) || !mism(c, null, d.birth_date)));
  }

  // ---------------- validasi baris ----------------
  function rowEmpty(d) {
    return !d || (!['full_name', 'birth_date', 'gender', 'discipline', 'g_name', 'g_phone', 'g_email', 'team_name', 'country', 'kab_kota']
      .some((k) => String(d[k] || '').trim()) && !Object.keys(d.docs || {}).length);
  }
  function validateAll() {
    const all = [...ROWS.values()].filter((r) => !rowEmpty(r.data));
    const dup = new Map(), catCount = new Map(), teamCount = new Map();
    all.forEach((r) => {
      const d = r.data;
      if (d.full_name && d.birth_date) { const k = JO.nameCase(d.full_name).toLowerCase() + '|' + d.birth_date; dup.set(k, (dup.get(k) || []).concat(r.no)); }
      if (!d.team_only && d.category_id) catCount.set(String(d.category_id), (catCount.get(String(d.category_id)) || 0) + 1);
      if (d.discipline === 'WAG' && (d.team_name || '').trim()) {
        const lvl = d.team_only ? d.team_level : (catById(d.category_id) || {}).level;
        const k = (lvl || '') + '|' + d.team_name.trim().toLowerCase(); teamCount.set(k, (teamCount.get(k) || 0) + 1);
      }
    });
    for (const r of ROWS.values()) r._E = rowErrors(r, dup, catCount, teamCount);
  }
  function rowErrors(r, dup, catCount, teamCount) {
    const d = r.data || {}, E = {};
    if (rowEmpty(d)) return E;
    if (!d.full_name || d.full_name.trim().length < 3) E.full_name = 'Isi nama lengkap sesuai identitas';
    if (!['M', 'F'].includes(d.gender)) E.gender = 'Pilih L atau P';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d.birth_date || '')) E.birth_date = 'Isi tanggal lahir';
    if (d.nationality === 'WNA') { if (!d.country || d.country.trim().length < 2) E.region = 'Isi negara asal'; }
    else { if (!d.province) E.region = 'Pilih provinsi sesuai identitas'; if (!(d.kab_kota || '').trim()) E.kab_kota = 'Isi kabupaten/kota'; }
    if (!d.discipline) E.discipline = 'Pilih disiplin';
    else if (d.team_only) {
      if (d.discipline !== 'WAG') E.category = '"Khusus beregu" hanya untuk Artistik Putri';
      if (!(d.team_name || '').trim()) E.extra = 'Isi nama tim';
    } else {
      const c = catById(d.category_id);
      if (!c && !(d.discipline === 'AER' && d.pair_category_id)) {
        if (!E.birth_date && !catOptions(d).length) {
          E.category = noCatMsg(d) + '. Periksa tanggal lahir, L/P, atau disiplin.';
          E.birth_date = `Kelahiran ${d.birth_date.slice(0, 4)} tidak masuk kategori ${DISC_NAME(d.discipline)} mana pun`;
        } else E.category = 'Pilih kategori';
      }
      if (c) {
        const m = mism(c, d.gender, d.birth_date);
        if (m) { E.category = 'Kategori ini ' + m; if (/kelahiran/.test(m)) E.birth_date = 'Tidak sesuai kategori yang dipilih'; }
        else if (c.jabar_only && !priOk(d)) E.category = 'Priangan khusus WNI dengan alamat identitas dan klub di Jawa Barat';
        else if (c.max_per_club && (catCount.get(String(c.id)) || 0) > c.max_per_club) E.category = `Maksimal ${c.max_per_club} atlet per klub di kategori ini`;
        if (d.discipline === 'RG') (c.apparatus || []).forEach((a, i) => {
          if (!DRIVE.test(((d.music || [])[i] || '').trim())) E['music' + (i + 1)] = `Tautan Google Drive musik ${appName('RG', a)} (https://drive.google.com/...)`;
        });
        if (d.discipline === 'WAG' && (d.team_name || '').trim() && !teamLevels('WAG').includes(c.level)) E.extra = 'Beregu hanya untuk Level 1–6';
      }
    }
    if (d.discipline === 'WAG' && (d.team_name || '').trim()) {
      const lvl = d.team_only ? d.team_level : (catById(d.category_id) || {}).level;
      const n = teamCount.get((lvl || '') + '|' + d.team_name.trim().toLowerCase()) || 0;
      if (n > (CFG.registration.team_max || 6)) E.extra = `Satu tim maksimal ${CFG.registration.team_max || 6} pesenam`;
    }
    if (d.discipline === 'AER' && (d.pair_category_id || d.pair_row)) {
      const pc = catById(d.pair_category_id);
      const p = ROWS.get(Number(d.pair_row));
      if (!pc) E.extra = 'Pilih kategori pasangan';
      else if (!d.pair_row) E.extra = 'Isi nomor baris pasangan';
      else if (Number(d.pair_row) === r.no) E.extra = 'Pasangan tidak boleh baris sendiri';
      else if (!p || String(p.data.pair_row) !== String(r.no) || String(p.data.pair_category_id) !== String(d.pair_category_id))
        E.extra = `Baris ${pad3(d.pair_row)} harus memilih kategori pasangan yang sama dan menunjuk balik ke baris ${pad3(r.no)}`;
      else if (mism(pc, null, d.birth_date)) E.extra = 'Kategori pasangan ' + mism(pc, null, d.birth_date);
      else if (pc.gender === 'X' && p.data.gender && p.data.gender === d.gender) E.extra = 'Pasangan campuran: satu putra dan satu putri';
    }
    if (JO.isMinor(d.birth_date)) {
      if (!d.g_name || d.g_name.trim().length < 3) E.g_name = 'Isi nama orang tua/wali';
      if (digits(d.g_phone).length < 9) E.g_phone = 'Isi WhatsApp orang tua/wali (min. 9 angka)';
      if (!EMAIL.test(cleanEmail(d.g_email))) E.g_email = 'Email orang tua/wali belum valid';
    }
    const docs = d.docs || {};
    if (d.nationality === 'WNA') { if (!docs.passport) E.docs = 'Unggah paspor'; }
    else if (!docs.akte) E.docs = 'Unggah Akte Kelahiran';
    if (!E.docs && !docs.photo) E.docs = 'Unggah pas foto';
    if (d.full_name && d.birth_date) {
      const same = dup.get(JO.nameCase(d.full_name).toLowerCase() + '|' + d.birth_date) || [];
      if (same.length > 1) E.full_name = 'Atlet yang sama juga ada di baris ' + same.filter((n) => n !== r.no).map(pad3).join(', ');
    }
    return E;
  }
  function rowState(r) {
    if (!r || rowEmpty(r.data)) return 'empty';
    if (r.batch_id) return 'sent';
    return Object.keys(r._E || {}).length ? 'bad' : 'ok';
  }

  // ---------------- penyimpanan ----------------
  function setSaveLabel() {
    document.querySelectorAll('[data-save]').forEach(setSaveEl);
  }
  function setSaveEl(el) {
    el.className = 'ms-save';
    if (saveErr) { el.classList.add('bad'); el.textContent = 'Belum tersimpan: ' + saveErr; return; }
    if (saving) { el.textContent = 'Menyimpan…'; return; }
    if (DIRTY.size) { el.textContent = 'Menunggu disimpan…'; return; }
    if (lastSaved) { el.classList.add('ok'); el.textContent = 'Tersimpan ' + new Date(lastSaved).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) + ' oleh ' + personName(); return; }
    el.textContent = 'Semua perubahan tersimpan otomatis';
  }
  function growRows(no) {
    // isi salah satu dari 5 baris terakhir yang tampil -> tambah 10 baris kosong di bawahnya
    const tb = document.querySelector('#ms-sheet tbody'); if (!tb || FILTER !== 'all' || Q) return;
    const trs = tb.querySelectorAll('tr[data-row]'); if (!trs.length) return;
    const lastShown = Number(trs[trs.length - 1].dataset.row);
    if (no < lastShown - 4 || lastShown >= maxAth()) return;
    const upto = Math.min(maxAth(), lastShown + 10);
    const used = [...ROWS.keys()].filter((k) => !rowEmpty((ROWS.get(k) || {}).data)).sort((a, b) => a - b);
    EXTRA_ROWS = Math.max(EXTRA_ROWS, upto - ((used.length ? used[used.length - 1] : 0) + 5));
    let h = ''; for (let i = lastShown + 1; i <= upto; i++) h += rowHtml(i);
    tb.insertAdjacentHTML('beforeend', h);
  }
  function markDirty(no) {
    DIRTY.add(no); setSaveLabel(); growRows(no);
    clearTimeout(saveTimer); saveTimer = setTimeout(flush, 1500);
  }
  function cleanData(d) {
    const o = { ...d }; delete o._E;
    if (o.g_email) o.g_email = cleanEmail(o.g_email);
    return o;
  }
  async function flush() {
    clearTimeout(saveTimer);
    if (saving) { saveTimer = setTimeout(flush, 700); return; }
    if (!DIRTY.size) { setSaveLabel(); return; }
    saving = true; setSaveLabel();
    const nos = [...DIRTY].slice(0, 50);
    nos.forEach((n) => DIRTY.delete(n));
    const payload = [], sentThumb = [];
    nos.forEach((no) => {
      const r = ROWS.get(no);
      if (!r || rowEmpty(r.data)) { if (r && r.saved) payload.push({ row_no: no, delete: true }); return; }
      const o = { row_no: no, data: cleanData(r.data) };
      if (THUMB.has(no)) { o.photo_thumb = THUMB.get(no); sentThumb.push(no); }
      payload.push(o);
    });
    try {
      if (payload.length) {
        const res = await rpc('public_bulk_save', { p_code: CODE, p_person: PERSON, p_rows: payload });
        lastSaved = res.at;
        payload.forEach((p) => {
          const r = ROWS.get(p.row_no); if (!r) return;
          if (p.delete) { r.saved = false; } else { r.saved = true; r.updated_by = res.by; r.updated_at = res.at; }
        });
        sentThumb.forEach((n) => THUMB.delete(n));
      }
      saveErr = '';
    } catch (e) {
      nos.forEach((n) => DIRTY.add(n));
      saveErr = errMsg(e);
      if (e.hint === 'ERR_BULK_EXPIRED' || e.hint === 'ERR_BULK_CODE' || e.hint === 'ERR_CLOSED') { saving = false; setSaveLabel(); return reloadAll(); }
    } finally {
      saving = false;
      setSaveLabel();
      if (DIRTY.size) saveTimer = setTimeout(flush, saveErr ? 6000 : 300);
    }
  }
  window.addEventListener('beforeunload', (e) => { if (DIRTY.size || saving) { e.preventDefault(); e.returnValue = ''; } });

  async function poll() {
    if (!ACC || saving || DIRTY.size || !LAST_SYNC) return;
    try {
      const res = await rpc('public_bulk_sheet', { p_code: CODE, p_person: PERSON, p_since: LAST_SYNC });
      LAST_SYNC = res.now; ACC = res.account; BATCHES = res.batches; LOG = res.log;
      const act = document.activeElement && document.activeElement.closest && document.activeElement.closest('tr[data-row]');
      const activeNo = act ? Number(act.dataset.row) : null;
      let changed = false;
      (res.rows || []).forEach((x) => {
        if (DIRTY.has(x.row_no) || x.row_no === activeNo) return;
        ROWS.set(x.row_no, { no: x.row_no, data: x.data || {}, has_photo: x.has_photo, batch_id: x.batch_id, updated_by: x.updated_by, updated_at: x.updated_at, saved: true });
        changed = true;
      });
      (res.deleted || []).forEach((n) => { if (!DIRTY.has(n) && n !== activeNo && ROWS.has(n)) { ROWS.delete(n); changed = true; } });
      if (changed && TAB === 'sheet') { validateAll(); drawRows(); drawSummary(); }
      if (TAB === 'batch') drawBatches();
      drawTop();
    } catch (e) { /* koneksi putus sesaat: dicoba lagi pada putaran berikutnya */ }
  }

  // ---------------- muat & rute ----------------
  async function reloadAll() {
    try {
      const res = await rpc('public_bulk_sheet', { p_code: CODE, p_person: PERSON, p_since: null });
      ACC = res.account; BATCHES = res.batches; LOG = res.log; LAST_SYNC = res.now;
      ROWS.clear();
      (res.rows || []).forEach((x) => ROWS.set(x.row_no, { no: x.row_no, data: x.data || {}, has_photo: x.has_photo, batch_id: x.batch_id, updated_by: x.updated_by, updated_at: x.updated_at, saved: true }));
      validateAll();
      drawMain();
    } catch (e) {
      if (e.hint === 'ERR_BULK_CODE') { CODE = ''; PERSON = ''; saveLS(); return drawIntro(errMsg(e)); }
      if (e.hint === 'ERR_BULK_PERSON' || e.hint === 'ERR_BULK_SETUP') { PERSON = ''; saveLS(); return route(); }
      app.innerHTML = `<div class="ms-narrow"><p class="note bad">${esc(errMsg(e))}</p><button class="btn btn-ghost" id="rt">Coba lagi</button></div>`;
      app.querySelector('#rt').onclick = reloadAll;
    }
  }
  async function route() {
    if (!CODE) return drawIntro();
    let o;
    try { o = await rpc('public_bulk_open', { p_code: CODE }); }
    catch (e) { return drawIntro(errMsg(e)); }
    if (!o.ok) { CODE = ''; PERSON = ''; saveLS(); return drawIntro(o.message); }
    ACC = o;
    if (!ACC.setup) return drawSetup(true);
    if (!PERSON || !(ACC.people || []).some((p) => p.id === PERSON)) return drawPerson();
    return reloadAll();
  }

  // ---------------- 1. pengantar & minta kode ----------------
  function drawIntro(err) {
    stopTimers();
    const discs = CFG.disciplines.filter((d) => d.registration_open);
    app.innerHTML = `<div class="ms-narrow">
      <div class="page-head"><h1>Pendaftaran massal</h1>
        <p>Untuk klub yang mendaftarkan <b>${minAth()} atlet atau lebih</b> sekaligus (maksimal ${maxAth()} per kode akses). Klub dengan kurang dari ${minAth()} atlet memakai <a href="daftar.html">formulir pendaftaran biasa</a>.</p></div>
      ${!INFO.open ? '<p class="note warn">Pendaftaran sedang ditutup.</p>' : ''}
      ${err ? `<p class="note bad">${esc(err)}</p>` : ''}
      <section class="card"><h2>Sudah punya kode akses?</h2>
        <form id="f-code" class="ms-bar" style="margin:0">
          <input id="code" class="input" style="flex:1;min-width:220px;text-transform:uppercase;letter-spacing:.06em" placeholder="MS-XXXX-XXXX-XXXX" autocomplete="off" required>
          <button class="btn btn-dark" type="submit">Masuk</button>
        </form>
        <p class="small muted" style="margin:8px 0 0">Satu kode untuk satu klub. Pemilik dan kolaborator memakai kode yang sama.</p>
      </section>
      <section class="card"><h2>Cara kerja</h2>
        <ol class="ms-steps">
          <li>Minta kode akses ke Inda (Finance Manager Jabar Open 2026) lewat WhatsApp.</li>
          <li>Masukkan kode, isi data klub, pemilik, dan maksimal 2 kolaborator.</li>
          <li>Isi lembar atlet dan unggah dokumen. Semua tersimpan otomatis dan bisa dilanjutkan dari perangkat mana pun selama <b>${INFO.days || 7} hari</b> sejak kode pertama dibuka.</li>
          <li>Kirim atlet per batch (batch pertama minimal ${minAth()} atlet).</li>
          <li>Transfer ke rekening BCA panitia dalam <b>2×24 jam</b>, boleh dipecah sampai 5 kali, lalu unggah setiap bukti transfer di portal.</li>
          <li>Setelah transfer diverifikasi, Athlete Identification Card (AIC) dikirim lewat email dan bisa diunduh di portal.</li>
        </ol>
      </section>
      <section class="card"><h2>Minta kode akses</h2>
        <form id="f-req">
          <div class="ms-grid2">
            <div class="field"><label class="f" for="r_name">Nama Anda</label><input id="r_name" class="input" required></div>
            <div class="field"><label class="f" for="r_club">Nama klub</label><input id="r_club" class="input" required></div>
            <div class="field"><label class="f" for="r_city">Kota / kabupaten</label><input id="r_city" class="input" required></div>
            <div class="field"><label class="f" for="r_n">Perkiraan jumlah atlet</label><input id="r_n" class="input" type="number" min="${minAth()}" max="${maxAth()}" required></div>
          </div>
          <div class="field"><span class="f">Disiplin</span><div class="ms-bar">${discs.map((d) => `<label class="check"><input type="checkbox" name="r_d" value="${esc(d.name_id)}"> <span>${esc(d.name_id)}</span></label>`).join('')}</div></div>
          <button class="btn btn-ok" type="submit">Minta kode akses ke Inda (WhatsApp)</button>
          <p class="small muted" style="margin:8px 0 0">Membuka WhatsApp dengan pesan yang sudah terisi.</p>
        </form>
      </section></div>`;
    app.querySelector('#f-code').onsubmit = async (e) => {
      e.preventDefault();
      CODE = app.querySelector('#code').value.trim().toUpperCase(); PERSON = ''; saveLS();
      route();
    };
    app.querySelector('#f-req').onsubmit = (e) => {
      e.preventDefault();
      const v = (id) => app.querySelector('#' + id).value.trim();
      const d = [...app.querySelectorAll('[name=r_d]:checked')].map((x) => x.value);
      const n = Number(v('r_n'));
      if (n && n < minAth()) { JO.toast(`Pendaftaran massal minimal ${minAth()} atlet. Untuk jumlah lebih kecil, gunakan formulir biasa.`, 'bad'); return; }
      const text = `Halo Kak Inda, saya ${JO.nameCase(v('r_name'))} dari ${v('r_club')}, ${v('r_city')}. Kami ingin mendaftarkan sekitar ${n} atlet${d.length ? ' ' + d.join(', ') : ''} di Jabar Open 2026 lewat Pendaftaran Massal. Mohon dibuatkan kode aksesnya. Terima kasih.`;
      window.open(waLink(text), '_blank', 'noopener');
    };
  }

  // ---------------- 2. data pemilik, klub, kolaborator ----------------
  function drawSetup(first) {
    stopTimers();
    const o = (ACC && ACC.owner) || {};
    const col = (ACC && ACC.collaborators) || [];
    const clubLocked = !first && BATCHES.length > 0;
    const club = ACC && ACC.club;
    let clubSel = club && club.id ? { id: club.id, name: club.name } : null;
    let clubNew = club && !club.id ? club : null;
    const html = `<div class="ms-narrow">
      <div class="page-head"><h1>${first ? 'Data klub dan pengisi' : 'Data klub dan kolaborator'}</h1>
        <p>${esc(ACC.label)} · ${esc(ACC.code_label)}${ACC.expires_at ? ` · berlaku sampai ${esc(fmtDT(ACC.expires_at))}` : ''}</p></div>
      <form id="f-setup">
        <section class="card"><h2>Pemilik</h2>
          <p class="small muted" style="margin-top:0">${first ? 'Anda yang pertama membuka kode ini menjadi pemilik. Hanya pemilik yang bisa mengubah daftar kolaborator.' : 'Hanya pemilik yang bisa mengubah data ini.'}</p>
          <div class="ms-grid2">
            <div class="field"><label class="f" for="o_name">Nama lengkap</label><input id="o_name" class="input" value="${esc(o.name || '')}" required></div>
            <div class="field"><label class="f" for="o_role">Peran di klub</label><select id="o_role" class="input" required><option value="">Pilih</option>${ROLES.map(([k, l]) => `<option value="${k}" ${o.role === k ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
            <div class="field"><label class="f" for="o_phone">WhatsApp</label><input id="o_phone" class="input" inputmode="tel" value="${esc(o.phone || '')}" required></div>
            <div class="field"><label class="f" for="o_email">Email (untuk tagihan dan AIC)</label><input id="o_email" class="input" type="email" value="${esc(o.email || '')}" required></div>
          </div>
        </section>
        <section class="card"><h2>Klub</h2><div id="clubbox"></div></section>
        <section class="card"><h2>Kolaborator (opsional, maks. 2)</h2>
          <p class="small muted" style="margin-top:0">Kolaborator memakai kode akses yang sama dan memilih namanya saat masuk. Setiap perubahan tercatat atas nama orang yang mengisi.</p>
          ${[0, 1].map((i) => `<div class="ms-grid2">
            <div class="field"><label class="f" for="c_name${i}">Nama kolaborator ${i + 1}</label><input id="c_name${i}" class="input" value="${esc((col[i] || {}).name || '')}"></div>
            <div class="field"><label class="f" for="c_phone${i}">WhatsApp kolaborator ${i + 1}</label><input id="c_phone${i}" class="input" inputmode="tel" value="${esc((col[i] || {}).phone || '')}"></div>
          </div>`).join('')}
        </section>
        <div id="setup-err"></div>
        <div class="ms-bar" style="margin-top:14px">
          <button class="btn btn-dark" type="submit">${first ? 'Simpan dan mulai mengisi' : 'Simpan'}</button>
          ${first ? '' : '<button class="btn btn-ghost" type="button" id="cancel">Batal</button>'}
        </div>
      </form></div>`;
    app.innerHTML = html;
    JO.autoNameCase(app, '#o_name, #c_name0, #c_name1');
    const box = app.querySelector('#clubbox');
    function drawClub() {
      if (clubLocked) { box.innerHTML = `<p style="margin:0"><b>${esc(clubName())}</b></p><p class="small muted">Klub tidak bisa diganti setelah batch pertama dikirim.</p>`; return; }
      if (clubSel) {
        box.innerHTML = `<p style="margin:0"><b>${esc(clubSel.name)}</b> <button type="button" class="btn-link" id="cl-x">Ganti</button></p>`;
        box.querySelector('#cl-x').onclick = () => { clubSel = null; drawClub(); }; return;
      }
      if (clubNew) {
        const cn = clubNew;
        box.innerHTML = `<div class="ms-grid2">
          <div class="field"><label class="f" for="cn_name">Nama klub</label><input id="cn_name" class="input" value="${esc(cn.name || '')}"></div>
          <div class="field"><label class="f" for="cn_country">Negara</label><input id="cn_country" class="input" value="${esc(cn.country || 'Indonesia')}"></div>
          <div class="field"><label class="f" for="cn_prov">Provinsi</label><select id="cn_prov" class="input"><option value="">Pilih</option>${R.provinces.map((p) => `<option ${p === cn.province ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
          <div class="field"><label class="f" for="cn_kab">Kabupaten / kota</label><input id="cn_kab" class="input" list="jabar-kab" value="${esc(cn.kab_kota || '')}"></div>
        </div><button type="button" class="btn-link" id="cl-back">Pilih dari daftar klub</button>`;
        ['name', 'country', 'prov', 'kab'].forEach((k) => { box.querySelector('#cn_' + k).oninput = (e) => { cn[{ name: 'name', country: 'country', prov: 'province', kab: 'kab_kota' }[k]] = e.target.value; }; });
        box.querySelector('#cl-back').onclick = () => { clubNew = null; drawClub(); };
        return;
      }
      box.innerHTML = `<div class="field"><label class="f" for="cl_q">Cari klub</label><input id="cl_q" class="input" placeholder="Ketik nama klub atau kota" autocomplete="off"></div>
        <div id="cl_list" class="ms-list" style="max-height:220px"></div>
        <p class="small" style="margin:8px 0 0">Klub belum ada? <button type="button" class="btn-link" id="cl-new">Tambahkan klub baru</button></p>`;
      const list = box.querySelector('#cl_list');
      const draw = () => {
        const s = box.querySelector('#cl_q').value.trim().toLowerCase();
        const res = CFG.clubs.filter((k) => !s || (k.name + ' ' + (k.kab_kota || '') + ' ' + (k.province || '')).toLowerCase().includes(s)).slice(0, 30);
        list.innerHTML = res.map((k) => `<div><span><b>${esc(k.name)}</b> <span class="muted">${esc([k.kab_kota, k.province, k.country !== 'Indonesia' ? k.country : ''].filter(Boolean).join(', '))}</span></span><button type="button" class="btn btn-ghost btn-sm" data-id="${k.id}">Pilih</button></div>`).join('') || '<div class="muted">Tidak ditemukan.</div>';
        list.querySelectorAll('[data-id]').forEach((b) => b.onclick = () => { const k = CFG.clubs.find((x) => x.id === b.dataset.id); clubSel = { id: k.id, name: k.name }; drawClub(); });
      };
      box.querySelector('#cl_q').oninput = draw; draw();
      box.querySelector('#cl-new').onclick = () => { clubNew = { name: box.querySelector('#cl_q').value.trim(), country: 'Indonesia', province: '', kab_kota: '' }; drawClub(); };
    }
    drawClub();
    if (!first) app.querySelector('#cancel').onclick = () => drawMain();
    app.querySelector('#f-setup').onsubmit = async (e) => {
      e.preventDefault();
      const v = (id) => app.querySelector('#' + id).value.trim();
      const p = { name: v('o_name'), role: v('o_role'), phone: v('o_phone'), email: cleanEmail(v('o_email')),
        collaborators: [0, 1].map((i) => ({ id: (col[i] || {}).id || '', name: v('c_name' + i), phone: v('c_phone' + i) })).filter((x) => x.name) };
      if (!clubLocked) {
        if (clubSel) p.club = { id: clubSel.id };
        else if (clubNew) p.club = { new: { name: clubNew.name, country: clubNew.country || 'Indonesia', province: clubNew.province, kab_kota: clubNew.kab_kota } };
      } else p.club = ACC.club && ACC.club.id ? { id: ACC.club.id } : { new: ACC.club };
      const btn = e.submitter; btn.disabled = true;
      try {
        ACC = await rpc('public_bulk_setup', { p_code: CODE, p_person: first ? null : PERSON, p });
        if (first) { PERSON = 'pemilik'; saveLS(); }
        JO.toast('Tersimpan.');
        reloadAll();
      } catch (err) {
        app.querySelector('#setup-err').innerHTML = `<p class="note bad">${esc(errMsg(err))}</p>`;
        btn.disabled = false;
      }
    };
  }

  // ---------------- 3. pilih nama ----------------
  function drawPerson() {
    stopTimers();
    app.innerHTML = `<div class="ms-narrow"><div class="page-head"><h1>Siapa yang mengisi?</h1>
      <p>${esc(clubName())} · ${esc(ACC.code_label)}</p></div>
      <section class="card"><div class="ms-bar">${ACC.people.map((p) => `<button class="btn btn-ghost" data-p="${esc(p.id)}">${esc(p.name)} <span class="muted small">(${esc(p.role)})</span></button>`).join('')}</div>
      <p class="small muted" style="margin:12px 0 0">Nama Anda tidak ada? Minta pemilik klub menambahkan Anda sebagai kolaborator.</p></section>
      <button class="btn-link" id="out" style="margin-top:12px">Pakai kode lain</button></div>`;
    app.querySelectorAll('[data-p]').forEach((b) => b.onclick = () => { PERSON = b.dataset.p; saveLS(); reloadAll(); });
    app.querySelector('#out').onclick = logout;
  }
  function logout() {
    if ((DIRTY.size || saving) && !confirm('Masih ada perubahan yang belum tersimpan. Keluar sekarang?')) return;
    stopTimers(); CODE = ''; PERSON = ''; saveLS(); ROWS.clear(); DIRTY.clear(); ACC = null; drawIntro();
  }
  function stopTimers() { clearInterval(pollTimer); clearInterval(clockTimer); pollTimer = clockTimer = null; }

  // ---------------- 4. portal ----------------
  function drawMain() {
    app.innerHTML = `<div class="ms-top" id="ms-top"></div>
      <div class="ms-tabs" role="tablist">
        <button role="tab" data-tab="sheet">Lembar atlet</button>
        <button role="tab" data-tab="batch">Batch &amp; pembayaran</button>
        <button role="tab" data-tab="log">Riwayat</button>
        ${PERSON === 'pemilik' ? '<button role="tab" data-tab="club">Data klub</button>' : ''}
      </div>
      <div id="ms-body"></div>
      <datalist id="jabar-kab">${R.jabar.map((k) => `<option value="${esc(k)}">`).join('')}</datalist>`;
    app.querySelectorAll('[data-tab]').forEach((b) => b.onclick = () => { if (b.dataset.tab === 'club') return drawSetup(false); TAB = b.dataset.tab; drawTab(); });
    drawTop(); drawTab();
    stopTimers();
    pollTimer = setInterval(poll, 20000);
    clockTimer = setInterval(drawTop, 60000);
  }
  function drawTop() {
    const el = document.getElementById('ms-top'); if (!el || !ACC) return;
    const ms = ACC.expires_at ? new Date(ACC.expires_at) - Date.now() : null;
    const done = [...ROWS.values()].filter((r) => ['ok', 'sent'].includes(rowState(r))).length;
    const total = [...ROWS.values()].filter((r) => rowState(r) !== 'empty').length;
    const clockCls = ms == null ? '' : ms <= 0 ? 'bad' : ms < 2 * 86400000 ? 'warn' : '';
    const askExt = ms != null && ms < 2 * 86400000 && !ACC.extended_days;
    el.innerHTML = `<div class="who"><b>${esc(clubName())}</b><small>${esc(ACC.code_label)} · ${esc(personName())}</small></div>
      <span class="ms-clock ${clockCls}">${ms == null ? '' : ms <= 0 ? 'Masa pengisian berakhir ' + esc(fmtDT(ACC.expires_at)) : 'Sisa waktu pengisian: ' + leftText(ms)}</span>
      <span class="sp"></span>
      <span class="ms-save" data-save></span>
      ${askExt ? `<a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="${esc(waLink(`Halo Kak Inda, saya ${personName()} dari ${clubName()}. Masa pengisian Pendaftaran Massal kami berakhir ${fmtDT(ACC.expires_at)}. Saat ini ${done} dari ${total} atlet sudah lengkap. Mohon perpanjangan waktu. Terima kasih.`))}">Minta perpanjangan</a>` : ''}
      <a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="${esc(waLink(`Halo Kak Inda, saya ${personName()} dari ${clubName()} (Pendaftaran Massal ${ACC.code_label}). Saya butuh bantuan terkait: `))}">Bantuan (WhatsApp Inda)</a>
      <button class="btn btn-ghost btn-sm" id="ms-out">Keluar</button>`;
    el.querySelector('#ms-out').onclick = logout;
    setSaveLabel();
  }
  function drawTab() {
    app.querySelectorAll('[data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === TAB)));
    if (TAB === 'sheet') drawSheet();
    else if (TAB === 'batch') drawBatches();
    else drawLog();
  }

  // ---------------- lembar ----------------
  function visibleNos() {
    const used = [...ROWS.keys()].sort((a, b) => a - b);
    const last = used.length ? used[used.length - 1] : 0;
    const upto = Math.min(maxAth(), Math.max(last + 5 + EXTRA_ROWS, 20));
    const nos = [];
    for (let i = 1; i <= upto; i++) nos.push(i);
    return nos.filter((no) => {
      const r = ROWS.get(no); const st = rowState(r);
      if (FILTER === 'bad' && st !== 'bad') return false;
      if (FILTER === 'ok' && st !== 'ok') return false;
      if (FILTER === 'sent' && st !== 'sent') return false;
      if (FILTER === 'docs' && !(r && r._E && r._E.docs)) return false;
      if (Q) { const d = (r && r.data) || {}; if (!((d.full_name || '') + ' ' + pad3(no)).toLowerCase().includes(Q)) return false; }
      return true;
    });
  }
  function drawSheet() {
    const body = document.getElementById('ms-body');
    const locked = ACC.locked;
    body.innerHTML = `${locked ? '<p class="note warn">Masa pengisian sudah berakhir. Lembar hanya bisa dilihat. Batch yang sudah dikirim tetap bisa dibayar di tab Batch &amp; pembayaran.</p>' : ''}
      ${locked ? '' : `<div class="ms-tools">
        <div class="ms-grp"><span class="ms-lbl">1. Isi data</span><div class="ms-btns">
          <button class="btn btn-primary btn-sm" id="ms-paste">Tempel dari Excel</button>
          <button class="btn btn-ghost btn-sm" id="ms-docs">Unggah dokumen sekaligus</button>
          <button class="btn btn-ghost btn-sm" id="ms-more">+ 10 baris</button></div></div>
        <div class="ms-grp"><span class="ms-lbl">2. Simpan</span><div class="ms-btns">
          <button class="btn btn-primary btn-sm" id="ms-save-now">Simpan sekarang</button>
          <span class="ms-save" data-save></span></div></div>
        <div class="ms-grp ms-grp-send"><span class="ms-lbl">3. Kirim</span><div class="ms-btns">
          <button class="btn btn-ghost btn-sm" id="ms-selok">Pilih semua yang siap</button>
          <button class="btn btn-dark btn-sm" id="ms-send">Kirim batch (<span id="ms-seln">0</span>)</button></div></div>
      </div>`}
      <div class="ms-filter"><span class="ms-lbl">Tampilkan</span><div class="ms-bar" id="ms-sum"></div>
        <input id="ms-q" class="input" placeholder="Cari nama atau no. baris" value="${esc(Q)}"></div>
      <div class="ms-sheet-wrap"><table class="ms-sheet" id="ms-sheet"><thead><tr>
        <th class="stk c-sel"><span class="sr-only">Pilih</span></th><th class="stk c-no">No</th><th class="stk c-name">Nama lengkap</th>
        <th>L/P</th><th>Tanggal lahir</th><th>WNI/WNA</th><th>Provinsi / negara</th><th>Kab/kota</th><th>Disiplin</th><th>Kategori</th>
        <th>Tim (Artistik) / Pasangan (Aerobik)</th><th>Orang tua/wali</th><th>Hubungan</th><th>WA orang tua/wali</th><th>Email orang tua/wali</th>
        <th>Musik 1 (Ritmik)</th><th>Musik 2</th><th>Musik 3</th><th>Dokumen</th><th>Status</th></tr></thead><tbody></tbody></table></div>
      <p class="small muted" style="margin-top:8px">Kolom orang tua/wali wajib untuk atlet di bawah 18 tahun. Nama file dokumen untuk unggah sekaligus: <code>012-akte.pdf</code>, <code>012-foto.jpg</code>, <code>012-ktp.jpg</code>, <code>012-bpjs.pdf</code>, <code>012-paspor.pdf</code>, <code>012-ijazah.pdf</code> (012 = nomor baris).</p>`;
    const q = body.querySelector('#ms-q');
    q.oninput = () => { Q = q.value.trim().toLowerCase(); drawRows(); };
    if (!locked) {
      body.querySelector('#ms-more').onclick = () => { EXTRA_ROWS += 10; drawRows(); };
      body.querySelector('#ms-paste').onclick = pasteBox;
      body.querySelector('#ms-docs').onclick = bulkDocs;
      body.querySelector('#ms-save-now').onclick = () => flush();
      body.querySelector('#ms-selok').onclick = () => {
        SEL.clear(); for (const r of ROWS.values()) if (rowState(r) === 'ok') SEL.add(r.no);
        drawRows(); updSel();
      };
      body.querySelector('#ms-send').onclick = sendBatch;
    }
    const tb = body.querySelector('#ms-sheet');
    tb.addEventListener('input', onInput);
    tb.addEventListener('change', onChange);
    tb.addEventListener('focusout', onBlur);
    tb.addEventListener('paste', onPaste);
    tb.addEventListener('click', onClick);
    drawSummary(); drawRows(); updSel(); setSaveLabel();
  }
  function drawSummary() {
    const el = document.getElementById('ms-sum'); if (!el) return;
    let n = 0, ok = 0, bad = 0, sent = 0, docs = 0;
    for (const r of ROWS.values()) {
      const st = rowState(r); if (st === 'empty') continue;
      n++; if (st === 'ok') ok++; if (st === 'bad') bad++; if (st === 'sent') sent++;
      if (st !== 'sent' && r._E && r._E.docs) docs++;
    }
    const chip = (k, label, v, cls) => `<button class="ms-chip ${cls || ''}" data-f="${k}" aria-pressed="${FILTER === k}">${label} <b>${v}</b></button>`;
    el.innerHTML = chip('all', 'Semua atlet', `${n} / ${maxAth()}`) + chip('ok', 'Siap kirim', ok) + chip('bad', 'Perlu dilengkapi', bad, bad ? 'bad' : '')
      + chip('docs', 'Dokumen belum lengkap', docs, docs ? 'bad' : '') + chip('sent', 'Sudah dikirim', sent);
    el.querySelectorAll('[data-f]').forEach((b) => b.onclick = () => { FILTER = b.dataset.f; drawSummary(); drawRows(); });
  }
  function updSel() {
    for (const n of [...SEL]) if (rowState(ROWS.get(n)) !== 'ok') SEL.delete(n);
    const el = document.getElementById('ms-seln'); if (el) el.textContent = SEL.size;
  }
  function drawRows() {
    const tb = document.querySelector('#ms-sheet tbody'); if (!tb) return;
    tb.innerHTML = visibleNos().map(rowHtml).join('');
  }
  function redrawRow(no, keepFocus) {
    const tr = document.querySelector(`#ms-sheet tr[data-row="${no}"]`); if (!tr) return;
    let fk = null, pos = null;
    if (keepFocus && document.activeElement && tr.contains(document.activeElement)) {
      fk = document.activeElement.dataset.k;
      try { pos = document.activeElement.selectionStart; } catch (e) { pos = null; }
    }
    tr.outerHTML = rowHtml(no);
    if (fk) {
      const el = document.querySelector(`#ms-sheet tr[data-row="${no}"] [data-k="${fk}"]`);
      if (el) { el.focus(); try { if (pos != null) el.setSelectionRange(pos, pos); } catch (e) { /* select */ } }
    }
  }
  function errHtml(c, msg, no) {
    if (!msg) return '';
    let h = esc(msg);
    if (c === 'category' && /^Tidak ada kategori/.test(msg)) {
      const d = (ROWS.get(no) || {}).data || {};
      const bd = d.birth_date ? d.birth_date.split('-').reverse().join('/') : '';
      const wa = waLink(`Halo Kak Inda, saya ${personName()} dari ${clubName()} (Pendaftaran Massal ${ACC.code_label || ''}). Atlet baris ${pad3(no)} (${d.full_name || '-'}, ${d.gender === 'M' ? 'L' : d.gender === 'F' ? 'P' : '-'}, lahir ${bd}, ${DISC_NAME(d.discipline)}) tidak menemukan kategori yang sesuai. Mohon bantuannya. Terima kasih.`);
      h += ` <a href="${FAQ_CAT}" target="_blank" rel="noopener">Lihat aturan kategori</a> · <a href="${esc(wa)}" target="_blank" rel="noopener">Tanya Inda</a>`;
    }
    return h;
  }
  function refreshStates() {
    // perbarui tanda merah dan status tanpa menggambar ulang input (agar ketikan tidak terganggu)
    document.querySelectorAll('#ms-sheet tr[data-row]').forEach((tr) => {
      const r = ROWS.get(Number(tr.dataset.row)); const E = (r && r._E) || {};
      tr.querySelectorAll('td[data-c]').forEach((td) => {
        const msg = E[td.dataset.c] || '';
        td.classList.toggle('bad-cell', !!msg);
        const no = Number(tr.dataset.row); let box = td.querySelector('.ms-err');
        if (!box) { box = document.createElement('div'); box.className = 'ms-err'; td.appendChild(box); }
        const h = errHtml(td.dataset.c, msg, no); if (box.innerHTML !== h) box.innerHTML = h;
      });
      const st = tr.querySelector('.ms-st'); if (st) st.innerHTML = statusHtml(r, Number(tr.dataset.row));
      const cb = tr.querySelector('[data-sel]'); if (cb) cb.disabled = rowState(r) !== 'ok';
    });
    drawSummary(); updSel(); drawTop();
  }
  function statusHtml(r, no) {
    const st = rowState(r);
    const del = !ACC.locked && r && !r.batch_id && st !== 'empty' ? `<button class="ms-del" data-del="${no}">Hapus</button>` : '';
    const by = r && r.updated_by && st !== 'empty' ? `<span class="by">diubah ${esc(r.updated_by)}</span>` : '';
    if (st === 'empty') return '';
    if (st === 'sent') { const b = BATCHES.find((x) => x.id === r.batch_id); return `<span class="lk">Terkirim${b ? ' · ' + esc(b.code.split('-').pop()) : ''}</span>${by}`; }
    if (st === 'ok') return `<span class="ok">Siap</span> ${del}${by}`;
    const list = Object.values(r._E);
    return `<span class="bad" title="${esc(list.join('\n'))}">${list.length} perlu dilengkapi</span> ${del}${by}`;
  }
  function rowHtml(no) {
    const r = ROWS.get(no) || { no, data: {} };
    const d = r.data || {}; const E = r._E || {};
    const lock = !!r.batch_id || ACC.locked;
    const dis = lock ? 'disabled' : '';
    const st = rowState(r);
    const td = (c, inner, cls) => `<td data-c="${c}" class="${cls || ''} ${E[c] ? 'bad-cell' : ''}">${inner}<div class="ms-err">${errHtml(c, E[c], no)}</div></td>`;
    const inp = (k, v, extra) => `<input data-row-no="${no}" data-k="${k}" value="${esc(v == null ? '' : v)}" ${dis} ${extra || ''}>`;
    const sel = (k, opts, v, extra) => `<select data-k="${k}" ${dis} ${extra || ''}>${opts.map(([val, lab]) => `<option value="${esc(val)}" ${String(val) === String(v == null ? '' : v) ? 'selected' : ''}>${esc(lab)}</option>`).join('')}</select>`;
    const wna = d.nationality === 'WNA';
    const minor = !d.birth_date || JO.isMinor(d.birth_date);
    // kategori
    let catSel = '';
    if (d.discipline) {
      const co = catOptions(d);
      const opts = [['', co.length || !/^\d{4}-/.test(d.birth_date || '') ? 'Pilih kategori' : 'Tidak ada kategori yang sesuai']].concat(co.map((c) => [String(c.id), c.name_id]));
      if (d.discipline === 'WAG') teamLevels('WAG').forEach((l) => opts.push(['team:' + l, `Khusus beregu – ${l}`]));
      catSel = sel('category', opts, d.team_only ? 'team:' + d.team_level : d.category_id);
    } else catSel = '<select disabled><option>Pilih disiplin dulu</option></select>';
    // tim / pasangan
    let extra = '<input disabled placeholder="–">';
    if (d.discipline === 'WAG') extra = inp('team_name', d.team_name, 'placeholder="Nama tim (opsional)"');
    else if (d.discipline === 'AER') {
      extra = `<div class="ms-x">${sel('pair_category', [['', 'Tanpa pasangan']].concat(pairOptions(d).map((c) => [String(c.id), c.name_id.replace('Aerobik ', '')])), d.pair_category_id)}${inp('pair_row', d.pair_row, 'inputmode="numeric" placeholder="No."')}</div>`;
    }
    // musik
    const c = catById(d.category_id);
    const apps = d.discipline === 'RG' && c ? (c.apparatus || []) : [];
    const mus = [0, 1, 2].map((i) => apps[i] ? inp('music' + (i + 1), (d.music || [])[i], `placeholder="${esc(appName('RG', apps[i]))}: https://drive.google.com/..."`) : '<input disabled placeholder="–">');
    // dokumen
    const keys = wna ? ['passport', 'photo'] : ['akte', 'ktp', 'ijazah', 'bpjs', 'photo'];
    const req = wna ? ['passport', 'photo'] : ['akte', 'photo'];
    const docs = keys.map((k) => {
      const has = d.docs && d.docs[k];
      return `<button type="button" class="ms-doc ${has ? 'has' : req.includes(k) ? 'req' : ''}" data-doc="${k}" ${lock ? 'disabled' : ''} title="${has ? esc(has.name || 'Terunggah') : 'Unggah ' + DOCS[k]}">${has ? '✓ ' : ''}${DOCS[k]}${req.includes(k) && !has ? '*' : ''}</button>`;
    }).join('');
    return `<tr data-row="${no}" class="${lock && r.batch_id ? 'locked' : ''} ${st === 'empty' ? 'empty-row' : ''}">
      <td class="stk c-sel"><input type="checkbox" data-sel="${no}" ${SEL.has(no) ? 'checked' : ''} ${st === 'ok' && !ACC.locked ? '' : 'disabled'} aria-label="Pilih baris ${no}"></td>
      <td class="stk c-no">${pad3(no)}</td>
      ${td('full_name', inp('full_name', d.full_name, 'placeholder="Nama sesuai identitas"'), 'stk c-name')}
      ${td('gender', sel('gender', [['', '–'], ['M', 'L'], ['F', 'P']], d.gender), 'w-g')}
      ${td('birth_date', inp('birth_date', d.birth_date, 'type="date" min="1950-01-01" max="2025-12-31"'), 'w-d')}
      ${td('nationality', sel('nationality', [['WNI', 'WNI'], ['WNA', 'WNA']], d.nationality || 'WNI'), 'w-n')}
      ${td('region', wna ? inp('region', d.country, 'placeholder="Negara"') : sel('region', [['', 'Pilih provinsi']].concat(R.provinces.map((p) => [p, p])), d.province), 'w-r')}
      ${td('kab_kota', wna ? '<input disabled placeholder="–">' : inp('kab_kota', d.kab_kota, d.province === 'Jawa Barat' ? 'list="jabar-kab" placeholder="Kab/kota"' : 'placeholder="Kab/kota"'), 'w-k')}
      ${td('discipline', sel('discipline', [['', 'Pilih']].concat(CFG.disciplines.filter((x) => x.registration_open || x.code === d.discipline).map((x) => [x.code, x.name_id])), d.discipline), 'w-disc')}
      ${td('category', catSel, 'w-cat')}
      ${td('extra', extra, 'w-x')}
      ${td('g_name', minor ? inp('g_name', d.g_name, 'placeholder="Nama"') : '<input disabled placeholder="18+">', 'w-gn')}
      ${td('g_relation', minor ? inp('g_relation', d.g_relation, 'placeholder="Ibu/Ayah"') : '<input disabled>', 'w-gr')}
      ${td('g_phone', minor ? inp('g_phone', d.g_phone, 'inputmode="tel" placeholder="08..."') : '<input disabled>', 'w-gp')}
      ${td('g_email', minor ? inp('g_email', d.g_email, 'type="email" placeholder="email"') : '<input disabled>', 'w-ge')}
      ${td('music1', mus[0], 'w-m')}${td('music2', mus[1], 'w-m')}${td('music3', mus[2], 'w-m')}
      ${td('docs', `<div class="ms-docs">${docs}</div>`)}
      <td class="ms-st">${statusHtml(r, no)}</td></tr>`;
  }
  function ensureRow(no) {
    if (!ROWS.has(no)) ROWS.set(no, { no, data: { nationality: 'WNI', docs: {} }, saved: false });
    const r = ROWS.get(no); r.data.docs = r.data.docs || {}; return r;
  }
  // tulis satu nilai ke data baris; mengembalikan true bila baris perlu digambar ulang
  function setVal(d, k, v) {
    switch (k) {
      case 'region':
        if (d.nationality === 'WNA') { d.country = v; return false; }
        if (d.province !== v) { d.province = v; d.kab_kota = ''; } return true;
      case 'nationality':
        d.nationality = v === 'WNA' ? 'WNA' : 'WNI';
        if (d.nationality === 'WNA') { d.province = ''; d.kab_kota = ''; } else d.country = '';
        return true;
      case 'discipline':
        if (d.discipline !== v) { d.discipline = v; d.category_id = null; d.team_only = false; d.team_level = null; d.team_name = ''; d.pair_category_id = null; d.pair_row = null; d.music = []; }
        return true;
      case 'category':
        if (String(v).startsWith('team:')) { d.team_only = true; d.team_level = v.slice(5); d.category_id = null; }
        else { d.team_only = false; d.team_level = null; d.category_id = v ? Number(v) : null; }
        return true;
      case 'pair_category': d.pair_category_id = v ? Number(v) : null; return false;
      case 'pair_row': d.pair_row = digits(v) ? Number(digits(v)) : null; return false;
      case 'music1': case 'music2': case 'music3': { const i = Number(k.slice(5)) - 1; d.music = (d.music || []).slice(); d.music[i] = v.trim(); return false; }
      case 'gender': case 'birth_date': d[k] = v; return true;
      default: d[k] = v; return false;
    }
  }
  function onInput(e) {
    const el = e.target; if (!el.dataset.k || el.tagName === 'SELECT' || el.type === 'date') return;
    const no = Number(el.closest('tr').dataset.row);
    const r = ensureRow(no);
    setVal(r.data, el.dataset.k, el.value);
    markDirty(no); validateAll(); refreshStates();
  }
  function onChange(e) {
    const el = e.target;
    if (el.dataset.sel) { const n = Number(el.dataset.sel); if (el.checked) SEL.add(n); else SEL.delete(n); updSel(); return; }
    if (!el.dataset.k) return;
    if (el.tagName !== 'SELECT' && el.type !== 'date') return;
    const no = Number(el.closest('tr').dataset.row);
    const r = ensureRow(no);
    setVal(r.data, el.dataset.k, el.value);
    markDirty(no); validateAll(); redrawRow(no, true); refreshStates();
  }
  function onBlur(e) {
    const el = e.target; const k = el.dataset && el.dataset.k; if (!k) return;
    const no = Number(el.closest('tr').dataset.row); const r = ROWS.get(no); if (!r) return;
    if (k === 'full_name' || k === 'g_name') {
      const v = JO.nameCase(el.value);
      if (v !== el.value) { el.value = v; r.data[k] = v; markDirty(no); validateAll(); refreshStates(); }
    }
    if (k === 'g_email') { const v = cleanEmail(el.value); if (v !== el.value) { el.value = v; r.data.g_email = v; markDirty(no); } }
    if (k === 'pair_row' || k === 'team_name') { validateAll(); refreshStates(); }
  }
  async function onClick(e) {
    const del = e.target.closest('[data-del]');
    if (del) {
      const no = Number(del.dataset.del); const r = ROWS.get(no);
      if (!confirm(`Hapus baris ${pad3(no)}${r && r.data.full_name ? ' (' + r.data.full_name + ')' : ''}? Dokumen baris ini ikut terhapus dari lembar.`)) return;
      r.data = { nationality: 'WNI', docs: {} }; SEL.delete(no);
      markDirty(no); validateAll(); redrawRow(no); refreshStates();
      return;
    }
    const doc = e.target.closest('[data-doc]');
    if (doc && !doc.disabled) {
      const no = Number(doc.closest('tr').dataset.row); const k = doc.dataset.doc;
      const r = ensureRow(no);
      if (r.data.docs[k]) {
        const ans = prompt(`${DOCS[k]} baris ${pad3(no)} sudah diunggah (${r.data.docs[k].name || 'berkas'}).\nKetik GANTI untuk mengunggah ulang atau HAPUS untuk menghapus.`, 'GANTI');
        if (!ans) return;
        if (ans.trim().toUpperCase() === 'HAPUS') {
          delete r.data.docs[k]; if (k === 'photo') { THUMB.set(no, ''); r.has_photo = false; }
          markDirty(no); validateAll(); redrawRow(no); refreshStates(); return;
        }
      }
      const f = document.createElement('input'); f.type = 'file';
      f.accept = k === 'photo' ? 'image/jpeg,image/png,image/webp' : 'image/jpeg,image/png,image/webp,application/pdf';
      f.onchange = () => { if (f.files[0]) uploadDoc(no, k, f.files[0], doc); };
      f.click();
    }
  }
  async function uploadDoc(no, k, file, btn) {
    if (btn) btn.classList.add('busy');
    try {
      if (k === 'photo' && !/^image\//.test(file.type) && !/\.(jpe?g|png|webp)$/i.test(file.name)) throw new Error('Pas foto harus berupa gambar (JPG/PNG).');
      const up = await JO.uploadFile('dokumen', file);
      const r = ensureRow(no);
      if (k === 'photo') { THUMB.set(no, await JO.photoThumb(file)); r.has_photo = true; }
      r.data.docs[k] = { path: up.path, name: file.name };
      markDirty(no); validateAll(); redrawRow(no); refreshStates();
      return true;
    } catch (e) { JO.toast(`Baris ${pad3(no)} ${DOCS[k]}: ${errMsg(e)}`, 'bad'); if (btn) btn.classList.remove('busy'); return false; }
  }

  // ---------------- tempel dari Excel / Google Sheets ----------------
  function normTxt(s) { return String(s || '').toLowerCase().replace(/[–—]/g, '-').replace(/\s+/g, ' ').trim(); }
  const MONTHS = { jan: 1, januari: 1, january: 1, feb: 2, februari: 2, february: 2, mar: 3, maret: 3, march: 3, apr: 4, april: 4, mei: 5, may: 5, jun: 6, juni: 6, june: 6, jul: 7, juli: 7, july: 7,
    agu: 8, agt: 8, agustus: 8, aug: 8, august: 8, sep: 9, september: 9, okt: 10, oktober: 10, oct: 10, october: 10, nov: 11, november: 11, des: 12, desember: 12, dec: 12, december: 12 };
  function parseDate(v) {
    v = String(v || '').trim(); if (!v) return '';
    let m;
    if ((m = v.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/))) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
    if ((m = v.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/))) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;   // format Indonesia: tanggal/bulan/tahun
    if ((m = v.match(/^(\d{1,2})\s+([A-Za-z]+)\.?\s+(\d{4})$/)) && MONTHS[m[2].toLowerCase()]) return `${m[3]}-${String(MONTHS[m[2].toLowerCase()]).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
    if (/^\d{5}$/.test(v)) { const dt = new Date(Date.UTC(1899, 11, 30) + Number(v) * 86400000); return dt.toISOString().slice(0, 10); }   // angka tanggal Excel
    return '';
  }
  function parseGender(v) { const s = normTxt(v); if (/^(l|lk|laki|laki-laki|laki laki|m|male|putra|pria|pa)$/.test(s)) return 'M'; if (/^(p|pr|perempuan|f|female|putri|wanita|pi|w)$/.test(s)) return 'F'; return ''; }
  function parseDisc(v) {
    const s = normTxt(v); if (!s) return '';
    const direct = CFG.disciplines.find((d) => d.code.toLowerCase() === s || normTxt(d.name_id) === s || normTxt(d.name_en) === s); if (direct) return direct.code;
    if (/ritmi|rhythm/.test(s)) return 'RG'; if (/aerob/.test(s)) return 'AER'; if (/putri|women|wag/.test(s)) return 'WAG'; if (/putra|men|mag/.test(s)) return 'MAG';
    return '';
  }
  function parseCat(d, v) {
    const s = normTxt(v); if (!s || !d.discipline) return null;
    const m = s.match(/khusus beregu\s*-?\s*(level \d)/); if (m && d.discipline === 'WAG') return 'team:' + m[1].replace('level', 'Level');
    const c = CFG.categories.find((x) => x.discipline === d.discipline && (normTxt(x.code) === s || normTxt(x.name_id) === s || normTxt(x.name_en) === s));
    return c ? String(c.id) : null;
  }
  function parseProv(v) {
    const s = normTxt(v); if (!s) return '';
    const alias = { jabar: 'Jawa Barat', jateng: 'Jawa Tengah', jatim: 'Jawa Timur', dki: 'DKI Jakarta', jakarta: 'DKI Jakarta', diy: 'DI Yogyakarta', yogyakarta: 'DI Yogyakarta', jogja: 'DI Yogyakarta' };
    if (alias[s]) return alias[s];
    return R.provinces.find((p) => normTxt(p) === s) || '';
  }
  function applyPaste(r, slot, raw) {
    const d = r.data; const v = String(raw == null ? '' : raw).trim();
    switch (slot) {
      case 'full_name': d.full_name = JO.nameCase(v); break;
      case 'gender': d.gender = parseGender(v); break;
      case 'birth_date': d.birth_date = parseDate(v); break;
      case 'nationality': setVal(d, 'nationality', /wna|asing|foreign/i.test(v) ? 'WNA' : 'WNI'); break;
      case 'region': if (d.nationality === 'WNA') d.country = v; else { d.province = parseProv(v); } break;
      case 'kab_kota': if (d.nationality !== 'WNA') d.kab_kota = v; break;
      case 'discipline': setVal(d, 'discipline', parseDisc(v)); break;
      case 'category': { const c = parseCat(d, v); if (c) setVal(d, 'category', c); break; }
      case 'extra':
        if (d.discipline === 'WAG') d.team_name = v;
        else if (d.discipline === 'AER' && digits(v)) {
          d.pair_row = Number(digits(v));
          if (!d.pair_category_id) { const opts = pairOptions(d); if (opts.length === 1) d.pair_category_id = opts[0].id; }
        }
        break;
      case 'g_name': d.g_name = JO.nameCase(v); break;
      case 'g_email': d.g_email = cleanEmail(v); break;
      case 'music1': case 'music2': case 'music3': setVal(d, slot, v); break;
      default: d[slot] = v;
    }
  }
  function onPaste(e) {
    const el = e.target; if (!el.dataset || !el.dataset.k) return;
    const text = (e.clipboardData || window.clipboardData).getData('text/plain') || '';
    if (!/[\t\n]/.test(text.replace(/\n$/, ''))) return;   // satu sel: biarkan perilaku biasa
    e.preventDefault();
    const lines = text.replace(/\r/g, '').split('\n'); while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
    const startNo = Number(el.closest('tr').dataset.row);
    const key = { team_name: 'extra', pair_row: 'extra', pair_category: 'extra' }[el.dataset.k] || el.dataset.k;
    const startIdx = PASTE.indexOf(key); if (startIdx < 0) return;
    pasteLines(lines, startNo, startIdx);
  }
  function firstFreeRow() {
    for (let no = 1; no <= maxAth(); no++) { const r = ROWS.get(no); if (!r || (!r.batch_id && rowEmpty(r.data))) return no; }
    return null;
  }
  function pasteLines(lines, startNo, startIdx) {
    let done = 0, stopped = '';
    for (let i = 0; i < lines.length; i++) {
      const no = startNo + i;
      if (no > maxAth()) { stopped = `Maksimal ${maxAth()} baris.`; break; }
      const ex = ROWS.get(no); if (ex && ex.batch_id) { stopped = `Baris ${pad3(no)} sudah dikirim; tempel berhenti di sana.`; break; }
      const r = ensureRow(no);
      const cells = lines[i].split('\t');
      cells.forEach((cell, j) => { const slot = PASTE[startIdx + j]; if (slot) applyPaste(r, slot, cell); });
      markDirty(no); done++;
    }
    validateAll(); drawRows(); refreshStates();
    JO.toast(`${done} baris ditempel.${stopped ? ' ' + stopped : ''} Periksa kolom yang berwarna merah.`, stopped ? 'bad' : undefined);
  }
  function pasteBox() {
    const start = firstFreeRow();
    const m = modal(`<h2>Tempel dari Excel atau Google Sheets</h2>
      <p>Di Excel, susun kolom dengan urutan di bawah, blok semua baris atlet <b>tanpa judul kolom</b>, salin (Ctrl+C / Cmd+C), lalu tempel di kotak ini (Ctrl+V / Cmd+V).</p>
      <textarea id="pbox" class="input" rows="6" style="width:100%;font-family:ui-monospace,monospace;font-size:.8rem" placeholder="Tempel di sini"></textarea>
      <p class="small" id="pinfo">${start ? `Data akan mengisi mulai baris <b>${pad3(start)}</b> (baris kosong pertama).` : 'Lembar sudah penuh.'}</p>
      <details class="small"><summary>Urutan kolom</summary>
      <ol class="small" style="line-height:1.7">
        <li>Nama lengkap</li><li>L/P (L atau P)</li><li>Tanggal lahir (tanggal/bulan/tahun, mis. 05/03/2014)</li><li>WNI atau WNA</li>
        <li>Provinsi (WNI) atau negara (WNA)</li><li>Kabupaten/kota</li><li>Disiplin (Ritmik, Artistik Putri, Artistik Putra, Aerobik)</li>
        <li>Kategori (kode, mis. RG-A-KU1112, atau nama persis seperti di daftar)</li><li>Nama tim (Artistik) atau no. baris pasangan (Aerobik)</li>
        <li>Nama orang tua/wali</li><li>Hubungan</li><li>WhatsApp orang tua/wali</li><li>Email orang tua/wali</li><li>Musik 1, Musik 2, Musik 3 (Ritmik)</li>
      </ol>
      </details>
      <p class="small muted">Untuk mengisi kolom tertentu saja (mis. hanya orang tua/wali), klik sel pertama kolom itu di lembar lalu tempel langsung di sana. Dokumen tidak bisa ditempel; gunakan "Unggah dokumen sekaligus".</p>
      <div class="acts"><button class="btn btn-ghost" id="cx">Batal</button><button class="btn btn-dark" id="ok" disabled>Masukkan ke lembar</button></div>`);
    const ta = m.querySelector('#pbox'), ok = m.querySelector('#ok'), info = m.querySelector('#pinfo');
    const lines = () => { const l = ta.value.replace(/\r/g, '').split('\n'); while (l.length && !l[l.length - 1].trim()) l.pop(); return l; };
    ta.oninput = () => {
      const n = lines().length; ok.disabled = !n || !start;
      if (start && n) info.innerHTML = `${n} baris akan mengisi baris <b>${pad3(start)}</b> sampai <b>${pad3(Math.min(maxAth(), start + n - 1))}</b>.`;
    };
    m.querySelector('#cx').onclick = () => m.remove();
    ok.onclick = () => { const l = lines(); m.remove(); if (FILTER !== 'all' || Q) { FILTER = 'all'; Q = ''; const q = document.getElementById('ms-q'); if (q) q.value = ''; drawSummary(); } pasteLines(l, start, 0); };
    setTimeout(() => ta.focus(), 50);
  }

  // ---------------- unggah dokumen sekaligus ----------------
  function bulkDocs() {
    const m = modal(`<h2>Unggah dokumen sekaligus</h2>
      <p class="small">Beri nama setiap berkas dengan nomor baris dan jenis dokumen, lalu pilih atau seret semua berkasnya ke sini:</p>
      <p class="small"><code>012-akte.pdf</code> · <code>012-foto.jpg</code> · <code>012-ktp.jpg</code> · <code>012-ijazah.pdf</code> · <code>012-bpjs.pdf</code> · <code>012-paspor.pdf</code></p>
      <div class="ms-drop" id="drop">Seret berkas ke sini atau <button class="btn-link" id="pick">pilih berkas</button></div>
      <div id="res"></div>
      <div class="acts"><button class="btn btn-ghost" id="close">Tutup</button><button class="btn btn-dark" id="go" disabled>Unggah</button></div>`, true);
    let items = [];
    const res = m.querySelector('#res'); const go = m.querySelector('#go');
    const KEY = [[/akt[ae]|akte/i, 'akte'], [/ktp/i, 'ktp'], [/ijaz/i, 'ijazah'], [/bpjs/i, 'bpjs'], [/pasp|passport/i, 'passport'], [/foto|photo|pas ?foto/i, 'photo']];
    function take(files) {
      items = [...files].map((f) => {
        const base = f.name.replace(/\.[^.]+$/, '');
        const mm = base.match(/^\s*0*(\d{1,3})\s*[-_ .]\s*(.+)$/);
        let no = mm ? Number(mm[1]) : null, k = null;
        if (mm) { const hit = KEY.find(([re]) => re.test(mm[2])); k = hit ? hit[1] : null; }
        let why = '';
        const r = no && ROWS.get(no);
        if (!no || !k) why = 'Nama berkas tidak dikenali';
        else if (no > maxAth()) why = 'Nomor baris di luar batas';
        else if (r && r.batch_id) why = 'Baris sudah dikirim';
        else if (r && r.data.nationality === 'WNA' && ['akte', 'ktp', 'ijazah', 'bpjs'].includes(k)) why = 'Atlet WNA: hanya paspor dan foto';
        return { f, no, k, why };
      });
      const ok = items.filter((x) => !x.why);
      res.innerHTML = `<p class="small" style="margin:10px 0 0"><b>${ok.length}</b> berkas siap diunggah${items.length - ok.length ? `, <b style="color:var(--bad)">${items.length - ok.length}</b> dilewati` : ''}.</p>
        <div class="ms-list">${items.map((x) => `<div><span>${esc(x.f.name)}</span><span class="${x.why ? 'muted' : ''}">${x.why ? esc(x.why) : `Baris ${pad3(x.no)} · ${DOCS[x.k]}${ROWS.get(x.no) && ROWS.get(x.no).data.docs && ROWS.get(x.no).data.docs[x.k] ? ' (mengganti)' : ''}`}</span></div>`).join('')}</div>
        <div class="ms-prog"><i id="bar"></i></div>`;
      go.disabled = !ok.length;
    }
    const drop = m.querySelector('#drop');
    drop.ondragover = (e) => { e.preventDefault(); drop.classList.add('over'); };
    drop.ondragleave = () => drop.classList.remove('over');
    drop.ondrop = (e) => { e.preventDefault(); drop.classList.remove('over'); take(e.dataTransfer.files); };
    m.querySelector('#pick').onclick = () => { const f = document.createElement('input'); f.type = 'file'; f.multiple = true; f.accept = 'image/jpeg,image/png,image/webp,application/pdf'; f.onchange = () => take(f.files); f.click(); };
    m.querySelector('#close').onclick = () => { if (!m.dataset.busy) m.remove(); };
    go.onclick = async () => {
      const ok = items.filter((x) => !x.why); if (!ok.length) return;
      m.dataset.busy = '1'; go.disabled = true; m.querySelector('#close').disabled = true;
      let i = 0, done = 0, fail = 0;
      const bar = m.querySelector('#bar');
      async function worker() {
        while (i < ok.length) {
          const x = ok[i++];
          const good = await uploadDoc(x.no, x.k, x.f, null);
          if (good) done++; else fail++;
          bar.style.width = Math.round(((done + fail) / ok.length) * 100) + '%';
        }
      }
      await Promise.all([worker(), worker(), worker()]);
      delete m.dataset.busy; m.querySelector('#close').disabled = false;
      JO.toast(`${done} berkas terunggah${fail ? `, ${fail} gagal` : ''}.`, fail ? 'bad' : undefined);
      flush();
      if (!fail) m.remove();
    };
  }

  // ---------------- kirim batch ----------------
  function batchCalc(nos) {
    const per = {}; let total = 0; const teams = new Set();
    nos.forEach((no) => {
      const d = ROWS.get(no).data; const disc = d.discipline;
      per[disc] = per[disc] || { n: 0, amount: 0 };
      per[disc].n++;
      if (!d.team_only) { const c = catById(d.category_id); if (c) { per[disc].amount += c.fee; total += c.fee; } }
      if (d.pair_category_id && Number(d.pair_row) > no) { const pc = catById(d.pair_category_id); if (pc) { per[disc].amount += pc.fee; total += pc.fee; } }
      if (disc === 'WAG' && (d.team_name || '').trim()) {
        const lvl = d.team_only ? d.team_level : (catById(d.category_id) || {}).level;
        const k = lvl + '|' + d.team_name.trim().toLowerCase();
        if (!teams.has(k)) { teams.add(k); per[disc].amount += CFG.registration.team_fee; total += CFG.registration.team_fee; }
      }
    });
    return { per, total, teams: teams.size };
  }
  function sendBatch() {
    flush();
    const nos = [...SEL].filter((n) => rowState(ROWS.get(n)) === 'ok').sort((a, b) => a - b);
    const first = !BATCHES.some((b) => b.status !== 'dibatalkan');
    if (!nos.length) { JO.toast('Pilih atlet yang siap dikirim (centang di kolom paling kiri), atau tekan "Pilih semua yang siap".', 'bad'); return; }
    if (first && nos.length < minAth()) { JO.toast(`Batch pertama minimal ${minAth()} atlet. Saat ini dipilih ${nos.length}.`, 'bad'); return; }
    // pasangan dan tim harus ikut lengkap dalam batch yang sama
    const miss = [];
    nos.forEach((no) => { const d = ROWS.get(no).data; if (d.pair_row && !nos.includes(Number(d.pair_row))) miss.push(`baris ${pad3(no)} (pasangan baris ${pad3(d.pair_row)})`); });
    if (miss.length) { JO.toast('Pasangan harus dikirim di batch yang sama: ' + miss.join(', '), 'bad'); return; }
    const calc = batchCalc(nos);
    const bank = INFO.bank;
    const m = modal(`<h2>Kirim batch</h2>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Disiplin</th><th>Atlet</th><th style="text-align:right">Biaya</th></tr></thead><tbody>
        ${Object.entries(calc.per).map(([k, v]) => `<tr><td>${esc(discName(k))}</td><td>${v.n}</td><td style="text-align:right">${fmtRp(v.amount)}</td></tr>`).join('')}
        <tr><td><b>Total</b></td><td><b>${nos.length}</b></td><td style="text-align:right"><b>${fmtRp(calc.total)}</b></td></tr></tbody></table></div>
      ${calc.teams ? `<p class="small muted">Termasuk biaya beregu ${fmtRp(CFG.registration.team_fee)} × ${calc.teams} tim.</p>` : ''}
      <h3 style="margin-top:16px">Rencana transfer</h3>
      <div class="ms-split">
        <label><input type="radio" name="mode" value="penuh" checked> Sekali transfer (penuh)</label>
        <label><input type="radio" name="mode" value="rata"> Bagi rata menjadi <select id="rata_n" class="input" style="width:auto;padding:4px 8px">${[2, 3, 4, 5].map((n) => `<option>${n}</option>`).join('')}</select> transfer</label>
        <label><input type="radio" name="mode" value="bebas"> Nominal bebas, <select id="bebas_n" class="input" style="width:auto;padding:4px 8px">${[2, 3, 4, 5].map((n) => `<option>${n}</option>`).join('')}</select> transfer</label>
      </div>
      <div id="amts"></div>
      <div class="ms-bank" style="margin-top:14px"><span>Transfer ke <b>${esc(bank.bank)}</b></span><b class="num">${esc(bank.number)}</b><span>a.n. <b>${esc(bank.name)}</b> (${esc(bank.title)})</span></div>
      <label class="check" style="margin-top:14px;align-items:flex-start"><input type="checkbox" id="agree"> <span>Saya akan mentransfer <b>${fmtRp(calc.total)}</b> ke ${esc(bank.bank)} ${esc(bank.number)} a.n. ${esc(bank.name)} <b>dalam 2×24 jam</b> setelah batch dikirim, dan mengunggah setiap bukti transfer di portal ini. Data ${nos.length} atlet ini terkunci setelah dikirim.</span></label>
      <div id="b-err"></div>
      <div class="acts" id="acts"><button class="btn btn-ghost" id="no">Batal</button><button class="btn btn-dark" id="next" disabled>Kirim batch</button></div>`, true);
    let amounts = [calc.total];
    const amtsBox = m.querySelector('#amts');
    function even(n) { const base = Math.floor(calc.total / n / 1000) * 1000; const a = Array(n).fill(base); a[n - 1] = calc.total - base * (n - 1); return a; }
    function drawAmts() {
      const mode = m.querySelector('[name=mode]:checked').value;
      if (mode === 'penuh') { amounts = [calc.total]; amtsBox.innerHTML = ''; }
      else if (mode === 'rata') {
        amounts = even(Number(m.querySelector('#rata_n').value));
        amtsBox.innerHTML = `<div class="ms-amts">${amounts.map((a, i) => `<div class="note info small" style="margin:0">Transfer ${i + 1}<br><b>${fmtRp(a)}</b></div>`).join('')}</div>`;
      } else {
        const n = Number(m.querySelector('#bebas_n').value);
        if (amounts.length !== n) amounts = even(n);
        amtsBox.innerHTML = `<div class="ms-amts">${amounts.map((a, i) => `<div class="field" style="margin:0"><label class="f small" for="am${i}">Transfer ${i + 1}</label><input id="am${i}" class="input" inputmode="numeric" value="${a}"></div>`).join('')}</div><p class="small" id="am-sum"></p>`;
        amounts.forEach((_, i) => { m.querySelector('#am' + i).oninput = (e) => { amounts[i] = Number(digits(e.target.value)); sumNote(); }; });
        sumNote();
      }
      check();
    }
    function sumNote() {
      const s = amounts.reduce((a, b) => a + (b || 0), 0); const el = m.querySelector('#am-sum'); if (!el) return;
      el.innerHTML = s === calc.total ? `<span style="color:var(--ok)">Jumlah sesuai: ${fmtRp(s)}</span>` : `<span style="color:var(--bad)">Jumlah ${fmtRp(s)}; harus ${fmtRp(calc.total)} (selisih ${fmtRp(Math.abs(calc.total - s))}).</span>`;
      check();
    }
    function check() {
      const okSum = amounts.reduce((a, b) => a + (b || 0), 0) === calc.total && amounts.every((a) => a > 0);
      m.querySelector('#next').disabled = !(m.querySelector('#agree').checked && okSum);
    }
    m.querySelectorAll('[name=mode]').forEach((x) => x.onchange = drawAmts);
    m.querySelector('#rata_n').onchange = () => { m.querySelector('[value=rata]').checked = true; drawAmts(); };
    m.querySelector('#bebas_n').onchange = () => { m.querySelector('[value=bebas]').checked = true; amounts = []; drawAmts(); };
    m.querySelector('#agree').onchange = check;
    m.querySelector('#no').onclick = () => m.remove();
    m.querySelector('#next').onclick = () => {
      // konfirmasi kedua
      m.querySelector('#acts').innerHTML = `<p class="note warn" style="margin:0;flex-basis:100%">Kirim <b>${nos.length} atlet</b> dengan tagihan <b>${fmtRp(calc.total)}</b>? Setelah dikirim, data atlet ini tidak bisa diubah lagi dari portal.</p>
        <button class="btn btn-ghost" id="back">Kembali</button><button class="btn btn-ok" id="send">Ya, kirim sekarang</button>`;
      m.querySelector('#back').onclick = () => { m.remove(); sendBatch(); };
      m.querySelector('#send').onclick = async (e) => {
        const btn = e.target; btn.disabled = true; btn.textContent = 'Mengirim…'; m.dataset.busy = '1';
        try {
          await flush();
          while (saving || DIRTY.size) { await new Promise((r) => setTimeout(r, 400)); if (!saving && DIRTY.size) await flush(); if (saveErr) throw new Error('Perubahan belum tersimpan: ' + saveErr); }
          const mode = m.querySelector('[name=mode]:checked').value;
          const res = await rpc('public_bulk_submit', { p_code: CODE, p_person: PERSON, p_rows: nos, p_split: { mode, amounts }, p_confirm: 'SAYA SETUJU' });
          m.remove(); SEL.clear();
          JO.toast(`Batch ${res.batch.code} terkirim. Transfer ${fmtRp(res.batch.total)} paling lambat ${fmtDT(res.batch.due_at)}.`);
          TAB = 'batch'; await reloadAll();
        } catch (err) {
          delete m.dataset.busy;
          m.querySelector('#acts').innerHTML = `<p class="note bad" style="margin:0;flex-basis:100%">${esc(errMsg(err))}</p><button class="btn btn-ghost" id="cl">Tutup</button>`;
          m.querySelector('#cl').onclick = () => m.remove();
        }
      };
    };
    drawAmts();
  }

  // ---------------- batch & pembayaran ----------------
  function drawBatches() {
    const body = document.getElementById('ms-body'); if (!body) return;
    const bank = INFO.bank;
    if (!BATCHES.length) {
      body.innerHTML = `<section class="card"><h2>Belum ada batch</h2><p>Lengkapi lembar atlet, centang atlet yang siap, lalu tekan <b>Kirim batch</b>. Batch pertama minimal ${minAth()} atlet.</p></section>`;
      return;
    }
    body.innerHTML = `<section class="card" style="margin-bottom:12px"><h2>Rekening transfer</h2>
        <div class="ms-bank"><span>${esc(bank.bank)}</span><span><b class="num">${esc(bank.number)}</b> <button class="btn-link" id="cp">Salin</button></span><span>a.n. <b>${esc(bank.name)}</b> (${esc(bank.title)})</span></div>
        <p class="small muted" style="margin:8px 0 0">Tulis kode batch di berita transfer. Unggah setiap bukti transfer di bawah, lalu konfirmasi ke Inda lewat WhatsApp.</p></section>
      ${BATCHES.slice().reverse().map(batchHtml).join('')}`;
    body.querySelector('#cp').onclick = () => { navigator.clipboard && navigator.clipboard.writeText(bank.number); JO.toast('Nomor rekening disalin.'); };
    body.querySelectorAll('form[data-pay]').forEach((f) => f.onsubmit = (e) => payUpload(e, f));
    body.querySelectorAll('[data-cpcode]').forEach((b) => b.onclick = () => { navigator.clipboard && navigator.clipboard.writeText(b.dataset.cpcode); JO.toast('Kode batch disalin.'); });
  }
  function batchHtml(b) {
    const plan = (b.split && b.split.amounts) || [b.total];
    const live = b.payments.filter((p) => p.status !== 'tidak_cocok');
    const nextAmt = plan[live.length] || Math.max(0, b.total - b.paid_verified - b.paid_pending);
    const due = new Date(b.due_at) - Date.now();
    const pill = b.status === 'lunas' ? '<span class="pill ok">Lunas</span>' : b.status === 'dibatalkan' ? '<span class="pill bad">Dibatalkan</span>'
      : b.overdue ? '<span class="pill bad">Lewat batas bayar</span>' : '<span class="pill warn">Menunggu pembayaran</span>';
    const pctV = Math.min(100, Math.round((b.paid_verified / b.total) * 100)), pctP = Math.min(100 - pctV, Math.round((b.paid_pending / b.total) * 100));
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jakarta' });
    const cats = {};
    for (const r of ROWS.values()) if (r.batch_id === b.id && !r.data.team_only && r.data.category_id) {
      const c = catById(r.data.category_id); if (c) { cats[c.discipline] = cats[c.discipline] || {}; cats[c.discipline][c.id] = c.name_id; }
    }
    return `<div class="ms-batch">
      <div class="hd"><h3>${esc(b.code)} <button class="btn-link small" data-cpcode="${esc(b.code)}">Salin</button></h3>${pill}</div>
      <p class="small muted" style="margin:4px 0 0">${b.athletes} atlet · dikirim ${esc(fmtDT(b.created_at))} oleh ${esc(b.person || '-')}</p>
      <p style="margin:10px 0 0;font-size:1.15rem"><b>${fmtRp(b.total)}</b></p>
      <div class="ms-paybar"><i style="width:${pctV}%;float:left"></i><i class="p" style="width:${pctP}%;float:left"></i></div>
      <p class="small" style="margin:0">Terverifikasi ${fmtRp(b.paid_verified)}${b.paid_pending ? ` · menunggu verifikasi ${fmtRp(b.paid_pending)}` : ''} · sisa ${fmtRp(Math.max(0, b.total - b.paid_verified))}</p>
      ${b.status === 'menunggu' ? `<p class="small ${b.overdue ? '' : 'muted'}" style="margin:4px 0 0;${b.overdue ? 'color:var(--bad);font-weight:600' : ''}">Batas transfer dan unggah bukti: ${esc(fmtDT(b.due_at))}${due > 0 ? ` (sisa ${leftText(due)})` : ''}</p>` : ''}
      <p class="small" style="margin:8px 0 0">Rencana: ${plan.map((a, i) => `transfer ${i + 1} ${fmtRp(a)}`).join(' · ')}</p>
      ${b.payments.length ? `<div class="tbl-wrap" style="margin-top:10px"><table class="tbl"><thead><tr><th>#</th><th>Nominal</th><th>Tanggal transfer</th><th>Diunggah</th><th>Status</th></tr></thead><tbody>
        ${b.payments.map((p, i) => `<tr><td>${i + 1}</td><td>${fmtRp(p.amount)}</td><td>${esc(fmtD(p.transfer_date))}</td><td class="small">${esc(p.person || '')}<br><span class="muted">${esc(fmtDT(p.uploaded_at))}</span></td>
          <td>${p.status === 'cocok' ? '<span class="pill ok">Terverifikasi</span>' : p.status === 'tidak_cocok' ? `<span class="pill bad">Tidak cocok</span><div class="small" style="color:var(--bad)">${esc(p.note || '')}</div>` : '<span class="pill warn">Menunggu verifikasi</span>'}</td></tr>`).join('')}
        </tbody></table></div>` : ''}
      ${b.status === 'menunggu' ? `<form data-pay="${b.id}" class="card" style="margin-top:12px;padding:14px">
        <b>Unggah bukti transfer ${live.length + 1}${plan.length > 1 ? ` dari ${plan.length}` : ''}</b>
        <div class="ms-grid2" style="margin-top:8px">
          <div class="field"><label class="f small">Nominal ditransfer</label><input class="input" name="amount" inputmode="numeric" value="${nextAmt}" required></div>
          <div class="field"><label class="f small">Tanggal transfer</label><input class="input" name="date" type="date" max="${today}" value="${today}" required></div>
        </div>
        <div class="field"><label class="f small">Bukti transfer (foto atau PDF)</label><input name="file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" required></div>
        <button class="btn btn-dark btn-sm" type="submit">Unggah bukti</button>
        <div data-wa></div></form>` : ''}
      ${b.status === 'lunas' ? `<div class="note ok" style="margin-top:12px"><b>Lunas.</b> AIC sudah dikirim ke ${esc((ACC.owner || {}).email || 'email pemilik')} dengan tembusan ke orang tua/wali. Unduh di sini:
        <div style="margin-top:8px;display:grid;gap:6px">${b.submissions.map((s) => `<div><b>${esc(discName(s.discipline))}</b> (${esc(s.code)}, ${s.athletes} atlet): <a href="status.html?k=${encodeURIComponent(s.code)}&t=${encodeURIComponent(s.token)}&aic=all" target="_blank" rel="noopener">semua AIC (1 PDF)</a>
          ${Object.entries((cats[s.discipline]) || {}).map(([id, nm]) => ` · <a href="status.html?k=${encodeURIComponent(s.code)}&t=${encodeURIComponent(s.token)}&aic=cat:${id}" target="_blank" rel="noopener">${esc(nm)}</a>`).join('')}</div>`).join('')}</div></div>` : ''}
    </div>`;
  }
  async function payUpload(e, f) {
    e.preventDefault();
    const b = BATCHES.find((x) => x.id === f.dataset.pay);
    const amount = Number(digits(f.amount.value)); const date = f.date.value; const file = f.file.files[0];
    const btn = f.querySelector('button[type=submit]');
    if (!amount || !date || !file) { JO.toast('Lengkapi nominal, tanggal, dan bukti transfer.', 'bad'); return; }
    btn.disabled = true; btn.textContent = 'Mengunggah…';
    try {
      const up = await JO.uploadFile('bukti', file);
      const res = await rpc('public_bulk_pay', { p_code: CODE, p_person: PERSON, p_batch: b.id, p_amount: amount, p_date: date, p_path: up.path });
      BATCHES = res.batches;
      const nb = BATCHES.find((x) => x.id === b.id);
      const live = nb.payments.filter((p) => p.status !== 'tidak_cocok').length;
      const plan = (nb.split && nb.split.amounts || [nb.total]).length;
      const text = `Halo Kak Inda, saya ${personName()} dari ${clubName()}. Kami sudah transfer ${fmtRp(amount)} untuk ${nb.code} (pembayaran ${live} dari ${Math.max(plan, live)}) ke ${INFO.bank.bank} ${INFO.bank.number} a.n. ${INFO.bank.name} pada ${fmtD(date)}. Bukti sudah diunggah di portal. Mohon diverifikasi. Terima kasih.`;
      drawBatches();
      const box = document.querySelector(`form[data-pay="${b.id}"] [data-wa]`) || document.getElementById('ms-body');
      const note = document.createElement('div');
      note.className = 'note ok'; note.style.marginTop = '12px';
      note.innerHTML = `Bukti transfer ${fmtRp(amount)} terunggah. <a class="btn btn-ok btn-sm" style="margin-left:8px" target="_blank" rel="noopener" href="${esc(waLink(text))}">Konfirmasi ke Inda (WhatsApp)</a>`;
      (box.closest && box.closest('.ms-batch') ? box.closest('.ms-batch') : document.getElementById('ms-body')).prepend(note);
    } catch (err) {
      JO.toast(errMsg(err), 'bad'); btn.disabled = false; btn.textContent = 'Unggah bukti';
    }
  }

  // ---------------- riwayat ----------------
  const LOGTXT = {
    kode_dibuat: 'Kode akses dibuat', kode_dibuka: 'Kode pertama kali dibuka; masa pengisian dimulai', data_pemilik: 'Data pemilik dan klub diisi',
    data_pemilik_diubah: 'Data klub/kolaborator diubah', lembar_diubah: 'Mengisi lembar atlet', baris_dihapus: 'Menghapus baris', batch_dikirim: 'Mengirim batch',
    bukti_transfer: 'Mengunggah bukti transfer', transfer_cocok: 'Transfer diverifikasi', transfer_tidak_cocok: 'Transfer tidak cocok', batch_lunas: 'Batch lunas',
    diperpanjang: 'Masa pengisian diperpanjang', batas_bayar_diperpanjang: 'Batas bayar diperpanjang', kode_diganti: 'Kode akses diganti', kode_dicabut: 'Kode akses dicabut',
  };
  function logDetail(l) {
    const d = l.detail || {};
    if (l.action === 'batch_dikirim') return `${d.code}: ${d.athletes} atlet, ${fmtRp(d.total || 0)}`;
    if (['bukti_transfer', 'transfer_cocok', 'transfer_tidak_cocok'].includes(l.action)) return `${d.code}: ${fmtRp(d.amount || 0)}${d.note ? ' · ' + d.note : ''}`;
    if (l.action === 'baris_dihapus') return `Baris ${pad3(d.row_no)}${d.name ? ' (' + d.name + ')' : ''}`;
    if (l.action === 'diperpanjang') return `${d.days} hari, sampai ${fmtDT(d.expires_at)}`;
    if (l.action === 'batch_lunas') return d.code || '';
    return '';
  }
  function drawLog() {
    const body = document.getElementById('ms-body');
    body.innerHTML = `<section class="card"><h2>Riwayat</h2><div class="ms-log">${LOG.map((l) => `<div><small>${esc(fmtDT(l.at))}</small><br><b>${esc(l.person || 'Panitia')}</b> · ${esc(LOGTXT[l.action] || l.action.replace(/_/g, ' '))}${logDetail(l) ? ' · ' + esc(logDetail(l)) : ''}</div>`).join('') || '<p class="muted">Belum ada catatan.</p>'}</div></section>`;
  }

  // ---------------- mulai ----------------
  async function init() {
    JO.header('daftar.html'); JO.footer(); JO.applyI18n();
    try {
      await JO.ensureSession();
      [CFG, INFO] = await Promise.all([rpc('public_config'), rpc('public_bulk_info')]);
    } catch (e) {
      app.innerHTML = `<p class="note bad">${esc(errMsg(e))}</p>`; return;
    }
    const ls = loadLS(); CODE = ls.code || ''; PERSON = ls.person || '';
    if (JO.qs('kode')) { CODE = JO.qs('kode').toUpperCase(); PERSON = ''; saveLS(); }
    route();
  }
  init();
})();
