/* Jabar Open 2026 — FAQ: dipakai di beranda (#faq) dan halaman faq.html.
   Berdiri sendiri (tanpa common.js): mengambil data lewat REST RPC public_faq. */
(function () {
  'use strict';
  const C = window.JO_CONFIG || {};
  const L = {
    id: { search: 'Cari pertanyaan', search_ph: 'Ketik kata kunci, mis. BPJS, musik, QRIS', all: 'Semua', copy: 'Salin tautan', copied: 'Tautan disalin',
      none: 'Tidak ada pertanyaan yang cocok. Coba kata lain, atau hubungi panitia.', results: '{n} pertanyaan', clear: 'Hapus pencarian',
      tabs: 'Kategori pertanyaan', more: 'Lihat semua pertanyaan', error: 'FAQ belum bisa dimuat. Muat ulang halaman ini.' },
    en: { search: 'Search questions', search_ph: 'Type a keyword, e.g. BPJS, music, QRIS', all: 'All', copy: 'Copy link', copied: 'Link copied',
      none: 'No matching questions. Try another word, or contact the committee.', results: '{n} questions', clear: 'Clear search',
      tabs: 'Question categories', more: 'See all questions', error: 'The FAQ could not be loaded. Reload this page.' },
  };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const site = () => (C.siteUrl || (location.origin + location.pathname.replace(/[^/]*$/, ''))).replace(/\/?$/, '/');

  // teks jawaban → HTML aman: paragraf, daftar "- ", **tebal**, [teks](tautan)
  function inline(s) {
    let h = esc(s);
    h = h.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    h = h.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, txt, url) => {
      const u = url.replace(/&amp;/g, '&');
      if (!/^(https?:\/\/|mailto:|[a-z0-9_-]+\.html(?:[?#][^\s]*)?$|#[a-z0-9-]+$)/i.test(u)) return txt;
      const ext = /^https?:/i.test(u);
      return `<a href="${esc(u)}"${ext ? ' target="_blank" rel="noopener"' : ''}>${txt}</a>`;
    });
    return h;
  }
  function render(text) {
    const blocks = String(text || '').replace(/\r/g, '').split(/\n\s*\n/);
    return blocks.map((b) => {
      const lines = b.split('\n').map((x) => x.trim()).filter(Boolean);
      if (!lines.length) return '';
      if (lines.every((x) => /^- /.test(x))) return '<ul>' + lines.map((x) => `<li>${inline(x.slice(2))}</li>`).join('') + '</ul>';
      const out = []; let list = [];
      const flush = () => { if (list.length) { out.push('<ul>' + list.map((x) => `<li>${inline(x)}</li>`).join('') + '</ul>'); list = []; } };
      let para = [];
      const flushP = () => { if (para.length) { out.push('<p>' + para.map(inline).join('<br>') + '</p>'); para = []; } };
      lines.forEach((x) => { if (/^- /.test(x)) { flushP(); list.push(x.slice(2)); } else { flush(); para.push(x); } });
      flushP(); flush();
      return out.join('');
    }).join('');
  }
  const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\*\*|\[|\]\([^)]*\)/g, ' ');

  let cache = null;
  async function load() {
    if (cache) return cache;
    cache = fetch(C.supabaseUrl + '/rest/v1/rpc/public_faq', {
      method: 'POST', headers: { apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey, 'Content-Type': 'application/json' }, body: '{}',
    }).then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .catch((e) => { cache = null; throw e; });
    return cache;
  }

  /* mount(el, { lang, mode: 'page' | 'landing', onReady(hasItems), onRender(el) }) */
  function mount(el, opt) {
    opt = opt || {};
    const st = { lang: opt.lang === 'en' ? 'en' : 'id', q: '', tab: null, data: null };
    const T = (k, v) => { let s = L[st.lang][k]; if (v) Object.keys(v).forEach((x) => { s = s.split('{' + x + '}').join(v[x]); }); return s; };
    const q = (it) => (st.lang === 'en' && it.q_en) || it.q_id;
    const a = (it) => (st.lang === 'en' && it.a_en) || it.a_id;
    const catName = (c) => (st.lang === 'en' && c.name_en) || c.name_id;
    const uid = 'faq' + Math.random().toString(36).slice(2, 7);

    function draw(openSlug) {
      const D = st.data; if (!D) return;
      const was = new Set([...el.querySelectorAll('.faq-item[open]')].map((d) => d.dataset.slug));
      if (openSlug) was.add(openSlug);
      const term = norm(st.q.trim());
      const words = term.split(/\s+/).filter(Boolean);
      const hit = (it) => { const hay = norm(q(it) + ' ' + a(it) + ' ' + it.q_id + ' ' + it.a_id); return words.every((w) => hay.includes(w)); };
      const list = words.length ? D.items.filter(hit) : D.items.filter((it) => st.tab === 'all' || it.category === st.tab);
      const byCat = {}; list.forEach((it) => { (byCat[it.category] = byCat[it.category] || []).push(it); });
      const showHeads = words.length || st.tab === 'all';
      const box = el.querySelector('.faq-list');
      box.innerHTML = list.length ? D.categories.filter((c) => byCat[c.key]).map((c) => `
        <div class="faq-group">${showHeads ? `<h3 class="faq-cat">${esc(catName(c))}</h3>` : ''}
          ${byCat[c.key].map((it) => `<details class="faq-item" id="${esc(it.slug)}" data-slug="${esc(it.slug)}"${was.has(it.slug) ? ' open' : ''}>
            <summary><span class="faq-q">${esc(q(it))}</span><i class="faq-tog tog" aria-hidden="true"></i></summary>
            <div class="faq-a">${render(a(it))}
              <p class="faq-link"><button type="button" class="faq-copy" data-copy="${esc(it.slug)}">${esc(T('copy'))}</button></p></div>
          </details>`).join('')}</div>`).join('')
        : `<p class="faq-none">${esc(T('none'))}</p>`;
      el.querySelector('.faq-count').textContent = words.length ? T('results', { n: list.length }) : '';
      el.querySelectorAll('.faq-tab').forEach((b) => b.setAttribute('aria-pressed', String(!words.length && b.dataset.tab === st.tab)));
      box.querySelectorAll('[data-copy]').forEach((b) => b.onclick = () => copy(b));
      if (opt.onRender) opt.onRender(box);
    }
    function frame() {
      const D = st.data;
      el.innerHTML = `<div class="faq-tools">
          <label class="faq-search"><span class="faq-sr">${esc(T('search'))}</span>
            <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>
            <input type="search" id="${uid}-q" placeholder="${esc(T('search_ph'))}" autocomplete="off" value="${esc(st.q)}"></label>
          <div class="faq-tabs" role="group" aria-label="${esc(T('tabs'))}">
            <button type="button" class="faq-tab" data-tab="all">${esc(T('all'))}</button>
            ${D.categories.map((c) => `<button type="button" class="faq-tab" data-tab="${esc(c.key)}">${esc(catName(c))}</button>`).join('')}
          </div>
          <p class="faq-count" aria-live="polite"></p>
        </div>
        <div class="faq-list"></div>`;
      const inp = el.querySelector('input');
      let tmr = null;
      inp.addEventListener('input', () => { clearTimeout(tmr); tmr = setTimeout(() => { st.q = inp.value; draw(); }, 120); });
      el.querySelectorAll('.faq-tab').forEach((b) => b.addEventListener('click', () => {
        st.tab = b.dataset.tab; st.q = ''; inp.value = ''; draw();
      }));
      draw();
    }
    async function copy(b) {
      const url = site() + 'faq.html#' + b.dataset.copy;
      let ok = false;
      try { await navigator.clipboard.writeText(url); ok = true; } catch (e) {
        const t = document.createElement('textarea'); t.value = url; t.style.position = 'fixed'; t.style.opacity = '0';
        document.body.appendChild(t); t.select(); try { ok = document.execCommand('copy'); } catch (x) {} t.remove();
      }
      const old = b.textContent; b.textContent = ok ? T('copied') : url; b.classList.toggle('done', ok);
      setTimeout(() => { b.textContent = old; b.classList.remove('done'); }, 2200);
    }
    function openHash() {
      const slug = decodeURIComponent((location.hash || '').slice(1));
      const it = slug && st.data && st.data.items.find((x) => x.slug === slug);
      if (!it) return false;
      st.q = ''; st.tab = st.tab === 'all' ? 'all' : it.category;
      const inp = el.querySelector('input'); if (inp) inp.value = '';
      draw(slug);
      const d = document.getElementById(slug);
      if (d) { d.open = true; d.classList.add('faq-hl'); setTimeout(() => d.classList.remove('faq-hl'), 2400); setTimeout(() => d.scrollIntoView({ block: 'start' }), 30); }
      return true;
    }

    load().then((D) => {
      st.data = { categories: D.categories || [], items: D.items || [] };
      const has = st.data.items.length > 0;
      if (opt.onReady) opt.onReady(has);
      if (!has) { el.innerHTML = ''; return; }
      st.tab = opt.mode === 'landing' ? st.data.categories[0].key : 'all';
      frame();
      if (opt.mode === 'page') { openHash(); window.addEventListener('hashchange', openHash); }
    }).catch(() => {
      if (opt.onReady) opt.onReady(opt.mode === 'page' ? null : false);
      if (opt.mode === 'page') el.innerHTML = `<p class="faq-none">${esc(T('error'))}</p>`;
    });

    return {
      setLang(l) {
        st.lang = l === 'en' ? 'en' : 'id';
        if (st.data && st.data.items.length) { const q0 = st.q; frame(); if (q0) { st.q = q0; el.querySelector('input').value = q0; draw(); } }
      },
    };
  }

  // jumlah butir terbit, disimpan per sesi peramban (untuk tautan menu)
  async function count() {
    try { const v = sessionStorage.getItem('jo26-faq'); if (v !== null) return Number(v); } catch (e) {}
    const r = await fetch(C.supabaseUrl + '/rest/v1/rpc/public_faq_count', {
      method: 'POST', headers: { apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey, 'Content-Type': 'application/json' }, body: '{}',
    });
    const n = r.ok ? Number(await r.json()) || 0 : 0;
    try { sessionStorage.setItem('jo26-faq', String(n)); } catch (e) {}
    return n;
  }

  window.JOFaq = { mount, render, count };
})();
