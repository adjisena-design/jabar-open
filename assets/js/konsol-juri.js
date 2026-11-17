/* =====================================================================
   Jabar Open 2026 — modul konsol juri (/juri/)
   Penilaian (asisten juri), verifikasi nilai, pantau (TD), panel juri,
   start list simulasi (dummy), konfirmasi hasil TD + PDF, layar live.
   Dimuat oleh panitia.js lewat loadModule('konsol-juri').
   ===================================================================== */
(function () {
  'use strict';
  const ST_LBL = { draft: 'Draf', submitted: 'Menunggu verifikasi', returned: 'Dikembalikan', verified: 'Terverifikasi' };
  const ST_CLS = { draft: '', submitted: 'warn', returned: 'bad', verified: 'ok' };
  const COMP_LBL = { D: 'D', E: 'E', A: 'A', PEN: 'Pen' };
  const S = { cat: '', app: '' };              // pilihan kategori & alat bertahan antarhalaman
  let JC = null;                               // console_j_categories

  const f3 = (v) => (v == null || v === '' ? '–' : Number(v).toFixed(3));
  const f1 = (v) => (v == null || v === '' ? '–' : Number(v).toFixed(Number(v) % 1 === 0 ? 1 : 3).replace(/0+$/, '').replace(/\.$/, '.0'));
  const pill = (st) => (st ? `<span class="pill ${ST_CLS[st]}">${ST_LBL[st]}</span>` : '<span class="pill">Belum diisi</span>');
  const num = (s) => { const t = String(s == null ? '' : s).trim().replace(',', '.'); if (t === '') return null; const n = Number(t); return Number.isFinite(n) ? n : NaN; };

  // sama dengan jo.trimmed_mean & jo.calc_slots di database
  function tmean(a) {
    if (!a.length) return null;
    const s = a.reduce((x, y) => x + y, 0);
    if (a.length >= 4) return Math.round(((s - Math.min(...a) - Math.max(...a)) / (a.length - 2)) * 1000) / 1000;
    return Math.round((s / a.length) * 1000) / 1000;
  }
  const sfx = (r) => (r === 1 ? '' : '@' + r);
  const r3 = (x) => Math.round(x * 1000) / 1000;
  // sama dengan jo.calc_slots di database (lembar standar & lembar artistik, 1–3 lompatan)
  function calc(panel, slots) {
    const runs = Math.max(1, panel.runs || 1); const art = panel.sheet === 'artistik';
    const out = { runs: [], flags: [] }; let nr = 0, sd = 0, se = 0, sa = 0, sp = 0, st = 0, anyD = false, anyE = false, anyA = false;
    for (let r = 1; r <= runs; r++) {
      const g = { D: [], E: [], A: [], PEN: [] }; let have = 0;
      (panel.slots || []).forEach((sl) => { const v = num(slots[sl.key + sfx(r)]); if (v == null || Number.isNaN(v)) return; have++; g[sl.comp].push(v); });
      const d = tmean(g.D), a = tmean(g.A); let eAuto = tmean(g.E);
      if (eAuto != null && panel.e_mode === 'deduction') eAuto = r3(Number(panel.e_base || 10) - eAuto);
      const pen = r3(g.PEN.reduce((x, y) => x + y, 0));
      let e = eAuto;
      if (art) { const ov = num(slots['RERATA' + sfx(r)]); if (ov != null && !Number.isNaN(ov)) { e = ov; have++; if (eAuto == null || r3(ov) !== r3(eAuto)) out.flags.push({ field: 'RERATA', run: r, auto: eAuto, manual: ov }); } }
      const akAuto = have ? r3((d || 0) + (e || 0) + (a || 0) - pen) : null;
      let ak = akAuto;
      if (art) { const ov = num(slots['AKHIR' + sfx(r)]); if (ov != null && !Number.isNaN(ov)) { ak = ov; if (akAuto == null || r3(ov) !== r3(akAuto)) out.flags.push({ field: 'AKHIR', run: r, auto: akAuto, manual: ov }); } }
      out.runs.push({ run: r, d, a, pen, e_auto: eAuto, e, akhir_auto: akAuto, akhir: ak });
      if (ak != null) { nr++; st += ak; sp += pen; if (d != null) { anyD = true; sd += d; } if (e != null) { anyE = true; se += e; } if (a != null) { anyA = true; sa += a; } }
    }
    out.d = anyD ? r3(sd / nr) : null; out.e = anyE ? r3(se / nr) : null; out.a = anyA ? r3(sa / nr) : null;
    out.pen = nr ? r3(sp / nr) : 0; out.total = nr === runs ? r3(st / nr) : null; out.partial = nr ? r3(st / nr) : null;
    return out;
  }
  const FLD = { RERATA: 'Rerata', AKHIR: 'Nilai Akhir' };
  const flagText = (f, runs) => `${runs > 1 ? 'Lompatan ' + f.run + ' · ' : ''}${FLD[f.field]}: otomatis ${f3(f.auto)} → manual ${f3(f.manual)}`;

  // ---------- isian bermasker: angka saja, titik desimal otomatis & tidak bisa dihapus ----------
  const decOf = (k) => (/^(RERATA|AKHIR)/.test(k) ? 3 : 2);
  const toDg = (v, dec) => (v == null || v === '' || Number.isNaN(Number(v)) ? '' : String(Math.round(Number(v) * 10 ** dec)));
  const fmtDg = (dg, dec) => { if (!dg) return ''; const p = dg.padStart(dec + 1, '0'); return p.slice(0, -dec).replace(/^0+(?=\d)/, '') + '.' + p.slice(-dec); };
  function formHtml(panel, slots, editable, esc, names) {
    names = names || {};
    const art = panel.sheet === 'artistik'; const runs = Math.max(1, panel.runs || 1);
    const main = (panel.slots || []).filter((x) => x.comp !== 'PEN'); const pens = (panel.slots || []).filter((x) => x.comp === 'PEN');
    const lbl = (sl) => (art && sl.comp === 'D' && /^D$/i.test(sl.label) ? 'D1/D2' : art && sl.comp === 'PEN' && /^Pen$/i.test(sl.label) ? 'Pinalti' : sl.label);
    const inp = (k, label, cls) => { const dec = decOf(k); return `<input class="mk ${cls || ''}" data-k="${esc(k)}" data-dec="${dec}" data-dg="${toDg(slots[k], dec)}" value="${fmtDg(toDg(slots[k], dec), dec)}" inputmode="numeric" autocomplete="off" aria-label="${esc(label)}" ${editable ? '' : 'disabled'}>`; };
    let h = `<div class="sf-wrap"><table class="sf"><thead><tr>${runs > 1 ? '<th></th>' : ''}${main.map((x) => `<th>${esc(lbl(x))}${names['SEAT:' + x.key] ? `<small class="sfn">${esc(names['SEAT:' + x.key].name)}</small>` : ''}</th>`).join('')}${art ? '<th class="au">Rerata</th>' : ''}${pens.map((x) => `<th>${esc(lbl(x))}</th>`).join('')}${art ? '<th class="au">Nilai Akhir</th>' : ''}${runs > 1 ? '<th class="au">Average</th>' : ''}</tr></thead><tbody>`;
    for (let r = 1; r <= runs; r++) {
      h += `<tr>${runs > 1 ? `<th class="rn">Lompatan ${r}</th>` : ''}${main.map((x) => `<td>${inp(x.key + sfx(r), lbl(x))}</td>`).join('')}
        ${art ? `<td>${inp('RERATA' + sfx(r), 'Rerata', 'auto')}</td>` : ''}${pens.map((x) => `<td>${inp(x.key + sfx(r), lbl(x))}</td>`).join('')}
        ${art ? `<td>${inp('AKHIR' + sfx(r), 'Nilai Akhir', 'auto')}</td>` : ''}${runs > 1 && r === 1 ? `<td rowspan="${runs}" class="avg" data-avg></td>` : ''}</tr>`;
    }
    return h + '</tbody></table></div><div class="sf-flags" data-flags></div><div class="calc" data-calc></div>';
  }
  function bindForm(root, panel, opts) {
    const art = panel.sheet === 'artistik'; const runs = Math.max(1, panel.runs || 1);
    const inputs = [...root.querySelectorAll('input.mk')];
    const nav = inputs.filter((x) => !x.classList.contains('auto'));
    const read = () => { const o = {}; inputs.forEach((x) => { if (x.dataset.dg) o[x.dataset.k] = fmtDg(x.dataset.dg, Number(x.dataset.dec)); }); return o; };
    const update = () => {
      const r = calc(panel, read());
      if (art) r.runs.forEach((x) => {
        const re = root.querySelector(`input[data-k="RERATA${sfx(x.run)}"]`); const ak = root.querySelector(`input[data-k="AKHIR${sfx(x.run)}"]`);
        if (re) { re.placeholder = x.e_auto == null ? '' : f3(x.e_auto); re.classList.toggle('man', !!re.dataset.dg); }
        if (ak) { ak.placeholder = x.akhir_auto == null ? '' : f3(x.akhir_auto); ak.classList.toggle('man', !!ak.dataset.dg); }
      });
      const avg = root.querySelector('[data-avg]'); if (avg) avg.textContent = r.total != null ? f3(r.total) : r.partial != null ? f3(r.partial) + ' *' : '';
      const fl = root.querySelector('[data-flags]');
      if (fl) fl.innerHTML = r.flags.length ? `<span class="pill warn">Diubah manual</span> ${r.flags.map((f) => opts.esc(flagText(f, runs))).join(' · ')}` : '';
      const c = root.querySelector('[data-calc]');
      if (c) c.innerHTML = `<span>D <b>${f3(r.d)}</b></span><span>${art ? 'Rerata' : 'E'} <b>${f3(r.e)}</b></span>${hasA(panel) ? `<span>A <b>${f3(r.a)}</b></span>` : ''}<span>Pen <b>${r.pen ? '-' + f3(r.pen) : '0'}</b></span>${runs > 1 && r.total == null && r.partial != null ? '<span class="muted small">* lompatan belum lengkap</span>' : ''}<span class="tot">Total <b>${f3(r.total)}</b></span>`;
      if (opts.onChange) opts.onChange(r);
      return r;
    };
    inputs.forEach((el) => {
      const dec = Number(el.dataset.dec); const max = dec === 3 ? 5 : 4;
      const set = (dg) => { el.dataset.dg = dg.replace(/^0+(?=\d)/, '').slice(0, max); if (el.dataset.dg === '0' && !dg.length) el.dataset.dg = ''; el.value = fmtDg(el.dataset.dg, dec); try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {} update(); };
      el.addEventListener('beforeinput', (ev) => {
        ev.preventDefault();
        const all = el.value && el.selectionStart === 0 && el.selectionEnd === el.value.length;
        let dg = all ? '' : (el.dataset.dg || '');
        const t = ev.inputType || '';
        if (t.startsWith('insert')) {
          const txt = ev.data != null ? ev.data : ev.dataTransfer ? ev.dataTransfer.getData('text') : '';
          const add = String(txt || '').replace(/\D/g, '');
          if (t === 'insertFromPaste' && /[.,]/.test(txt)) { const n = num(txt); if (n != null && !Number.isNaN(n)) return set(toDg(n, dec)); }
          if (!add) return;
          if (dg.length >= max && !all) return;
          set(dg + add);
        } else if (t.startsWith('delete')) set(all ? '' : dg.slice(0, -1));
      });
      el.addEventListener('focus', () => { if (el.value) setTimeout(() => el.select(), 0); });
      el.addEventListener('keydown', (ev) => {
        if (ev.key !== 'Enter') return; ev.preventDefault();
        const i = nav.indexOf(el); const nxt = i >= 0 ? nav[i + 1] : nav.find((x) => inputs.indexOf(x) > inputs.indexOf(el));
        if (nxt) { nxt.focus(); return; }
        if (opts.onEnterLast) opts.onEnterLast();
      });
    });
    update();
    return { read, update, inputs, nav, calc: () => calc(panel, read()) };
  }
  const hasA = (panel) => (panel.slots || []).some((x) => x.comp === 'A');

  async function loadCats(ctx, force) { if (!JC || force) JC = await ctx.api('console_j_categories'); return JC; }
  function catOptions(sel, filter) {
    const discs = {}; JC.disciplines.forEach((d) => { discs[d.code] = d.name; });
    const groups = {};
    JC.categories.filter(filter || (() => true)).forEach((c) => { (groups[c.discipline] = groups[c.discipline] || []).push(c); });
    return Object.entries(groups).map(([d, list]) => `<optgroup label="${discs[d] || d}">${list.map((c) => `<option value="${c.id}" ${String(sel) === String(c.id) ? 'selected' : ''}>${c.name}${c.paid ? ` (${c.paid})` : ' (0)'}${c.pending ? ` · ${c.pending} menunggu` : ''}</option>`).join('')}</optgroup>`).join('');
  }
  const modeBanner = (ctx) => (JC && JC.mode === 'dummy' ? '<p class="note warn small" style="margin:0 0 12px">Mode simulasi: nama atlet bertanda DUMMY TEST, nilai tidak masuk hasil resmi.</p>' : '');

  // =====================================================================
  //  LEMBAR NILAI (asisten juri, verifikator, TD/pemantau)
  // =====================================================================
  async function sheetPage(v, ctx, kind) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    const hp = ctx.hashParams(); if (hp.get('c')) S.cat = hp.get('c');
    if (S.cat && !JC.categories.some((c) => String(c.id) === String(S.cat))) S.cat = '';
    if (!S.cat) { const first = JC.categories.find((c) => c.paid > 0) || JC.categories[0]; S.cat = first ? String(first.id) : ''; }
    const title = kind === 'asjur' ? 'Penilaian' : kind === 'verif' ? 'Lembar nilai' : 'Pantau nilai';
    const lead = kind === 'asjur' ? 'Ketik nilai dari lembar juri, lalu kirim ke verifikator. Enter pindah ke isian berikutnya; Enter di isian terakhir langsung mengirim.'
      : kind === 'verif' ? 'Semua nilai satu kategori. Nilai terverifikasi langsung tampil di Public Live View.' : 'Hanya baca. Nilai terverifikasi tampil di Public Live View (belum resmi).';
    v.innerHTML = `<h1>${title}</h1><p class="muted">${lead}</p>${modeBanner(ctx)}
      <div class="bar"><div class="field" style="flex:1;min-width:240px"><label class="f" for="jc">Kategori</label><select id="jc">${catOptions(S.cat)}</select></div></div>
      <div id="apps" class="jtabs" role="tablist"></div><div id="sheet"></div>`;
    let D = null;
    const sheetBox = v.querySelector('#sheet');
    const load = async (quiet) => {
      if (!S.cat) { sheetBox.innerHTML = '<p class="empty">Belum ada kategori.</p>'; return; }
      if (!quiet) ctx.loading(sheetBox);
      D = await api('console_j_sheet', { p_category: Number(S.cat) });
      if (!D.apparatus.some((a) => a.code === S.app)) S.app = D.apparatus[0] ? D.apparatus[0].code : '';
      drawApps(); drawSheet();
    };
    const drawApps = () => {
      const box = v.querySelector('#apps');
      box.innerHTML = D.apparatus.map((a) => {
        const n = D.entries.filter((e) => e.scores[a.code] && e.scores[a.code].status === 'verified').length;
        const w = D.entries.filter((e) => e.scores[a.code] && e.scores[a.code].status === 'submitted').length;
        return `<button type="button" role="tab" data-a="${a.code}" aria-selected="${a.code === S.app}">${esc(a.id)}<small>${n}/${D.entries.filter((e) => e.status === 'aktif').length}${w ? ` · ${w} menunggu` : ''}</small></button>`;
      }).join('');
      box.querySelectorAll('[data-a]').forEach((b) => b.onclick = () => { S.app = b.dataset.a; drawApps(); drawSheet(); });
    };
    const drawSheet = () => {
      const panel = D.panels[S.app] || { slots: [] };
      const withA = hasA(panel);
      const rows = D.entries;
      if (!rows.length) { sheetBox.innerHTML = `<p class="empty">Belum ada atlet lunas di kategori ini.${JC.mode === 'dummy' ? '' : ''}</p>`; return; }
      const runs = Math.max(1, panel.runs || 1); const art = panel.sheet === 'artistik';
      sheetBox.innerHTML = `<div class="tbl-wrap"><table class="tbl jsheet"><thead><tr><th class="c">#</th><th>Atlet</th>
          ${runs > 1 ? Array.from({ length: runs }, (_, k) => `<th class="r">Lompatan ${k + 1}</th>`).join('') : ''}
          <th class="r">D</th><th class="r">${art ? 'Rerata' : 'E'}</th>${withA ? '<th class="r">A</th>' : ''}<th class="r">Pen</th><th class="r">${runs > 1 ? 'Average' : art ? 'Nilai Akhir' : 'Total'}</th><th>Status</th></tr></thead><tbody>
        ${rows.map((e, i) => { const sc = e.scores[S.app]; const cr = sc ? calc(panel, sc.slots || {}) : null; const fl = sc && sc.flags && sc.flags.length;
          return `<tr class="${e.status === 'aktif' ? 'click' : 'muted'}" data-e="${e.entry_id}">
            <td class="c">${e.start_order || i + 1}</td>
            <td><strong>${esc(e.name)}</strong>${e.status === 'dns' ? ' <span class="pill bad">DNS</span>' : ''}<br><span class="tiny muted">${esc(e.club || '')}</span></td>
            ${runs > 1 ? Array.from({ length: runs }, (_, k) => `<td class="r num">${cr && cr.runs[k] && cr.runs[k].akhir != null ? f3(cr.runs[k].akhir) : ''}</td>`).join('') : ''}
            <td class="r num">${sc ? f3(sc.d) : ''}</td><td class="r num">${sc ? f3(sc.e) : ''}</td>${withA ? `<td class="r num">${sc ? f3(sc.a) : ''}</td>` : ''}
            <td class="r num">${sc && Number(sc.pen) ? '-' + f3(sc.pen) : ''}</td><td class="r num"><strong>${sc ? f3(sc.total) : ''}</strong></td>
            <td>${pill(sc && sc.status)}${fl ? ' <span class="pill warn" title="Rerata / Nilai Akhir diketik manual">Manual</span>' : ''}${sc && sc.status === 'returned' && sc.note ? `<br><span class="tiny" style="color:var(--bad)">${esc(sc.note)}</span>` : ''}</td></tr>`; }).join('')}
        </tbody></table></div>
        <p class="tiny muted" style="margin-top:8px">Panel ${esc(S.app)}: ${panel.slots.map((x) => esc(x.label)).join(', ')}${runs > 1 ? ` · ${runs} lompatan, nilai alat = rata-rata Nilai Akhir` : ''}. ${art ? 'Rerata' : 'D, E, A'} = rata-rata isian (4 isian atau lebih: tertinggi dan terendah dibuang)${panel.e_mode === 'deduction' ? `; E = ${panel.e_base} − rata-rata pengurangan` : ''}; Pen = jumlah.</p>`;
      sheetBox.querySelectorAll('tr[data-e]').forEach((tr) => tr.onclick = () => {
        const e = D.entries.find((x) => x.entry_id === tr.dataset.e);
        if (e.status !== 'aktif') return;
        openEditor(e);
      });
    };
    // ---------- editor satu atlet x satu alat ----------
    const openEditor = (e, draft) => {
      const panel = D.panels[S.app] || { slots: [] };
      const sc = e.scores[S.app] || null;
      const st = sc ? sc.status : null;
      const role = ctx.ME.role;
      const sup = role === 'owner' || role === 'superadmin';
      const canEnter = (kind === 'asjur' || sup) && (!st || st === 'draft' || st === 'returned');
      const canVer = (kind === 'verif' || sup) && kind !== 'pantau';
      const editable = kind !== 'pantau' && (canEnter || (canVer));
      const appName = (D.apparatus.find((a) => a.code === S.app) || {}).id || S.app;
      const dlg = document.getElementById('dlg');
      const btns = [];
      if (kind !== 'pantau') {
        if (canEnter) { btns.push(['draft', 'Simpan draf', 'btn-ghost']); btns.push(['submit', 'Kirim ke verifikator', 'btn-primary']); }
        if ((kind === 'asjur' || sup) && st === 'submitted') btns.push(['unsubmit', 'Tarik kembali', 'btn-ghost']);
        if (canVer && st !== 'verified') { if (st === 'submitted') btns.push(['return', 'Kembalikan ke asjur', 'btn-ghost']); btns.push(['verify', st ? 'Simpan & verifikasi' : 'Isi & verifikasi', 'btn-ok']); }
        if (canVer && st === 'verified') { btns.push(['unverify', 'Batalkan verifikasi', 'btn-ghost']); btns.push(['correct', 'Simpan koreksi', 'btn-primary']); }
        if (sc && (canVer || (canEnter && st !== 'submitted'))) btns.push(['clear', 'Hapus nilai', 'btn-bad']);
      }
      const cur = draft || (sc ? sc.slots : {});
      const rs = (D.roster && e.session_id && D.roster[e.session_id]) || {};
      const nm = rs[S.app] || {};
      const crew = [['KETUA', 'Ketua panel'], ['ASJUR', 'Asisten juri'], ['VERIF', 'Verifikator']].filter(([k]) => nm[k]).map(([k, l]) => `${l}: ${esc(nm[k].name)}`)
        .concat(rs['*'] && rs['*'].TD ? [`TD: ${esc(rs['*'].TD.name)}`] : []);
      dlg.style.maxWidth = 'min(860px, calc(100% - 24px))';
      dlg.innerHTML = `<form method="dialog" novalidate class="jed"><div class="dlg-head"><h2 style="margin:0;font-size:1.15rem">${esc(e.name)}</h2>
          <div class="small muted">${esc(e.club || '')} · ${esc(appName)} · ${pill(st)}</div></div>
        <div class="dlg-body">
          ${st === 'returned' && sc.note ? `<p class="note bad small">Dikembalikan verifikator: ${esc(sc.note)}</p>` : ''}
          ${sc && sc.verified_by ? `<p class="small muted">Diverifikasi ${esc(sc.verified_by)} ${ctx.dt(sc.verified_at)}${sc.entered_by ? ` · diisi ${esc(sc.entered_by)}` : ''}</p>` : sc && sc.entered_by ? `<p class="small muted">Diisi ${esc(sc.entered_by)} ${ctx.dt(sc.updated_at)}</p>` : ''}
          ${crew.length ? `<p class="small muted" style="margin:0 0 4px">${crew.join(' · ')}</p>` : ''}
          ${formHtml(panel, cur, editable, esc, nm)}
          <div data-err></div>
        </div>
        <div class="dlg-foot jfoot"><button type="button" class="btn btn-ghost" data-x>Tutup</button>${btns.map(([a, l, c]) => `<button type="button" class="btn ${c}" data-act="${a}">${l}</button>`).join('')}</div></form>`;
      dlg.showModal();
      const F = bindForm(dlg, panel, { esc, onEnterLast: () => { const def = dlg.querySelector('[data-act=submit]') || dlg.querySelector('[data-act=verify]') || dlg.querySelector('[data-act=correct]'); if (def) def.click(); } });
      const read = F.read;
      const firstEmpty = F.nav.find((i) => !i.value) || F.nav[0];
      if (firstEmpty && editable) setTimeout(() => { firstEmpty.focus(); }, 30);
      dlg.querySelector('[data-x]').onclick = () => dlg.close();
      dlg.querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
        const act = b.dataset.act; let note = null; let closed = false;
        const slots = ['unsubmit', 'return', 'unverify', 'clear'].includes(act) ? null : read();
        const needNote = ['return', 'unverify', 'correct'].includes(act) || (act === 'clear' && st === 'verified');
        if (['submit', 'verify'].includes(act) && slots) {
          const fl = calc(panel, slots).flags;
          if (fl.length) {
            dlg.close(); await new Promise((r) => setTimeout(r, 40));
            const ok = await ctx.dialog({ title: 'Ada nilai yang diubah manual', ok: act === 'submit' ? 'Tetap kirim ke verifikator' : 'Tetap verifikasi',
              body: `<p>Rerata / Nilai Akhir berikut diketik manual, bukan hitungan otomatis. Tercatat di log dan terlihat oleh verifikator dan TD di konsol juri (tidak tampil di live view, situs, atau PDF resmi).</p><ul>${fl.map((f) => `<li>${esc(flagText(f, panel.runs || 1))}</li>`).join('')}</ul>` });
            if (!ok) return openEditor(e, slots);
            closed = true;
          }
        }
        if (needNote) {
          dlg.close(); closed = true; await new Promise((r) => setTimeout(r, 40));
          note = await ctx.askReason(act === 'return' ? 'Kembalikan ke asisten juri' : act === 'unverify' ? 'Batalkan verifikasi' : act === 'correct' ? 'Alasan koreksi' : 'Hapus nilai terverifikasi',
            act === 'return' ? 'Catatan (mis. E2 salah ketik, cek lembar juri)' : 'Alasan', { min: act === 'return' ? 2 : 3 });
          if (note == null) return openEditor(e, slots || undefined);
        } else if (!closed) {
          dlg.querySelectorAll('[data-act]').forEach((x) => { x.disabled = true; });
        }
        try {
          const r = await api('console_j_save', { p_entry: e.entry_id, p_apparatus: S.app, p_slots: slots, p_action: act, p_note: note });
          if (r.score) e.scores[S.app] = r.score; else delete e.scores[S.app];
          ctx.toast({ draft: 'Draf disimpan.', submit: 'Dikirim ke verifikator.', unsubmit: 'Ditarik kembali.', verify: 'Terverifikasi, tampil di live.', correct: 'Koreksi tersimpan, live diperbarui.', return: 'Dikembalikan ke asisten juri.', unverify: 'Verifikasi dibatalkan, dihapus dari live.', clear: 'Nilai dihapus.' }[act]);
          if (dlg.open) dlg.close();
          drawApps(); drawSheet();
          // lanjut otomatis ke atlet berikutnya yang belum dinilai di alat ini
          if (act === 'submit' || (act === 'verify' && !st)) {
            const idx = D.entries.findIndex((x) => x.entry_id === e.entry_id);
            const nx = D.entries.slice(idx + 1).find((x) => x.status === 'aktif' && (!x.scores[S.app] || ['draft', 'returned'].includes(x.scores[S.app].status)));
            if (nx) openEditor(nx);
          }
        } catch (err) {
          if (closed) { ctx.toast(err.message, 'bad'); return openEditor(e, slots || undefined); }
          dlg.querySelector('[data-err]').innerHTML = `<p class="note bad" style="margin-top:12px">${esc(err.message)}</p>`;
          dlg.querySelectorAll('[data-act]').forEach((x) => { x.disabled = false; });
        }
      });
    };
    v.querySelector('#jc').onchange = (ev) => { S.cat = ev.target.value; load(); };
    await load();
    // segarkan status setiap 5 detik saat tidak sedang mengetik
    ctx.setPageTimer(async () => { if (document.getElementById('dlg').open || !v.isConnected) return; try { await load(true); } catch (e) {} }, 5000);
  }

  // =====================================================================
  //  VERIFIKASI: antrean nilai yang dikirim asisten juri
  // =====================================================================
  async function verifPage(v, ctx) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    v.innerHTML = `<h1>Verifikasi nilai</h1><p class="muted">Nilai yang dikirim asisten juri. Verifikasi = langsung tampil di Public Live View (belum resmi sampai dikonfirmasi TD).</p>${modeBanner(ctx)}
      <div class="tabs"><button data-t="q" aria-selected="true">Antrean <span id="qn"></span></button><button data-t="s" aria-selected="false">Lembar kategori</button></div><div id="vb"></div>`;
    const vb = v.querySelector('#vb');
    let tab = 'q', Q = [], busy = false;
    const drawQ = () => {
      v.querySelector('#qn').textContent = Q.filter((x) => x.status === 'submitted').length ? `(${Q.filter((x) => x.status === 'submitted').length})` : '';
      if (!Q.length) { vb.innerHTML = '<p class="empty">Tidak ada nilai yang menunggu. Halaman ini diperbarui otomatis setiap 3 detik.</p>'; return; }
      vb.innerHTML = `<div class="jq">${Q.map((q, i) => { const p = q.panel || { slots: [] };
        return `<article class="jq-card ${q.status}" data-i="${i}">
          <header><div><strong>${esc(q.name)}</strong><br><span class="small muted">${esc(q.category)} · ${esc(q.apparatus)} · ${esc(q.club || '')}</span></div>${pill(q.status)}</header>
          ${q.status === 'returned' ? `<p class="small" style="color:var(--bad);margin:6px 0 0">Catatan: ${esc(q.note || '')}</p>` : ''}
          ${formHtml(p, q.slots || {}, q.status !== 'returned', esc)}<div data-chg></div>
          <footer><span class="tiny muted">${q.entered_by ? 'Diisi ' + esc(q.entered_by) + ' · ' : ''}${ctx.dt(q.submitted_at || q.updated_at)}</span>
            ${q.status === 'submitted' ? '<span class="acts"><button class="btn btn-ghost btn-sm" data-a="return">Kembalikan</button><button class="btn btn-ok btn-sm" data-a="verify">Verifikasi</button></span>' : ''}</footer>
        </article>`; }).join('')}</div>`;
      vb.querySelectorAll('.jq-card').forEach((card) => {
        const q = Q[Number(card.dataset.i)]; const p = q.panel || { slots: [] };
        const norm = (o) => JSON.stringify(Object.keys(o).sort().map((k) => [k, Number(o[k])]));
        let F = null;
        F = bindForm(card, p, { esc, onChange: () => { if (!F) return; card.querySelector('[data-chg]').innerHTML = norm(F.read()) !== norm(q.slots || {}) ? '<span class="pill warn">diubah verifikator</span>' : ''; } });
        const read = F.read;
        F.inputs.forEach((i) => { i.addEventListener('focus', () => { busy = true; }); i.addEventListener('blur', () => { busy = false; }); });
        F.update();
        card.querySelectorAll('[data-a]').forEach((b) => b.onclick = async () => {
          let note = null;
          if (b.dataset.a === 'return') { note = await ctx.askReason('Kembalikan ke asisten juri', 'Catatan (mis. E2 salah ketik)', { min: 2 }); if (note == null) return; }
          card.querySelectorAll('button').forEach((x) => { x.disabled = true; });
          try {
            await api('console_j_save', { p_entry: q.entry_id, p_apparatus: q.apparatus, p_slots: b.dataset.a === 'verify' ? read() : null, p_action: b.dataset.a, p_note: note });
            ctx.toast(b.dataset.a === 'verify' ? `${q.name}: ${f3(calc(p, read()).total)} terverifikasi, tampil di live.` : 'Dikembalikan ke asisten juri.');
            busy = false; await refresh();
          } catch (e) { ctx.toast(e.message, 'bad'); card.querySelectorAll('button').forEach((x) => { x.disabled = false; }); }
        });
      });
    };
    const refresh = async () => { if (tab !== 'q') return; Q = await api('console_j_queue'); drawQ(); };
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = async () => {
      v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b)));
      tab = b.dataset.t;
      if (tab === 'q') { ctx.loading(vb); await refresh(); ctx.setPageTimer(tick, 3000); }
      else { const box = document.createElement('div'); vb.innerHTML = ''; vb.appendChild(box); await sheetPage(box, ctx, 'verif'); box.querySelector('h1').remove(); }
    });
    const tick = async () => { if (busy || document.getElementById('dlg').open || !v.isConnected || tab !== 'q') return; try { await refresh(); } catch (e) {} };
    await refresh();
    ctx.setPageTimer(tick, 3000);
  }

  // =====================================================================
  //  PANEL JURI: atur isian (tambah/hapus E, A, D, Pen) per disiplin/kategori/alat
  // =====================================================================
  async function panelPage(v, ctx) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    const P = await api('console_j_panels');
    const discName = (c) => (JC.disciplines.find((d) => d.code === c) || {}).name || c;
    v.innerHTML = `<h1>Panel juri</h1><p class="muted">Isian yang diketik asisten juri. Panel dasar berlaku untuk satu disiplin; panel khusus menimpa untuk kategori dan/atau alat tertentu. Nilai yang sudah masuk dihitung ulang saat disimpan berikutnya.</p>
      <div class="acts-l" style="margin-bottom:14px"><button class="btn btn-primary btn-sm" id="padd">Tambah panel khusus</button></div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Berlaku untuk</th><th>Isian</th><th>E</th><th></th></tr></thead><tbody>
      ${P.map((p, i) => `<tr><td><strong>${esc(discName(p.discipline))}</strong><br><span class="small muted">${p.category ? esc(p.category) : 'Semua kategori'} · ${p.apparatus ? esc(p.apparatus) : 'semua alat'}</span></td>
        <td class="small">${p.slots.map((s) => `<span class="pill">${esc(s.label)} <span class="muted">${s.comp}</span></span>`).join(' ')}</td>
        <td class="small">${p.e_mode === 'deduction' ? `${p.e_base} − pengurangan` : 'nilai E langsung'}${p.sheet === 'artistik' ? '<br>Lembar artistik' : ''}${(p.runs || 1) > 1 ? `<br>${p.runs} lompatan` : ''}</td>
        <td class="r"><button class="btn btn-ghost btn-sm" data-pe="${i}">Ubah</button></td></tr>`).join('')}</tbody></table></div>`;
    const edit = async (p) => {
      const cats = JC.categories;
      let slots = p ? p.slots.map((x) => ({ ...x })) : [{ key: 'D', comp: 'D', label: 'D' }, { key: 'E1', comp: 'E', label: 'E1' }, { key: 'E2', comp: 'E', label: 'E2' }, { key: 'E3', comp: 'E', label: 'E3' }, { key: 'PEN', comp: 'PEN', label: 'Pen' }];
      const rowsHtml = () => slots.map((s, i) => `<div class="pslot" data-i="${i}"><input data-f="key" value="${esc(s.key)}" placeholder="Kode" style="width:80px">
        <select data-f="comp">${['D', 'E', 'A', 'PEN'].map((c) => `<option ${s.comp === c ? 'selected' : ''}>${c}</option>`).join('')}</select>
        <input data-f="label" value="${esc(s.label)}" placeholder="Label" style="width:110px"><button type="button" class="btn btn-ghost btn-sm" data-rm="${i}" title="Hapus isian">Hapus</button></div>`).join('');
      const base = !p || (!p.category_id && !p.apparatus);
      const res = await ctx.dialog({ title: p ? 'Ubah panel' : 'Panel khusus baru', ok: 'Simpan', wide: true,
        body: `<div class="grid-2"><div class="field"><label class="f">Disiplin</label><select id="pd" ${p ? 'disabled' : ''}>${JC.disciplines.map((d) => `<option value="${d.code}" ${p && p.discipline === d.code ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select></div>
          <div class="field"><label class="f">Kategori</label><select id="pc" ${p ? 'disabled' : ''}><option value="">Semua kategori</option>${cats.map((c) => `<option value="${c.id}" data-d="${c.discipline}" ${p && p.category_id === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div></div>
          <div class="grid-2"><div class="field"><label class="f">Alat (kosong = semua)</label><input id="pa" value="${esc(p && p.apparatus ? p.apparatus : '')}" placeholder="mis. VT" ${p ? 'disabled' : ''}></div>
          <div class="field"><label class="f">Cara isi E</label><select id="pm"><option value="score" ${!p || p.e_mode !== 'deduction' ? 'selected' : ''}>Nilai E langsung (rata-rata)</option><option value="deduction" ${p && p.e_mode === 'deduction' ? 'selected' : ''}>Pengurangan (E = dasar − rata-rata)</option></select></div></div>
          <div class="grid-3"><div class="field"><label class="f">Nilai dasar E (mode pengurangan)</label><input id="pb" value="${p ? p.e_base : 10}" style="width:100px"></div>
          <div class="field"><label class="f">Format lembar</label><select id="psh"><option value="standar" ${!p || p.sheet !== 'artistik' ? 'selected' : ''}>Standar</option><option value="artistik" ${p && p.sheet === 'artistik' ? 'selected' : ''}>Artistik (Rerata & Nilai Akhir otomatis, bisa diubah manual)</option></select></div>
          <div class="field"><label class="f">Lompatan / percobaan</label><select id="pr">${[1, 2, 3].map((n) => `<option value="${n}" ${(p ? p.runs || 1 : 1) === n ? 'selected' : ''}>${n}${n > 1 ? ' (nilai = rata-rata)' : ''}</option>`).join('')}</select></div></div>
          <span class="f">Isian</span><div id="pslots">${rowsHtml()}</div>
          <div class="acts-l" style="margin-top:8px"><button type="button" class="btn btn-ghost btn-sm" data-add="E">+ E</button><button type="button" class="btn btn-ghost btn-sm" data-add="D">+ D</button><button type="button" class="btn btn-ghost btn-sm" data-add="A">+ A</button><button type="button" class="btn btn-ghost btn-sm" data-add="PEN">+ Pen</button></div>
          <p class="tiny muted">D, E, A = rata-rata isian komponennya (4 isian atau lebih: tertinggi & terendah dibuang). Pen = jumlah semua isian Pen.</p>
          ${p && !base ? '<label class="check"><input type="checkbox" id="pdel"><span>Hapus panel khusus ini (kembali ke panel dasar)</span></label>' : ''}`,
        onOk: async (d) => {
          slots = [...d.querySelectorAll('.pslot')].map((r) => ({ key: r.querySelector('[data-f=key]').value, comp: r.querySelector('[data-f=comp]').value, label: r.querySelector('[data-f=label]').value }));
          const del = d.querySelector('#pdel') && d.querySelector('#pdel').checked;
          await api('console_j_panel_save', { p: { discipline: p ? p.discipline : d.querySelector('#pd').value, category_id: p ? p.category_id : d.querySelector('#pc').value,
            apparatus: p ? p.apparatus : d.querySelector('#pa').value, slots, e_mode: d.querySelector('#pm').value, e_base: d.querySelector('#pb').value, sheet: d.querySelector('#psh').value, runs: d.querySelector('#pr').value, delete: del ? 'true' : 'false' } });
          return true;
        } });
      if (res) { ctx.toast('Panel juri disimpan.'); panelPage(v, ctx); }
    };
    // tombol tambah/hapus isian di dalam dialog
    const wire = () => setTimeout(() => {
      const d = document.getElementById('dlg'); if (!d || !d.open) return;
      const box = d.querySelector('#pslots'); if (!box || box.dataset.w) return; box.dataset.w = '1';
      d.querySelector('form').addEventListener('click', (ev) => {
        const add = ev.target.closest('[data-add]'); const rm = ev.target.closest('[data-rm]');
        if (!add && !rm) return;
        const rows = [...box.querySelectorAll('.pslot')].map((r) => ({ key: r.querySelector('[data-f=key]').value, comp: r.querySelector('[data-f=comp]').value, label: r.querySelector('[data-f=label]').value }));
        if (add) { const c = add.dataset.add; const n = rows.filter((x) => x.comp === c).length + 1; const k = c === 'PEN' ? 'PEN' + n : c + n;
          const at = c === 'PEN' ? rows.length : rows.filter((x) => x.comp !== 'PEN').length; rows.splice(at, 0, { key: k, comp: c, label: c === 'PEN' ? 'Pen ' + n : k }); }
        if (rm) rows.splice(Number(rm.dataset.rm), 1);
        box.innerHTML = rows.map((s, i) => `<div class="pslot" data-i="${i}"><input data-f="key" value="${esc(s.key)}" style="width:80px"><select data-f="comp">${['D', 'E', 'A', 'PEN'].map((c) => `<option ${s.comp === c ? 'selected' : ''}>${c}</option>`).join('')}</select><input data-f="label" value="${esc(s.label)}" style="width:110px"><button type="button" class="btn btn-ghost btn-sm" data-rm="${i}">Hapus</button></div>`).join('');
      });
    }, 30);
    v.querySelector('#padd').onclick = () => { wire(); edit(null); };
    v.querySelectorAll('[data-pe]').forEach((b) => b.onclick = () => { wire(); edit(P[Number(b.dataset.pe)]); });
  }

  // =====================================================================
  //  START LIST SIMULASI (kode dummy)
  // =====================================================================
  async function simStartPage(v, ctx) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    if (!S.cat) { const first = JC.categories.find((c) => c.paid > 0); S.cat = first ? String(first.id) : ''; }
    v.innerHTML = `<h1>Start list simulasi</h1><p class="muted">Urutan tampil khusus simulasi. Start list resmi tidak berubah.</p>${modeBanner(ctx)}
      <div class="bar"><div class="field" style="flex:1;min-width:240px"><label class="f" for="jc">Kategori</label><select id="jc">${catOptions(S.cat, (c) => c.paid > 0)}</select></div></div><div id="sl"></div>`;
    const box = v.querySelector('#sl');
    const load = async () => {
      if (!S.cat) { box.innerHTML = '<p class="empty">Belum ada kategori dengan atlet lunas.</p>'; return; }
      ctx.loading(box);
      const D = await api('console_j_sheet', { p_category: Number(S.cat) });
      const rows = D.entries.filter((e) => e.status === 'aktif');
      box.innerHTML = `<section class="card"><h2 style="margin-top:0">${esc(D.category.name)} <span class="muted small">${rows.length} atlet</span></h2>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Atlet</th><th>Klub</th><th>Grup</th><th>Urutan</th></tr></thead><tbody>
        ${rows.map((e) => `<tr data-e="${e.entry_id}"><td>${esc(e.name)}</td><td class="small">${esc(e.club || '')}</td>
          <td><input data-f="group_no" type="number" min="1" style="width:70px" value="${e.group_no || ''}"></td>
          <td><input data-f="start_order" type="number" min="1" style="width:80px" value="${e.start_order || ''}"></td></tr>`).join('')}</tbody></table></div>
        <div class="sticky-actions"><button class="btn btn-dark" id="save">Simpan</button><button class="btn btn-ghost" id="draw">Undi urutan acak</button>
          <a class="btn btn-ghost" href="#/nilai?c=${D.category.id}">Ke penilaian</a></div></section>`;
      const read = () => [...box.querySelectorAll('tr[data-e]')].map((tr) => ({ entry_id: tr.dataset.e, group_no: tr.querySelector('[data-f=group_no]').value, start_order: tr.querySelector('[data-f=start_order]').value }));
      box.querySelector('#save').onclick = async () => { try { await api('console_sim_startlist_save', { p_category: Number(S.cat), p_rows: read() }); ctx.toast('Start list simulasi disimpan.'); load(); } catch (e) { ctx.toast(e.message, 'bad'); } };
      box.querySelector('#draw').onclick = async () => { try { await api('console_sim_draw', { p_category: Number(S.cat) }); ctx.toast('Urutan diundi.'); load(); } catch (e) { ctx.toast(e.message, 'bad'); } };
    };
    v.querySelector('#jc').onchange = (ev) => { S.cat = ev.target.value; load(); };
    await load();
  }

  // =====================================================================
  //  KONFIRMASI HASIL (TD): PDF hasil lengkap -> konfirmasi -> medali resmi
  // =====================================================================
  function resultsPdf(doc, R, opts) {
    const { jsPDF } = window.jspdf;
    doc = doc || new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
    if (opts && opts.newPage) doc.addPage();
    const c = R.category; const apps = R.apparatus; const W = 297, M = 10;
    let y = 14;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(13); doc.text('JABAR OPEN 2026 · HASIL PERTANDINGAN', M, y);
    doc.setFontSize(11); doc.text(c.name_id, M, y + 6);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8);
    doc.text(`Gymnasium Arcamanik, Bandung · dicetak ${new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })} WIB${c.td_confirmed_at ? ' · dikonfirmasi TD' : ' · DRAF untuk diperiksa TD'}`, M, y + 11);
    y += 17;
    const appW = apps.length > 1 ? Math.min(28, (W - 2 * M - 120) / apps.length) : 0;
    const cols = [['Per.', 10], ['Atlet', 58], ['Klub / kab-kota', 50]];
    apps.forEach((a) => cols.push([a.code, appW || 30]));
    cols.push(['Total', 18], ['Medali', 22]);
    const head = () => {
      doc.setFillColor(19, 40, 74); doc.rect(M, y - 4, W - 2 * M, 6, 'F'); doc.setTextColor(255); doc.setFont('helvetica', 'bold'); doc.setFontSize(7.5);
      let x = M + 1; cols.forEach(([t, w]) => { doc.text(t, x, y); x += w; }); doc.setTextColor(0); doc.setFont('helvetica', 'normal'); y += 5;
    };
    head();
    const MED = { emas: 'Emas', perak: 'Perak', perunggu: 'Perunggu' };
    const ties = new Set(); R.results.forEach((r, i) => { const o = R.results.find((x, j) => j !== i && x.rank && x.rank === r.rank); if (o && r.rank) ties.add(r.entry_id); });
    R.results.forEach((r, i) => {
      if (y > 192) { doc.addPage(); y = 14; head(); }
      if (i % 2) { doc.setFillColor(244, 246, 250); doc.rect(M, y - 3.6, W - 2 * M, 7.6, 'F'); }
      let x = M + 1; doc.setFontSize(8);
      doc.setFont('helvetica', 'bold'); doc.text(String(r.rank || '–') + (ties.has(r.entry_id) ? '=' : ''), x, y); x += cols[0][1];
      doc.text(doc.splitTextToSize(r.athletes.map((a) => a.name).join(' & '), cols[1][1] - 2)[0], x, y); doc.setFont('helvetica', 'normal');
      doc.setFontSize(6.5); doc.text(r.athletes.map((a) => a.athlete_no || '').join(' '), x, y + 3); doc.setFontSize(8); x += cols[1][1];
      doc.text(doc.splitTextToSize(r.club || '', cols[2][1] - 2)[0], x, y); doc.setFontSize(6.5); doc.text(doc.splitTextToSize(r.region || '', cols[2][1] - 2)[0], x, y + 3); doc.setFontSize(8); x += cols[2][1];
      apps.forEach((a) => {
        const det = R.detail[r.entry_id + ':' + a.code];
        doc.text(f3(r.scores[a.code]), x, y);
        if (det) { doc.setFontSize(5.8); doc.text(`D${f3(det.d)} E${f3(det.e)}${det.a != null ? ' A' + f3(det.a) : ''}${det.pen ? ' P-' + f3(det.pen) : ''}`, x, y + 3); doc.setFontSize(8); }
        x += appW || 30;
      });
      doc.setFont('helvetica', 'bold'); doc.text(f3(r.total), x, y); doc.setFont('helvetica', 'normal'); x += 18;
      doc.text(r.medal ? MED[r.medal] : r.mini ? 'Mini ' + r.award_rank : '', x, y);
      y += 7.6;
    });
    // panel juri & petugas per sesi + alat (dari menu Petugas & panel juri)
    const ses = R.sessions || []; const ro = R.roster || {};
    const lines = [];
    ses.forEach((ss) => { const m = ro[ss.id]; if (!m) return;
      const head = `${ss.name}${ss.day ? ' · ' + new Date(ss.day + 'T00:00:00').toLocaleDateString('id-ID', { day: 'numeric', month: 'short' }) : ''}`;
      if (m['*']) lines.push(`${head} · ${Object.values(m['*']).sort((x, y) => (x.sort || 0) - (y.sort || 0)).map((p) => (p.label || '') + ': ' + p.name).join(' · ')}`);
      apps.forEach((a) => { const pm = m[a.code]; if (!pm) return;
        lines.push(`${head} · ${a.id || a.code}: ${Object.values(pm).sort((x, y) => (x.sort || 0) - (y.sort || 0)).map((p) => (p.label || '') + ' ' + p.name).join(' · ')}`); });
    });
    if (lines.length) {
      y += 4; if (y > 180) { doc.addPage(); y = 20; }
      doc.setFont('helvetica', 'bold'); doc.setFontSize(8); doc.text('Panel juri & petugas', M, y); y += 4;
      doc.setFont('helvetica', 'normal'); doc.setFontSize(7);
      lines.forEach((ln) => { doc.splitTextToSize(ln, W - 2 * M).forEach((t) => { if (y > 196) { doc.addPage(); y = 16; } doc.text(t, M, y); y += 3.4; }); });
    }
    const tdName = (() => { for (const ss of ses) { const m = ro[ss.id]; if (m && m['*'] && m['*'].TD) return m['*'].TD.name; } return ''; })();
    y += 4; if (y > 185) { doc.addPage(); y = 20; }
    doc.setFontSize(7); doc.text('Per. = peringkat serba bisa; "=" menandai nilai seri (perlu keputusan TD). Rincian per alat: D, E (rata-rata), A, P = penalti.', M, y);
    doc.text('Technical Delegate', W - M - 60, y + 6); doc.line(W - M - 60, y + 22, W - M, y + 22);
    doc.text(tdName || c.td_confirmed_by_name || '', W - M - 60, y + 26);
    return doc;
  }

  async function tdPage(v, ctx) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    const ME = ctx.ME;
    if (!S.cat) { const first = JC.categories.find((c) => c.verified > 0) || JC.categories[0]; S.cat = first ? String(first.id) : ''; }
    v.innerHTML = `<h1>Konfirmasi hasil (TD)</h1>
      <p class="muted">Live view tidak resmi. Hasil resmi: 1) unduh dan periksa PDF hasil, 2) konfirmasi TD, lalu medali dan hasil tampil di halaman Hasil situs.</p>
      <div class="bar"><div class="field" style="flex:1;min-width:240px"><label class="f" for="jc">Kategori</label><select id="jc">${catOptions(S.cat)}</select></div>
        <button class="btn btn-ghost btn-sm" id="alldisc" style="align-self:end">PDF semua kategori ${esc(ctx.DGN[ME.group] || '')}</button></div><div id="tr"></div>`;
    const box = v.querySelector('#tr');
    const load = async () => {
      if (!S.cat) { box.innerHTML = '<p class="empty">Pilih kategori.</p>'; return; }
      ctx.loading(box);
      const R = await api('console_td_results', { p_category: Number(S.cat) });
      const c = R.category; const apps = R.apparatus;
      const ties = R.results.filter((r, i) => r.rank && R.results.some((x, j) => j !== i && x.rank === r.rank));
      const sup = ME.role === 'owner' || ME.role === 'superadmin';
      box.innerHTML = `<section class="card"><div class="row" style="justify-content:space-between;gap:8px"><h2 style="margin:0">${esc(c.name_id)}</h2>
          ${c.td_confirmed_at ? `<span class="pill ok">Resmi · dikonfirmasi ${esc(c.td_confirmed_by_name || 'TD')} ${ctx.dt(c.td_confirmed_at)}</span>` : c.results_published ? '<span class="pill ok">Dipublikasikan</span>' : '<span class="pill">Belum resmi</span>'}</div>
        ${R.pending ? `<p class="note warn small">${R.pending} nilai belum terverifikasi. Konfirmasi baru bisa setelah semua nilai diverifikasi.</p>` : ''}
        ${ties.length ? `<p class="note warn small">Nilai seri: ${ties.map((r) => esc(r.athletes.map((a) => a.name).join(' & ')) + ' (per. ' + r.rank + ')').join(', ')}. Periksa aturan pemisah nilai sebelum konfirmasi.</p>` : ''}
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">Per.</th><th>Atlet</th><th>Klub</th>${apps.map((a) => `<th class="r">${esc(a.code)}<br><span class="tiny muted">D / E / Pen</span></th>`).join('')}<th class="r">Total</th><th>Medali</th></tr></thead><tbody>
        ${R.results.map((r) => `<tr><td class="c"><span class="rank">${r.rank || '–'}</span></td><td>${r.athletes.map((a) => esc(a.name)).join('<br>')}</td><td class="small">${esc(r.club)}<br><span class="muted">${esc(r.region || '')}</span></td>
          ${apps.map((a) => { const d = R.detail[r.entry_id + ':' + a.code]; return `<td class="r num">${f3(r.scores[a.code])}${d ? `<br><span class="tiny muted">${f3(d.d)} / ${f3(d.e)} / ${d.pen ? '-' + f3(d.pen) : '0'}</span>${d.status !== 'verified' ? ` <span class="pill warn">${ST_LBL[d.status]}</span>` : ''}${d.flags && d.flags.length ? ' <span class="pill warn" title="Rerata / Nilai Akhir diketik manual">Manual</span>' : ''}` : ''}</td>`; }).join('')}
          <td class="r num"><strong>${f3(r.total)}</strong></td><td>${r.medal ? `<span class="medal ${r.medal}"></span>` : r.mini ? `<span class="pill">Mini ${r.award_rank}</span>` : ''}</td></tr>`).join('')}</tbody></table></div>
        <ol class="td-steps">
          <li class="${c.td_pdf_at ? 'done' : ''}"><b>PDF hasil lengkap</b> <span class="small muted">${c.td_pdf_at ? 'dibuat ' + ctx.dt(c.td_pdf_at) : 'belum dibuat'}</span><br><button class="btn btn-dark btn-sm" id="pdf">Unduh PDF hasil</button></li>
          <li class="${c.td_confirmed_at ? 'done' : ''}"><b>Konfirmasi TD & publikasi medali</b><br>
            ${c.td_confirmed_at ? (sup ? '<button class="btn btn-bad btn-sm" id="revoke">Tarik hasil resmi</button>' : '<span class="small">Sudah resmi.</span>')
              : `<button class="btn btn-primary btn-sm" id="conf" ${!c.td_pdf_at || R.pending ? 'disabled' : ''}>Konfirmasi hasil & publikasikan medali</button>`}</li></ol></section>`;
      box.querySelector('#pdf').onclick = async () => {
        try { resultsPdf(null, R).save(`hasil-${c.code}.pdf`); await api('console_td_confirm', { p_category: c.id, p_step: 'pdf' }); load(); }
        catch (e) { ctx.toast(e.message, 'bad'); }
      };
      const conf = box.querySelector('#conf');
      if (conf) conf.onclick = async () => {
        const ok = await ctx.dialog({ title: 'Konfirmasi hasil resmi?', ok: 'Konfirmasi & publikasikan', body: `<p>Hasil <strong>${esc(c.name_id)}</strong> menjadi resmi: tampil di halaman Hasil situs, tabel medali bertambah, sertifikat bisa diunduh peserta. Pastikan PDF sudah diperiksa.</p>` });
        if (!ok) return;
        try { await api('console_td_confirm', { p_category: c.id, p_step: 'publish' }); ctx.toast('Hasil resmi dipublikasikan.'); load(); } catch (e) { ctx.toast(e.message, 'bad'); }
      };
      const rv = box.querySelector('#revoke');
      if (rv) rv.onclick = async () => {
        if (!(await ctx.dialog({ title: 'Tarik hasil resmi?', ok: 'Tarik', okClass: 'btn-bad', body: '<p>Hasil dan medali kategori ini hilang dari situs. TD perlu membuat PDF dan konfirmasi ulang.</p>' }))) return;
        try { await api('console_td_confirm', { p_category: c.id, p_step: 'revoke' }); load(); } catch (e) { ctx.toast(e.message, 'bad'); }
      };
    };
    v.querySelector('#jc').onchange = (ev) => { S.cat = ev.target.value; load(); };
    v.querySelector('#alldisc').onclick = async (ev) => {
      const b = ev.currentTarget; b.disabled = true; const t = b.textContent; b.textContent = 'Membuat PDF…';
      try {
        let doc = null;
        for (const c of JC.categories.filter((x) => x.verified > 0)) {
          const R = await api('console_td_results', { p_category: c.id });
          if (!R.results.some((r) => r.total != null)) continue;
          doc = resultsPdf(doc, R, { newPage: !!doc });
        }
        if (doc) doc.save(`hasil-${(ctx.DGN[ME.group] || 'semua').toLowerCase()}-${new Date().toISOString().slice(0, 10)}.pdf`); else ctx.toast('Belum ada nilai terverifikasi.', 'bad');
      } catch (e) { ctx.toast(e.message, 'bad'); }
      finally { b.disabled = false; b.textContent = t; }
    };
    await load();
  }

  // =====================================================================
  //  LAYAR LIVE
  // =====================================================================
  async function layarPage(v, ctx) {
    const { esc, api } = ctx;
    await loadCats(ctx, true);
    let L = await api('console_live_screens');
    const site = (window.JO && JO.siteUrl ? JO.siteUrl() : location.origin + '/');
    const draw = () => {
      const sup = ctx.ME.role === 'owner' || ctx.ME.role === 'superadmin';
      v.innerHTML = `<h1>Layar live</h1><p class="muted">Setiap layar = satu TV di venue atau satu tayangan di halaman Public Live View. Tautan venue memakai kunci layar dan tetap jalan walau tayangan publik dijeda.</p>${modeBanner(ctx)}
        <section class="card"><div class="row" style="justify-content:space-between;gap:10px;flex-wrap:wrap">
          <div><b>Public Live View</b><br><a class="small" href="${esc(site)}live.html" target="_blank" rel="noopener">${esc(site)}live.html</a></div>
          <div class="acts-l">
            ${L.mode === 'dummy' || sup ? `<button class="btn btn-sm ${L.dummy_on ? 'btn-bad' : 'btn-dark'}" id="dmy">${L.dummy_on ? 'Sembunyikan simulasi dari publik' : 'Tayangkan simulasi (DUMMY) ke publik'}</button>` : ''}
            ${L.can_public ? `<button class="btn btn-sm ${L.public_on ? 'btn-ghost' : 'btn-primary'}" id="pub">${L.public_on ? 'Jeda tayangan publik (venue tetap jalan)' : 'Buka lagi tayangan publik'}</button>` : ''}
          </div></div>
          <p class="small" style="margin:10px 0 0">${L.public_on ? '<span class="pill ok">Publik: tayang</span>' : '<span class="pill warn">Publik: dijeda</span>'} ${L.dummy_on ? '<span class="pill bad">Simulasi sedang tayang di situs</span>' : '<span class="pill">Simulasi tidak tayang</span>'}</p></section>
        <section class="card" style="margin-top:14px"><h2 style="margin-top:0">Teks berjalan${L.mode === 'dummy' ? ' (simulasi)' : ''}</h2>
          <textarea id="tk" rows="2" maxlength="600" placeholder="Mis. Sesi berikutnya: Artistik Putri Level 5 pukul 13.00 WIB · Terima kasih para mitra">${esc(L.mode === 'dummy' ? L.ticker_dummy : L.ticker)}</textarea>
          <div class="acts-l" style="margin-top:8px"><button class="btn btn-dark btn-sm" id="tks" ${L.can_edit ? '' : 'disabled'}>Simpan teks berjalan</button></div></section>
        <div class="row" style="justify-content:space-between;margin:18px 0 8px"><h2 style="margin:0">Layar</h2>${L.can_edit ? '<button class="btn btn-primary btn-sm" id="add">+ Tambah layar</button>' : ''}</div>
        ${L.screens.length ? `<div class="scr-grid">${L.screens.map((s) => `<article class="scr ${s.active ? 'on' : ''} ${s.mode}">
          <header><div><b>${esc(s.name)}</b>${s.mode === 'dummy' ? ' <span class="pill bad">DUMMY</span>' : ''}<br><span class="small muted">${esc(s.category || 'Belum pilih kategori')} · ${s.view === 'aa' ? 'Serba bisa' : s.view === 'app' ? 'Alat ' + esc(s.apparatus || '') : 'Bergantian serba bisa & per alat'} · layout ${s.layout}</span></div>
            <span class="pill ${s.active ? 'ok' : ''}">${s.active ? 'Tayang' : 'Mati'}</span></header>
          <div class="small">Publik: <a href="${esc(site)}live.html?layar=${s.id}" target="_blank" rel="noopener">live.html?layar=${s.id}</a><br>
            Venue (TV): <code class="tiny">live.html?layar=${s.id}&amp;k=${esc(s.vkey)}</code> <button class="btn btn-ghost btn-sm" data-cp="${esc(site)}live.html?layar=${s.id}&k=${esc(s.vkey)}&tv=1">Salin</button></div>
          ${L.can_edit && (s.mode === L.mode || sup) ? `<footer><button class="btn btn-sm ${s.active ? 'btn-ghost' : 'btn-ok'}" data-tg="${s.id}">${s.active ? 'Matikan' : 'Tayangkan'}</button><button class="btn btn-ghost btn-sm" data-ed="${s.id}">Ubah</button>
            <a class="btn btn-ghost btn-sm" target="_blank" rel="noopener" href="${esc(site)}live.html?layar=${s.id}&k=${esc(s.vkey)}&tv=1">Buka</a></footer>` : ''}</article>`).join('')}</div>` : '<p class="empty">Belum ada layar. Tambahkan satu layar per TV.</p>'}`;
      const set = async (p, msg) => { try { L = await api('console_live_settings', { p }); ctx.toast(msg); draw(); } catch (e) { ctx.toast(e.message, 'bad'); } };
      const dmy = v.querySelector('#dmy'); if (dmy) dmy.onclick = () => set({ dummy_on: !L.dummy_on }, L.dummy_on ? 'Simulasi disembunyikan.' : 'Simulasi tayang di situs publik.');
      const pub = v.querySelector('#pub'); if (pub) pub.onclick = () => set({ public_on: !L.public_on }, L.public_on ? 'Tayangan publik dijeda.' : 'Tayangan publik dibuka.');
      v.querySelector('#tks').onclick = () => set({ ticker: v.querySelector('#tk').value }, 'Teks berjalan disimpan.');
      v.querySelectorAll('[data-cp]').forEach((b) => b.onclick = () => navigator.clipboard.writeText(b.dataset.cp).then(() => ctx.toast('Tautan disalin.')));
      v.querySelectorAll('[data-tg]').forEach((b) => b.onclick = async () => { const s = L.screens.find((x) => x.id === Number(b.dataset.tg)); try { L = await api('console_live_screen_save', { p: { ...s, active: !s.active } }); draw(); } catch (e) { ctx.toast(e.message, 'bad'); } });
      v.querySelectorAll('[data-ed]').forEach((b) => b.onclick = () => edit(L.screens.find((x) => x.id === Number(b.dataset.ed))));
      const add = v.querySelector('#add'); if (add) add.onclick = () => edit(null);
    };
    const edit = async (s) => {
      const sup = ctx.ME.role === 'owner' || ctx.ME.role === 'superadmin';
      const cats = JC.categories;
      const appsOf = (cid) => { const c = cats.find((x) => String(x.id) === String(cid)); if (!c) return []; const d = JC.disciplines.find((x) => x.code === c.discipline); return (d ? d.apparatus : []).filter((a) => c.apparatus.includes(a.code)); };
      const r = await ctx.dialog({ title: s ? 'Ubah layar' : 'Layar baru', ok: 'Simpan', wide: true,
        body: `<div class="grid-2"><div class="field"><label class="f">Nama layar</label><input id="ln" value="${esc(s ? s.name : '')}" placeholder="mis. TV 1 Tribun Barat"></div>
          ${sup && !s ? `<div class="field"><label class="f">Mode</label><select id="lmo"><option value="real">Resmi (real)</option><option value="dummy">Simulasi (DUMMY)</option></select></div>` : '<div></div>'}</div>
          <div class="field"><label class="f">Kategori</label><select id="lc"><option value="">Pilih kategori</option>${catOptions(s ? s.category_id : '')}</select></div>
          <div class="grid-2"><div class="field"><label class="f">Tampilan</label><select id="lv">
            <option value="aa" ${!s || s.view === 'aa' ? 'selected' : ''}>Serba bisa (total semua alat)</option>
            <option value="app" ${s && s.view === 'app' ? 'selected' : ''}>Satu alat</option>
            <option value="rotate" ${s && s.view === 'rotate' ? 'selected' : ''}>Bergantian: serba bisa lalu tiap alat</option></select></div>
          <div class="field"><label class="f">Alat (tampilan satu alat)</label><select id="la"></select></div></div>
          <div class="field"><span class="f">Layout</span><div class="seg" id="ll">${[1, 2, 3].map((n) => `<label><input type="radio" name="ll" value="${n}" ${(s ? s.layout : 1) === n ? 'checked' : ''}>${n === 1 ? '1 · papan penuh' : n === 2 ? '2 · papan + 1 kamera' : '3 · 2 kamera + 3 teratas'}</label>`).join('')}</div></div>
          <div class="grid-2"><div class="field"><label class="f">Kamera 1 (tautan YouTube Live / embed)</label><input id="c1" value="${esc(s && s.cam1 ? s.cam1 : '')}" placeholder="https://youtube.com/live/..."></div>
          <div class="field"><label class="f">Kamera 2</label><input id="c2" value="${esc(s && s.cam2 ? s.cam2 : '')}" placeholder="https://youtube.com/live/..."></div></div>
          <div class="grid-3"><div class="field"><label class="f">Atlet di slide 1</label><input id="f1" type="number" min="3" max="14" value="${s ? s.first_n : 6}"></div>
          <div class="field"><label class="f">Atlet slide berikutnya</label><input id="n1" type="number" min="3" max="14" value="${s ? s.next_n : 10}"></div>
          <div class="field"><label class="f">Detik per slide</label><input id="ps" type="number" min="4" max="60" value="${s ? s.page_secs : 8}"></div></div>
          <label class="check"><input type="checkbox" id="lact" ${s && s.active ? 'checked' : ''}><span>Tayangkan sekarang</span></label>
          ${s ? '<label class="check"><input type="checkbox" id="ldel"><span>Hapus layar ini</span></label>' : ''}`,
        onOk: async (d) => {
          const del = d.querySelector('#ldel') && d.querySelector('#ldel').checked;
          L = await api('console_live_screen_save', { p: { id: s ? s.id : null, delete: del ? 'true' : 'false', mode: d.querySelector('#lmo') ? d.querySelector('#lmo').value : (s ? s.mode : L.mode),
            name: d.querySelector('#ln').value, category_id: d.querySelector('#lc').value, view: d.querySelector('#lv').value, apparatus: d.querySelector('#la').value,
            layout: d.querySelector('input[name=ll]:checked').value, cam1: d.querySelector('#c1').value, cam2: d.querySelector('#c2').value,
            first_n: d.querySelector('#f1').value, next_n: d.querySelector('#n1').value, page_secs: d.querySelector('#ps').value, active: d.querySelector('#lact').checked } });
          return true;
        } });
      if (r) { ctx.toast('Layar disimpan.'); draw(); }
      setTimeout(() => {}, 0);
    };
    // isi pilihan alat saat kategori berganti (dialog)
    document.getElementById('dlg').addEventListener('change', (ev) => {
      if (ev.target.id !== 'lc') return;
      fillApps();
    });
    const fillApps = () => {
      const d = document.getElementById('dlg'); const lc = d.querySelector('#lc'); const la = d.querySelector('#la'); if (!lc || !la) return;
      const c = JC.categories.find((x) => String(x.id) === lc.value); const disc = c && JC.disciplines.find((x) => x.code === c.discipline);
      const cur = la.value || la.dataset.cur || '';
      la.innerHTML = '<option value="">–</option>' + (disc ? disc.apparatus.filter((a) => c.apparatus.includes(a.code)).map((a) => `<option value="${a.code}" ${cur === a.code ? 'selected' : ''}>${esc(a.id)}</option>`).join('') : '');
    };
    new MutationObserver(() => { const d = document.getElementById('dlg'); const la = d && d.querySelector('#la'); if (la && !la.dataset.done) { la.dataset.done = '1'; const s = L.screens.find((x) => d.querySelector('#ln') && x.name === d.querySelector('#ln').value); if (s) la.dataset.cur = s.apparatus || ''; fillApps(); } })
      .observe(document.getElementById('dlg'), { childList: true, subtree: true });
    draw();
  }

  // =====================================================================
  //  LOG (owner, superadmin): riwayat nilai & aktivitas konsol juri
  // =====================================================================
  const ACT = { simpan: 'Simpan draf', kirim: 'Kirim ke verifikator', tarik: 'Tarik kembali', verifikasi: 'Verifikasi', koreksi: 'Koreksi',
    kembalikan: 'Kembalikan', batal_verifikasi: 'Batal verifikasi', hapus: 'Hapus nilai',
    masuk_konsol_juri: 'Masuk konsol juri', ganti_disiplin_konsol_juri: 'Ganti disiplin', panel_juri_diubah: 'Panel juri diubah', panel_juri_dihapus: 'Panel khusus dihapus',
    layar_diubah: 'Layar diubah', simulasi_dihapus: 'Data simulasi dihapus', simulasi_tayang: 'Simulasi ditayangkan', simulasi_disembunyikan: 'Simulasi disembunyikan',
    live_publik_dibuka: 'Tayangan publik dibuka', live_publik_dijeda: 'Tayangan publik dijeda', td_pdf_hasil: 'PDF hasil dibuat (TD)', td_konfirmasi_hasil: 'Hasil resmi dikonfirmasi (TD)', td_hasil_ditarik: 'Hasil resmi ditarik' };
  async function logPage(v, ctx) {
    const { esc, api } = ctx;
    let tab = 'nilai';
    v.innerHTML = `<h1>Log konsol juri</h1><p class="muted">Semua perubahan nilai dan aktivitas di konsol juri ${esc(ctx.DGN[ctx.ME.group] || '')}. Hanya owner dan superadmin.</p>
      <div class="tabs"><button data-t="nilai" aria-selected="true">Nilai</button><button data-t="sim" aria-selected="false">Nilai simulasi</button><button data-t="akt" aria-selected="false">Aktivitas</button></div>
      <div class="bar"><input id="lq" type="search" placeholder="Cari nama atlet, kategori, pemegang kode, alasan" style="flex:1;min-width:220px"></div><div id="lb"></div>`;
    const lb = v.querySelector('#lb'); let rows = [];
    const draw = () => {
      const q = v.querySelector('#lq').value.trim().toLowerCase();
      const R = rows.filter((r) => !q || JSON.stringify(r).toLowerCase().includes(q));
      if (!R.length) { lb.innerHTML = '<p class="empty">Belum ada catatan.</p>'; return; }
      lb.innerHTML = tab === 'akt'
        ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th>Aktivitas</th><th>Oleh</th><th>Rincian</th></tr></thead><tbody>
          ${R.map((r) => `<tr><td class="small nowrap">${ctx.dt(r.at)}</td><td>${esc(ACT[r.action] || r.action)}</td><td>${esc(r.by || 'Sistem')}${r.role ? ` <span class="tiny muted">${esc(ctx.ROLE[r.role] || r.role)}${r.dummy ? ' · DUMMY' : ''}</span>` : ''}</td>
            <td class="tiny muted">${esc([r.detail && r.detail.disiplin ? ctx.DGN[r.detail.disiplin] : '', r.detail && r.detail.alasan, r.detail && r.detail.name, r.target_type === 'category' ? 'kategori #' + r.target_id : ''].filter(Boolean).join(' · '))}</td></tr>`).join('')}</tbody></table></div>`
        : `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Waktu</th><th>Atlet</th><th>Alat</th><th>Tindakan</th><th class="r">Sebelum</th><th class="r">Sesudah</th><th>Oleh</th><th>Alasan / catatan</th></tr></thead><tbody>
          ${R.map((r) => `<tr><td class="small nowrap">${ctx.dt(r.at)}</td><td><strong>${esc(r.name)}</strong><br><span class="tiny muted">${esc(r.category)}</span></td><td>${esc(r.apparatus)}</td>
            <td>${esc(ACT[r.action] || r.action)}${r.flags && r.flags.length ? ` <span class="pill warn" title="${esc(r.flags.map((f) => flagText(f, 2)).join('; '))}">Manual</span>` : ''}</td><td class="r num">${r.old != null ? f3(r.old) : '–'}</td><td class="r num">${r.new != null ? f3(r.new) : '–'}</td>
            <td class="small">${esc(r.by || '')}${r.role ? `<br><span class="tiny muted">${esc(ctx.ROLE[r.role] || r.role)}</span>` : ''}</td><td class="small">${esc(r.reason || '')}</td></tr>`).join('')}</tbody></table></div>`;
    };
    const load = async () => {
      ctx.loading(lb);
      rows = await api('console_j_audit', { p_kind: tab === 'akt' ? 'aktivitas' : 'nilai', p_mode: tab === 'sim' ? 'dummy' : 'real', p_limit: 500 });
      draw();
    };
    v.querySelectorAll('[data-t]').forEach((b) => b.onclick = () => { v.querySelectorAll('[data-t]').forEach((x) => x.setAttribute('aria-selected', String(x === b))); tab = b.dataset.t; load(); });
    v.querySelector('#lq').oninput = draw;
    await load();
  }

  // =====================================================================
  //  PETUGAS & PANEL JURI per sesi + alat
  // =====================================================================
  const FIX = { KETUA: 'Ketua panel', ASJUR: 'Asisten juri', VERIF: 'Verifikator', TD: 'Technical Delegate (TD)' };
  async function petugasPage(v, ctx) {
    const { esc, api } = ctx;
    let L = await api('console_roster_sessions');
    const hp = ctx.hashParams(); let sid = hp.get('s') || (S.sid && L.sessions.some((x) => String(x.id) === String(S.sid)) ? S.sid : (L.sessions[0] && L.sessions[0].id));
    const dayTxt = (x) => [x.day ? new Date(x.day + 'T00:00:00').toLocaleDateString('id-ID', { weekday: 'short', day: 'numeric', month: 'short' }) : '', x.start_time ? String(x.start_time).slice(0, 5) : ''].filter(Boolean).join(' ');
    v.innerHTML = `<h1>Petugas & panel juri</h1><p class="muted">Nama juri dan petugas per sesi dan alat. Nama muncul di lembar nilai asisten juri dan di PDF hasil resmi.</p>
      ${L.sessions.length ? `<div class="bar"><div class="field" style="flex:1;min-width:260px"><label class="f" for="ss">Sesi</label><select id="ss">${L.sessions.map((x) => `<option value="${x.id}" ${String(x.id) === String(sid) ? 'selected' : ''}>${esc(x.name)} · ${esc(dayTxt(x))}${x.filled ? ` · ${x.filled} nama` : ''}</option>`).join('')}</select></div></div><div id="rb"></div>`
        : '<p class="empty">Belum ada sesi untuk disiplin ini. Buat sesi di menu Start list.</p>'}`;
    if (!L.sessions.length) return;
    const rb = v.querySelector('#rb');
    const load = async () => {
      S.sid = sid; ctx.loading(rb);
      const R = await api('console_roster_get', { p_session: Number(sid) });
      draw(R);
    };
    const draw = (R) => {
      const ed = R.can_edit;
      const byKey = {}; R.rows.forEach((r) => { byKey[r.apparatus + '|' + r.position] = r; });
      const extras = (app) => R.rows.filter((r) => r.apparatus === app && /^X:/.test(r.position));
      const row = (app, pos, label, fixed) => { const r = byKey[app + '|' + pos] || {};
        return `<div class="rr" data-app="${esc(app)}" data-pos="${esc(pos)}">
          ${fixed ? `<span class="rl">${esc(label)}</span>` : `<input class="rl" data-f="label" value="${esc(r.label || label || '')}" placeholder="Nama posisi" ${ed ? '' : 'disabled'}>`}
          <input data-f="name" list="ppl" value="${esc(r.name || '')}" placeholder="${ed ? 'Ketik atau pilih nama' : '–'}" ${ed ? '' : 'disabled'}>
          ${!fixed && ed ? '<button type="button" class="btn btn-ghost btn-sm" data-rm>Hapus</button>' : ''}</div>`; };
      const card = (app, title, fixedRows) => `<section class="card rcard" data-card="${esc(app)}"><h2>${esc(title)}</h2>
          ${fixedRows.map(([pos, label]) => row(app, pos, label, true)).join('')}
          <div data-extra>${extras(app).map((r) => row(app, r.position, r.label, false)).join('')}</div>
          ${ed ? '<button type="button" class="btn btn-ghost btn-sm" data-add>+ Tambah posisi</button>' : ''}</section>`;
      rb.innerHTML = `<datalist id="ppl">${R.people.map((p) => `<option value="${esc(p.name)}">${esc(p.src === 'juri' ? 'Pendaftar juri' : ctx.ROLE[p.src] || p.src)}</option>`).join('')}</datalist>
        <div class="rgrid">
        ${card('*', 'Seluruh sesi', [['TD', FIX.TD]])}
        ${R.apparatus.map((a) => card(a.code, a.name, [['KETUA', FIX.KETUA], ...a.seats.map((x) => [x.position, x.label]), ['ASJUR', FIX.ASJUR], ['VERIF', FIX.VERIF]])).join('')}
        </div>
        ${ed ? `<div class="sticky-actions"><button class="btn btn-primary" id="rsave">Simpan petugas</button>
          ${R.others.length ? `<select id="rfrom"><option value="">Salin dari sesi lain…</option>${R.others.map((o) => `<option value="${o.id}">${esc(o.name)} · ${esc(dayTxt(o))}</option>`).join('')}</select>` : ''}</div>` : '<p class="small muted">Hanya owner, superadmin, dan TD yang bisa mengubah.</p>'}`;
      let xn = Date.now();
      rb.querySelectorAll('[data-add]').forEach((b) => b.onclick = () => {
        const c = b.closest('[data-card]'); const box = c.querySelector('[data-extra]');
        box.insertAdjacentHTML('beforeend', row(c.dataset.card, 'X:' + (xn++).toString(36), '', false));
        box.lastElementChild.querySelector('[data-f=label]').focus();
      });
      rb.addEventListener('click', (ev) => { const x = ev.target.closest('[data-rm]'); if (x) x.closest('.rr').remove(); });
      const sv = rb.querySelector('#rsave');
      if (sv) sv.onclick = async () => {
        const rows = [...rb.querySelectorAll('.rr')].map((r) => ({ apparatus: r.dataset.app, position: r.dataset.pos,
          label: r.querySelector('[data-f=label]') ? r.querySelector('[data-f=label]').value : r.querySelector('.rl').textContent,
          name: r.querySelector('[data-f=name]').value })).filter((r) => r.name.trim());
        sv.disabled = true;
        try { const R2 = await api('console_roster_save', { p_session: Number(sid), p_rows: rows }); ctx.toast(`Petugas disimpan (${R2.rows.length} nama).`); draw(R2); }
        catch (e) { ctx.toast(e.message, 'bad'); sv.disabled = false; }
      };
      const rf = rb.querySelector('#rfrom');
      if (rf) rf.onchange = async () => {
        if (!rf.value) return;
        if (!(await ctx.dialog({ title: 'Salin petugas?', ok: 'Salin', body: '<p>Semua nama di sesi ini diganti dengan nama dari sesi yang dipilih.</p>' }))) { rf.value = ''; return; }
        try { draw(await api('console_roster_copy', { p_from: Number(rf.value), p_to: Number(sid) })); ctx.toast('Petugas disalin.'); } catch (e) { ctx.toast(e.message, 'bad'); }
      };
    };
    v.querySelector('#ss').onchange = (ev) => { sid = ev.target.value; load(); };
    await load();
  }

  window.JO_MOD = window.JO_MOD || {};
  window.JO_MOD['konsol-juri'] = {
    penilaian: (v, ctx) => sheetPage(v, ctx, 'asjur'),
    verifikasi: (v, ctx) => verifPage(v, ctx),
    pantau: (v, ctx) => sheetPage(v, ctx, 'pantau'),
    panel: (v, ctx) => panelPage(v, ctx),
    simstart: (v, ctx) => simStartPage(v, ctx),
    td: (v, ctx) => tdPage(v, ctx),
    layar: (v, ctx) => layarPage(v, ctx),
    log: (v, ctx) => logPage(v, ctx),
    petugas: (v, ctx) => petugasPage(v, ctx),
  };
})();
