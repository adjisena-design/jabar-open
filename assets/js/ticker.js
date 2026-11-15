// Teks berjalan beranda: diatur dari konsol (Buka/tutup & teks beranda), dibaca lewat public_site_notice.
(function () {
  const C = window.JO_CONFIG; if (!C) return;
  const css = `.jo-tk{background:var(--blue,#2c4c7b);font-family:inherit;color:#fff;font-size:14px;line-height:1.3;position:relative;z-index:61;overflow:hidden}
.jo-tk a,.jo-tk span.jo-tk-t{color:#fff;text-decoration:none;display:block}
.jo-tk a:hover .jo-tk-msg,.jo-tk a:focus-visible .jo-tk-msg{text-decoration:underline}
.jo-tk-vp{overflow:hidden;padding:9px 0}
.jo-tk-run{display:inline-flex;white-space:nowrap;will-change:transform;animation:jo-tk var(--d,30s) linear infinite}
.jo-tk:hover .jo-tk-run,.jo-tk:focus-within .jo-tk-run{animation-play-state:paused}
.jo-tk-msg{padding:0 48px 0 0}
.jo-tk-msg::before{content:"";display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--gold,#e4c87d);margin:0 12px 1px 0;vertical-align:middle}
@keyframes jo-tk{from{transform:translateX(0)}to{transform:translateX(-50%)}}
@media (prefers-reduced-motion:reduce){.jo-tk-run{animation:none;white-space:normal;display:block;padding:0 16px}.jo-tk-run .jo-tk-msg+.jo-tk-msg{display:none}}`;
  fetch(C.supabaseUrl + '/rest/v1/rpc/public_site_notice', {
    method: 'POST', headers: { apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey, 'Content-Type': 'application/json' }, body: '{}',
  }).then((r) => (r.ok ? r.json() : null)).then((d) => {
    const t = d && d.ticker; if (!t || !t.text) return;
    const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);
    const bar = document.createElement('div'); bar.className = 'jo-tk'; bar.setAttribute('role', 'region'); bar.setAttribute('aria-label', 'Pengumuman');
    const link = t.link && (/^https:\/\//i.test(t.link) || /^[a-z0-9_-]+\.html(#.*)?$/i.test(t.link) || /^#/.test(t.link)) ? t.link : null;
    const wrap = document.createElement(link ? 'a' : 'span'); wrap.className = 'jo-tk-t';
    if (link) { wrap.href = link; if (/^https:/i.test(link)) { wrap.target = '_blank'; wrap.rel = 'noopener'; } }
    const vp = document.createElement('div'); vp.className = 'jo-tk-vp';
    const run = document.createElement('div'); run.className = 'jo-tk-run';
    const sr = document.createElement('span'); sr.className = 'sr-only'; sr.textContent = t.text; wrap.appendChild(sr);
    run.setAttribute('aria-hidden', 'true');
    vp.appendChild(run); wrap.appendChild(vp); bar.appendChild(wrap);
    const nav = document.getElementById('nav');
    (nav && nav.parentNode ? nav.parentNode.insertBefore(bar, nav) : document.body.prepend(bar));
    // isi cukup panjang agar layar selalu penuh, lalu digandakan untuk putaran tanpa jeda
    const one = () => { const s = document.createElement('span'); s.className = 'jo-tk-msg'; s.textContent = t.text; return s; };
    run.appendChild(one());
    const w = Math.max(run.scrollWidth, 1); const reps = Math.max(1, Math.ceil(window.innerWidth / w));
    for (let i = 1; i < reps; i++) run.appendChild(one());
    const half = run.innerHTML; run.innerHTML = half + half;
    run.style.setProperty('--d', Math.max(12, Math.round((run.scrollWidth / 2) / 70)) + 's');   // ~70 px per detik
  }).catch(() => {});
})();
