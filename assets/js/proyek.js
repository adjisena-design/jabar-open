/* =====================================================================
   Jabar Open 2026 — Modul Proyek (Gantt, Struktur, RAB, Pendapatan)
   Dimuat terpisah oleh konsol saat salah satu halamannya dibuka.
   Hanya owner yang mengubah; peran lain melihat dan mengunduh.
   Database tetap penjaga akses; tampilan ini hanya menyembunyikan tombol.
   ===================================================================== */
(function () {
  'use strict';
  window.JO_MOD = window.JO_MOD || {};

  const STATUS = ['Belum mulai', 'Berjalan', 'Selesai', 'Tertunda'];
  const ST_CLS = { 'Belum mulai': '', Berjalan: 'info', Selesai: 'ok', Tertunda: 'warn' };
  const SYS = ['', 'SISTEM', 'DIKURANGI', 'DIHAPUS'];
  const LEDGER = { WAG: 'Artistik Putri (WAG)', MAG: 'Artistik Putra (MAG)', RG: 'Ritmik (RG)', AER: 'Aerobik (perorangan)', 'AER-MP': 'Aerobik Mixed Pair' };
  const RANGE = ['2026-10-21', '2027-01-31'];
  const EVENT = ['2026-12-12', '2026-12-20'];
  const BLN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  const F = { phase: '', div: '', status: '', warn: false, q: '', zoom: 'hari' };
  const RF = { sec: '', q: '' };

  // ---------------- util ----------------
  const day = (s) => { if (!s) return null; const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return Date.UTC(y, m - 1, d) / 864e5; };
  const iso = (n) => new Date(n * 864e5).toISOString().slice(0, 10);
  const tgl = (s, yr) => { if (!s) return '–'; const d = new Date(day(s) * 864e5); return `${d.getUTCDate()} ${BLN[d.getUTCMonth()]}${yr ? ' ' + d.getUTCFullYear() : ''}`; };
  const num = (n, dg) => (n === null || n === undefined || n === '' ? '–' : Number(n).toLocaleString('id-ID', { maximumFractionDigits: dg ?? 0 }));
  const pct = (n) => Math.round(Number(n || 0) * 100) + '%';
  const rp = (n) => (n === null || n === undefined ? '–' : (Number(n) < 0 ? '−Rp' : 'Rp') + Math.abs(Math.round(Number(n))).toLocaleString('id-ID'));
  const stamp = () => { const d = new Date(); const p = (x) => String(x).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };
  const norm = (v) => (v === null || v === undefined ? '' : String(v).trim());
  let cssDone = false;
  function css(C) {
    if (cssDone || document.getElementById('pm-css')) return;
    const l = document.createElement('link'); l.id = 'pm-css'; l.rel = 'stylesheet'; l.href = `../assets/css/proyek.css?v=${C.version}`;
    document.head.appendChild(l); cssDone = true;
  }
  const opt = (list, cur) => list.map(([v, l]) => `<option value="${v}" ${String(cur ?? '') === String(v) ? 'selected' : ''}>${l}</option>`).join('');
  const val = (d, id) => { const el = d.querySelector('#' + id); return el ? (el.type === 'checkbox' ? el.checked : el.value.trim()) : undefined; };
  const confirmArchive = (C, what) => C.dialog({ title: 'Arsipkan ' + what + '?', ok: 'Arsipkan', okClass: 'btn-bad',
    body: `<p>Baris ini hilang dari tampilan dan unduhan, tetapi tidak dihapus: masih ada di database dan backup, dan bisa dipulihkan.</p>` });

  function toolbar(C, can, extra) {
    return `<div class="pm-tools">${extra || ''}<span class="pm-sp"></span>
      <button class="btn btn-ghost btn-sm" data-pm="dl">${C.icon('log')} Unduh xlsx</button>
      ${can ? `<button class="btn btn-ghost btn-sm" data-pm="ul">Unggah xlsx</button><input type="file" accept=".xlsx" hidden data-pm-file>` : ''}</div>`;
  }
  function wireTools(v, C, rerender) {
    const dl = v.querySelector('[data-pm="dl"]');
    if (dl) dl.onclick = async () => { dl.disabled = true; try { await downloadXlsx(C); } catch (e) { C.toast(e.message, 'bad'); } finally { dl.disabled = false; } };
    const ul = v.querySelector('[data-pm="ul"]'); const fi = v.querySelector('[data-pm-file]');
    if (ul && fi) {
      ul.onclick = () => fi.click();
      fi.onchange = async () => { const f = fi.files[0]; fi.value = ''; if (f) { try { if (await uploadXlsx(C, f)) rerender(); } catch (e) { C.toast(e.message, 'bad'); } } };
    }
  }

  // =====================================================================
  //  GANTT
  // =====================================================================
  function taskForm(C, ov, t) {
    t = t || { status: 'Belum mulai', percent: 0, critical: false };
    const divs = [['', '(tanpa divisi)'], ...ov.divisions.map((d) => [d.id, C.esc(d.name)])];
    const phases = [['', '(tanpa fase)'], ...ov.phases.map((p) => [p.no, `${p.no}. ${C.esc(p.name)}`])];
    return `<div class="grid-2">
      <div class="field"><label class="f" for="t_no">No</label><input id="t_no" inputmode="numeric" value="${C.esc(t.no ?? '')}" placeholder="otomatis"></div>
      <div class="field"><label class="f" for="t_ph">Fase</label><select id="t_ph">${opt(phases, t.phase)}</select></div></div>
      <div class="field"><label class="f" for="t_task">Tugas</label><input id="t_task" required value="${C.esc(t.task || '')}"></div>
      <div class="grid-2">
      <div class="field"><label class="f" for="t_pic">PIC</label><input id="t_pic" value="${C.esc(t.pic || '')}"></div>
      <div class="field"><label class="f" for="t_role">Peran</label><input id="t_role" value="${C.esc(t.role_text || '')}"></div></div>
      <div class="field"><label class="f" for="t_div">Divisi</label><select id="t_div">${opt(divs, t.division_id || '')}</select></div>
      <div class="grid-2">
      <div class="field"><label class="f" for="t_s">Mulai</label><input id="t_s" type="date" value="${C.esc(t.start_date || '')}"></div>
      <div class="field"><label class="f" for="t_e">Selesai</label><input id="t_e" type="date" value="${C.esc(t.end_date || '')}"></div></div>
      <div class="grid-2">
      <div class="field"><label class="f" for="t_st">Status</label><select id="t_st">${opt(STATUS.map((s) => [s, s]), t.status)}</select></div>
      <div class="field"><label class="f" for="t_pc">Progres (%)</label><input id="t_pc" type="number" min="0" max="100" step="5" value="${Math.round(Number(t.percent || 0) * 100)}"></div></div>
      <div class="field"><label class="f" for="t_pred">Pendahulu (nomor tugas)</label><input id="t_pred" value="${C.esc((t.predecessors || []).join(', '))}" placeholder="mis. 3, 7"></div>
      <label class="check"><input type="checkbox" id="t_cr" ${t.critical ? 'checked' : ''}><span>Jalur kritis</span></label>
      <div class="field"><label class="f" for="t_note">Catatan</label><textarea id="t_note">${C.esc(t.note || '')}</textarea></div>`;
  }
  function readTask(d, id) {
    const s = val(d, 't_s'); const e = val(d, 't_e');
    if (s && e && e < s) throw new Error('Tanggal selesai lebih awal dari tanggal mulai.');
    return { id: id || '', no: val(d, 't_no'), phase: val(d, 't_ph'), task: val(d, 't_task'), pic: val(d, 't_pic'), role_text: val(d, 't_role'),
      division_id: val(d, 't_div'), start_date: s, end_date: e, status: val(d, 't_st'), percent: Math.min(100, Math.max(0, Number(val(d, 't_pc') || 0))) / 100,
      predecessors: val(d, 't_pred'), critical: val(d, 't_cr'), note: val(d, 't_note') };
  }
  async function editTask(C, ov, t) {
    return C.dialog({ title: t ? `Ubah tugas ${t.no ?? ''}` : 'Tambah tugas', wide: true, body: taskForm(C, ov, t),
      onOk: (d) => C.api('console_pm_save', { p_kind: 'task', p: readTask(d, t && t.id) }) });
  }
  function showTask(C, ov, t) {
    const dv = ov.divisions.find((d) => d.id === t.division_id);
    const ph = ov.phases.find((p) => p.no === t.phase);
    C.dialog({ title: `Tugas ${t.no ?? ''}`, ok: null, cancel: 'Tutup',
      body: `<h3 style="margin-top:0">${C.esc(t.task)}</h3><dl class="pm-dl">
        <dt>Fase</dt><dd>${ph ? C.esc(`${ph.no}. ${ph.name}`) : '–'}</dd>
        <dt>PIC</dt><dd>${C.esc(t.pic || '–')}${t.role_text ? ` · ${C.esc(t.role_text)}` : ''}</dd>
        <dt>Divisi</dt><dd>${C.esc(dv ? dv.name : '–')}</dd>
        <dt>Jadwal</dt><dd>${tgl(t.start_date, 1)} – ${tgl(t.end_date, 1)}${t.duration ? ` (${t.duration} hari)` : ''}</dd>
        <dt>Status</dt><dd>${C.esc(t.status)} · ${pct(t.percent)}${t.warning ? ` <span class="pill bad">${t.warning}</span>` : ''}</dd>
        <dt>Pendahulu</dt><dd>${(t.predecessors || []).join(', ') || '–'}</dd>
        <dt>Kritis</dt><dd>${t.critical ? 'Ya' : 'Tidak'}</dd>
        ${t.note ? `<dt>Catatan</dt><dd>${C.esc(t.note)}</dd>` : ''}
        ${t.flagged ? `<dt>Tanda</dt><dd><span class="pill warn">${C.esc(t.flagged)}</span></dd>` : ''}</dl>` });
  }

  async function gantt(v, C) {
    css(C);
    const ov = await C.api('console_pm_overview');
    const can = ov.can_edit; const today = day(ov.today);
    const divName = Object.fromEntries(ov.divisions.map((d) => [d.id, d.name]));
    const T = ov.tasks;
    const cnt = { all: T.length, done: T.filter((t) => t.status === 'Selesai').length, run: T.filter((t) => t.status === 'Berjalan').length,
      late: T.filter((t) => t.warning === 'TERLAMBAT').length, start: T.filter((t) => t.warning === 'HARUS MULAI').length,
      crit: T.filter((t) => t.critical && t.status !== 'Selesai').length };
    const avg = T.length ? T.reduce((a, t) => a + Number(t.percent || 0), 0) / T.length : 0;

    const q = F.q.toLowerCase();
    const shown = T.filter((t) => (!F.phase || String(t.phase) === F.phase) && (!F.div || (F.div === '-' ? !t.division_id : t.division_id === F.div))
      && (!F.status || t.status === F.status) && (!F.warn || t.warning)
      && (!q || [t.task, t.pic, t.role_text, divName[t.division_id], t.no].join(' ').toLowerCase().includes(q)));

    // rentang grafik: 21 Okt 2026 – 31 Jan 2027, melebar bila ada tugas di luar itu
    let o = day(RANGE[0]); let z = day(RANGE[1]);
    T.forEach((t) => { if (t.start_date) o = Math.min(o, day(t.start_date)); if (t.end_date) z = Math.max(z, day(t.end_date)); });
    const W = F.zoom === 'hari' ? 22 : 5; const days = z - o + 1; const width = days * W;
    const x = (n) => (n - o) * W;

    // skala atas: bulan + hari/minggu
    let scaleM = ''; let scaleD = '';
    for (let n = o; n <= z; n++) {
      const d = new Date(n * 864e5);
      if (d.getUTCDate() === 1 || n === o) {
        const end = Math.min(z + 1, Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1) / 864e5);
        scaleM += `<span style="left:${x(n)}px;width:${(end - n) * W}px">${BLN[d.getUTCMonth()]} ${d.getUTCFullYear()}</span>`;
      }
      if (F.zoom === 'hari') scaleD += `<span class="${d.getUTCDay() % 6 === 0 ? 'we' : ''}${n === today ? ' td' : ''}" style="left:${x(n)}px;width:${W}px">${d.getUTCDate()}</span>`;
      else if (d.getUTCDay() === 1) scaleD += `<span style="left:${x(n)}px;width:${7 * W}px">${d.getUTCDate()}/${d.getUTCMonth() + 1}</span>`;
    }
    const firstMon = o + ((8 - new Date(o * 864e5).getUTCDay()) % 7);
    const gridBg = F.zoom === 'hari'
      ? `background-image:linear-gradient(to right,var(--line) 1px,transparent 1px);background-size:${W}px 100%`
      : `background-image:linear-gradient(to right,var(--line) 1px,transparent 1px);background-size:${7 * W}px 100%;background-position:${x(firstMon)}px 0`;
    const ev = `<i class="gt-ev" style="left:${x(day(EVENT[0]))}px;width:${(day(EVENT[1]) - day(EVENT[0]) + 1) * W}px"></i>`;
    const tl = today >= o && today <= z ? `<i class="gt-today" style="left:${x(today) + W / 2}px"></i>` : '';

    const bar = (t) => {
      if (!t.start_date || !t.end_date) return '';
      const s = day(t.start_date); const e = day(t.end_date);
      return `<span class="gt-bar s-${(t.status || '').replace(/\s/g, '-').toLowerCase()}${t.critical ? ' crit' : ''}${t.warning === 'TERLAMBAT' ? ' late' : ''}"
        style="left:${x(s)}px;width:${Math.max(W, (e - s + 1) * W)}px" title="${C.esc(`${t.no}. ${t.task} · ${tgl(t.start_date)}–${tgl(t.end_date)} · ${t.status} ${pct(t.percent)}`)}">
        <b style="width:${pct(t.percent)}"></b></span>`;
    };
    const warnPill = (t) => (t.warning ? `<span class="pill ${t.warning === 'TERLAMBAT' ? 'bad' : 'warn'}">${t.warning === 'TERLAMBAT' ? 'Terlambat' : 'Harus mulai'}</span>` : '');
    const menu = (t) => (can ? C.rowMenu('', [{ label: 'Ubah', attr: `data-ed="${t.id}"` }, { label: 'Arsipkan', danger: true, attr: `data-ar="${t.id}"` }]) : '');

    const groups = [];
    const byPh = new Map();
    shown.forEach((t) => { const k = t.phase ?? 'x'; if (!byPh.has(k)) { byPh.set(k, []); groups.push(k); } byPh.get(k).push(t); });
    const phName = (k) => { const p = ov.phases.find((p2) => p2.no === k); return p ? `${p.no}. ${p.name}` : 'Tanpa fase'; };

    const desk = groups.map((k) => `<tr class="gt-ph"><th class="gt-l">${C.esc(phName(k))} <span class="muted">· ${byPh.get(k).length}</span></th><td class="gt-tc"><div class="gt-tr" style="width:${width}px;${gridBg}">${ev}${tl}</div></td></tr>`
      + byPh.get(k).map((t) => `<tr data-t="${t.id}" class="${t.flagged ? 'flag' : ''}"><th class="gt-l">
          <div class="gt-name"><span class="gt-no">${t.no ?? ''}</span><span class="gt-tx" title="${C.esc(t.task)}">${C.esc(t.task)}</span>${menu(t)}</div>
          <div class="gt-meta">${C.esc(t.pic || divName[t.division_id] || '–')} · ${tgl(t.start_date)}–${tgl(t.end_date)} · <span class="pill ${ST_CLS[t.status]}">${C.esc(t.status)} ${pct(t.percent)}</span> ${warnPill(t)}${t.critical ? ' <span class="pill bad" title="Jalur kritis">K</span>' : ''}${t.flagged ? ' <span class="pill warn">Tidak ada di unggahan</span>' : ''}</div></th>
        <td class="gt-tc"><div class="gt-tr" style="width:${width}px;${gridBg}">${ev}${tl}${bar(t)}</div></td></tr>`).join('')).join('');

    const mob = groups.map((k) => `<h3 class="gm-ph">${C.esc(phName(k))}</h3>` + byPh.get(k).map((t) => `
      <article class="gm-card${t.flagged ? ' flag' : ''}" data-t="${t.id}">
        <div class="gm-top"><span class="gt-no">${t.no ?? ''}</span><b>${C.esc(t.task)}</b>${menu(t)}</div>
        <div class="gm-meta">${C.esc(t.pic || '–')}${divName[t.division_id] ? ` · ${C.esc(divName[t.division_id])}` : ''}</div>
        <div class="gm-meta">${tgl(t.start_date, 1)} – ${tgl(t.end_date, 1)}${t.duration ? ` · ${t.duration} hari` : ''}</div>
        <div class="gm-prog"><span class="gm-pb"><b style="width:${pct(t.percent)}"></b></span><span class="pill ${ST_CLS[t.status]}">${C.esc(t.status)} ${pct(t.percent)}</span></div>
        ${t.warning || t.critical || t.flagged ? `<div class="gm-flags">${warnPill(t)}${t.critical ? '<span class="pill bad">Kritis</span>' : ''}${t.flagged ? '<span class="pill warn">Tidak ada di unggahan</span>' : ''}</div>` : ''}
      </article>`).join('')).join('');

    v.innerHTML = `<h1>Gantt</h1>
      <p class="muted">Jadwal kerja panitia per fase, ${tgl(RANGE[0], 1)} sampai ${tgl(RANGE[1], 1)}. Garis merah = hari ini, arsiran = hari lomba 12–20 Desember.${can ? ' Klik tugas untuk mengubah.' : ''}</p>
      ${ov.enabled ? '' : '<p class="note warn small">Modul proyek sedang dinonaktifkan di Pengaturan. Hanya owner yang melihat halaman ini.</p>'}
      <div class="stats pm-stats pm-stats-4">
        <div class="stat"><h3>Tugas</h3><div class="big">${cnt.all}</div><p class="small muted" style="margin:4px 0 0">Progres rata-rata ${pct(avg)}</p></div>
        <div class="stat"><h3>Selesai</h3><div class="big">${cnt.done}</div><p class="small muted" style="margin:4px 0 0">${cnt.run} sedang berjalan</p></div>
        <div class="stat${cnt.late ? ' pm-bad' : ''}"><h3>Terlambat</h3><div class="big">${cnt.late}</div><p class="small muted" style="margin:4px 0 0">Lewat tanggal selesai</p></div>
        <div class="stat${cnt.start ? ' pm-warn' : ''}"><h3>Harus mulai</h3><div class="big">${cnt.start}</div><p class="small muted" style="margin:4px 0 0">${cnt.crit} tugas kritis belum selesai</p></div>
      </div>
      <div class="bar pm-filter">
        <div class="field"><label class="f" for="g_ph">Fase</label><select id="g_ph"><option value="">Semua fase</option>${opt(ov.phases.map((p) => [p.no, `${p.no}. ${C.esc(p.name)}`]), F.phase)}</select></div>
        <div class="field"><label class="f" for="g_dv">Divisi</label><select id="g_dv"><option value="">Semua divisi</option>${opt([...ov.divisions.map((d) => [d.id, C.esc(d.name)]), ['-', 'Tanpa divisi']], F.div)}</select></div>
        <div class="field"><label class="f" for="g_st">Status</label><select id="g_st"><option value="">Semua status</option>${opt(STATUS.map((s) => [s, s]), F.status)}</select></div>
        <div class="field"><label class="f" for="g_q">Cari</label><input id="g_q" type="search" value="${C.esc(F.q)}" placeholder="Tugas, PIC, nomor"></div>
        <label class="check pm-chk"><input type="checkbox" id="g_w" ${F.warn ? 'checked' : ''}><span>Hanya yang perlu perhatian</span></label>
      </div>
      ${toolbar(C, can, `<div class="seg gt-zoom" role="radiogroup" aria-label="Skala"><label><input type="radio" name="gz" value="hari" ${F.zoom === 'hari' ? 'checked' : ''}>Harian</label><label><input type="radio" name="gz" value="minggu" ${F.zoom === 'minggu' ? 'checked' : ''}>Mingguan</label></div>
        ${can ? '<button class="btn btn-primary btn-sm" id="g_add">Tambah tugas</button>' : ''}`)}
      <p class="small muted" style="margin:6px 0 10px">Menampilkan ${shown.length} dari ${T.length} tugas.</p>
      ${shown.length ? `<div class="gt-wrap gt-desk"><table class="gt"><thead><tr><th class="gt-l gt-h">Tugas</th>
          <th class="gt-tc gt-h"><div class="gt-scale" style="width:${width}px"><div class="gt-m">${scaleM}</div><div class="gt-d ${F.zoom}">${scaleD}</div></div></th></tr></thead>
          <tbody>${desk}</tbody></table></div>
        <div class="gt-mob">${mob}</div>` : '<div class="empty">Tidak ada tugas yang cocok dengan filter.</div>'}`;

    const rer = () => gantt(v, C);
    const set = (k, el, ev2) => { const e = v.querySelector(el); if (e) e.addEventListener(ev2 || 'change', () => { F[k] = e.type === 'checkbox' ? e.checked : e.value; rer(); }); };
    set('phase', '#g_ph'); set('div', '#g_dv'); set('status', '#g_st'); set('warn', '#g_w');
    const qi = v.querySelector('#g_q'); let tm;
    qi.addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(() => { F.q = qi.value; rer().then(() => { const n = v.querySelector('#g_q'); n.focus(); n.setSelectionRange(n.value.length, n.value.length); }); }, 300); });
    v.querySelectorAll('input[name=gz]').forEach((r) => (r.onchange = () => { F.zoom = r.value; rer(); }));
    wireTools(v, C, rer);
    const wrap = v.querySelector('.gt-wrap');
    if (wrap && today >= o && today <= z) wrap.scrollLeft = Math.max(0, x(today) - (F.zoom === 'hari' ? 160 : 60));
    const add = v.querySelector('#g_add');
    if (add) add.onclick = async () => { if (await editTask(C, ov, null)) { C.toast('Tugas ditambahkan.', 'ok'); rer(); } };
    const byId = Object.fromEntries(T.map((t) => [t.id, t]));
    v.querySelectorAll('[data-ed]').forEach((b) => (b.onclick = async (e) => { e.stopPropagation(); if (await editTask(C, ov, byId[b.dataset.ed])) { C.toast('Tersimpan.', 'ok'); rer(); } }));
    v.querySelectorAll('[data-ar]').forEach((b) => (b.onclick = async (e) => {
      e.stopPropagation();
      if (await confirmArchive(C, 'tugas')) { try { await C.api('console_pm_archive', { p_kind: 'task', p_id: b.dataset.ar }); C.toast('Tugas diarsipkan.', 'ok'); rer(); } catch (x2) { C.toast(x2.message, 'bad'); } }
    }));
    v.querySelectorAll('[data-t]').forEach((r) => r.addEventListener('click', async (e) => {
      if (e.target.closest('.rm')) return;
      const t = byId[r.dataset.t];
      if (can) { if (await editTask(C, ov, t)) { C.toast('Tersimpan.', 'ok'); rer(); } } else showTask(C, ov, t);
    }));
  }

  // =====================================================================
  //  STRUKTUR
  // =====================================================================
  async function struktur(v, C) {
    css(C);
    const ov = await C.api('console_pm_overview');
    const can = ov.can_edit;
    const peng = ov.divisions.filter((d) => d.tier === 'pengarah');
    const pm = ov.divisions.filter((d) => d.tier === 'pm');
    const divs = ov.divisions.filter((d) => d.tier === 'divisi');
    const tasksOf = (id) => ov.tasks.filter((t) => t.division_id === id);
    const memOf = (id) => ov.members.filter((m) => m.division_id === id);
    const prog = (list) => (list.length ? list.reduce((a, t) => a + Number(t.percent || 0), 0) / list.length : 0);
    const head = (d) => (d.head_name ? `<div class="og-head"><b>${C.esc(d.head_name)}</b>${d.head_title ? `<span class="muted"> · ${C.esc(d.head_title)}</span>` : ''}</div>`
      : '<div class="og-head muted"><i>Belum ditentukan</i></div>');
    const dmenu = (d) => (can ? C.rowMenu('', [{ label: 'Ubah divisi', attr: `data-dv="${d.id}"` }, { label: 'Tambah anggota', attr: `data-am="${d.id}"` }, { sep: true }, { label: 'Arsipkan divisi', danger: true, attr: `data-da="${d.id}"` }]) : '');
    const card = (d, cls) => {
      const ts = tasksOf(d.id); const ms = memOf(d.id);
      const late = ts.filter((t) => t.warning === 'TERLAMBAT').length;
      return `<article class="og-card ${cls || ''}">
        <header><h3>${C.esc(d.name)}</h3>${dmenu(d)}</header>
        ${head(d)}
        ${d.description ? `<p class="small muted og-desc">${C.esc(d.description)}</p>` : ''}
        ${ms.length ? `<ul class="og-mem">${ms.map((m) => `<li><span>${C.esc(m.name)}${m.role_text ? `<span class="muted"> · ${C.esc(m.role_text)}</span>` : ''}</span>
            ${can ? C.rowMenu('', [{ label: 'Ubah', attr: `data-me="${m.id}"` }, { label: 'Arsipkan', danger: true, attr: `data-ma="${m.id}"` }]) : ''}</li>`).join('')}</ul>` : ''}
        ${ts.length ? `<details class="og-tasks"><summary>${ts.length} tugas · ${pct(prog(ts))}${late ? ` · <span class="bad-t">${late} terlambat</span>` : ''}</summary>
            <ol>${ts.map((t) => `<li><span class="gt-no">${t.no ?? ''}</span> ${C.esc(t.task)} <span class="muted">· ${tgl(t.end_date)}</span> <span class="pill ${ST_CLS[t.status]}">${C.esc(t.status)}</span></li>`).join('')}</ol></details>`
          : (cls === 'og-peng' ? '' : '<p class="small muted" style="margin:8px 0 0">Belum ada tugas.</p>')}
      </article>`;
    };
    const loose = ov.tasks.filter((t) => !t.division_id);
    v.innerHTML = `<h1>Struktur</h1>
      <p class="muted">Bagan panitia dari data divisi dan tugas di Gantt. Pengarah memberi arahan lewat Project Manager; PM satu pintu ke seluruh divisi.</p>
      ${toolbar(C, false, can ? '<button class="btn btn-primary btn-sm" id="o_add">Tambah divisi</button>' : '')}
      <div class="og">
        <div class="og-row og-top">${peng.map((d) => card(d, 'og-peng')).join('')}</div>
        <div class="og-link" aria-hidden="true"></div>
        <div class="og-row og-mid">${pm.map((d) => card(d, 'og-pm')).join('')}</div>
        <div class="og-link solid" aria-hidden="true"></div>
        <div class="og-grid">${divs.map((d) => card(d)).join('')}</div>
      </div>
      ${loose.length ? `<section class="card" style="margin-top:18px"><h2>Tugas tanpa divisi (${loose.length})</h2>
        <ol class="og-loose">${loose.map((t) => `<li><span class="gt-no">${t.no ?? ''}</span> ${C.esc(t.task)} <span class="muted">· ${C.esc(t.pic || '–')} · ${tgl(t.end_date)}</span></li>`).join('')}</ol></section>` : ''}`;

    const rer = () => struktur(v, C);
    wireTools(v, C, rer);
    const divForm = (d) => `<div class="field"><label class="f" for="d_n">Nama divisi</label><input id="d_n" required value="${C.esc(d.name || '')}"></div>
      <div class="field"><label class="f" for="d_t">Tingkat</label><select id="d_t">${opt([['divisi', 'Divisi'], ['pm', 'Project Manager'], ['pengarah', 'Pengarah']], d.tier || 'divisi')}</select></div>
      <div class="grid-2"><div class="field"><label class="f" for="d_h">Ketua / kepala</label><input id="d_h" value="${C.esc(d.head_name || '')}" placeholder="kosong = belum ditentukan"></div>
      <div class="field"><label class="f" for="d_ht">Jabatan</label><input id="d_ht" value="${C.esc(d.head_title || '')}"></div></div>
      <div class="field"><label class="f" for="d_d">Keterangan</label><textarea id="d_d">${C.esc(d.description || '')}</textarea></div>`;
    const saveDiv = (d) => C.dialog({ title: d.id ? 'Ubah divisi' : 'Tambah divisi', body: divForm(d),
      onOk: (x) => C.api('console_pm_save', { p_kind: 'division', p: { id: d.id || '', name: val(x, 'd_n'), tier: val(x, 'd_t'), head_name: val(x, 'd_h'), head_title: val(x, 'd_ht'), description: val(x, 'd_d') } }) });
    const memForm = (m) => `<div class="field"><label class="f" for="m_d">Divisi</label><select id="m_d">${opt(ov.divisions.map((d) => [d.id, C.esc(d.name)]), m.division_id)}</select></div>
      <div class="field"><label class="f" for="m_n">Nama</label><input id="m_n" required value="${C.esc(m.name || '')}"></div>
      <div class="field"><label class="f" for="m_r">Peran</label><input id="m_r" value="${C.esc(m.role_text || '')}"></div>
      <div class="field"><label class="f" for="m_p">Nomor WhatsApp</label><input id="m_p" inputmode="tel" value="${C.esc(m.phone || '')}"></div>`;
    const saveMem = (m) => C.dialog({ title: m.id ? 'Ubah anggota' : 'Tambah anggota', body: memForm(m),
      onOk: (x) => C.api('console_pm_save', { p_kind: 'member', p: { id: m.id || '', division_id: val(x, 'm_d'), name: val(x, 'm_n'), role_text: val(x, 'm_r'), phone: val(x, 'm_p') } }) });
    const D = Object.fromEntries(ov.divisions.map((d) => [d.id, d])); const M = Object.fromEntries(ov.members.map((m) => [m.id, m]));
    const done = (ok, msg) => { if (ok) { C.toast(msg || 'Tersimpan.', 'ok'); rer(); } };
    const arch = async (kind, id, what) => { if (await confirmArchive(C, what)) { try { await C.api('console_pm_archive', { p_kind: kind, p_id: id }); done(true, 'Diarsipkan.'); } catch (e) { C.toast(e.message, 'bad'); } } };
    const a = v.querySelector('#o_add'); if (a) a.onclick = async () => done(await saveDiv({}));
    v.querySelectorAll('[data-dv]').forEach((b) => (b.onclick = async () => done(await saveDiv(D[b.dataset.dv]))));
    v.querySelectorAll('[data-am]').forEach((b) => (b.onclick = async () => done(await saveMem({ division_id: b.dataset.am }))));
    v.querySelectorAll('[data-me]').forEach((b) => (b.onclick = async () => done(await saveMem(M[b.dataset.me]))));
    v.querySelectorAll('[data-da]').forEach((b) => (b.onclick = () => arch('division', b.dataset.da, 'divisi')));
    v.querySelectorAll('[data-ma]').forEach((b) => (b.onclick = () => arch('member', b.dataset.ma, 'anggota')));
  }

  // =====================================================================
  //  RAB
  // =====================================================================
  const SRC = ['Inda Sofia (Sheet1)', 'RAB Aktual 2025 +20%', 'Usulan Daffa', 'RAB Aktual 2025 (analisis sistem)'];
  function rabForm(C, fin, it) {
    const secs = fin.sections.map((s) => [s.code, `${s.code}. ${C.esc(s.name)}`]);
    const srcs = [...new Set([...SRC, it.source || ''].filter(Boolean))].map((x) => [x, x]);
    return `<div class="field"><label class="f" for="r_sec">Seksi</label><select id="r_sec">${opt(secs, it.section)}</select></div>
      <div class="field"><label class="f" for="r_u">Uraian kebutuhan</label><input id="r_u" required value="${C.esc(it.uraian || '')}"></div>
      <div class="grid-2"><div class="field"><label class="f" for="r_v">Volume</label><input id="r_v" inputmode="decimal" value="${C.esc(it.vol ?? '')}">
          <label class="check pm-chk"><input type="checkbox" id="r_vd" ${it.vol_days ? 'checked' : ''}><span>Ikut jumlah hari kegiatan (${num(fin.params.event_days)})</span></label></div>
        <div class="field"><label class="f" for="r_s">Satuan</label><input id="r_s" value="${C.esc(it.satuan || '')}"></div></div>
      <div class="grid-2"><div class="field"><label class="f" for="r_f">Frekuensi</label><input id="r_f" inputmode="decimal" value="${C.esc(it.freq ?? '')}">
          <label class="check pm-chk"><input type="checkbox" id="r_fd" ${it.freq_days ? 'checked' : ''}><span>Ikut jumlah hari kegiatan</span></label><p class="f-hint">Kosong = 1.</p></div>
        <div class="field"><label class="f" for="r_fu">Satuan frekuensi</label><input id="r_fu" value="${C.esc(it.freq_unit || '')}" placeholder="hari, jam, keping, orang"></div></div>
      <div class="field"><label class="f" for="r_pf">Harga satuan (Rp)</label><input id="r_pf" inputmode="numeric" value="${C.esc(it.price_final ?? '')}"><p class="f-hint">Jumlah = volume × frekuensi × harga satuan.</p></div>
      <div class="grid-2"><div class="field"><label class="f" for="r_c">Dihitung di total</label><select id="r_c">${opt([['true', 'Ya'], ['false', 'Tidak (acuan)']], String(it.counted !== false))}</select></div>
        <div class="field"><label class="f" for="r_src">Sumber</label><select id="r_src"><option value="">(tidak ada)</option>${opt(srcs, it.source || '')}</select></div></div>
      <div class="field"><label class="f" for="r_k">Keterangan</label><input id="r_k" value="${C.esc(it.keterangan || '')}"></div>
      <div class="field"><label class="f" for="r_n">Catatan</label><textarea id="r_n">${C.esc(it.note || '')}</textarea></div>`;
  }
  function editRab(C, fin, it) {
    return C.dialog({ title: it.id ? 'Ubah baris RAB' : 'Tambah baris RAB', wide: true, body: rabForm(C, fin, it),
      onOk: (d) => C.api('console_pm_save', { p_kind: 'rab_item', p: { id: it.id || '', section: val(d, 'r_sec'), sort: it.sort ?? '', uraian: val(d, 'r_u'), keterangan: val(d, 'r_k'),
        vol: val(d, 'r_v'), satuan: val(d, 'r_s'), vol_days: val(d, 'r_vd'), freq: val(d, 'r_f'), freq_unit: val(d, 'r_fu'), freq_days: val(d, 'r_fd'),
        price_final: val(d, 'r_pf'), counted: val(d, 'r_c') === 'true', source: val(d, 'r_src'), status_sistem: it.status_sistem || '', pct_replaced: it.pct_replaced || 0, note: val(d, 'r_n') } }) });
  }

  async function rab(v, C) {
    css(C);
    const fin = await C.api('console_pm_finance');
    const can = fin.can_edit; const S = fin.summary; const P = fin.params;
    const q = RF.q.toLowerCase();
    const items = fin.items.filter((i) => (!RF.sec || i.section === RF.sec) && (!q || [i.uraian, i.keterangan, i.note, i.satuan, i.source].join(' ').toLowerCase().includes(q)));
    const dayTag = (on) => (on ? ' <span class="pill" title="Ikut jumlah hari kegiatan">hari</span>' : '');
    const secHtml = fin.sections.filter((s) => items.some((i) => i.section === s.code)).map((s) => {
      const rows = items.filter((i) => i.section === s.code);
      const all = fin.items.filter((i) => i.section === s.code);
      const sub = all.filter((i) => s.is_note || i.counted !== false).reduce((a, i) => a + Number(i.total || 0), 0);
      const ref = s.is_note ? 0 : all.filter((i) => i.counted === false).reduce((a, i) => a + Number(i.total || 0), 0);
      return `<section class="rab-sec${s.is_note ? ' rab-note' : ''}"><header><h2>${C.esc(s.code)}. ${C.esc(s.name)}</h2>
          <span class="rab-sub">${s.is_note ? '<span class="muted">tidak dihitung · </span>' : ''}${rp(sub)}${ref ? ` <span class="muted">· acuan ${rp(ref)}</span>` : ''}</span>
          ${can ? `<button class="btn btn-ghost btn-sm" data-ra="${C.esc(s.code)}">Tambah baris</button>` : ''}</header>
        <div class="tbl-wrap"><table class="tbl rab-tbl"><thead><tr><th>Uraian</th><th class="r">Vol</th><th>Satuan</th><th class="r">Frek</th><th>Satuan frek</th>
          <th class="r">Harga satuan</th><th class="r">Jumlah</th><th>Dihitung</th><th>Sumber</th>${can ? '<th></th>' : ''}</tr></thead><tbody>
          ${rows.map((i) => { const nc = i.counted === false || s.is_note; const hl = i.status_sistem === 'SISTEM' && !nc;
            return `<tr data-r="${i.id}" class="${can ? 'click ' : ''}${nc ? 'rab-nc' : ''}${hl ? ' rab-hl' : ''}${i.flagged ? ' flag' : ''}">
            <td><b>${C.esc(i.uraian)}</b>${i.keterangan ? `<div class="tiny muted">${C.esc(i.keterangan)}</div>` : ''}${i.note ? `<div class="tiny muted">Catatan: ${C.esc(i.note)}</div>` : ''}${i.flagged ? `<div><span class="pill warn">${C.esc(i.flagged)}</span></div>` : ''}</td>
            <td class="r num">${num(i.vol_eff, 2)}${dayTag(i.vol_days)}</td><td>${C.esc(i.satuan || '')}</td>
            <td class="r num">${i.freq_eff === null || i.freq_eff === undefined ? '–' : num(i.freq_eff, 2)}${dayTag(i.freq_days)}</td><td>${C.esc(i.freq_unit || '')}</td>
            <td class="r num">${rp(i.price_2026)}</td><td class="r num"><b>${rp(i.total)}</b></td>
            <td>${nc ? '<span class="pill">Tidak</span>' : hl ? '<span class="pill bad">Ya · dihitung</span>' : 'Ya'}</td>
            <td class="small">${C.esc(i.source || '')}</td>
            ${can ? `<td class="r">${C.rowMenu('', [{ label: 'Ubah', attr: `data-re="${i.id}"` }, { label: 'Arsipkan', danger: true, attr: `data-rx="${i.id}"` }])}</td>` : ''}</tr>`; }).join('')}
          </tbody></table></div></section>`;
    }).join('');
    v.innerHTML = `<h1>RAB</h1>
      <p class="muted">Jumlah = volume × frekuensi × harga satuan. Baris bertanda <span class="pill">hari</span> mengikuti jumlah hari kegiatan. Baris "Tidak" tampil sebagai acuan dan tidak masuk total.</p>
      <div class="stats pm-stats">
        <div class="stat"><h3>Total anggaran (dihitung)</h3><div class="big">${rp(S.total)}</div><ul><li><span>Di luar sistem website</span><b>${rp(S.ops)}</b></li><li><span>Sistem website</span><b>${rp(S.system)}</b></li></ul></div>
        <div class="stat"><h3>Acuan (tidak dihitung)</h3><div class="big">${rp(S.reference)}</div><ul><li><span>Efisiensi karena sistem (nilai 2025)</span><b>${rp(S.efficiency)}</b></li></ul></div>
        <div class="stat"><h3>Dibanding pendapatan</h3><div class="big ${S.balance < 0 ? 'bad-t' : 'ok-t'}">${rp(S.balance)}</div><ul><li><span>Target pendapatan</span><b>${rp(S.income)}</b></li><li><span>Total anggaran</span><b>${rp(S.total)}</b></li></ul></div>
      </div>
      <section class="card pm-params"><div><h2 style="margin:0 0 4px">Parameter</h2>
        <p class="small" style="margin:0">Jumlah hari kegiatan <b>${num(P.event_days)}</b></p>
        ${P.note ? `<p class="small muted" style="margin:6px 0 0;white-space:pre-line">${C.esc(P.note)}</p>` : ''}</div>
        ${can ? '<button class="btn btn-ghost btn-sm" id="r_par">Ubah parameter</button>' : ''}</section>
      <div class="bar pm-filter">
        <div class="field"><label class="f" for="r_fs">Seksi</label><select id="r_fs"><option value="">Semua seksi</option>${opt(fin.sections.map((s) => [s.code, `${s.code}. ${C.esc(s.name)}`]), RF.sec)}</select></div>
        <div class="field"><label class="f" for="r_q">Cari</label><input id="r_q" type="search" value="${C.esc(RF.q)}" placeholder="Uraian, sumber, catatan"></div>
      </div>
      ${toolbar(C, can)}
      ${secHtml || '<div class="empty">Tidak ada baris yang cocok.</div>'}`;
    C.labelTables(v);
    const rer = () => rab(v, C);
    wireTools(v, C, rer);
    v.querySelector('#r_fs').onchange = (e) => { RF.sec = e.target.value; rer(); };
    const qi = v.querySelector('#r_q'); let tm;
    qi.addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(() => { RF.q = qi.value; rer().then(() => { const n = v.querySelector('#r_q'); n.focus(); n.setSelectionRange(n.value.length, n.value.length); }); }, 300); });
    const byId = Object.fromEntries(fin.items.map((i) => [i.id, i]));
    const done = (ok, m) => { if (ok) { C.toast(m || 'Tersimpan.', 'ok'); rer(); } };
    const par = v.querySelector('#r_par');
    if (par) par.onclick = async () => done(await C.dialog({ title: 'Parameter RAB',
      body: `<div class="field"><label class="f" for="p_e">Jumlah hari kegiatan</label><input id="p_e" type="number" min="1" value="${P.event_days}"><p class="f-hint">Dipakai semua baris bertanda "hari".</p></div>
        <div class="field"><label class="f" for="p_n">Catatan</label><textarea id="p_n" rows="5">${C.esc(P.note || '')}</textarea></div>`,
      onOk: (d) => C.api('console_pm_save', { p_kind: 'params', p: { event_days: val(d, 'p_e'), note: val(d, 'p_n') } }) }));
    v.querySelectorAll('[data-ra]').forEach((b) => (b.onclick = async () => done(await editRab(C, fin, { section: b.dataset.ra, vol: 1, counted: true }))));
    v.querySelectorAll('[data-re]').forEach((b) => (b.onclick = async (e) => { e.stopPropagation(); done(await editRab(C, fin, byId[b.dataset.re])); }));
    v.querySelectorAll('[data-rx]').forEach((b) => (b.onclick = async (e) => {
      e.stopPropagation();
      if (await confirmArchive(C, 'baris RAB')) { try { await C.api('console_pm_archive', { p_kind: 'rab_item', p_id: b.dataset.rx }); done(true, 'Diarsipkan.'); } catch (x) { C.toast(x.message, 'bad'); } }
    }));
    if (can) v.querySelectorAll('tr[data-r]').forEach((r) => r.addEventListener('click', async (e) => { if (!e.target.closest('.rm')) done(await editRab(C, fin, byId[r.dataset.r])); }));
  }

  // =====================================================================
  //  PENDAPATAN
  // =====================================================================
  function actualOf(fin, key) {
    const A = fin.actual.by_discipline || {};
    if (key === 'AER-MP') { const a = A.AER || {}; return { n: a.pairs_paid || 0, unit: 'pasangan lunas', rp: a.pair_fees || 0 }; }
    const a = A[key]; if (!a) return null;
    const rpv = key === 'AER' ? (a.paid || 0) - (a.pair_fees || 0) : a.paid || 0;
    return { n: a.athletes_paid || 0, reg: a.athletes_registered || 0, unit: 'atlet lunas', rp: rpv };
  }
  async function editIncome(C, it) {
    return C.dialog({ title: it.id ? 'Ubah sumber pendapatan' : 'Tambah sumber pendapatan',
      body: `<div class="field"><label class="f" for="i_g">Kelompok</label><select id="i_g">${opt([['2025', 'A. Dasar 2025'], ['2026', 'B. Tambahan 2026']], it.grp)}</select></div>
        <div class="field"><label class="f" for="i_s">Sumber</label><input id="i_s" required value="${C.esc(it.source || '')}"></div>
        <div class="field"><label class="f" for="i_k">Keterangan</label><input id="i_k" value="${C.esc(it.keterangan || '')}"></div>
        <div class="grid-2"><div class="field"><label class="f" for="i_v">Volume</label><input id="i_v" inputmode="decimal" value="${C.esc(it.vol ?? '')}"></div>
        <div class="field"><label class="f" for="i_u">Satuan</label><input id="i_u" value="${C.esc(it.unit || '')}"></div></div>
        <div class="field"><label class="f" for="i_r">Tarif (Rp)</label><input id="i_r" inputmode="numeric" value="${C.esc(it.rate ?? '')}"></div>
        <div class="field"><label class="f" for="i_l">Bandingkan dengan pendaftaran</label><select id="i_l">${opt([['', '(tidak)'], ...Object.entries(LEDGER)], it.ledger_key || '')}</select></div>
        <div class="field"><label class="f" for="i_n">Catatan</label><textarea id="i_n">${C.esc(it.note || '')}</textarea></div>`,
      onOk: (d) => {
        if (val(d, 'i_s').length < 2) throw new Error('Isi sumber pendapatan.');
        return C.api('console_pm_save', { p_kind: 'income_item', p: { id: it.id || '', grp: val(d, 'i_g'), source: val(d, 'i_s'), keterangan: val(d, 'i_k'), vol: val(d, 'i_v'), unit: val(d, 'i_u'), rate: val(d, 'i_r'), ledger_key: val(d, 'i_l'), note: val(d, 'i_n') } });
      } });
  }
  async function pendapatan(v, C) {
    css(C);
    const fin = await C.api('console_pm_finance');
    const can = fin.can_edit; const S = fin.summary; const Act = fin.actual;
    const grp = (g, title) => {
      const rows = fin.income.filter((i) => i.grp === g); const tot = rows.reduce((a, i) => a + Number(i.total || 0), 0);
      return `<section class="rab-sec"><header><h2>${title}</h2><span class="rab-sub">${rp(tot)}</span>${can ? `<button class="btn btn-ghost btn-sm" data-ia="${g}">Tambah baris</button>` : ''}</header>
        ${rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Sumber</th><th class="r">Vol</th><th>Satuan</th><th class="r">Tarif</th><th class="r">Target</th><th class="r">Realisasi (lunas)</th><th class="r">Capaian</th>${can ? '<th></th>' : ''}</tr></thead><tbody>
          ${rows.map((i) => { const a = i.ledger_key ? actualOf(fin, i.ledger_key) : null; const p = a && Number(i.total) ? a.rp / Number(i.total) : null;
            return `<tr data-i="${i.id}" class="${can ? 'click' : ''}${i.flagged ? ' flag' : ''}"><td><b>${C.esc(i.source || '–')}</b>${i.keterangan ? `<div class="tiny muted">${C.esc(i.keterangan)}</div>` : ''}${i.note ? `<div class="tiny muted">Catatan: ${C.esc(i.note)}</div>` : ''}${i.flagged ? `<div><span class="pill warn">${C.esc(i.flagged)}</span></div>` : ''}</td>
              <td class="r num">${num(i.vol, 2)}</td><td>${C.esc(i.unit || '')}</td><td class="r num">${rp(i.rate)}</td><td class="r num"><b>${rp(i.total)}</b></td>
              <td class="r num">${a ? `${rp(a.rp)}<div class="tiny muted">${a.n} ${a.unit}${a.reg !== undefined ? ` · ${a.reg} terdaftar` : ''}</div>` : '<span class="muted">–</span>'}</td>
              <td class="r">${p === null ? '' : `<span class="pm-pb" title="${pct(p)}"><b style="width:${Math.min(100, p * 100)}%"></b></span> ${pct(p)}`}</td>
              ${can ? `<td class="r">${C.rowMenu('', [{ label: 'Ubah', attr: `data-ie="${i.id}"` }, { label: 'Arsipkan', danger: true, attr: `data-ix="${i.id}"` }])}</td>` : ''}</tr>`; }).join('')}
          </tbody></table></div>` : '<p class="small muted">Belum ada baris.</p>'}</section>`;
    };
    v.innerHTML = `<h1>Pendapatan</h1>
      <p class="muted">Target pendapatan (dasar 2025 dan tambahan 2026) berdampingan dengan realisasi dari pendaftaran yang sudah lunas di konsol. Realisasi diperbarui setiap halaman dibuka.</p>
      <div class="stats pm-stats">
        <div class="stat"><h3>Target pendapatan</h3><div class="big">${rp(S.income)}</div><ul><li><span>Total anggaran</span><b>${rp(S.after_saving)}</b></li><li><span>Selisih target</span><b class="${S.balance < 0 ? 'bad-t' : 'ok-t'}">${rp(S.balance)}</b></li></ul></div>
        <div class="stat"><h3>Sudah lunas</h3><div class="big">${rp(Act.paid_total)}</div><ul><li><span>Capaian target</span><b>${S.income ? pct(Act.paid_total / S.income) : '–'}</b></li><li><span>Belum lunas (tagihan aktif)</span><b>${rp(Act.outstanding)}</b></li></ul></div>
      </div>
      ${toolbar(C, can)}
      ${grp('2025', 'A. Dasar 2025')}
      ${grp('2026', 'B. Tambahan 2026')}`;
    C.labelTables(v);
    const rer = () => pendapatan(v, C);
    wireTools(v, C, rer);
    const byId = Object.fromEntries(fin.income.map((i) => [i.id, i]));
    const done = (ok, m) => { if (ok) { C.toast(m || 'Tersimpan.', 'ok'); rer(); } };
    v.querySelectorAll('[data-ia]').forEach((b) => (b.onclick = async () => done(await editIncome(C, { grp: b.dataset.ia, vol: 1 }))));
    v.querySelectorAll('[data-ie]').forEach((b) => (b.onclick = async (e) => { e.stopPropagation(); done(await editIncome(C, byId[b.dataset.ie])); }));
    v.querySelectorAll('[data-ix]').forEach((b) => (b.onclick = async (e) => {
      e.stopPropagation();
      if (await confirmArchive(C, 'baris pendapatan')) { try { await C.api('console_pm_archive', { p_kind: 'income_item', p_id: b.dataset.ix }); done(true, 'Diarsipkan.'); } catch (x) { C.toast(x.message, 'bad'); } }
    }));
    if (can) v.querySelectorAll('tr[data-i]').forEach((r) => r.addEventListener('click', async (e) => { if (!e.target.closest('.rm')) done(await editIncome(C, byId[r.dataset.i])); }));
  }

  // =====================================================================
  //  XLSX: unduh (rumus hidup, kolom ID tersembunyi) & unggah (pratinjau)
  // =====================================================================
  const serial = (s) => (s ? day(s) + 25569 : null);           // tanggal -> nomor seri Excel
  const enc = (r, c) => XLSX.utils.encode_cell({ r, c });
  function sheet(rows, cols) {
    // rows: array of arrays; sel boleh {f, z} / {v, z} / nilai biasa
    const ws = {};
    let maxC = 0;
    rows.forEach((row, r) => row.forEach((cell, c) => {
      if (cell === undefined || cell === null || cell === '') return;
      maxC = Math.max(maxC, c);
      const o = typeof cell === 'object' ? { ...cell } : { v: cell };
      if (o.f) { o.t = o.t || (o.s ? 's' : 'n'); delete o.s; } else if (o.t === undefined) o.t = typeof o.v === 'number' ? 'n' : typeof o.v === 'boolean' ? 'b' : 's';
      ws[enc(r, c)] = o;
    }));
    ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: Math.max(rows.length - 1, 0), c: Math.max(maxC, cols.length - 1) } });
    ws['!cols'] = cols;
    return ws;
  }
  const D_ = (s) => (s ? { v: serial(s), t: 'n', z: 'dd/mm/yyyy' } : '');
  const RP = (n) => (n === null || n === undefined || n === '' ? '' : { v: Number(n), t: 'n', z: '#,##0' });
  const N_ = (n) => (n === null || n === undefined || n === '' ? '' : Number(n));

  async function downloadXlsx(C) {
    if (!window.XLSX) throw new Error('Pustaka Excel belum termuat. Muat ulang halaman.');
    const ov = await C.api('console_pm_overview');
    const fin = ov.can_finance ? await C.api('console_pm_finance') : null;
    const wb = XLSX.utils.book_new();
    const divName = Object.fromEntries(ov.divisions.map((d) => [d.id, d.name]));
    const phName = Object.fromEntries(ov.phases.map((p) => [p.no, p.name]));
    const ro = 'Kolom abu-abu (Durasi, Peringatan) dihitung otomatis. Kolom A (ID) tersembunyi: jangan diubah. Baris baru: biarkan ID kosong.';

    // ---- Gantt ----
    const GH = ['ID', 'No', 'Fase', 'Nama fase', 'Tugas', 'PIC', 'Peran', 'Divisi', 'Mulai', 'Selesai', 'Durasi (hari)', 'Pendahulu', 'Kritis', 'Status', 'Progres', 'Peringatan', 'Catatan', 'Tanda'];
    const g = [['GANTT · Jabar Open 2026'], [ro], [`Status: ${STATUS.join(' / ')}. Kritis: Ya / Tidak. Progres 0–100%. Divisi harus sama persis dengan nama di tab Struktur.`], GH];
    ov.tasks.forEach((t) => {
      const r = g.length + 1;
      g.push([t.id, N_(t.no), N_(t.phase), phName[t.phase] || '', t.task, t.pic || '', t.role_text || '', divName[t.division_id] || '', D_(t.start_date), D_(t.end_date),
        { f: `IF(OR(I${r}="",J${r}=""),"",J${r}-I${r}+1)` }, (t.predecessors || []).join(', '), t.critical ? 'Ya' : 'Tidak', t.status,
        { v: Number(t.percent || 0), t: 'n', z: '0%' },
        { f: `IF(OR(J${r}="",N${r}="Selesai"),"",IF(J${r}<TODAY(),"TERLAMBAT",IF(AND(I${r}<=TODAY(),N${r}="Belum mulai"),"HARUS MULAI","")))`, s: 1 },
        t.note || '', t.flagged || '']);
    });
    XLSX.utils.book_append_sheet(wb, sheet(g, [{ hidden: true, wch: 38 }, { wch: 5 }, { wch: 5 }, { wch: 22 }, { wch: 52 }, { wch: 22 }, { wch: 22 }, { wch: 24 }, { wch: 11 }, { wch: 11 }, { wch: 8 }, { wch: 10 }, { wch: 7 }, { wch: 12 }, { wch: 9 }, { wch: 13 }, { wch: 30 }, { wch: 24 }]), 'Gantt');

    // ---- Struktur (dibaca saja; jumlah tugas pakai rumus) ----
    const s = [['STRUKTUR · Jabar Open 2026'], ['Dibuat dari tab Gantt dan data divisi. Tab ini tidak dibaca saat unggah; ubah struktur di konsol.'], [],
      ['Divisi', 'Tingkat', 'Ketua / kepala', 'Jabatan', 'Anggota', 'Jumlah tugas', 'Tugas selesai', 'Keterangan']];
    ov.divisions.forEach((d) => {
      const r = s.length + 1; const nm = d.name.replace(/"/g, '""');
      s.push([d.name, { pengarah: 'Pengarah', pm: 'Project Manager', divisi: 'Divisi' }[d.tier] || d.tier, d.head_name || 'Belum ditentukan', d.head_title || '',
        ov.members.filter((m) => m.division_id === d.id).map((m) => m.name + (m.role_text ? ` (${m.role_text})` : '')).join('; '),
        { f: `COUNTIF(Gantt!H:H,"${nm}")` }, { f: `COUNTIFS(Gantt!H:H,"${nm}",Gantt!N:N,"Selesai")` }, d.description || '']);
      void r;
    });
    XLSX.utils.book_append_sheet(wb, sheet(s, [{ wch: 30 }, { wch: 16 }, { wch: 32 }, { wch: 30 }, { wch: 60 }, { wch: 12 }, { wch: 12 }, { wch: 60 }]), 'Struktur');

    if (fin) {
      const P = fin.params;
      const secName = Object.fromEntries(fin.sections.map((x) => [x.code, x.name]));
      const notes = new Set(fin.sections.filter((x) => x.is_note).map((x) => x.code));
      // ---- RAB ----
      const H = 10; // baris judul kolom
      const first = H + 1; const last = H + fin.items.length;
      const rng = (c) => `${c}$${first}:${c}$${Math.max(last, first)}`;
      const exNote = [...notes].map((c) => `,${rng('B')},"<>${c}"`).join('');
      const R = [['RAB 2026 · Jabar Open 2026'],
        ['Parameter', 'Jumlah hari kegiatan', Number(P.event_days)],
        ['Ringkasan', 'Total anggaran (dihitung)', { f: `SUMIFS(${rng('K')},${rng('L')},"Ya"${exNote})`, z: '#,##0' }],
        ['', 'Acuan (tidak dihitung)', { f: `SUMIFS(${rng('K')},${rng('L')},"Tidak"${exNote})`, z: '#,##0' }],
        ['', 'Efisiensi karena sistem (nilai 2025)', { f: [...notes].map((c) => `SUMIFS(${rng('K')},${rng('B')},"${c}")`).join('+') || '0', z: '#,##0' }],
        ['', 'Target pendapatan', { f: 'Pendapatan!C3', z: '#,##0' }],
        ['', 'Selisih', { f: 'C6-C3', z: '#,##0' }],
        [],
        [ro + ' Jumlah = rumus (Vol × Frek × Harga satuan). Ikut hari: Vol / Frek / Vol+Frek mengikuti C2. Dihitung: Ya / Tidak.'],
        ['ID', 'Seksi', 'No', 'Uraian', 'Keterangan', 'Vol', 'Satuan', 'Frek', 'Satuan frek', 'Harga satuan', 'Jumlah', 'Dihitung', 'Ikut hari', 'Sumber', 'Status sistem', 'Catatan', 'Nama seksi', 'Tanda']];
      const nos = {};
      fin.items.forEach((i) => {
        const r = R.length + 1; nos[i.section] = (nos[i.section] || 0) + 1;
        const ih = i.vol_days && i.freq_days ? 'Vol+Frek' : i.vol_days ? 'Vol' : i.freq_days ? 'Frek' : '';
        R.push([i.id, i.section, nos[i.section], i.uraian, i.keterangan || '', i.vol_days ? { f: '$C$2' } : N_(i.vol), i.satuan || '',
          i.freq_days ? { f: '$C$2' } : N_(i.freq), i.freq_unit || '', RP(i.price_final),
          { f: `IF(F${r}="",0,F${r})*IF(H${r}="",1,H${r})*IF(J${r}="",0,J${r})`, z: '#,##0' },
          notes.has(i.section) || i.counted === false ? 'Tidak' : 'Ya', ih, i.source || '', i.status_sistem || '', i.note || '', secName[i.section] || '', i.flagged || '']);
      });
      R.push([]); R.push(['', 'Kode seksi: ' + fin.sections.map((x) => `${x.code} = ${x.name}`).join('; ')]);
      if (P.note) R.push(['', 'Catatan: ' + P.note]);
      XLSX.utils.book_append_sheet(wb, sheet(R, [{ hidden: true, wch: 38 }, { wch: 22 }, { wch: 5 }, { wch: 46 }, { wch: 24 }, { wch: 7 }, { wch: 9 }, { wch: 7 }, { wch: 10 }, { wch: 13 }, { wch: 15 }, { wch: 9 }, { wch: 9 }, { wch: 22 }, { wch: 11 }, { wch: 34 }, { wch: 28 }, { wch: 22 }]), 'RAB');

      // ---- Pendapatan ----
      const IH = 7; const i1 = IH + 1; const i2 = IH + fin.income.length;
      const ir = (c) => `${c}$${i1}:${c}$${Math.max(i2, i1)}`;
      const A = fin.actual;
      const PD = [['PENDAPATAN · Jabar Open 2026'],
        ['', 'A. Dasar 2025', { f: `SUMIFS(${ir('I')},${ir('B')},"2025")`, z: '#,##0' }],
        ['', 'Total target', { f: `SUM(${ir('I')})`, z: '#,##0' }],
        ['', `Realisasi lunas (konsol, ${stamp()})`, RP(A.paid_total)],
        ['', 'B. Tambahan 2026', { f: `SUMIFS(${ir('I')},${ir('B')},"2026")`, z: '#,##0' }],
        [ro + ' Kelompok: 2025 atau 2026. Total = Vol × Tarif. Realisasi = angka konsol saat diunduh (tidak dibaca saat unggah).'],
        ['ID', 'Kelompok', 'No', 'Sumber', 'Keterangan', 'Vol', 'Satuan', 'Tarif', 'Total', 'Catatan', 'Kunci ledger', 'Realisasi lunas', 'Capaian', 'Tanda']];
      const ino = {};
      fin.income.forEach((i) => {
        const r = PD.length + 1; ino[i.grp] = (ino[i.grp] || 0) + 1;
        const a = i.ledger_key ? actualOf(fin, i.ledger_key) : null;
        PD.push([i.id, i.grp, ino[i.grp], i.source || '', i.keterangan || '', N_(i.vol), i.unit || '', RP(i.rate), { f: `F${r}*H${r}`, z: '#,##0' }, i.note || '', i.ledger_key || '',
          a ? RP(a.rp) : '', a ? { f: `IF(I${r}=0,"",L${r}/I${r})`, z: '0%' } : '', i.flagged || '']);
      });
      XLSX.utils.book_append_sheet(wb, sheet(PD, [{ hidden: true, wch: 38 }, { wch: 10 }, { wch: 5 }, { wch: 30 }, { wch: 30 }, { wch: 8 }, { wch: 10 }, { wch: 13 }, { wch: 15 }, { wch: 30 }, { wch: 12 }, { wch: 15 }, { wch: 9 }, { wch: 22 }]), 'Pendapatan');
    }
    XLSX.writeFile(wb, `jabar-open-proyek-${stamp()}.xlsx`);
  }

  // ---------------- unggah ----------------
  function readSheet(ws) {
    if (!ws) return null;
    const aoa = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: '' });
    const h = aoa.findIndex((r) => norm(r[0]) === 'ID');
    if (h < 0) return null;
    const head = aoa[h].map(norm);
    return { head, rows: aoa.slice(h + 1).map((r, k) => ({ line: h + k + 2, get: (name) => r[head.indexOf(name)] })) };
  }
  const xdate = (v) => {
    if (v === '' || v === null || v === undefined) return '';
    if (v instanceof Date) return `${v.getFullYear()}-${String(v.getMonth() + 1).padStart(2, '0')}-${String(v.getDate()).padStart(2, '0')}`;
    if (typeof v === 'number') return iso(Math.round(v) - 25569);
    const s = String(v).trim(); let m;
    if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/))) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
    if ((m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/))) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
    throw new Error(`Tanggal tidak dikenali: "${s}" (pakai dd/mm/yyyy)`);
  };
  const xnum = (v) => { if (v === '' || v === null || v === undefined) return ''; if (typeof v === 'number') return v; const s = String(v).replace(/[^0-9,.-]/g, '').replace(/\.(?=\d{3}(\D|$))/g, '').replace(',', '.'); if (s === '') return ''; const n = Number(s); if (!Number.isFinite(n)) throw new Error(`Angka tidak dikenali: "${v}"`); return n; };
  const xpct = (v) => { const n = xnum(typeof v === 'string' ? v.replace('%', '') : v); if (n === '') return 0; return typeof v === 'string' && /%/.test(v) ? n / 100 : n > 1 ? n / 100 : n; };
  const same = (a, b) => {
    const A = a === null || a === undefined ? '' : a; const B = b === null || b === undefined ? '' : b;
    if (A === '' && B === '') return true;
    if (typeof A === 'number' || typeof B === 'number' || (/^-?[\d.]+$/.test(String(A)) && /^-?[\d.]+$/.test(String(B)))) return Math.abs(Number(A) - Number(B)) < 1e-9 && String(A) !== '' && String(B) !== '';
    return norm(A) === norm(B);
  };

  async function uploadXlsx(C, file) {
    if (!window.XLSX) throw new Error('Pustaka Excel belum termuat. Muat ulang halaman.');
    const wb = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: false });
    const ov = await C.api('console_pm_overview');
    const fin = await C.api('console_pm_finance');
    const errs = []; const out = { params: null, tasks: [], rab_items: [], income_items: [], missing: { tasks: [], rab_items: [], income_items: [] }, file: file.name };
    const prev = { tasks: { add: [], chg: [], miss: [] }, rab_items: { add: [], chg: [], miss: [] }, income_items: { add: [], chg: [], miss: [] }, params: [] };
    const divByName = Object.fromEntries(ov.divisions.map((d) => [d.name.trim().toLowerCase(), d]));
    const divName = Object.fromEntries(ov.divisions.map((d) => [d.id, d.name]));
    const seen = (sheetKey, list, cur, label) => {
      const ids = new Set(list.map((x) => x.id).filter(Boolean));
      cur.forEach((c) => { if (!ids.has(c.id)) { out.missing[sheetKey].push(c.id); prev[sheetKey].miss.push(label(c)); } });
    };
    const diff = (sheetKey, row, cur, fields, label) => {
      if (!row.id || !cur) { prev[sheetKey].add.push(label(row)); out[sheetKey].push({ ...row, id: '' }); return; }
      const ch = fields.filter(([k, curK]) => !same(row[k], typeof curK === 'function' ? curK(cur) : cur[curK || k]));
      if (ch.length) { prev[sheetKey].chg.push(`${label(row)} <span class="muted">(${ch.map(([k]) => k).join(', ')})</span>`); out[sheetKey].push(row); }
    };

    // Gantt
    const G = readSheet(wb.Sheets.Gantt);
    if (G) {
      const cur = Object.fromEntries(ov.tasks.map((t) => [t.id, t])); const list = [];
      G.rows.forEach((r) => {
        const task = norm(r.get('Tugas')); const id = norm(r.get('ID'));
        if (!task && !id) return;
        try {
          if (!task) throw new Error('kolom Tugas kosong');
          const dn = norm(r.get('Divisi')); const dv = dn ? divByName[dn.toLowerCase()] : null;
          if (dn && !dv) throw new Error(`divisi "${dn}" tidak ada di Struktur`);
          const st = norm(r.get('Status')) || 'Belum mulai';
          if (!STATUS.includes(st)) throw new Error(`status "${st}" tidak dikenal`);
          const s = xdate(r.get('Mulai')); const e = xdate(r.get('Selesai'));
          if (s && e && e < s) throw new Error('Selesai lebih awal dari Mulai');
          const row = { id: cur[id] ? id : '', no: xnum(r.get('No')), phase: xnum(r.get('Fase')), task, pic: norm(r.get('PIC')), role_text: norm(r.get('Peran')),
            division: dv ? dv.name : '', start_date: s, end_date: e, predecessors: norm(r.get('Pendahulu')).replace(/[^0-9]+/g, ', ').replace(/^, |, $/g, ''),
            critical: /^(ya|y|true|1)$/i.test(norm(r.get('Kritis'))), status: st, percent: Math.min(1, Math.max(0, xpct(r.get('Progres')))), note: norm(r.get('Catatan')) };
          list.push(row);
          diff('tasks', row, cur[row.id], [['no'], ['phase'], ['task'], ['pic'], ['role_text'], ['division', (c) => divName[c.division_id] || ''], ['start_date'], ['end_date'],
            ['predecessors', (c) => (c.predecessors || []).join(', ')], ['critical', (c) => !!c.critical], ['status'], ['percent'], ['note']],
          (x) => `${x.no || '(baru)'}. ${C.esc(x.task)}`);
        } catch (e) { errs.push(`Gantt baris ${r.line}: ${e.message}`); }
      });
      seen('tasks', list, ov.tasks, (c) => `${c.no}. ${C.esc(c.task)}`);
    }
    // RAB
    const RS = wb.Sheets.RAB;
    const R = readSheet(RS);
    if (RS) {
      const lab = {}; for (let r = 1; r <= 4; r++) { const k = RS['B' + r] && norm(RS['B' + r].v); if (k) lab[k] = RS['C' + r] ? RS['C' + r].v : ''; }
      const ed = xnum(lab['Jumlah hari kegiatan']); const P = fin.params; const pc = [];
      if (ed !== '' && !same(ed, P.event_days)) { if (!(ed > 0)) errs.push('RAB: Jumlah hari kegiatan harus angka lebih dari 0.'); out.params = { event_days: ed }; pc.push(`Jumlah hari kegiatan ${P.event_days} → ${ed}`); prev.params = pc; }
    }
    if (R) {
      const cur = Object.fromEntries(fin.items.map((i) => [i.id, i])); const list = [];
      const secs = new Set(fin.sections.map((s) => s.code));
      R.rows.forEach((r) => {
        const ur = norm(r.get('Uraian')); const id = norm(r.get('ID'));
        if (!ur && !id) return;
        try {
          if (!ur) throw new Error('kolom Uraian kosong');
          const sec = norm(r.get('Seksi')).toUpperCase();
          if (!secs.has(sec)) throw new Error(`seksi "${sec}" tidak dikenal`);
          const ss = norm(r.get('Status sistem')).toUpperCase();
          if (!SYS.includes(ss)) throw new Error(`status sistem "${ss}" tidak dikenal`);
          const dh = norm(r.get('Dihitung')).toLowerCase();
          if (dh && !['ya', 'tidak'].includes(dh)) throw new Error(`Dihitung harus Ya atau Tidak, bukan "${dh}"`);
          const ih = norm(r.get('Ikut hari')).toLowerCase().replace(/\s/g, '');
          if (ih && !['vol', 'frek', 'vol+frek'].includes(ih)) throw new Error(`Ikut hari harus Vol, Frek, atau Vol+Frek, bukan "${ih}"`);
          const vd = ih === 'vol' || ih === 'vol+frek'; const fd = ih === 'frek' || ih === 'vol+frek';
          const c0 = cur[id];
          const row = { id: c0 ? id : '', section: sec, sort: c0 ? c0.sort : '', uraian: ur, keterangan: norm(r.get('Keterangan')),
            vol: vd ? (c0 ? c0.vol : 0) : xnum(r.get('Vol')) || 0, satuan: norm(r.get('Satuan')), vol_days: vd,
            freq: fd ? (c0 ? c0.freq : '') : xnum(r.get('Frek')), freq_unit: norm(r.get('Satuan frek')), freq_days: fd,
            price_final: xnum(r.get('Harga satuan')), counted: dh !== 'tidak', source: norm(r.get('Sumber')),
            status_sistem: ss, pct_replaced: c0 ? c0.pct_replaced : 0, note: norm(r.get('Catatan')) };
          list.push(row);
          diff('rab_items', row, c0, [['section'], ['uraian'], ['keterangan'], ['vol'], ['satuan'], ['vol_days', (c) => !!c.vol_days], ['freq'], ['freq_unit'],
            ['freq_days', (c) => !!c.freq_days], ['price_final'], ['counted', (c) => c.counted !== false], ['source'], ['status_sistem'], ['note']],
            (x) => `${x.section}. ${C.esc(x.uraian)}`);
        } catch (e) { errs.push(`RAB baris ${r.line}: ${e.message}`); }
      });
      seen('rab_items', list, fin.items, (c) => `${c.section}. ${C.esc(c.uraian)}`);
    }
    // Pendapatan
    const I = readSheet(wb.Sheets.Pendapatan);
    if (I) {
      const cur = Object.fromEntries(fin.income.map((i) => [i.id, i])); const list = [];
      I.rows.forEach((r) => {
        const src = norm(r.get('Sumber')); const id = norm(r.get('ID'));
        if (!src && !id) return;
        try {
          if (!src) throw new Error('kolom Sumber kosong');
          const gp = norm(r.get('Kelompok'));
          if (!['2025', '2026'].includes(gp)) throw new Error('Kelompok harus 2025 atau 2026');
          const lk = norm(r.get('Kunci ledger')).toUpperCase();
          if (lk && !LEDGER[lk]) throw new Error(`kunci ledger "${lk}" tidak dikenal`);
          const row = { id: cur[id] ? id : '', grp: gp, source: src, keterangan: norm(r.get('Keterangan')), vol: xnum(r.get('Vol')) || 0, unit: norm(r.get('Satuan')),
            rate: xnum(r.get('Tarif')) || 0, note: norm(r.get('Catatan')), ledger_key: lk };
          list.push(row);
          diff('income_items', row, cur[row.id], [['grp'], ['source'], ['keterangan'], ['vol'], ['unit'], ['rate'], ['note'], ['ledger_key']], (x) => C.esc(x.source));
        } catch (e) { errs.push(`Pendapatan baris ${r.line}: ${e.message}`); }
      });
      seen('income_items', list, fin.income, (c) => C.esc(c.source || ''));
    }
    if (!G && !R && !I) throw new Error('Tab Gantt, RAB, atau Pendapatan tidak ditemukan. Pakai file hasil "Unduh xlsx".');

    const block = (title, p) => {
      const li = (arr, cls) => arr.slice(0, 40).map((x) => `<li class="${cls}">${x}</li>`).join('') + (arr.length > 40 ? `<li class="muted">… dan ${arr.length - 40} lagi</li>` : '');
      const n = p.add.length + p.chg.length + p.miss.length;
      return `<details class="pm-prev" ${n ? 'open' : ''}><summary><b>${title}</b>: ${p.add.length} baru · ${p.chg.length} berubah · ${p.miss.length} tidak ada di file</summary>
        ${n ? `<ul>${li(p.add, 'add')}${li(p.chg, 'chg')}${li(p.miss, 'miss')}</ul>` : ''}</details>`;
    };
    const total = ['tasks', 'rab_items', 'income_items'].reduce((a, k) => a + prev[k].add.length + prev[k].chg.length + prev[k].miss.length, 0) + prev.params.length;
    const res = await C.dialog({ title: 'Pratinjau unggahan', wide: true, ok: errs.length || !total ? null : 'Terapkan semua', cancel: 'Tutup',
      body: `<p class="small">File <b>${C.esc(file.name)}</b>. Hanya kolom isian yang dibaca; kolom rumus dan tab Struktur diabaikan. Baris yang tidak ada di file <b>tidak dihapus</b>, hanya ditandai. Perubahan diterapkan sekaligus, atau tidak sama sekali.</p>
        ${errs.length ? `<div class="note bad small"><b>Perbaiki dulu di file, lalu unggah ulang:</b><ul>${errs.slice(0, 30).map((e) => `<li>${C.esc(e)}</li>`).join('')}${errs.length > 30 ? `<li>… dan ${errs.length - 30} lagi</li>` : ''}</ul></div>` : ''}
        ${!errs.length && !total ? '<p class="note ok small">Tidak ada perubahan dibanding data di konsol.</p>' : ''}
        ${prev.params.length ? `<p class="small"><b>Parameter RAB:</b> ${prev.params.join(' · ')}</p>` : ''}
        ${G ? block('Gantt', prev.tasks) : ''}${R ? block('RAB', prev.rab_items) : ''}${I ? block('Pendapatan', prev.income_items) : ''}`,
      onOk: () => C.api('console_pm_import', { p: out }) });
    if (res) C.toast(`Diterapkan: ${res.inserted} baru, ${res.updated} diubah, ${res.flagged} ditandai.`, 'ok');
    return !!res;
  }

  window.JO_MOD.proyek = { gantt, struktur, rab, pendapatan };
})();
