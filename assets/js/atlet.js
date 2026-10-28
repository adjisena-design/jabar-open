/* Jabar Open 2026 — direktori atlet publik (dibuka otomatis 12 Des 2026 atau dari konsol) */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    at_title: ['Atlet', 'Athletes'],
    at_lead: ['Atlet dan tim beregu yang terdaftar penuh di Jabar Open 2026. Setelah jadwal pertandingan atau hasil diumumkan, klik kartu untuk melihat jadwal tampil dan medali.', 'Fully registered athletes and teams at Jabar Open 2026. Once the competition schedule or results are announced, tap a card to see start times and medals.'],
    at_soon_t: ['Segera hadir', 'Coming soon'],
    at_soon_d: ['Halaman ini sedang disiapkan. Pantau Instagram @gimnastikjabar.', 'This page is being prepared. Follow Instagram @gimnastikjabar.'],
    at_q: ['Nama atlet, tim, atau klub', 'Athlete, team or club name'],
    at_all_disc: ['Semua disiplin', 'All disciplines'], at_all_region: ['Semua kab/kota', 'All regencies/cities'],
    at_all_club: ['Semua klub', 'All clubs'], at_all_gender: ['Putra dan putri', 'Men and women'],
    at_m: ['Putra', 'Men'], at_f: ['Putri', 'Women'], at_x: ['Campuran', 'Mixed'],
    at_reset: ['Hapus saringan', 'Clear filters'],
    at_count: ['{a} atlet · {t} tim beregu', '{a} athletes · {t} teams'],
    at_count_a: ['{a} atlet', '{a} athletes'],
    at_none: ['Tidak ada atlet yang cocok dengan pencarian ini.', 'No athletes match this search.'],
    at_more: ['Muat lebih banyak', 'Load more'], at_shown: ['{n} dari {t} ditampilkan', 'Showing {n} of {t}'],
    at_team: ['Tim beregu', 'Team'], at_members: ['Anggota', 'Members'],
    at_view: ['Lihat jadwal & hasil', 'See schedule & results'],
    at_close: ['Tutup', 'Close'],
    at_sched: ['Jadwal', 'Schedule'], at_result: ['Hasil', 'Result'],
    at_session: ['Sesi', 'Session'], at_group: ['Grup', 'Group'], at_order: ['Urutan', 'Order'],
    at_rank: ['Peringkat {r}', 'Place {r}'], at_score: ['Nilai {s}', 'Score {s}'],
    at_pri: ['Priangan: peringkat {r}', 'Priangan: place {r}'],
    at_team_only: ['Khusus beregu', 'Team only'], at_dns: ['Tidak tampil', 'Did not start'],
    at_pending: ['Jadwal kategori ini belum diumumkan.', 'The schedule for this category has not been announced.'],
    at_exh: ['Eksibisi', 'Exhibition'], at_app_medals: ['Medali alat', 'Apparatus medals'],
    at_team_result: ['Hasil tim', 'Team result'], at_trophy: ['Piala', 'Trophy'],
    at_err: ['Data tidak bisa dimuat. Coba lagi.', 'Could not load the data. Please try again.'],
  });
  const DISC = { MAG: ['Artistik Putra', "Men's Artistic"], WAG: ['Artistik Putri', "Women's Artistic"], RG: ['Ritmik', 'Rhythmic'], AER: ['Aerobik', 'Aerobic'] };
  const disc = (k) => (DISC[k] ? DISC[k][JO.lang === 'en' ? 1 : 0] : k);
  const gen = (g) => t(g === 'M' ? 'at_m' : g === 'F' ? 'at_f' : 'at_x');
  const PAGE = 24;
  const app = document.getElementById('app');
  const F = { q: '', discipline: '', region: '', club: '', gender: '' };
  let items = [], total = 0, nA = 0, nT = 0, filters = { regions: [], clubs: [] }, busy = false, reqId = 0;

  const initials = (n) => n.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const icTeam = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="8" cy="8" r="3"/><circle cx="16.5" cy="8.5" r="2.5"/><path d="M2.5 19c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5M14 14.3c.8-.4 1.6-.6 2.5-.6 2.3 0 4.2 1.6 4.8 4.3"/></svg>';
  const icPin = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M8 14.5s4.5-4.2 4.5-7.7A4.5 4.5 0 0 0 3.5 6.8c0 3.5 4.5 7.7 4.5 7.7z"/><circle cx="8" cy="6.8" r="1.6"/></svg>';
  const icChev = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 3.5L10.5 8 6 12.5"/></svg>';

  function card(x) {
    const cats = JO.lang === 'en' ? x.cats_en : x.cats_id;
    const av = x.kind === 'team' ? `<span class="av av-team">${icTeam}</span>`
      : x.photo ? `<img class="av" src="${esc(x.photo)}" alt="" loading="lazy" width="72" height="72">` : `<span class="av av-ini" aria-hidden="true">${esc(initials(x.name))}</span>`;
    const members = x.kind === 'team' && x.members && x.members.length
      ? `<p class="ac-mem"><span class="sr-only">${esc(t('at_members'))}: </span>${esc(x.members.slice(0, 3).join(', '))}${x.members.length > 3 ? ` +${x.members.length - 3}` : ''}</p>` : '';
    const inner = `${av}<div class="ac-body">
        ${x.kind === 'team' ? `<span class="pill gold ac-tag">${esc(t('at_team'))}</span>` : ''}
        <h2 class="ac-name">${esc(x.name)}</h2>
        <p class="ac-club">${esc(x.club)}</p>
        <p class="ac-meta">${icPin}<span>${esc(x.region)}</span></p>
        <p class="ac-meta ac-disc"><span>${esc(disc(x.discipline))}</span><span class="dot" aria-hidden="true"></span><span>${esc(gen(x.gender))}</span></p>
        ${members}
        <p class="ac-cats">${(cats || []).map((c) => `<span>${esc(c)}</span>`).join('')}</p>
      </div>`;
    return x.has_detail
      ? `<li><button type="button" class="acard is-link" data-kind="${x.kind}" data-id="${esc(x.id)}" aria-haspopup="dialog">${inner}<span class="ac-go"><span>${esc(t('at_view'))}</span>${icChev}</span></button></li>`
      : `<li><div class="acard">${inner}</div></li>`;
  }

  function opts(list, cur, allKey) {
    return `<option value="">${esc(t(allKey))}</option>` + list.map((o) => `<option value="${esc(o.v)}" ${o.v === cur ? 'selected' : ''}>${esc(o.l)}</option>`).join('');
  }
  function clubList() {
    return filters.clubs.filter((c) => !F.region || c.region === F.region).map((c) => ({ v: c.name, l: c.name }));
  }
  function countLine() {
    if (!total) return '';
    return esc(nT ? t('at_count', { a: nA, t: nT }) : t('at_count_a', { a: nA }));
  }
  function listHtml() {
    if (!items.length) return `<p class="empty">${esc(t('at_none'))}</p>`;
    return `<ul class="agrid">${items.map(card).join('')}</ul>
      ${items.length < total ? `<div class="amore"><p class="tiny muted">${esc(t('at_shown', { n: items.length, t: total }))}</p><button type="button" class="btn btn-ghost" id="more">${esc(t('at_more'))}</button></div>` : ''}`;
  }
  function drawList() {
    app.querySelector('#acount').innerHTML = countLine();
    const box = app.querySelector('#alist');
    box.innerHTML = listHtml();
    box.querySelectorAll('[data-kind]').forEach((b) => b.onclick = () => openDetail(b.dataset.kind, b.dataset.id, b));
    const m = box.querySelector('#more');
    if (m) m.onclick = () => load(true);
  }

  function render() {
    const any = F.q || F.discipline || F.region || F.club || F.gender;
    app.innerHTML = `<div class="page-head"><h1>${esc(t('at_title'))}</h1><p>${esc(t('at_lead'))}</p></div>
      <section class="afilter" aria-label="${esc(t('at_q'))}">
        <div class="aq"><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="9" cy="9" r="6"/><path d="M14 14l4 4"/></svg>
          <label class="sr-only" for="aq">${esc(t('at_q'))}</label><input id="aq" type="search" placeholder="${esc(t('at_q'))}" value="${esc(F.q)}" autocomplete="off"></div>
        <div class="asel">
          <select id="fd" aria-label="${esc(t('at_all_disc'))}">${opts(Object.keys(DISC).map((k) => ({ v: k, l: disc(k) })), F.discipline, 'at_all_disc')}</select>
          <select id="fr" aria-label="${esc(t('at_all_region'))}">${opts(filters.regions.map((r) => ({ v: r, l: r })), F.region, 'at_all_region')}</select>
          <select id="fc" aria-label="${esc(t('at_all_club'))}">${opts(clubList(), F.club, 'at_all_club')}</select>
          <select id="fg" aria-label="${esc(t('at_all_gender'))}">${opts([{ v: 'M', l: t('at_m') }, { v: 'F', l: t('at_f') }], F.gender, 'at_all_gender')}</select>
        </div>
      </section>
      <div class="acount"><p id="acount" class="small muted"></p>${any ? `<button type="button" class="btn-link small" id="reset">${esc(t('at_reset'))}</button>` : ''}</div>
      <div id="alist"></div>`;
    let timer;
    app.querySelector('#aq').oninput = (e) => { clearTimeout(timer); timer = setTimeout(() => { F.q = e.target.value.trim(); load(false); }, 280); };
    const sel = (id, k) => { app.querySelector(id).onchange = (e) => { F[k] = e.target.value; if (k === 'region') F.club = ''; load(false, true); }; };
    sel('#fd', 'discipline'); sel('#fr', 'region'); sel('#fc', 'club'); sel('#fg', 'gender');
    const r = app.querySelector('#reset');
    if (r) r.onclick = () => { Object.keys(F).forEach((k) => { F[k] = ''; }); load(false, true); };
    drawList();
  }

  async function load(append, rerender) {
    if (busy && append) return;
    const my = ++reqId; busy = true;
    const m = app.querySelector('#more'); if (m) m.classList.add('loading');
    try {
      const r = await rpc('public_athletes', { p: { ...F, offset: append ? items.length : 0, limit: PAGE } });
      if (my !== reqId) return;
      if (!r.open) { closed(); return; }
      items = append ? items.concat(r.items) : r.items;
      total = r.total; nA = r.athletes; nT = r.teams;
      if (rerender) render(); else drawList();
    } catch (e) {
      if (my === reqId) JO.toast(t('at_err'), 'bad');
    } finally { if (my === reqId) busy = false; }
  }

  // ---------- rincian: jadwal & hasil ----------
  function schedLine(s) {
    if (!s) return '';
    const parts = [s.session, s.day ? JO.fmtDate(s.day, { weekday: 'long', day: 'numeric', month: 'long' }) : '', s.start_time ? s.start_time.slice(0, 5).replace(':', '.') : ''].filter(Boolean);
    const pos = [s.group_no ? `${t('at_group')} ${s.group_no}` : '', s.start_order ? `${t('at_order')} ${s.start_order}` : ''].filter(Boolean);
    return `<div class="dl-row"><span class="dl-k">${esc(t('at_sched'))}</span><span>${esc(parts.join(' · ') || '–')}${pos.length ? `<br><span class="small muted">${esc(pos.join(' · '))}</span>` : ''}</span></div>`;
  }
  function resultLine(r) {
    if (!r || (r.rank == null && r.total == null)) return '';
    const bits = [];
    if (r.rank != null) bits.push(t('at_rank', { r: r.rank }));
    if (r.total != null) bits.push(t('at_score', { s: Number(r.total).toFixed(3) }));
    const medal = r.medal ? ` <span class="medal ${r.medal}"></span> ${esc(t('medal_' + r.medal))}` : '';
    const app = r.app_medals && Object.keys(r.app_medals).length
      ? `<br><span class="small muted">${esc(t('at_app_medals'))}: ${Object.entries(r.app_medals).map(([k, v]) => `${esc(k)} <span class="medal ${v}" title="${esc(t('medal_' + v))}"></span>`).join(' &nbsp;')}</span>` : '';
    const pri = r.priangan_rank ? `<br><span class="small muted">${esc(t('at_pri', { r: r.priangan_rank }))}${r.priangan_medal ? ` <span class="medal ${r.priangan_medal}"></span>` : ''}</span>` : '';
    return `<div class="dl-row"><span class="dl-k">${esc(t('at_result'))}</span><span><strong>${esc(bits.join(' · '))}</strong>${medal}${r.exhibition ? ` <span class="pill">${esc(t('at_exh'))}</span>` : ''}${app}${pri}</span></div>`;
  }
  function entryBlock(e, title) {
    const name = JO.lang === 'en' ? e.name_en : e.name_id;
    const tags = [e.team_only ? `<span class="pill gold">${esc(t('at_team_only'))}</span>` : '', e.dns ? `<span class="pill bad">${esc(t('at_dns'))}</span>` : ''].join('');
    const body = (e.schedule ? schedLine(e.schedule) : `<p class="small muted" style="margin:0">${esc(t('at_pending'))}</p>`) + resultLine(e.result);
    return `<section class="dblock"><h3>${title ? esc(title) + '<br><span class="small muted dsub">' + esc(name) + '</span>' : esc(name)} ${tags}</h3>${body}</section>`;
  }
  function teamResult(r, label) {
    if (!r || (r.rank == null && r.total == null)) return '';
    const bits = [r.rank != null ? t('at_rank', { r: r.rank }) : '', r.total != null ? t('at_score', { s: Number(r.total).toFixed(3) }) : ''].filter(Boolean);
    const med = r.trophy ? ` <span class="medal ${['emas', 'perak', 'perunggu'][r.rank - 1]}"></span> ${esc(t('at_trophy'))}` : '';
    return `<section class="dblock dteam"><h3>${esc(label)}</h3><div class="dl-row"><span class="dl-k">${esc(t('at_result'))}</span><span><strong>${esc(bits.join(' · '))}</strong>${med}</span></div></section>`;
  }

  let dlg;
  async function openDetail(kind, id, btn) {
    const x = items.find((i) => i.id === id && i.kind === kind); if (!x) return;
    if (!dlg) { dlg = document.createElement('dialog'); dlg.className = 'adlg'; document.body.appendChild(dlg); dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); }); }
    const head = `<header class="dh">${x.kind === 'team' ? `<span class="av av-team">${icTeam}</span>` : x.photo ? `<img class="av" src="${esc(x.photo)}" alt="">` : `<span class="av av-ini">${esc(initials(x.name))}</span>`}
      <div><h2>${esc(x.name)}</h2><p class="small muted">${esc(x.club)} · ${esc(x.region)}<br>${esc(disc(x.discipline))} · ${esc(gen(x.gender))}</p></div>
      <button type="button" class="dx" aria-label="${esc(t('at_close'))}"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg></button></header>`;
    dlg.innerHTML = head + '<div class="db"><div class="empty"><span class="spinner"></span></div></div>';
    dlg.querySelector('.dx').onclick = () => dlg.close();
    dlg.onclose = () => { if (btn && document.contains(btn)) btn.focus(); };
    if (!dlg.open) dlg.showModal();
    const box = dlg.querySelector('.db');
    try {
      const D = await rpc('public_athlete_detail', { p_kind: kind, p_id: id });
      if (!D.open) { dlg.close(); closed(); return; }
      if (kind === 'team') {
        box.innerHTML = teamResult(D.result, t('at_team_result')) + `<h3 class="dsec">${esc(t('at_members'))}</h3>` + D.members.map((m) => entryBlock(m, m.name)).join('');
      } else {
        box.innerHTML = D.entries.map((e) => entryBlock(e)).join('') + (D.teams || []).map((tm) => teamResult(tm.result, `${t('at_team')}: ${tm.name}`)).join('');
      }
    } catch (e) { box.innerHTML = `<p class="note bad">${esc(e.message || t('at_err'))}</p>`; }
  }

  function closed() {
    app.innerHTML = `<div class="asoon"><img src="assets/img/brand/jabar-open.webp" alt="Jabar Open 2026" width="360" height="246">
      <h1>${esc(t('at_soon_t'))}</h1><p>${esc(t('at_soon_d'))}</p><a class="btn btn-ghost" href="index.html">${esc(t('nav_home'))}</a></div>`;
  }

  async function init() {
    JO.header('atlet.html'); JO.footer(); JO.applyI18n();
    try {
      const [fl, first] = await Promise.all([rpc('public_athletes_filters'), rpc('public_athletes', { p: { offset: 0, limit: PAGE } })]);
      if (!fl.open || !first.open) { closed(); JO.onLang(closed); return; }
      filters = { regions: fl.regions || [], clubs: fl.clubs || [] };
      items = first.items; total = first.total; nA = first.athletes; nT = first.teams;
    } catch (e) {
      // fungsi belum dipasang di database atau jaringan putus: tampilkan "segera" saja
      closed(); JO.onLang(closed); return;
    }
    render();
    JO.onLang(render);
  }
  init();
})();
