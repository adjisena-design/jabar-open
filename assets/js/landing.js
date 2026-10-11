/* Jabar Open 2026 — beranda: bahasa, navigasi, animasi muncul, hitung mundur, angka langsung, galeri */
(function () {
  'use strict';
  const EN = {
    n_about: 'About', n_sched: 'Schedule', n_fee: 'Fees', n_startlist: 'Start list', n_results: 'Results', n_merch: 'Merch',
    n_contact: 'Contact', n_status: 'Check status', n_register: 'Register', n_verify: 'Verify a certificate',
    h_kick1: 'Open gymnastics championship', h_kick2: '12–20 December 2026 · Bandung',
    h_t1: 'One arena.', h_t2: 'Four disciplines.', h_t3: 'Hundreds of dreams.',
    h_lead: "Men's Artistic, Women's Artistic, Rhythmic and Aerobic meet at Gymnasium Arcamanik. Open to schools, clubs, associations and individual athletes from across Indonesia and abroad.",
    cta_reg: 'Register now', cta_fee: 'Fees & how to register', cta_ticket: 'Spectator tickets', soon: 'soon',
    h_meta: 'Register by 12 November',
    h_medals_alt: 'Jabar Open 2026 silver, gold and bronze medals',
    s_ath: 'Athletes registered', s_live: 'live', s_club: 'Clubs and schools', s_disc: 'Disciplines', s_days: 'Days until 12 December',
    c_eyebrow: 'Why we compete',
    c_title: 'We compete to <em>grow,</em> not only to win.',
    c_lead: 'Competition is an honest mirror. Months of training are tested in a single routine, judged by the same rules for everyone, and carried into the next step. Jabar Open exists to hold up that mirror for gymnasts from West Java and across Indonesia.',
    c1_t: 'Fair play', c1_d: 'Every athlete performs in the same arena, schedule and judging, with the FIG Code of Points as the reference. Respecting opponents, judges and results is part of the competition itself.',
    c2_t: 'Progress', c2_d: 'Medals go to the top three, but scores count for everyone. Each score shows clearly what has been mastered and what needs more training. Time on the floor at an official competition is part of development.',
    c3_t: 'The <em>mother of all sports</em>', c3_d: 'Gymnastics builds the basic movement skills: strength, flexibility, balance, coordination and body awareness. Athletes carry this foundation into almost every other sport, which is why gymnastics is called the mother of all sports.',
    m_tr: 'Say less, show more. To the stars, through hardship.', m_cite: 'Motto of Gimnastik Indonesia West Java',
    i_eyebrow: 'About the championship',
    i_title: 'Open to all, <em>judged by the same standard.</em>',
    i_lead: 'Jabar Open 2026 is a national open gymnastics championship organised by Gimnastik Indonesia (GI) West Java. Registration, payment verification, start lists and official results are all managed through this site.',
    i_r3: 'Dates', i_r3v: '12–20 December 2026', i_r4: 'Venue', i_r5: 'Participants',
    i_r5v: 'Schools, clubs, associations, regency/city teams and individual athletes from Indonesia and abroad',
    i_r6: 'Registration', i_r6v: 'Online through this site, by 12 November 2026',
    i_r7: 'Rules', i_r7v: 'FIG Code of Points 2025–2028, Technical Regulation 2025, ALP MAG & WAG (no bonus), Aerobic special rules',
    i_r8: 'Protests', i_r8v: 'None', i_r9: 'Organiser',
    d1_w: '12–15 Dec', d2_w: '12–15 Dec', d3_w: '16–18 Dec', d4_w: '19–20 Dec',
    d1_n: "Men's Artistic", d1_d: 'ALP Levels 1–4 and Junior (CoP), individual all-around. Apparatus: floor, pommel horse, rings, vault, parallel bars, high bar. Up to 10 gymnasts per category per club.',
    d2_n: "Women's Artistic", d2_d: 'ALP Levels 1–6, Pre Junior and Junior (CoP), individual all-around. Apparatus: vault, uneven bars, balance beam, floor. Music for Levels 4–6 is provided.',
    d3_n: 'Rhythmic', d3_d: 'Professional and Amateur categories for age groups 5–6, 7–8, 9–10, 11–12 and Junior. Apparatus by age group: freehand, hoop, ball, clubs, ribbon. Age groups use the festival system.',
    d4_n: 'Aerobic', d4_d: 'Junior (15–17) and Youth (12–14): individual men, individual women, mixed pair. National Development (9–11) and Pre National Development (6–8): individual men and women. Straight finals.',
    sc_eyebrow: 'Schedule', sc_title: 'Nine days, <em>three stages.</em>',
    sc_lead: "Provisional schedule. Each athlete's session, group and start order are announced on the start list page after registration closes.",
    dec26: 'December 2026', sc_art: "Artistic <em>Men's &amp; Women's</em>", sc_rg: '<em>Rhythmic</em>', sc_aer: '<em>Aerobic</em>',
    day_sat12: 'Sat, 12 Dec', day_sun13: 'Sun, 13 Dec', day_mon14: 'Mon, 14 Dec', day_tue15: 'Tue, 15 Dec', day_wed16: 'Wed, 16 Dec', day_thu17: 'Thu, 17 Dec', day_fri18: 'Fri, 18 Dec', day_sat19: 'Sat, 19 Dec', day_sun20: 'Sun, 20 Dec',
    sc_a1: 'Judges meeting, podium training for MAG Level 4, WAG Level 4 and Junior', sc_comp: 'Competition', sc_upp: 'Award ceremony', sc_tba: 'To be announced',
    sc_r1: 'Judges meeting, podium training, competition', sc_e1: 'Orientation meeting (max. 1 coach and/or 1 manager per delegation), judges refresher, official training', sc_e2: 'Competition and award ceremony',
    sc_note: 'The schedule may change. There is no on-site check-in: follow the <a href="startlist.html">start list</a> and Instagram <a href="https://www.instagram.com/gimnastikjabar/" target="_blank" rel="noopener">@gimnastikjabar</a> for official announcements.',
    f_eyebrow: 'Registration', f_title: 'Fees and <em>how to register.</em>',
    f_lead: 'Register as an individual or as a club or school (up to five athletes at once). Fees are per athlete or per pair, paid once with QRIS.',
    f_r1: "Men's Artistic <small>per gymnast</small>", f_r2: "Women's Artistic <small>per gymnast</small>", f_r3: 'Rhythmic individual <small>per gymnast</small>',
    f_r4: 'Aerobic individual <small>IM / IW, per gymnast</small>', f_r5: 'Aerobic mixed pair <small>MP, per pair</small>', f_r6: 'Priangan category add-on <small>per entry, optional</small>',
    f_pri_t: 'Priangan category',
    f_pri: 'Every athlete competes in the same Jabar Open arena, schedule and judging. Indonesian athletes with a West Java address on their ID, from a West Java club, can choose Priangan when registering. Their results are re-ranked among Priangan entrants for separate awards and a separate medal table.',
    f_s1t: 'Fill in the online form', f_s1: 'Choose the discipline, club, athlete details and categories. Categories follow the date of birth automatically.',
    f_s2t: 'Pay with QRIS', f_s2: 'Type the exact amount shown, including the unique code in the last three digits, so the payment matches your registration right away.',
    f_s3t: 'Upload the payment proof', f_s3: 'From the invoice or status page. The committee verifies payments and documents.',
    f_s4t: 'Receive e-tickets', f_s4: "Each athlete's PDF e-ticket is emailed and can be downloaded from the status page.",
    f_docs: "<strong>Have ready:</strong> a photo or PDF of the athlete's ID (national ID, birth certificate, school certificate or passport) and parent/guardian details for athletes under 18. Participants must hold BPJS or insurance as stated in the Invitation. Registration and payment deadline: <strong>12 November 2026</strong>.",
    at_eyebrow: 'Athlete registration is open', at_t1: 'This is your stage.', at_t2: 'Show who you are.',
    at_lead: 'Write your name on the podium at Gymnasium Arcamanik. Register on your own or with your club, pay once, and receive an e-ticket for every athlete.',
    at_f1b: '12 November', at_f1: 'Registration deadline', at_f2b: '4 disciplines', at_f2: 'MAG, WAG, RG, AER',
    at_f3b: 'From Rp300,000', at_f3: 'Fee per athlete', at_f4b: 'Priangan', at_f4: 'Special ranking for West Java athletes',
    at_alt: 'A female gymnast in a split leap on the beam', photo: 'Photo',
    mem_eyebrow: 'Jabar Open 2025', mem_title: 'Moments that <em>brought us here.</em>',
    mem_lead: 'A glimpse of the previous edition: courage on the mat, coaches at the edge of the floor, and the togetherness we want to bring back to Arcamanik.',
    m1a: 'Rhythmic,', m1b: 'clubs', m2a: 'Opening', m2b: 'ceremony', m3a: 'Artistic,', m3b: 'rings', m4b: 'ribbon',
    m5a: 'Coach', m5b: 'and athlete', m6b: 'floor', m7a: 'Team', m7b: 'spirit', m8b: 'pommel horse', m9b: 'freehand',
    mc_eyebrow: 'Official merchandise', mc_soon: 'Coming soon', mc_title: 'Limited edition. <em>Worn with pride.</em>',
    mc_lead: 'The official Jabar Open 2026 collection is being prepared. Designed from the championship identity and made in limited numbers, for athletes, coaches, families and anyone who wants to take home a piece of the story from the arena.',
    mc_p1: 'Produced in limited numbers for the 2026 edition, never reprinted.', mc_p2: 'Collection details, prices and ordering are announced on this site.',
    mc_p3: 'News always lands first on Instagram @gimnastikjabar.', mc_cta: 'Follow the news', mc_badge: 'Collection preview',
    mc_alt: 'Jabar Open 2026 merchandise preview: flag banner, t-shirt and water bottles',
    ig_lead: 'The official Instagram account of Gimnastik Indonesia West Java. Announcements, start lists and moments from the arena appear there first.',
    ig_cta: 'Follow on Instagram',
    k_eyebrow: 'Get in touch', k_title: 'Questions? <em>We are here to help.</em>',
    k_lead: 'Questions about registration, payment or athlete data go by email. Technical questions per discipline can go to each discipline contact on WhatsApp.',
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
      entries.forEach((en) => { if (en.isIntersecting) { en.target.classList.add('in'); rvObs.unobserve(en.target); } });
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
