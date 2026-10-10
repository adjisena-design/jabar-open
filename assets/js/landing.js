/* Jabar Open 2026 — beranda: bahasa, hitung mundur, angka langsung */
(function () {
  'use strict';
  const EN = {
    n_about: 'About', n_info: 'Information', n_sched: 'Schedule', n_fee: 'Fees & how to register', n_startlist: 'Start list', n_results: 'Results',
    n_contact: 'Contact', n_status: 'Check status', n_register: 'Register', n_verify: 'Verify a certificate',
    h_badge: 'National Gymnastics Championship',
    h_desc: "Men's Artistic, Women's Artistic, Rhythmic and Aerobic at Gymnasium Arcamanik, Bandung, 12–20 December 2026. Open to schools, clubs, associations and individual athletes from across Indonesia and abroad.",
    h_count: 'Until the first day of competition, Saturday 12 December 2026',
    cd_d: 'days', cd_h: 'hours', cd_m: 'minutes',
    h_cta1: 'Register now', h_cta2: 'Fees & how to register', h_cta3: 'Spectator tickets (soon)',
    s_ath: 'Athletes registered', s_club: 'Clubs & schools', s_disc: 'Disciplines', s_date: 'December 2026', s_venue: 'Gymnasium Arcamanik',
    a_eyebrow: 'Introduction', a_title: 'Building a high-performance sport ecosystem',
    a_p1: '<strong>Jabar Open 2026</strong> is a national gymnastics championship organised by Gimnastik Indonesia (GI) West Java. It brings together athletes from regencies, cities and provinces across four disciplines: Men\'s Artistic, Women\'s Artistic, Rhythmic and Aerobic.',
    a_p2: 'Building on previous editions, Jabar Open 2026 is planned to be more <strong>structured and professional</strong>: online registration, recorded payment verification, and official start lists and results published on this site.',
    a_p3: 'The championship is also a place for development and friendship among athletes, coaches, judges and gymnastics families in West Java and Indonesia.',
    p1_t: 'Bringing athletes together', p1_d: 'Athletes from across Indonesia and abroad compete in the same arena, schedule and judging.',
    p2_t: 'Competition experience', p2_d: 'Age groups and levels from beginner to junior give young athletes real competition time.',
    p3_t: 'Priangan awards', p3_d: 'West Java athletes can also be re-ranked for the special Priangan category awards.',
    p4_t: 'Fair play', p4_d: 'Judging under the FIG Code of Points 2025–2028 by FIG, national and regional licensed judges.',
    j_eyebrow: 'Official mascot', j_title: 'Meet Jagat',
    j_p1: '<strong>Jagat, the Javan leopard</strong>, is the symbol of strength and prestige at Jabar Open 2026. Inspired by "Jagabaya", the guardian, Jagat stands for the technical precision and mental toughness every athlete needs to conquer the arena.',
    j_p2: 'Sharp eyes and explosive power capture the precision of <strong>Artistic</strong>, the grace of <strong>Rhythmic</strong> and the energy of <strong>Aerobic</strong> at Gymnasium Arcamanik.',
    j_p3: 'Time to roar with Jagat!',
    i_eyebrow: 'Event details', i_title: 'Event information', i_item: 'Item', i_val: 'Details',
    i_r1: 'Event', i_r2: 'Disciplines', i_r2v: "Men's Artistic (MAG), Women's Artistic (WAG), Rhythmic (RG), Aerobic (AER)",
    i_r3: 'Dates', i_r3v: '12–20 December 2026', i_r4: 'Venue', i_r5: 'Participants',
    i_r5v: 'Schools, clubs, associations, regency/city teams and individual athletes from Indonesia and abroad',
    i_r6: 'Registration', i_r6v: 'Online through this site, by 12 November 2026',
    i_r7: 'Rules', i_r7v: 'FIG Code of Points 2025–2028, Technical Regulation 2025, ALP MAG & WAG (no bonus), Aerobic special rules',
    i_r8: 'Protests', i_r8v: 'None', i_r9: 'Organiser',
    i_disc: 'Disciplines',
    d1_n: "Men's Artistic (MAG)", d1_d: 'ALP Levels 1–4 and Junior (CoP), individual all-around. Apparatus: floor, pommel horse, rings, vault, parallel bars, high bar. Up to 10 gymnasts per category per club.',
    d2_n: "Women's Artistic (WAG)", d2_d: 'ALP Levels 1–6, Pre Junior and Junior (CoP), individual all-around. Apparatus: vault, uneven bars, balance beam, floor. Music for Levels 4–6 is provided.',
    d3_n: 'Rhythmic (RG)', d3_d: 'Professional and Amateur categories for age groups 5–6, 7–8, 9–10, 11–12 and Junior. Apparatus by age group: freehand, hoop, ball, clubs, ribbon. Age groups use the festival system.',
    d4_n: 'Aerobic (AER)', d4_d: 'Junior (15–17) and Youth (12–14): individual men, individual women, mixed pair. National Development (9–11) and Pre National Development (6–8): individual men and women. Straight finals.',
    sc_eyebrow: 'Schedule', sc_title: 'Provisional schedule', sc_art: "Men's & Women's Artistic", sc_rg: 'Rhythmic', sc_aer: 'Aerobic',
    day_sat12: 'Sat, 12 Dec', day_sun13: 'Sun, 13 Dec', day_mon14: 'Mon, 14 Dec', day_tue15: 'Tue, 15 Dec', day_wed16: 'Wed, 16 Dec', day_thu17: 'Thu, 17 Dec', day_fri18: 'Fri, 18 Dec', day_sat19: 'Sat, 19 Dec', day_sun20: 'Sun, 20 Dec',
    sc_a1: 'Judges meeting, podium training for MAG Level 4, WAG Level 4 and Junior', sc_comp: 'Competition', sc_upp: 'Award ceremony', sc_tba: 'To be announced',
    sc_r1: 'Judges meeting, podium training, competition', sc_e1: 'Orientation meeting (max. 1 coach and/or 1 manager per delegation), judges refresher, official training', sc_e2: 'Competition and award ceremony',
    sc_note: 'The schedule may change. There is no on-site check-in: each athlete\'s session, group and start order are announced on the <a href="startlist.html">start list page</a> and Instagram <a href="https://www.instagram.com/gimnastikjabar/" target="_blank" rel="noopener">@gimnastikjabar</a>.',
    f_eyebrow: 'Registration', f_title: 'Fees & how to register',
    f_r1: "Men's Artistic (MAG), per gymnast", f_r2: "Women's Artistic (WAG), per gymnast", f_r3: 'Rhythmic individual, per gymnast',
    f_r4: 'Aerobic individual (IM / IW), per gymnast', f_r5: 'Aerobic mixed pair (MP), per pair', f_r6: 'Priangan category add-on, per entry (optional)',
    f_pri: '<strong>Priangan category.</strong> Every athlete competes in the same Jabar Open field, schedule and judging. Indonesian athletes with a West Java address on their ID, from a West Java club, can tick Priangan when registering. Their results are re-ranked among Priangan entrants for separate awards and a separate medal table.',
    f_s1: '<b>Fill in the online form</b>Choose discipline, club, athlete details and categories. Categories follow the date of birth automatically. One club registration holds up to 5 athletes.',
    f_s2: '<b>Pay with QRIS</b>Type the exact amount shown, including the three-digit unique code, so the payment matches your registration right away.',
    f_s3: '<b>Upload the payment proof</b>From the invoice or status page. The committee verifies payments and documents.',
    f_s4: '<b>Receive e-tickets</b>Each athlete\'s PDF e-ticket is emailed and can be downloaded from the status page.',
    f_docs: '<strong>Have ready:</strong> a photo or PDF of the athlete\'s ID (national ID, birth certificate, school certificate or passport) and parent/guardian details for athletes under 18. Participants must hold BPJS or insurance as stated in the Invitation. Registration and payment deadline: <strong>12 November 2026</strong>.',
    at_eyebrow: 'Athlete registration', at_t1: 'This is your stage.', at_t2: 'Show who you are.',
    at_lead: 'Write your name on the podium at Gymnasium Arcamanik, Bandung, 12–20 December 2026. Online registration is open until 12 November 2026.',
    c_eyebrow: 'Get in touch', c_title: 'Committee contacts',
    c_lead: 'Questions about registration, payment or athlete data can be sent by email. Technical questions per discipline go to each discipline contact.',
    c_mail: 'Send an email', cp1: "Men's Artistic", cp2: "Women's Artistic", cp3: 'Rhythmic', cp4: 'Aerobic',
  };
  const ID = {};
  document.querySelectorAll('[data-i18n]').forEach((el) => { ID[el.dataset.i18n] = el.textContent; });
  document.querySelectorAll('[data-i18n-html]').forEach((el) => { ID[el.dataset.i18nHtml] = el.innerHTML; });
  function setLang(l) {
    const d = l === 'en' ? EN : ID;
    document.querySelectorAll('[data-i18n]').forEach((el) => { const v = d[el.dataset.i18n]; if (v) el.textContent = v; });
    document.querySelectorAll('[data-i18n-html]').forEach((el) => { const v = d[el.dataset.i18nHtml]; if (v) el.innerHTML = v; });
    document.querySelectorAll('.lang-sw button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.lang === l)));
    document.documentElement.lang = l;
    try { localStorage.setItem('jo26-lang', l); } catch (e) {}
  }
  document.querySelectorAll('.lang-sw button').forEach((b) => b.addEventListener('click', () => setLang(b.dataset.lang)));
  let saved = 'id'; try { saved = localStorage.getItem('jo26-lang') || 'id'; } catch (e) {}
  if (saved === 'en') setLang('en');

  // hitung mundur ke 12 Desember 2026 07.00 WIB
  const target = new Date('2026-12-12T07:00:00+07:00').getTime();
  function tick() {
    const ms = Math.max(0, target - Date.now());
    const d = Math.floor(ms / 864e5), h = Math.floor(ms % 864e5 / 36e5), m = Math.floor(ms % 36e5 / 6e4);
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    set('cd-d', d); set('cd-h', h); set('cd-m', m);
  }
  tick(); setInterval(tick, 30000);

  // angka langsung dari basis data
  const C = window.JO_CONFIG;
  if (C && C.supabaseUrl) {
    fetch(C.supabaseUrl + '/rest/v1/rpc/public_stats', {
      method: 'POST', headers: { apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey, 'Content-Type': 'application/json' }, body: '{}',
    }).then((r) => (r.ok ? r.json() : null)).then((s) => {
      if (!s) return;
      const fmt = (n) => Number(n).toLocaleString('id-ID');
      document.getElementById('st-ath').textContent = fmt(s.athletes);
      document.getElementById('st-club').textContent = fmt(s.clubs);
    }).catch(() => {});
  }
})();
