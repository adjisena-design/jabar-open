/* Jabar Open 2026 — hasil & perolehan medali (publik) */
(function () {
  'use strict';
  const { t, esc, rpc } = JO;
  JO.addDict({
    h_title: ['Hasil & perolehan medali', 'Results & medal table'],
    h_lead: ['Hasil resmi dipublikasikan setelah upacara penyerahan penghargaan (UPP) setiap disiplin.', 'Official results are published after each discipline\'s award ceremony.'],
    h_medals: ['Perolehan medali', 'Medal table'], h_general: ['Jabar Open', 'Jabar Open'], h_priangan: ['Priangan', 'Priangan'],
    h_by_region: ['Per kabupaten / kota', 'By regency / city'], h_by_club: ['Per klub', 'By club'],
    h_name: ['Nama', 'Name'], h_club: ['Klub', 'Club'], h_total: ['Total', 'Total'],
    h_gold: ['Emas', 'Gold'], h_silver: ['Perak', 'Silver'], h_bronze: ['Perunggu', 'Bronze'],
    h_empty: ['Belum ada hasil yang dipublikasikan untuk disiplin ini.', 'No results published for this discipline yet.'],
    h_empty_medal: ['Tabel medali terisi setelah hasil pertama dipublikasikan.', 'The medal table fills in once the first results are published.'],
    h_pri_note: ['Atlet Jawa Barat yang mengikuti kategori Priangan diperingkat ulang dari hasil yang sama.', 'West Java athletes in the Priangan category are re-ranked from the same results.'],
    h_exhibition: ['Eksibisi: medali tidak dihitung dalam perolehan.', 'Exhibition: medals do not count toward the table.'],
    h_rank: ['Per.', 'Rank'], h_pri_rank: ['Priangan', 'Priangan'],
    h_published: ['Dipublikasikan {d}', 'Published {d}'],
  });
  const app = document.getElementById('app');
  let R = [], M = { general: null, priangan: null }, tab = 'medals', pri = false;

  function medalTable(rows, labelKey) {
    if (!rows.length) return `<p class="empty">${esc(t('h_empty_medal'))}</p>`;
    return `<div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">#</th><th>${esc(t(labelKey))}</th>
      <th class="c"><span class="medal emas"></span> <span class="sr-only">${esc(t('h_gold'))}</span></th>
      <th class="c"><span class="medal perak"></span> <span class="sr-only">${esc(t('h_silver'))}</span></th>
      <th class="c"><span class="medal perunggu"></span> <span class="sr-only">${esc(t('h_bronze'))}</span></th>
      <th class="c">${esc(t('h_total'))}</th></tr></thead><tbody>
      ${rows.map((r, i) => `<tr><td class="c rank">${i + 1}</td><td>${esc(r.label)}${r.region && labelKey === 'h_club' ? `<br><span class="tiny muted">${esc(r.region)}</span>` : ''}</td>
        <td class="c num">${r.emas}</td><td class="c num">${r.perak}</td><td class="c num">${r.perunggu}</td><td class="c num"><strong>${r.total}</strong></td></tr>`).join('')}
      </tbody></table></div>`;
  }
  function renderMedals(box) {
    const m = pri ? M.priangan : M.general;
    box.innerHTML = `<div class="row" style="margin-bottom:16px"><div class="seg" role="radiogroup">
        <label><input type="radio" name="mt" value="0" ${!pri ? 'checked' : ''}>${esc(t('h_general'))}</label>
        <label><input type="radio" name="mt" value="1" ${pri ? 'checked' : ''}>${esc(t('h_priangan'))}</label></div>
        ${pri ? `<span class="small muted">${esc(t('h_pri_note'))}</span>` : ''}</div>
      <div class="grid-2" style="align-items:start">
        <div><h2>${esc(t('h_by_region'))}</h2>${medalTable(m.by_region, 'h_name')}</div>
        <div><h2>${esc(t('h_by_club'))}</h2>${medalTable(m.by_club, 'h_club')}</div>
      </div>`;
    box.querySelectorAll('input[name=mt]').forEach((r) => r.onchange = () => { pri = r.value === '1'; renderMedals(box); });
  }
  function renderDisc(box, code) {
    const cats = R.filter((c) => c.discipline === code);
    if (!cats.length) { box.innerHTML = `<p class="empty">${esc(t('h_empty'))}</p>`; return; }
    const disc = (window.JO_DISC || {})[code] || {};
    box.innerHTML = cats.map((c) => {
      const apps = c.apparatus || [];
      const anyPri = c.results.some((r) => r.priangan);
      const appName = (x) => { const d = (disc.apparatus || []).find((y) => y.code === x); return d ? (JO.lang === 'en' ? d.en : d.id) : x; };
      return `<section class="card" style="margin-bottom:16px"><h2>${esc(JO.lang === 'en' ? c.name_en : c.name_id)}</h2>
        <p class="tiny muted">${esc(t('h_published', { d: JO.fmtDateTime(c.published_at) }))}${c.exhibition ? '. ' + esc(t('h_exhibition')) : ''}</p>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th class="c">${esc(t('h_rank'))}</th><th>${esc(t('h_name'))}</th><th>${esc(t('h_club'))}</th>
          ${apps.length > 1 ? apps.map((a) => `<th class="r" title="${esc(appName(a))}">${esc(a)}</th>`).join('') : ''}
          <th class="r">${esc(t('h_total'))}</th>${anyPri ? `<th class="c">${esc(t('h_pri_rank'))}</th>` : ''}</tr></thead><tbody>
          ${c.results.map((r) => `<tr><td class="c"><span class="rank">${r.rank || '–'}</span>${r.medal ? ` <span class="medal ${r.medal}" title="${esc(t('medal_' + r.medal))}"></span>` : ''}</td>
            <td>${r.athletes.map((a) => `${esc(a.name)} <span class="tiny muted">${esc(a.athlete_no || '')}</span>`).join('<br>')}</td>
            <td>${esc(r.club)}<br><span class="tiny muted">${esc(r.region || '')}</span></td>
            ${apps.length > 1 ? apps.map((a) => `<td class="r num">${r.scores && r.scores[a] != null ? Number(r.scores[a]).toFixed(3) : '–'}</td>`).join('') : ''}
            <td class="r num"><strong>${r.total != null ? Number(r.total).toFixed(3) : '–'}</strong></td>
            ${anyPri ? `<td class="c">${r.priangan_rank ? `<span class="num">${r.priangan_rank}</span>${r.priangan_medal ? ` <span class="medal ${r.priangan_medal}"></span>` : ''}` : ''}</td>` : ''}</tr>`).join('')}
        </tbody></table></div></section>`;
    }).join('');
  }
  function render() {
    const tabs = [['medals', t('h_medals')], ['MAG', JO.DISC_NAME.MAG], ['WAG', JO.DISC_NAME.WAG], ['RG', JO.DISC_NAME.RG], ['AER', JO.DISC_NAME.AER]];
    app.innerHTML = `<div class="page-head"><h1>${esc(t('h_title'))}</h1><p>${esc(t('h_lead'))}</p></div>
      <div class="tabs" role="tablist">${tabs.map(([k, l]) => `<button role="tab" aria-selected="${tab === k}" data-tab="${k}">${esc(l)}</button>`).join('')}</div>
      <div id="tabbox"></div>`;
    app.querySelectorAll('[data-tab]').forEach((b) => b.onclick = () => { tab = b.dataset.tab; history.replaceState(null, '', '#' + tab); render(); });
    const box = app.querySelector('#tabbox');
    if (tab === 'medals') renderMedals(box); else renderDisc(box, tab);
  }
  async function init() {
    JO.header('hasil.html'); JO.footer(); JO.applyI18n();
    if (/^#(MAG|WAG|RG|AER|medals)$/.test(location.hash)) tab = location.hash.slice(1);
    try {
      const [res, mg, mp, cfg] = await Promise.all([rpc('public_results', { p_discipline: null }), rpc('public_medal_table', { p_priangan: false }), rpc('public_medal_table', { p_priangan: true }), rpc('public_config')]);
      R = res; M.general = mg; M.priangan = mp;
      window.JO_DISC = Object.fromEntries(cfg.disciplines.map((d) => [d.code, d]));
    } catch (e) { app.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; return; }
    render();
    JO.onLang(render);
  }
  init();
})();
