/* Jabar Open 2026 — beranda: bahasa, navigasi, animasi muncul, hitung mundur, angka langsung, galeri */
(function () {
  'use strict';
  const EN = {
    n_about: 'About', n_sched: 'Schedule', n_fee: 'Fees', n_startlist: 'Start list', n_results: 'Results', n_merch: 'Merch',
    n_contact: 'Contact', n_status: 'Check status', n_register: 'Register', n_verify: 'Verify a certificate',
    h_kick1: 'Open gymnastics championship', h_kick2: '12–20 December 2026 · Bandung',
    h_t1: 'One arena.', h_t2: 'Four disciplines.', h_t3: 'Hundreds of dreams.',
    cta_reg: 'Register now', cta_fee: 'Fees & how to register', cta_ticket: 'Spectator tickets', soon: 'soon',
    h_medals_alt: 'Jabar Open 2026 silver, gold and bronze medals with the official lanyard', h_ath_alt: "Men's and women's artistic gymnasts",
    s_ath: 'Athletes registered', s_live: 'live', s_club: 'Clubs and schools', s_disc: 'Disciplines', s_days: 'Days until 12 December',
    swipe: 'Swipe to see all',
    c_eyebrow: 'Why we compete',
    c_title: 'We compete to grow, <em>not only to win.</em>',
    c_lead: 'Competition is an honest mirror. Months of training are tested in a single routine, judged by the same rules for everyone, and carried into the next step.',
    c1_t: 'Fair play', c1_d: 'Every athlete performs in the same arena, schedule and judging, guided by the FIG Code of Points. Respecting opponents, judges and results is part of the competition.',
    c2_t: 'Progress', c2_d: 'Medals for the top three, scores for everyone. Each score shows what has been mastered and what needs more training. Time on the floor is part of development.',
    c3_t: 'The mother of <em>all sports</em>', c3_d: 'Strength, flexibility, balance, coordination and body awareness: the movement foundation gymnastics builds carries into almost every other sport.',
    m_tr: 'Say less, show more. To the stars, through hardship.', m_cite: 'Motto of Gimnastik Indonesia West Java',
    i_eyebrow: 'About the championship',
    i_title: 'Open to all, <em>one judging standard.</em>',
    i_r3: 'Dates', i_r3v: '12–20 December 2026', i_r4: 'Venue', i_r5: 'Participants',
    i_r5v: 'Schools, clubs, regency/city teams, individuals, including from abroad',
    i_r6: 'Registration', i_r6v: 'Online, by 12 November 2026',
    i_r7: 'Rules', i_r7v: 'FIG CoP 2025–2028 · TR 2025 · ALP without bonus',
    i_r8: 'Protests', i_r8v: 'None',
    d1_w: '12–15 Dec', d2_w: '12–15 Dec', d3_w: '16–18 Dec', d4_w: '19–20 Dec',
    d1_n: "Men's Artistic", d2_n: "Women's Artistic", d3_n: 'Rhythmic', d4_n: 'Aerobic',
    l_cat: 'Categories', l_fmt: 'Format', l_app: 'Apparatus', l_quota: 'Quota', l_note: 'Note', l_age: 'Age groups',
    v_aa: 'Individual all-around', v_quota: 'Up to 10 gymnasts per category per club', v_music: 'Music for Levels 4–6 is provided',
    v_rgcat: 'Professional · Amateur', v_fest: 'Age groups use the festival system',
    v_aer1: 'Individual men, individual women, mixed pair', v_aer2: 'Individual men and women', v_final: 'Straight finals',
    ap_fx: 'Floor', ap_ph: 'Pommel horse', ap_sr: 'Rings', ap_vt: 'Vault', ap_pb: 'Parallel bars', ap_hb: 'High bar',
    ap_ub: 'Uneven bars', ap_bb: 'Balance beam', ap_fh: 'Freehand', ap_hoop: 'Hoop', ap_ball: 'Ball', ap_clubs: 'Clubs', ap_rib: 'Ribbon',
    sc_eyebrow: 'Provisional schedule', sc_title: 'Nine days, <em>three stages.</em>',
    sc_lead: "Each athlete's session, group and start order are announced on the start list page after registration closes. There is no on-site check-in.",
    dec26: 'December 2026', sc_art: "Artistic <em>Men's &amp; Women's</em>",
    day_sat12: 'Sat, 12 Dec', day_sun13: 'Sun, 13 Dec', day_mon14: 'Mon, 14 Dec', day_tue15: 'Tue, 15 Dec', day_wed16: 'Wed, 16 Dec', day_thu17: 'Thu, 17 Dec', day_fri18: 'Fri, 18 Dec', day_sat19: 'Sat, 19 Dec', day_sun20: 'Sun, 20 Dec',
    sc_a1: 'Judges meeting, podium training for MAG Level 4, WAG Level 4 and Junior', sc_comp: 'Competition', sc_upp: 'Award ceremony', sc_tba: 'To be announced',
    sc_r1: 'Judges meeting, podium training, competition', sc_e1: 'Orientation meeting (max. 1 coach and/or 1 manager per delegation), judges refresher, official training', sc_e2: 'Competition and award ceremony',
    sc_note: 'The schedule may change. Official announcements on the <a href="startlist.html">start list</a> and Instagram <a href="https://www.instagram.com/gimnastikjabar/" target="_blank" rel="noopener">@gimnastikjabar</a>.',
    f_eyebrow: 'Registration', f_title: 'Fees and <em>how to register.</em>',
    f_lead: 'Register as an individual or as a club or school, up to five athletes at once. Pay once with QRIS. Registration closes 12 November 2026.',
    f_head: 'Fee per athlete',
    f_r1: "Men's Artistic <small>per gymnast</small>", f_r2: "Women's Artistic <small>per gymnast</small>", f_r3: 'Rhythmic individual <small>per gymnast</small>',
    f_r4: 'Aerobic individual <small>IM / IW, per gymnast</small>', f_r5: 'Aerobic mixed pair <small>MP, per pair</small>',
    f_pri_t: 'Priangan category add-on',
    f_pri: 'Optional, per entry. For Indonesian athletes with a West Java address on their ID, from a West Java club: results are re-ranked for the Priangan awards and medal table.',
    f_s1t: 'Fill in the online form', f_s1: 'Choose discipline, club, athletes and categories. Categories follow the date of birth.',
    f_s2t: 'Pay with QRIS', f_s2: 'Type the exact amount, including the three-digit unique code.',
    f_s3t: 'Upload the payment proof', f_s3: 'From the invoice or status page. The committee verifies it.',
    f_s4t: 'Receive e-tickets', f_s4: 'A PDF for every athlete, by email and on the status page.',
    f_ready_t: 'Have this ready', f_ready: "Athlete ID (national ID, birth certificate, school certificate or passport), guardian details for athletes under 18, and BPJS or insurance.",
    at_eyebrow: 'Athlete registration is open', at_t1: 'This is your stage.', at_t2: 'Show who you are.',
    at_lead: 'Write your name on the podium at Gymnasium Arcamanik. Register on your own or with your club, pay once, and receive an e-ticket for every athlete.',
    at_f1b: '12 November', at_f1: 'Registration deadline', at_f2b: '4 disciplines', at_f2: 'MAG, WAG, RG, AER',
    at_f3b: 'From Rp300,000', at_f3: 'Fee per athlete', at_f4b: 'Priangan', at_f4: 'Special ranking for West Java athletes',
    at_alt: 'A female gymnast in a split leap on the beam', photo: 'Photo',
    mem_eyebrow: 'From the arena', mem_title: 'Moments that <em>brought us here.</em>',
    mem_lead: 'Courage on the mat, coaches at the edge of the floor, and the togetherness we want to bring back to Arcamanik.',
    m1a: 'Rhythmic,', m1b: 'clubs', m2a: 'Opening', m2b: 'ceremony', m3a: 'Artistic,', m3b: 'rings', m4b: 'ribbon',
    m5a: 'Coach', m5b: 'and athlete', m6b: 'floor', m7a: 'Team', m7b: 'spirit', m8b: 'pommel horse', m9b: 'freehand',
    m10b: 'uneven bars', m11a: 'Focus', m11b: 'before the routine', m12a: 'Preparation,', m12b: 'wrist guards', m13a: 'Strength,', m13b: 'V-sit on floor',
    sc_alt: 'A female gymnast walking toward the apparatus',
    mc_eyebrow: 'Official merchandise', mc_soon: 'Coming soon', mc_title: 'Limited edition. <em>Worn with pride.</em>',
    mc_lead: 'The official Jabar Open 2026 collection is being prepared: designed from the championship identity, made in limited numbers, for anyone who wants to take home a piece of the story from the arena.',
    mc_p1: 'Produced in limited numbers for the 2026 edition, never reprinted.', mc_p2: 'Collection details, prices and ordering are announced on this site.',
    mc_p3: 'News always lands first on Instagram @gimnastikjabar.', mc_cta: 'Follow the news', mc_badge: 'Collection preview',
    mc_alt: 'Jabar Open 2026 merchandise preview: flag banner, t-shirt and water bottles',
    ig_lead: 'The official account of Gimnastik Indonesia West Java. Announcements, start lists and moments from the arena appear there first.',
    ig_cta: 'Follow on Instagram',
    k_eyebrow: 'Get in touch', k_title: 'Questions? <em>We are here to help.</em>',
    k_lead: 'Registration, payment and athlete data by email. Technical questions per discipline go to each discipline contact on WhatsApp.',
    k_mail_t: 'Registration and payment', k_mail_d: 'Include your registration code (JO26-…) so we can help you faster.', k_mail_cta: 'Send an email',
    cp1: "Men's Artistic", cp2: "Women's Artistic", cp3: 'Rhythmic', cp4: 'Aerobic',
    cl_t1: 'See you at', cl_d: 'Gymnasium Arcamanik, Bandung · 12–20 December 2026',
    ft_org: 'Organised by Gimnastik Indonesia (GI) West Java under KONI West Java.', ft_sec: 'Secretariat', ft_map: 'View on map',
    ft_links: 'Links', ft_contact: 'Contact', ft_credit: 'Built and maintained by Daffa Adjisena, M.B.A.',
  };

  // ---------- bahasa ----------
  const ID = {};
  document.querySelectorAll('[data-i18n]').forEach((el) => { ID[el.dataset.i18n] = el.textContent; });
  document.querySelectorAll('[data-i18n-html]').forEach((el) => { ID[el.dataset.i18nHtml] = el.innerHTML; });
  document.querySelectorAll('[data-i18n-alt]').forEach((el) => { ID[el.dataset.i18nAlt] = el.alt; });
  function setLang(l) {
    const d = l === 'en' ? EN : ID;
    document.querySelectorAll('[data-i18n]').forEach((el) => { const v = d[el.dataset.i18n]; if (v) el.textContent = v; });
    document.querySelectorAll('[data-i18n-html]').forEach((el) => { const v = d[el.dataset.i18nHtml]; if (v) el.innerHTML = v; });
    document.querySelectorAll('[data-i18n-alt]').forEach((el) => { const v = d[el.dataset.i18nAlt]; if (v) el.alt = v; });
    document.querySelectorAll('.lang-sw button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.lang === l)));
    document.documentElement.lang = l;
    try { localStorage.setItem('jo26-lang', l); } catch (e) {}
  }
  document.querySelectorAll('.lang-sw button').forEach((b) => b.addEventListener('click', () => setLang(b.dataset.lang)));
  let saved = 'id'; try { saved = localStorage.getItem('jo26-lang') || 'id'; } catch (e) {}

  // ---------- galeri: gandakan set foto agar bisa bergerak tanpa putus ----------
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const strip = document.querySelector('.mem-strip');
  if (strip && !reduce) {
    const set = strip.querySelector('.mem-set');
    const clone = set.cloneNode(true);
    clone.setAttribute('aria-hidden', 'true');
    clone.querySelectorAll('img').forEach((img) => { img.alt = ''; });
    set.parentNode.appendChild(clone);
    strip.classList.add('go');
    strip.removeAttribute('tabindex');
  }
  if (saved === 'en') setLang('en');
  // galeri tanpa animasi (gerak dikurangi) memakai gulir bawaan: jaga agar tidak pernah bergeser vertikal
  if (strip) strip.addEventListener('scroll', () => { if (strip.scrollTop) strip.scrollTop = 0; }, { passive: true });

  // ---------- baris geser di ponsel ----------
  // Bukan gulir bawaan: .rail memotong, .swipe digeser ke samping dengan translateX.
  // Gerakan vertikal diserahkan ke halaman, jadi baris tidak pernah bisa bergeser naik-turun.
  const railMq = window.matchMedia('(max-width:700px)');
  const rails = [];
  document.querySelectorAll('.rail').forEach((rail) => {
    const track = rail.querySelector('.swipe');
    if (!track || !track.children.length) return;
    const items = Array.from(track.children);
    let x = 0; let pts = [0]; let max = 0; let on = false; let st = null; let justDragged = false; let wheelT = 0;

    const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
    function put(v, animate) {
      x = v;
      track.style.transition = animate ? '' : 'none';
      track.style.transform = v ? 'translate3d(' + (-v).toFixed(1) + 'px,0,0)' : '';
    }
    function nearest(v) {
      let k = 0;
      pts.forEach((p, i) => { if (Math.abs(p - v) < Math.abs(pts[k] - v)) k = i; });
      return k;
    }
    function go(i, animate = true) { put(pts[clamp(i, 0, pts.length - 1)], animate); }
    function measure() {
      const cs = getComputedStyle(track);
      const pl = parseFloat(cs.paddingLeft) || 0; const pr = parseFloat(cs.paddingRight) || 0;
      const last = items[items.length - 1];
      max = Math.max(0, Math.round(last.offsetLeft + last.offsetWidth + pr - track.clientWidth));
      const all = items.map((it) => clamp(Math.round(it.offsetLeft - pl), 0, max));
      pts = all.filter((p, i) => i === 0 || p > all[i - 1] + 1);
    }
    function apply() {
      const was = on ? nearest(x) : 0;
      on = railMq.matches;
      if (on) { rail.tabIndex = 0; measure(); go(was, false); }
      else { rail.removeAttribute('tabindex'); put(0, false); }
      rail.scrollLeft = 0; rail.scrollTop = 0;
    }
    rails.push(apply);

    rail.addEventListener('pointerdown', (e) => {
      if (!on || !e.isPrimary || (e.pointerType === 'mouse' && e.button !== 0)) return;
      st = { id: e.pointerId, x0: e.clientX, y0: e.clientY, base: x, from: nearest(x), lock: '', s: [[e.timeStamp, e.clientX]] };
    });
    rail.addEventListener('pointermove', (e) => {
      if (!st || e.pointerId !== st.id) return;
      const dx = e.clientX - st.x0; const dy = e.clientY - st.y0;
      if (!st.lock) {
        if (Math.abs(dx) < 7 && Math.abs(dy) < 7) return;
        if (Math.abs(dx) <= Math.abs(dy)) { st = null; return; } // gerakan vertikal: biarkan halaman bergulir
        st.lock = 'x';
        track.classList.add('drag');
        try { rail.setPointerCapture(e.pointerId); } catch (err) { /* abaikan */ }
      }
      let v = st.base - dx;
      if (v < 0) v *= 0.3; else if (v > max) v = max + (v - max) * 0.3;
      put(v, false);
      st.s.push([e.timeStamp, e.clientX]);
      while (st.s.length > 2 && e.timeStamp - st.s[0][0] > 100) st.s.shift();
    });
    function release(e, cancelled) {
      if (!st || e.pointerId !== st.id) return;
      const s = st; st = null;
      if (s.lock !== 'x') return;
      track.classList.remove('drag');
      justDragged = true; setTimeout(() => { justDragged = false; }, 0);
      const a = s.s[0]; const b = s.s[s.s.length - 1];
      // px/ms, positif = maju; nol bila jari sempat diam sebelum diangkat
      const vel = b[0] > a[0] && e.timeStamp - b[0] < 120 ? (a[1] - b[1]) / (b[0] - a[0]) : 0;
      const moved = x - s.base;
      let k = nearest(clamp(x + vel * 180, 0, max));
      if (!cancelled && k === s.from && (Math.abs(vel) > 0.25 || Math.abs(moved) > rail.clientWidth * 0.18)) {
        k = s.from + ((Math.abs(vel) > 0.25 ? vel : moved) > 0 ? 1 : -1);
      }
      go(k);
    }
    rail.addEventListener('pointerup', (e) => release(e, false));
    rail.addEventListener('pointercancel', (e) => release(e, true));
    // saat menggeser ke samping, halaman tidak ikut bergulir
    rail.addEventListener('touchmove', (e) => { if (st && st.lock === 'x' && e.cancelable) e.preventDefault(); }, { passive: false });
    rail.addEventListener('click', (e) => { if (justDragged) { e.preventDefault(); e.stopPropagation(); } }, true);
    rail.addEventListener('dragstart', (e) => { if (on) e.preventDefault(); });
    // trackpad: gulir menyamping
    rail.addEventListener('wheel', (e) => {
      if (!on || Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
      e.preventDefault();
      put(clamp(x + e.deltaX, 0, max), false);
      clearTimeout(wheelT); wheelT = setTimeout(() => go(nearest(x)), 140);
    }, { passive: false });
    // papan ketik
    rail.addEventListener('keydown', (e) => {
      if (!on) return;
      if (e.key === 'ArrowRight') { e.preventDefault(); go(nearest(x) + 1); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); go(nearest(x) - 1); }
    });
    rail.addEventListener('focusin', (e) => {
      if (!on) return;
      const i = items.findIndex((it) => it.contains(e.target));
      if (i >= 0) { measure(); go(nearest(clamp(items[i].offsetLeft - (parseFloat(getComputedStyle(track).paddingLeft) || 0), 0, max))); }
    });
    // cadangan untuk peramban tanpa overflow:clip: jendela tidak boleh tergulir
    rail.addEventListener('scroll', () => { if (on) { rail.scrollLeft = 0; rail.scrollTop = 0; } }, { passive: true });
  });
  const applyRails = () => rails.forEach((f) => f());
  applyRails();
  let railT = 0;
  window.addEventListener('resize', () => { clearTimeout(railT); railT = setTimeout(applyRails, 120); });
  if (railMq.addEventListener) railMq.addEventListener('change', applyRails); else if (railMq.addListener) railMq.addListener(applyRails);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(applyRails);
  window.addEventListener('load', applyRails);

  // ---------- navigasi ----------
  const nav = document.getElementById('nav');
  const burger = document.querySelector('.burger');
  const links = document.getElementById('nav-links');
  function closeMenu() { links.classList.remove('open'); burger.setAttribute('aria-expanded', 'false'); }
  burger.addEventListener('click', () => {
    const open = !links.classList.contains('open');
    links.classList.toggle('open', open);
    burger.setAttribute('aria-expanded', String(open));
  });
  links.querySelectorAll('a').forEach((a) => a.addEventListener('click', closeMenu));
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeMenu(); });
  const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 8);
  onScroll(); window.addEventListener('scroll', onScroll, { passive: true });

  // tandai menu sesuai bagian yang sedang dibaca
  if ('IntersectionObserver' in window) {
    const map = {};
    links.querySelectorAll('a[href^="#"]').forEach((a) => { map[a.getAttribute('href').slice(1)] = a; });
    const order = ['tentang', 'info', 'jadwal', 'biaya', 'merch', 'kontak'];
    const seen = new Set();
    const secObs = new IntersectionObserver((entries) => {
      entries.forEach((en) => { if (en.isIntersecting) seen.add(en.target.id); else seen.delete(en.target.id); });
      const cur = order.find((id) => seen.has(id));
      const key = cur === 'info' ? 'tentang' : cur;
      Object.keys(map).forEach((id) => map[id].classList.toggle('on', id === key));
    }, { rootMargin: '-45% 0px -50% 0px' });
    order.forEach((id) => { const s = document.getElementById(id); if (s) secObs.observe(s); });

    // animasi muncul
    const rvObs = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (!en.isIntersecting) return;
        // kartu dalam baris geser muncul bersamaan, termasuk yang masih di luar layar
        const row = en.target.parentElement && en.target.parentElement.classList.contains('swipe') ? Array.from(en.target.parentElement.children) : [en.target];
        row.forEach((el) => { el.classList.add('in'); rvObs.unobserve(el); });
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    document.querySelectorAll('.rv').forEach((el) => rvObs.observe(el));
  } else {
    document.querySelectorAll('.rv').forEach((el) => el.classList.add('in'));
  }

  // ---------- hitung mundur (hari) ke 12 Desember 2026 07.00 WIB ----------
  const target = new Date('2026-12-12T07:00:00+07:00').getTime();
  function tick() {
    const d = Math.max(0, Math.ceil((target - Date.now()) / 864e5));
    const el = document.getElementById('st-days'); if (el) el.textContent = d;
  }
  tick(); setInterval(tick, 60000);

  // ---------- angka langsung dari basis data ----------
  const C = window.JO_CONFIG;
  if (C && C.supabaseUrl) {
    fetch(C.supabaseUrl + '/rest/v1/rpc/public_stats', {
      method: 'POST', headers: { apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey, 'Content-Type': 'application/json' }, body: '{}',
    }).then((r) => (r.ok ? r.json() : null)).then((s) => {
      if (!s) return;
      const fmt = (n) => Number(n || 0).toLocaleString('id-ID');
      document.getElementById('st-ath').textContent = fmt(s.athletes);
      document.getElementById('st-club').textContent = fmt(s.clubs);
    }).catch(() => {});
  }
})();
