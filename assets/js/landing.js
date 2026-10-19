/* Jabar Open 2026 — beranda: bahasa, navigasi, animasi muncul, hitung mundur, angka langsung, galeri */
(function () {
  'use strict';
  const EN = {
    n_about: 'About', n_sched: 'Schedule', n_fee: 'Fees', n_startlist: 'Start list', n_results: 'Results', n_merch: 'Merch',
    n_contact: 'Contact', n_faq: 'FAQ',
    fq_eyebrow: 'Frequently asked', fq_title: 'Common questions, <em>answered here.</em>', fq_lead: 'Search by keyword or pick a category.', fq_all: 'Open the FAQ page', n_status: 'Check status', n_register: 'Register', n_verify: 'Verify a certificate', n_jury: 'Judge application',
    h_kick1: 'Open gymnastics championship', h_kick2: '12–20 December 2026 · Bandung',
    h_t1: 'One arena.', h_t2: 'Four disciplines.', h_t3: 'Hundreds of dreams.',
    cta_reg: 'Register now', cta_fee: 'Schedule & fees', h_days: 'days to 12 December',
    h_ath_alt: "Men's and women's artistic gymnasts",
    h_medals_alt: 'Jabar Open 2026 silver, gold and bronze medals with the official lanyard',
    c_eyebrow: 'Why we compete',
    c_title: 'We compete to grow, <em>not only to win.</em>',
    c1_t: 'Fair play', c1_d: 'The same arena, schedule and judging for everyone.',
    c2_t: 'Progress', c2_d: 'Medals for the top three, scores for everyone.',
    c3_t: 'The mother of all sports', c3_d: 'A movement foundation for almost every other sport.',
    m_tr: 'Say less, show more. To the stars, through hardship.', m_cite: 'Motto of Gimnastik Indonesia West Java',
    t_eyebrow: 'Registration tutorial', t_title: 'Register an athlete <em>in 6 steps.</em>',
    t_lead: 'Watch this one-minute video before filling in the form. Registration is done by the club: its owner, admin or coach.',
    t_s1: 'Enter the club contact person.', t_s2: 'Find and choose your club, or add a new one.',
    t_s3: 'Enter athlete details, upload documents, choose a category.', t_s4: 'Add a team if any, tick the declarations, submit.',
    t_s5: 'Pay by QRIS and upload the proof within 15 minutes.', t_s6: 'Once paid, download the AIC from the email or status page.',
    t_dl: 'Download video', ft_console: 'Committee console', t_video: 'Jabar Open 2026 athlete registration tutorial video',
    i_eyebrow: 'About the championship',
    i_title: 'Open to all, <em>judged by the same standard.</em>',
    i_r3: 'Dates', i_r3v: '12–20 December 2026', i_r4: 'Venue', i_r5: 'Participants',
    i_r5v: 'Through clubs, schools or regency/city associations, including from abroad. No individual registration',
    i_r6: 'Registration', i_r6v: 'Online, by 12 November 2026',
    i_rules: 'Rules', i_r7: 'Regulations', i_r7v: 'FIG CoP 2025–2028 · TR 2025 · ALP without bonus',
    i_r8: 'Protests', i_r8v: 'None',
    more: 'Details',
    d1_w: '12–15 Dec', d2_w: '12–15 Dec', d3_w: '16–18 Dec', d4_w: '19–20 Dec',
    d1_n: "Men's Artistic", d2_n: "Women's Artistic", d3_n: 'Rhythmic', d4_n: 'Aerobic',
    l_fmt: 'Format', l_app: 'Apparatus', l_quota: 'Quota', l_note: 'Note', l_age: 'Age groups',
    v_aa: 'Individual all-around', v_quota: 'Up to 10 gymnasts per category per club', v_music: 'Music for Levels 4–6 is provided',
    l_team: 'Team', v_team: 'Levels 1–6, 1–6 gymnasts from one level, best 4 all-around scores count. Rp650,000 per team.',
    l_award: 'Awards', v_award_m: 'All-around places 1–6; Junior also has apparatus medals',
    v_award_w: 'All-around places 1–6; Levels 4–6, Pre Junior and Junior also have apparatus medals (max. 2 gymnasts per club)',
    l_rgmusic: 'Music', v_rgmusic: 'A Google Drive folder link per athlete is required at registration. It can be changed once on the <a href="musik.html">Music page</a>.',
    v_rgcat: 'Professional · Amateur', v_fest: 'Age groups use the festival system',
    v_aer1: 'Individual men, individual women, mixed pair', v_aer2: 'Individual men and women', v_final: 'Straight finals',
    ap_fx: 'Floor', ap_ph: 'Pommel horse', ap_sr: 'Rings', ap_vt: 'Vault', ap_pb: 'Parallel bars', ap_hb: 'High bar',
    ap_ub: 'Uneven bars', ap_bb: 'Balance beam', ap_fh: 'Freehand', ap_hoop: 'Hoop', ap_ball: 'Ball', ap_clubs: 'Clubs', ap_rib: 'Ribbon',
    sc_eyebrow: 'Provisional schedule', sc_title: 'Nine days, <em>three stages.</em>',
    sc_lead: 'The schedule may change. Sessions and start order are announced on the <a href="startlist.html">start list</a> after registration closes.',
    sc_alt: 'A female gymnast walking to the apparatus', sc_days: 'Day by day',
    dec26: 'December 2026', sc_art: "Artistic <em>Men's &amp; Women's</em>",
    day_sat12: 'Sat, 12 Dec', day_sun13: 'Sun, 13 Dec', day_mon14: 'Mon, 14 Dec', day_tue15: 'Tue, 15 Dec', day_wed16: 'Wed, 16 Dec', day_thu17: 'Thu, 17 Dec', day_fri18: 'Fri, 18 Dec', day_sat19: 'Sat, 19 Dec', day_sun20: 'Sun, 20 Dec',
    sc_a1: 'Judges meeting, podium training for MAG Level 4, WAG Level 4 and Junior', sc_comp: 'Competition', sc_upp: 'Award ceremony', sc_tba: 'To be announced',
    sc_r1: 'Judges meeting, podium training, competition', sc_e1: 'Orientation meeting (max. 1 coach and/or 1 manager per delegation), judges refresher, official training', sc_e2: 'Competition and award ceremony',
    mem_eyebrow: 'From the arena', mem_title: 'Moments that <em>brought us here.</em>',
    at_eyebrow: 'Athlete registration is open', at_t1: 'This is your stage.', at_t2: 'Show who you are.',
    f_lead: 'Registered by the club (owner, admin or coach), up to 10 athletes per registration, by 12 November 2026.',
    f_head: 'Fee per athlete',
    f_r1: "Men's / Women's Artistic", f_r3: 'Rhythmic individual',
    f_r4: 'Aerobic individual <small>IM / IW</small>', f_r5: 'Aerobic mixed pair <small>MP, per pair</small>',
    f_r6: "Women's Artistic team <small>Levels 1–6, per team, on top of individual fees</small>",
    f_pri_t: 'Rhythmic Priangan',
    f_pri: 'A separate Rhythmic level below Amateur, only for Indonesian athletes with a West Java address from West Java clubs. No extra fee.',
    f_s1t: 'The club fills in the form', f_s2t: 'Pay with QRIS', f_s3t: 'Upload payment proof', f_s4t: 'Receive athlete cards (AIC)',
    at_alt: 'A female gymnast in a split leap on the beam', photo: 'Photo',
    mc_eyebrow: 'Official merchandise', mc_soon: 'Coming soon', mc_title: 'Limited edition. <em>Worn with pride.</em>',
    mc_alt: 'Jabar Open 2026 merchandise preview: t-shirt and water bottles',
    k_eyebrow: 'Get in touch', k_title: 'Questions? <em>We are here to help.</em>',
    k_mail_t: 'Registration and payment', k_mail_d: 'Include your registration code (JO26-…) for a faster reply.', k_mail_cta: 'Send an email',
    ig_lead: 'Announcements and start lists appear here first.', ig_cta: 'Follow on Instagram',
    k_wa: 'Discipline contacts', k_jury: 'A licensed judge who would like to officiate at Jabar Open 2026?', k_jury_cta: 'Apply as a judge',
    cp1: "Men's Artistic", cp2: "Women's Artistic", cp3: 'Rhythmic', cp4: 'Aerobic',
    cl_t1: 'See you at',
    ft_org: 'Organised by Gimnastik Indonesia (GI) West Java under KONI West Java.', ft_sec: 'Secretariat', ft_map: 'View on map',
    ft_links: 'Links', ft_credit: 'Built and maintained by Daffa Adjisena, M.B.A.',
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
    if (faq) faq.setLang(l);
  }
  let faq = null;
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

  // ---------- lipatan: buka-tutup halus ----------
  // <details> bawaan langsung melompat. Di sini tingginya dianimasikan, isinya memudar masuk.
  function animateDetails(d) {
    if (d.dataset.anim) return; d.dataset.anim = '1';
    const sum = d.querySelector(':scope > summary');
    const body = d.querySelector(':scope > :not(summary)');
    if (!sum || !body || reduce || typeof d.animate !== 'function') return;
    let anim = null; let fade = null; let closing = false;
    const edge = () => d.offsetHeight - d.clientHeight; // garis tepi details
    function done(isOpen) {
      d.open = isOpen;
      d.classList.remove('closing');
      anim = null; closing = false;
      d.style.height = ''; d.style.overflow = '';
    }
    function run(from, to, isOpen) {
      if (anim) { anim.onfinish = null; anim.cancel(); }
      if (fade) fade.cancel();
      anim = d.animate({ height: [from + 'px', to + 'px'] }, { duration: isOpen ? 420 : 320, easing: isOpen ? 'cubic-bezier(.22,.8,.24,1)' : 'cubic-bezier(.4,0,.2,1)' });
      fade = body.animate(isOpen ? { opacity: [0, 1], transform: ['translateY(-6px)', 'none'] } : { opacity: [1, 0] },
        { duration: isOpen ? 360 : 220, delay: isOpen ? 60 : 0, easing: 'ease-out', fill: 'both' });
      anim.onfinish = () => { done(isOpen); if (fade) { fade.cancel(); fade = null; } };
    }
    sum.addEventListener('click', (e) => {
      e.preventDefault();
      d.style.overflow = 'hidden';
      if (closing || !d.open) {
        // buka: kunci tinggi sekarang, tampilkan isi, lalu tumbuh ke tinggi penuh
        const from = d.offsetHeight;
        d.style.height = from + 'px';
        d.open = true; d.classList.remove('closing');
        closing = false;
        requestAnimationFrame(() => run(from, sum.offsetHeight + body.offsetHeight + edge(), true));
      } else {
        closing = true;
        d.classList.add('closing');
        run(d.offsetHeight, sum.offsetHeight + edge(), false);
      }
    });
  }
  document.querySelectorAll('details').forEach(animateDetails);

  // ---------- FAQ: tampil hanya bila ada pertanyaan terbit ----------
  const faqSec = document.getElementById('faq');
  if (faqSec && window.JOFaq) {
    faq = window.JOFaq.mount(document.getElementById('faq-box'), {
      lang: saved === 'en' ? 'en' : 'id', mode: 'landing',
      onReady: (has) => {
        faqSec.hidden = !has;
        document.querySelectorAll('[data-faq-nav]').forEach((x) => { x.hidden = !has; });
      },
      onRender: (box) => box.querySelectorAll('details').forEach(animateDetails),
    });
  }

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
    const order = ['tentang', 'info', 'jadwal', 'kenangan', 'biaya', 'merch', 'faq', 'kontak'];
    const seen = new Set();
    const secObs = new IntersectionObserver((entries) => {
      entries.forEach((en) => { if (en.isIntersecting) seen.add(en.target.id); else seen.delete(en.target.id); });
      const cur = order.find((id) => seen.has(id));
      const key = cur === 'info' ? 'tentang' : cur === 'kenangan' ? '' : cur;
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

})();
