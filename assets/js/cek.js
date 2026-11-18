/* Jabar Open 2026 — cek kelayakan kategori (publik)
   Hasil dihitung server dengan aturan yang sama seperti saat mendaftar (Konsol → Aturan pendaftaran). */
(function () {
  'use strict';
  const { t, esc, fmtRp, rpc } = JO;
  JO.addDict({
    ck_title: ['Cek kategori', 'Category check'],
    ck_lead: ['Lihat kategori yang bisa diikuti atlet sebelum mendaftar. Isi tanggal lahir dan jenis kelamin sesuai identitas; tidak ada data yang disimpan.',
      "See which categories an athlete can enter before registering. Enter the date of birth and sex as on the ID; nothing is saved."],
    ck_birth: ['Tanggal lahir', 'Date of birth'], ck_sex: ['Jenis kelamin', 'Sex'], ck_m: ['Laki-laki', 'Male'], ck_f: ['Perempuan', 'Female'],
    ck_nat: ['Kewarganegaraan', 'Nationality'], ck_wni: ['WNI', 'Indonesian (WNI)'], ck_wna: ['WNA', 'Foreign (WNA)'],
    ck_prov: ['Provinsi (alamat identitas)', 'Province (ID address)'], ck_club: ['Klub', 'Club'],
    ck_club_none: ['Belum dipilih', 'Not chosen'], ck_club_other: ['Klub lain / belum terdaftar', 'Other / not listed'],
    ck_club_prov: ['Provinsi klub', 'Club province'], ck_choose: ['Pilih…', 'Choose…'],
    ck_fill: ['Isi tanggal lahir dan jenis kelamin untuk melihat kategori.', 'Enter the date of birth and sex to see categories.'],
    ck_age: ['Usia {y}: {a} tahun', 'Age in {y}: {a}'],
    ck_minor: ['Di bawah {g} tahun: data orang tua/wali wajib saat mendaftar', 'Under {g}: parent/guardian details are required'],
    ck_closed: ['Pendaftaran sedang ditutup', 'Registration is closed'], ck_dclosed: ['Pendaftaran disiplin ini ditutup', 'Registration for this discipline is closed'],
    ck_ok: ['Bisa', 'Eligible'], ck_no: ['Tidak bisa', 'Not eligible'], ck_none: ['Tidak ada kategori yang bisa diikuti di disiplin ini.', 'No category in this discipline fits.'],
    ck_off: ['{n} kategori tidak bisa diikuti (lihat alasannya)', '{n} categories do not fit (see why)'],
    ck_cat: ['Kategori', 'Category'], ck_agecol: ['Usia', 'Age'], ck_fee: ['Biaya', 'Fee'], ck_status: ['Status', 'Status'],
    ck_quota: ['Sisa kuota klub: {n}', 'Club quota left: {n}'], ck_pair: ['Pasangan', 'Pair'], ck_region: ['Khusus daerah', 'Regional'],
    ck_register: ['Daftar sekarang', 'Register now'],
    ck_wrong: ['Data atlet benar tetapi kategorinya terkunci? Jangan ubah tanggal lahir. Hubungi panitia di {e} agar aturan kategorinya ditinjau.',
      'Details are correct but the category is locked? Do not change the date of birth. Contact the committee at {e} so the category rule can be reviewed.'],
  });
  const app = document.getElementById('app');
  let CFG = null;
  const F = { b: '', g: '', n: 'WNI', p: '', k: '', kp: '' };
  const Y = () => (CFG && CFG.event.year) || 2026;
  function ageRange(c) {
    const lo = c.birth_year_max != null ? Y() - c.birth_year_max : null, hi = c.birth_year_min != null ? Y() - c.birth_year_min : null;
    const en = JO.lang === 'en';
    if (lo != null && hi != null) return lo === hi ? (en ? `${lo}` : `${lo} tahun`) : (en ? `${lo}–${hi}` : `${lo}–${hi} tahun`);
    if (hi != null) return en ? `${hi} & under` : `${hi} tahun ke bawah`;
    if (lo != null) return en ? `${lo} & over` : `${lo} tahun ke atas`;
    return en ? 'Open age' : 'Usia terbuka';
  }
  function form() {
    const R = window.JO_REGIONS;
    const clubs = (CFG.clubs || []).slice().sort((a, b) => a.name.localeCompare(b.name));
    app.innerHTML = `<div class="page-head"><h1>${esc(t('ck_title'))}</h1><p>${esc(t('ck_lead'))}</p></div>
      <div class="card"><div class="grid-2">
        <div class="field"><label class="f" for="ck_b">${esc(t('ck_birth'))}</label><input id="ck_b" type="date" value="${esc(F.b)}" max="${new Date().toISOString().slice(0, 10)}"></div>
        <div class="field"><span class="f">${esc(t('ck_sex'))}</span><div class="seg" role="radiogroup">
          <label><input type="radio" name="ck_g" value="M" ${F.g === 'M' ? 'checked' : ''}>${esc(t('ck_m'))}</label>
          <label><input type="radio" name="ck_g" value="F" ${F.g === 'F' ? 'checked' : ''}>${esc(t('ck_f'))}</label></div></div>
        <div class="field"><label class="f" for="ck_n">${esc(t('ck_nat'))}</label><select id="ck_n"><option value="WNI">${esc(t('ck_wni'))}</option><option value="WNA" ${F.n === 'WNA' ? 'selected' : ''}>${esc(t('ck_wna'))}</option></select></div>
        <div class="field" ${F.n === 'WNA' ? 'hidden' : ''} id="ck_pw"><label class="f" for="ck_p">${esc(t('ck_prov'))}</label><select id="ck_p"><option value="">${esc(t('ck_choose'))}</option>
          ${R.provinces.map((p) => `<option ${p === F.p ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
        <div class="field"><label class="f" for="ck_k">${esc(t('ck_club'))}</label><select id="ck_k"><option value="">${esc(t('ck_club_none'))}</option>
          ${clubs.map((k) => `<option value="${k.id}" ${k.id === F.k ? 'selected' : ''}>${esc(k.name)}${k.kab_kota ? ' · ' + esc(k.kab_kota) : ''}</option>`).join('')}
          <option value="_other" ${F.k === '_other' ? 'selected' : ''}>${esc(t('ck_club_other'))}</option></select></div>
        <div class="field" id="ck_kpw" ${F.k === '_other' ? '' : 'hidden'}><label class="f" for="ck_kp">${esc(t('ck_club_prov'))}</label><select id="ck_kp"><option value="">${esc(t('ck_choose'))}</option>
          ${R.provinces.map((p) => `<option ${p === F.kp ? 'selected' : ''}>${esc(p)}</option>`).join('')}</select></div>
      </div></div>
      <div id="ck_out" style="margin-top:18px" aria-live="polite"></div>`;
    const q = (s) => app.querySelector(s);
    const read = () => {
      F.b = q('#ck_b').value; const g = app.querySelector('input[name=ck_g]:checked'); F.g = g ? g.value : '';
      F.n = q('#ck_n').value; F.p = q('#ck_p').value; F.k = q('#ck_k').value; F.kp = q('#ck_kp').value;
      q('#ck_pw').hidden = F.n === 'WNA'; q('#ck_kpw').hidden = F.k !== '_other';
      run();
    };
    app.querySelectorAll('input,select').forEach((el) => el.addEventListener('change', read));
    run();
  }
  let seqNo = 0;
  async function run() {
    const out = app.querySelector('#ck_out');
    if (!F.b || !F.g) { out.innerHTML = `<p class="note info">${esc(t('ck_fill'))}</p>`; return; }
    const my = ++seqNo;
    out.innerHTML = '<div class="empty"><span class="spinner"></span></div>';
    const p = { birth_date: F.b, gender: F.g, nationality: F.n, province: F.n === 'WNA' ? '' : F.p };
    if (F.k === '_other') p.club_province = F.kp; else if (F.k) p.club_id = F.k;
    let x;
    try { x = await rpc('public_check_eligibility', { p }); }
    catch (e) { if (my === seqNo) out.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; return; }
    if (my !== seqNo) return;
    const en = JO.lang === 'en';
    const nm = (c) => (en ? c.name_en : c.name_id);
    const row = (c) => `<tr><td><b>${esc(nm(c))}</b>${c.entry_type === 'pair' ? ` <span class="pill">${esc(t('ck_pair'))}</span>` : ''}${c.jabar_only ? ` <span class="pill gold">${esc(t('ck_region'))}</span>` : ''}${c.note ? `<br><span class="small muted">${esc(c.note)}</span>` : ''}</td>
      <td class="small">${esc(ageRange(c))}</td><td class="r num">${fmtRp(c.fee)}</td>
      <td class="small">${c.reason ? `<span class="pill bad">${esc(t('ck_no'))}</span><br>${esc(c.reason)}` : `<span class="pill ok">${esc(t('ck_ok'))}</span>${c.quota_left != null ? `<br><span class="small muted">${esc(t('ck_quota', { n: c.quota_left }))}</span>` : ''}`}</td></tr>`;
    const tbl = (list) => `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>${esc(t('ck_cat'))}</th><th>${esc(t('ck_agecol'))}</th><th class="r">${esc(t('ck_fee'))}</th><th>${esc(t('ck_status'))}</th></tr></thead><tbody>${list.map(row).join('')}</tbody></table></div>`;
    out.innerHTML = `<p class="row" style="gap:8px;flex-wrap:wrap"><span class="pill dark">${esc(t('ck_age', { y: x.year, a: x.age }))}</span>
        ${x.minor ? `<span class="pill warn">${esc(t('ck_minor', { g: x.guardian_age }))}</span>` : ''}${x.registration_open ? '' : `<span class="pill bad">${esc(t('ck_closed'))}</span>`}</p>
      ${x.disciplines.map((d) => {
        const ok = d.categories.filter((c) => !c.reason), off = d.categories.filter((c) => c.reason);
        return `<section class="card" style="margin-top:14px"><h2 style="margin:0 0 10px;font-size:1.1rem">${esc(en ? d.name_en : d.name_id)}
            ${d.open ? '' : ` <span class="pill bad">${esc(t('ck_dclosed'))}</span>`}</h2>
          ${ok.length ? tbl(ok) : `<p class="small muted" style="margin:0">${esc(t('ck_none'))}</p>`}
          ${off.length ? `<details style="margin-top:10px"><summary class="small">${esc(t('ck_off', { n: off.length }))}</summary>${tbl(off)}</details>` : ''}
          ${ok.length && d.open && x.registration_open ? `<p style="margin:12px 0 0"><a class="btn btn-primary btn-sm" href="daftar.html?disiplin=${d.code}">${esc(t('ck_register'))}</a></p>` : ''}</section>`;
      }).join('')}
      <p class="small muted" style="margin-top:16px">${esc(t('ck_wrong', { e: (CFG.event && CFG.event.contact_email) || 'jabaropen2026@gmail.com' }))}</p>`;
  }
  async function init() {
    JO.header('daftar.html'); JO.footer(); JO.applyI18n();
    try { CFG = await rpc('public_config'); }
    catch (e) { app.innerHTML = `<p class="note bad">${esc(e.message)}</p>`; return; }
    const r = CFG.registration.rules || {};
    JO.setRuleVars({ ga: r.guardian_age == null ? 18 : r.guardian_age });
    ['b', 'g', 'n', 'p'].forEach((k) => { const v = JO.qs(k); if (v) F[k] = v; });
    form();
    JO.onLang(() => form());
  }
  init();
})();
