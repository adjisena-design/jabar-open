/* Jabar Open 2026 — start list publik */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    sl_title: ['Start list', 'Start list'],
    sl_lead: ['Sesi, grup, dan urutan tampil resmi. Tidak ada registrasi ulang: datang sesuai jadwal sesi Anda di Gymnasium Arcamanik, Bandung.', 'Official sessions, groups and start order. There is no on-site check-in: come for your session at Gymnasium Arcamanik, Bandung.'],
    sl_empty: ['Start list disiplin ini belum diumumkan. Pantau Instagram @gimnastikjabar.', 'The start list for this discipline has not been announced yet. Follow Instagram @gimnastikjabar.'],
    sl_search: ['Cari nama atlet atau klub', 'Search athlete or club'],
    sl_session: ['Sesi', 'Session'], sl_group: ['Grup', 'Group'], sl_order: ['Urutan', 'Order'], sl_name: ['Nama', 'Name'], sl_club: ['Klub', 'Club'],
    sl_noresult: ['Tidak ada yang cocok.', 'No matches.'],
    sl_team_only: ['beregu', 'team'], sl_team_only_t: ['Khusus beregu: dinilai untuk tim, tidak diperingkat perorangan', 'Team only: scored for the team, not ranked individually'],
  });
  const app = document.getElementById('app');
  const discs = ['MAG', 'WAG', 'RG', 'AER'];
  let tab = /^#(MAG|WAG|RG|AER)$/.test(location.hash) ? location.hash.slice(1) : 'MAG';
  let data = {}, q = '';
  const sess = (e) => [e.session, e.day ? JO.fmtDate(e.day, { weekday: 'short', day: 'numeric', month: 'short' }) : '', e.start_time ? e.start_time.slice(0, 5) : ''].filter(Boolean).join(', ');

  function body() {
    const cats = data[tab] || [];
    if (!cats.length) return `<p class="empty">${esc(t('sl_empty'))}</p>`;
    const s = q.toLowerCase();
    let shown = 0;
    const html = cats.map((c) => {
      const rows = c.entries.filter((e) => !s || (e.athletes.map((a) => a.name).join(' ') + ' ' + e.club).toLowerCase().includes(s));
      if (!rows.length) return '';
      shown += rows.length;
      return `<section class="card" style="margin-bottom:16px"><h2>${esc(JO.lang === 'en' ? c.name_en : c.name_id)}</h2>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>${esc(t('sl_session'))}</th><th class="c">${esc(t('sl_group'))}</th><th class="c">${esc(t('sl_order'))}</th><th>${esc(t('sl_name'))}</th><th>${esc(t('sl_club'))}</th></tr></thead><tbody>
        ${rows.map((e) => `<tr><td class="small">${esc(sess(e))}</td><td class="c num">${e.group_no || '–'}</td><td class="c num"><strong>${e.start_order || '–'}</strong></td>
          <td>${e.athletes.map((a) => `${esc(a.name)} <span class="tiny muted">${esc(a.athlete_no || '')}</span>`).join('<br>')}${e.team_only ? ` <span class="pill gold" title="${esc(t('sl_team_only_t'))}">${esc(t('sl_team_only'))}</span>` : ''}</td>
          <td>${esc(e.club)}<br><span class="tiny muted">${esc(e.region || '')}</span></td></tr>`).join('')}
        </tbody></table></div></section>`;
    }).join('');
    return shown ? html : `<p class="empty">${esc(t('sl_noresult'))}</p>`;
  }
  function render() {
    app.innerHTML = `<div class="page-head"><h1>${esc(t('sl_title'))}</h1><p>${esc(t('sl_lead'))}</p></div>
      <div class="tabs" role="tablist">${discs.map((k) => `<button role="tab" aria-selected="${tab === k}" data-tab="${k}">${esc(JO.DISC_NAME[k])}</button>`).join('')}</div>
      <div class="field" style="max-width:420px"><label class="sr-only" for="q">${esc(t('sl_search'))}</label><input id="q" type="search" placeholder="${esc(t('sl_search'))}" value="${esc(q)}"></div>
      <div id="list">${body()}</div>`;
    app.querySelectorAll('[data-tab]').forEach((b) => b.onclick = () => { tab = b.dataset.tab; history.replaceState(null, '', '#' + tab); render(); });
    app.querySelector('#q').oninput = (e) => { q = e.target.value; app.querySelector('#list').innerHTML = body(); };
  }
  async function init() {
    JO.header('startlist.html'); JO.footer(); JO.applyI18n();
    try {
      const all = await rpc('public_startlist', { p_discipline: null });
      for (const d of discs) data[d] = [];
      all.forEach((c) => (data[c.discipline] || (data[c.discipline] = [])).push(c));
    } catch (e) { app.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; return; }
    render();
    JO.onLang(render);
  }
  init();
})();
