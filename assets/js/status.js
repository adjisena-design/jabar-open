/* Jabar Open 2026 — halaman status pendaftaran */
(function () {
  'use strict';
  const { t, esc, fmtRp, rpc } = JO;
  JO.addDict({
    s_title: ['Status pendaftaran', 'Registration status'],
    s_find: ['Cari pendaftaran', 'Find a registration'],
    s_find_lead: ['Masukkan kode pendaftaran dan email penanggung jawab. Kami akan mengirim ulang tautan halaman status ke email tersebut.', 'Enter the registration code and contact email. We will resend the status page link to that email.'],
    s_code: ['Kode pendaftaran', 'Registration code'], s_email: ['Email penanggung jawab', 'Contact email'],
    s_send: ['Kirim tautan', 'Send link'],
    s_sent: ['Jika kode dan email cocok, tautan sudah dikirim. Periksa kotak masuk dan folder spam dalam beberapa menit.', 'If the code and email match, the link has been sent. Check your inbox and spam folder in a few minutes.'],
    s_mine: ['Pendaftaran dari perangkat ini', 'Registrations from this device'],
    s_notfound: ['Pendaftaran tidak ditemukan. Gunakan tautan dari email, atau minta tautan baru di bawah.', 'Registration not found. Use the link from your email, or request a new one below.'],
    s_club: ['Klub', 'Club'], s_contact: ['Penanggung jawab', 'Contact'], s_created: ['Didaftarkan', 'Registered'],
    s_individual: ['Perorangan', 'Independent'],
    s_pay: ['Pembayaran', 'Payment'],
    s_pay_waiting: ['Bukti pembayaran sudah diterima pada {d}. Panitia sedang memverifikasi; AIC dikirim lewat email setelah lunas.', 'Payment proof received on {d}. The committee is verifying it; AIC are emailed once confirmed.'],
    s_pay_fix: ['Bukti pembayaran perlu diperbaiki', 'Payment proof needs attention'],
    s_paid: ['Lunas pada {d}.', 'Paid on {d}.'],
    s_proof_again: ['Unggah bukti lain', 'Upload another proof'],
    s_athletes: ['Atlet', 'Athletes'],
    s_doc_menunggu: ['Dokumen belum diperiksa', 'Document not yet checked'], s_doc_valid: ['Dokumen valid', 'Document verified'], s_doc_tidak_valid: ['Dokumen perlu diganti, hubungi panitia', 'Document needs replacing, contact the committee'],
    s_pri: ['Priangan', 'Priangan'], s_pri_menunggu: ['menunggu verifikasi', 'pending'], s_pri_disetujui: ['disetujui', 'approved'], s_pri_ditolak: ['ditolak', 'rejected'],
    s_ticket: ['Unduh Athlete Identification Card (AIC)', 'Download Athlete Identification Card (AIC)'], s_ticket_wait: ['Athlete Identification Card (AIC) tersedia setelah pembayaran lunas. Tunjukkan secara digital di venue; tidak perlu dicetak.', 'The Athlete Identification Card (AIC) is available once payment is confirmed. Show it digitally at the venue; no printing needed.'],
    s_start: ['Jadwal tampil', 'Competition slot'], s_group: ['grup', 'group'], s_order: ['urutan', 'order'],
    s_result: ['Hasil', 'Result'], s_rank: ['Peringkat {r}', 'Rank {r}'], s_cert: ['Unduh sertifikat', 'Download certificate'],
    s_mini: ['Medali mini, peringkat {r}', 'Mini medal, place {r}'],
    s_capped: ['Penghargaan serba bisa diberikan ke pesenam berikutnya (maks. 2 pesenam per klub).', 'The all-around award passed to the next gymnast (max. 2 gymnasts per club).'],
    s_app_medals: ['Medali per alat', 'Apparatus medals'], s_cert_app: ['Sertifikat {a}', '{a} certificate'],
    s_pri_rank: ['Priangan: peringkat {r}', 'Priangan: rank {r}'],
    s_making: ['Membuat PDF…', 'Creating PDF…'],
    s_cancelled: ['Pendaftaran ini dibatalkan oleh panitia.', 'This registration was cancelled by the committee.'],
    s_reload: ['Muat ulang', 'Reload'],
    s_team: ['Beregu', 'Team'],
    s_team_ind: ['juga perorangan', 'also individual'], s_team_tim: ['khusus beregu', 'team only'],
    s_team_ind_note: ['Anggota "juga perorangan" memakai AIC dari pendaftaran perorangannya. AIC anggota "khusus beregu" ada di bagian Atlet di bawah.', 'Members entered "also individual" use the AIC from their individual registration. AICs for "team only" members are under Athletes below.'],
    s_team_rank: ['Peringkat beregu {r}', 'Team rank {r}'],
    s_team_total: ['Nilai tim {v}', 'Team score {v}'],
    s_team_counted: ['dihitung', 'counted'],
    s_team_cert: ['Sertifikat Juara Beregu', 'Team champion certificate'],
    s_team_wait: ['Peringkat beregu tampil di sini setelah hasil level ini dipublikasikan.', 'The team ranking appears here once results for this level are published.'],
    s_team_only_res: ['tidak diperingkat perorangan', 'not ranked individually'],
    s_music: ['Musik', 'Music'],
    s_jabar: ['Kategori Priangan: cek syarat Jawa Barat', 'Priangan category: West Java check'],
    s_bpjs_no: ['BPJS Ketenagakerjaan belum diunggah: bawa kartunya ke meja panitia di venue sebelum bertanding.', 'BPJS Ketenagakerjaan not uploaded: bring the card to the committee desk at the venue before competing.'],
    s_timer: ['Unggah bukti bayar dalam {m}. Bila tidak, pendaftaran ini dihapus otomatis pukul {h}.', 'Upload the payment proof within {m}. Otherwise this registration is deleted automatically at {h}.'],
    s_music_belum: ['Belum ada tautan', 'No link yet'], s_music_menunggu: ['Menunggu pemeriksaan panitia', 'Awaiting committee check'],
    s_music_ok: ['Sudah diperiksa, bisa dibuka', 'Checked, opens fine'], s_music_tidak_bisa: ['Tidak bisa dibuka, perbaiki akses', 'Cannot be opened, fix the sharing'],
    s_music_tidak_perlu: ['Tidak perlu', 'Not needed'],
    s_music_change: ['Ganti atau perbaiki musik', 'Change or fix music'],
    s_music_used: ['kesempatan ganti sudah dipakai', 'change already used'],
  });
  const app = document.getElementById('app');
  const code = (JO.qs('k') || '').trim();
  const token = (JO.qs('t') || '').trim();
  let D = null;

  function finder(msg) {
    let mine = [];
    try { mine = JSON.parse(localStorage.getItem('jo26-my') || '[]'); } catch (e) {}
    app.innerHTML = `<div class="page-head"><h1>${esc(t('s_title'))}</h1></div>
      ${msg ? `<p class="note warn">${esc(msg)}</p>` : ''}
      ${mine.length ? `<section class="card"><h2>${esc(t('s_mine'))}</h2><div class="choices">
        ${mine.map((m) => `<a class="choice" href="status.html?k=${encodeURIComponent(m.code)}&t=${encodeURIComponent(m.token)}" style="text-decoration:none;color:inherit">
          <span><span class="c-title code">${esc(m.code)}</span><br><span class="c-sub">${esc(JO.fmtDateTime(m.at))}</span></span></a>`).join('')}</div></section>` : ''}
      <section class="card"><h2>${esc(t('s_find'))}</h2><p class="muted small">${esc(t('s_find_lead'))}</p>
        <form id="f" class="grid-2" novalidate>
          <div class="field"><label class="f" for="fc">${esc(t('s_code'))}</label><input id="fc" type="text" placeholder="JO26-WAG-0001" autocapitalize="characters" value="${esc(code)}" required></div>
          <div class="field"><label class="f" for="fe">${esc(t('s_email'))}</label><input id="fe" type="email" inputmode="email" required></div>
          <div><button class="btn btn-dark" type="submit">${esc(t('s_send'))}</button></div>
        </form><div id="fmsg" style="margin-top:12px"></div></section>`;
    app.querySelector('#f').onsubmit = async (e) => {
      e.preventDefault();
      const c = app.querySelector('#fc').value.trim(), m = app.querySelector('#fe').value.trim();
      if (!c || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(m)) return;
      const btn = e.submitter || app.querySelector('#f button'); btn.disabled = true;
      try { await rpc('public_resend_link', { p_code: c, p_email: m }); app.querySelector('#fmsg').innerHTML = `<p class="note ok">${esc(t('s_sent'))}</p>`; }
      catch (err) { app.querySelector('#fmsg').innerHTML = `<p class="note bad">${esc(err.message)}</p>`; }
      finally { btn.disabled = false; }
    };
  }

  const catName = (e) => (JO.lang === 'en' ? e.category_name_en : e.category_name_id);
  const appName = (k) => { const n = D && D.apparatus_names && D.apparatus_names[k]; return n ? (JO.lang === 'en' ? n.en : n.id) : k; };
  function startText(s) {
    if (!s) return '';
    const parts = [s.session, s.day ? JO.fmtDate(s.day, { weekday: 'long', day: 'numeric', month: 'long' }) : '', s.start_time ? s.start_time.slice(0, 5) : '',
      s.group_no ? `${t('s_group')} ${s.group_no}` : '', s.start_order ? `${t('s_order')} ${s.start_order}` : ''].filter(Boolean);
    return parts.join(', ');
  }

  function render() {
    const d = D;
    const club = d.club ? d.club.name : t('s_individual');
    const discName = JO.lang === 'en' ? d.discipline_name_en : d.discipline_name_id;
    const payOpen = ['menunggu_pembayaran', 'menunggu_verifikasi', 'perlu_perbaikan'].includes(d.status);
    app.innerHTML = `<div class="page-head"><h1>${esc(t('s_title'))}</h1></div>
      <section class="card">
        <div class="row" style="justify-content:space-between"><span class="code" style="font-size:1.35rem;font-weight:800;color:var(--ink)">${esc(d.code)}</span>${JO.statusPill(d.status)}</div>
        <dl class="kv" style="margin-top:14px">
          <dt>${esc(t('q_disc') === 'q_disc' ? 'Disiplin' : t('q_disc'))}</dt><dd>${esc(discName)}</dd>
          <dt>${esc(t('s_club'))}</dt><dd>${esc(club)}</dd>
          <dt>${esc(t('s_contact'))}</dt><dd>${esc(d.contact.name)}<br><span class="small muted">${esc(d.contact.email)}</span></dd>
          <dt>${esc(t('s_created'))}</dt><dd>${esc(JO.fmtDateTime(d.created_at))}</dd>
        </dl>
      </section>
      ${d.status === 'dibatalkan' ? `<p class="note bad" style="margin-top:16px">${esc(t('s_cancelled'))}</p>` : ''}
      ${payOpen ? payCard(d) : ''}
      ${d.status === 'lunas' ? `<section class="card"><h2>${esc(t('s_pay'))}</h2><p class="note ok" style="margin:0">${esc(t('s_paid', { d: JO.fmtDateTime(d.paid_at) }))}</p></section>` : ''}
      ${d.team ? teamCard(d) : ''}
      <section class="card"><h2>${esc(t('s_athletes'))}</h2><div id="aths" class="stack"></div></section>`;
    const box = app.querySelector('#aths');
    d.athletes.forEach((a) => {
      const ents = d.entries.filter((e) => (e.athlete_ids || []).includes(a.id));
      const el = document.createElement('div');
      el.className = 'ath';
      el.innerHTML = `<div class="ath-head"><span class="bib">${esc(a.athlete_no || '')}</span><strong>${esc(a.full_name)}</strong></div>
        <div class="ath-body">
          <p class="small" style="margin-bottom:8px"><span class="pill ${a.doc_status === 'valid' ? 'ok' : a.doc_status === 'tidak_valid' ? 'bad' : ''}">${esc(t('s_doc_' + a.doc_status))}</span></p>
          ${a.nationality === 'WNI' && !a.has_bpjs ? `<p class="note warn small" style="margin:0 0 8px">${esc(t('s_bpjs_no'))}</p>` : ''}
          ${ents.map((e) => `<div style="padding:8px 0;border-top:1px solid var(--line)">
            <div><strong>${esc(catName(e))}</strong>${e.team_only ? ` <span class="pill gold">${esc(t('s_team_tim'))}</span>` : ''}${e.athlete_ids.length > 1 ? ` <span class="small muted">(${esc(e.athlete_ids.map((x) => (d.athletes.find((y) => y.id === x) || {}).full_name).join(' & '))})</span>` : ''}</div>
            ${e.priangan_requested ? `<div class="small">${esc(t('s_jabar'))}: ${esc(t('s_pri_' + e.priangan_status))}</div>` : ''}
            ${musicLine(e)}
            ${e.start ? `<div class="small"><strong>${esc(t('s_start'))}:</strong> ${esc(startText(e.start))}</div>` : ''}
            ${e.result ? `<div class="small" style="margin-top:4px"><strong>${esc(t('s_result'))}:</strong> ${e.result.rank ? esc(t('s_rank', { r: e.result.rank })) : e.team_only ? esc(t('s_team_only_res')) : '–'}
                ${e.result.medal ? ` <span class="medal ${e.result.medal}"></span> ${esc(t('medal_' + e.result.medal))}` : ''}
                ${e.result.mini ? ` <span class="pill">${esc(t('s_mini', { r: e.result.award_rank }))}</span>` : ''}
                ${e.result.total != null ? ` <span class="muted num">(${Number(e.result.total).toFixed(3)})</span>` : ''}
                ${e.result.capped ? `<br><span class="muted">${esc(t('s_capped'))}</span>` : ''}
                ${Object.keys(e.result.app_medals || {}).length ? `<br>${esc(t('s_app_medals'))}: ${Object.entries(e.result.app_medals).map(([k, m]) => `${esc(appName(k))} <span class="medal ${m}"></span> ${esc(t('medal_' + m))}`).join(', ')}` : ''}
</div>
              <div class="row" style="gap:6px;margin-top:8px;flex-wrap:wrap">
                <button class="btn btn-ghost btn-sm" data-cert="${e.id}" data-ath="${a.id}">${esc(t('s_cert'))}</button>
                ${Object.keys(e.result.app_medals || {}).map((k) => `<button class="btn btn-ghost btn-sm" data-cert="${e.id}" data-ath="${a.id}" data-app="${k}">${esc(t('s_cert_app', { a: appName(k) }))}</button>`).join('')}</div>` : ''}
          </div>`).join('')}
          <div style="margin-top:10px">${a.ticket_code ? `<button class="btn btn-dark btn-sm" data-ticket="${a.id}">${esc(t('s_ticket'))}</button>` : `<span class="small muted">${esc(t('s_ticket_wait'))}</span>`}</div>
        </div>`;
      box.appendChild(el);
    });
    box.querySelectorAll('[data-ticket]').forEach((b) => b.onclick = () => downloadTicket(b));
    box.querySelectorAll('[data-cert]').forEach((b) => b.onclick = () => downloadCert(b));
    app.querySelectorAll('[data-tcert]').forEach((b) => b.onclick = () => downloadTeamCert(b));
    const tmEl = app.querySelector('#s_timer');
    if (tmEl) {
      const end = new Date(d.expires_at).getTime();
      const hh = new Date(end).toLocaleTimeString(JO.lang === 'en' ? 'en-GB' : 'id-ID', { hour: '2-digit', minute: '2-digit' });
      const tick = () => {
        if (!document.body.contains(tmEl)) return clearInterval(iv);
        const left = Math.max(0, Math.round((end - Date.now()) / 1000));
        tmEl.textContent = t('s_timer', { m: Math.floor(left / 60) + ':' + String(left % 60).padStart(2, '0'), h: hh });
        if (!left) { clearInterval(iv); setTimeout(() => location.reload(), 3000); }
      };
      const iv = setInterval(tick, 1000); tick();
    }
    const up = app.querySelector('#proof_up');
    if (up) up.querySelector('input').onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      const st = up.querySelector('[data-st]'); st.innerHTML = `<span class="spinner"></span> ${esc(t('uploading'))}`;
      try {
        const u = await JO.uploadFile('bukti', file);
        D = await rpc('public_attach_proof', { p_code: code, p_token: token, p_path: u.path });
        render(); JO.toast(t('proof_done'));
      } catch (err) { st.textContent = err.message; st.style.color = 'var(--bad)'; }
    };
  }

  function payCard(d) {
    if (d.payment_method === 'manual') {
      return `<section class="card"><h2>${esc(t('s_pay'))}</h2><p class="note info" style="margin:0">${esc(t('pay_intl', { e: d.contact.email }))}</p></section>`;
    }
    const p = d.payment || {};
    const waiting = d.status === 'menunggu_verifikasi';
    return `<section class="card"><h2>${esc(t('s_pay'))}</h2>
      ${d.expires_at ? `<p class="note warn" id="s_timer"></p>` : ''}
      ${d.status === 'perlu_perbaikan' ? `<div class="note bad" style="margin-bottom:14px"><strong>${esc(t('s_pay_fix'))}.</strong> ${esc(d.verify_note || '')}</div>` : ''}
      ${waiting ? `<p class="note info">${esc(t('s_pay_waiting', { d: JO.fmtDateTime(d.proof_uploaded_at) }))}</p>` : ''}
      <div class="pay">
        <div class="qris">${p.qris_image_url ? `<img src="${esc(p.qris_image_url)}" alt="QRIS ${esc(p.qris_merchant || '')}">` : `<p class="small muted" style="margin:8px">${esc(t('pay_noqris'))}</p>`}</div>
        <div>
          ${JO.amountHtml(d.total_amount, d.unique_code)}
          <p style="margin:10px 0 6px;font-weight:700">${esc(t('pay_exact'))}</p>
          <p class="small muted">${esc(t('pay_why'))}</p>
          <table class="breakdown" style="margin:12px 0"><tbody>
            <tr><td>${esc(t(d.registrant_type === 'beregu' ? 'sum_team' : 'sum_fees'))}</td><td>${fmtRp(d.base_amount)}</td></tr>
            <tr><td>${esc(t('sum_uc'))}</td><td>${fmtRp(d.unique_code)}</td></tr>
          </tbody></table>
          ${p.note ? `<p class="small">${esc(p.note)}</p>` : ''}
          <p class="small muted">${esc(t('pay_deadline', { d: p.deadline_label || '12 November 2026' }))}</p>
        </div>
      </div>
      <hr class="divider">
      <h3>${esc(t('proof_title'))}</h3>
      <div class="upload" id="proof_up"><label class="btn ${waiting ? 'btn-ghost' : 'btn-dark'}" style="position:relative;overflow:hidden">${esc(waiting ? t('s_proof_again') : t('proof_title'))}
        <input type="file" accept="image/*,application/pdf" style="position:absolute;inset:0;opacity:0;cursor:pointer"></label><span class="small" data-st></span></div>
    </section>`;
  }

  const MUSIC_PILL = { belum: 'warn', menunggu: 'info', ok: 'ok', tidak_bisa: 'bad', tidak_perlu: '' };
  function musicLine(e) {
    if (D.discipline !== 'RG' || !e.music_status || e.music_status === 'tidak_perlu') return '';
    const link = `musik.html?k=${encodeURIComponent(D.code)}`;
    return `<div class="small" style="margin:4px 0"><strong>${esc(t('s_music'))}:</strong>
      <span class="pill ${MUSIC_PILL[e.music_status] || ''}">${esc(t('s_music_' + e.music_status))}</span>
      ${(e.apparatus || []).map((ap) => (e.music || {})[ap] ? `<br>${esc(appName(ap))}: <a class="mono-link" href="${esc(e.music[ap])}" target="_blank" rel="noopener">${esc(e.music[ap])}</a>` : `<br>${esc(appName(ap))}: <span class="bad-t">${esc(t('s_music_belum'))}</span>`).join('')}
      ${e.music_status === 'tidak_bisa' && e.music_note ? `<br><span class="bad-t">${esc(e.music_note)}</span>` : ''}
      ${e.music_changes > 0 ? `<br><span class="muted">${esc(t('s_music_used'))}</span>` : ''}
      ${D.status !== 'dibatalkan' ? `<br><a href="${link}">${esc(t('s_music_change'))}</a>` : ''}</div>`;
  }
  function teamCard(d) {
    const T = d.team; const R = T.result;
    const discName = JO.lang === 'en' ? d.discipline_name_en : d.discipline_name_id;
    const byId = {}; (R ? R.members : []).forEach((m) => { byId[m.athlete_id] = m; });
    return `<section class="card"><h2>${esc(t('s_team'))}: ${esc(T.name)}</h2>
      <p class="muted small" style="margin-top:-6px">${esc(discName)} · ${esc(T.level)}</p>
      ${R ? `<p style="margin:0 0 10px"><strong>${R.rank ? esc(t('s_team_rank', { r: R.rank })) : '–'}</strong>${R.trophy ? ` <span class="medal ${['emas', 'perak', 'perunggu'][R.rank - 1] || ''}"></span>` : ''}
          ${R.total != null ? ` <span class="muted num">${esc(t('s_team_total', { v: Number(R.total).toFixed(3) }))}</span>` : ''}</p>`
        : (d.status === 'lunas' ? `<p class="note info small">${esc(t('s_team_wait'))}</p>` : '')}
      <div class="tbl-wrap"><table class="tbl"><tbody>
        ${T.members.map((m) => { const r = byId[m.athlete_id];
          return `<tr><td><span class="bib">${esc(m.athlete_no || '')}</span> <strong>${esc(m.name)}</strong>
            <br><span class="small muted">${esc(JO.lang === 'en' ? m.category_name_en : m.category_name_id)}</span>
            <span class="pill ${m.team_only ? 'gold' : 'info'}">${esc(t(m.team_only ? 's_team_tim' : 's_team_ind'))}</span></td>
            <td class="r num">${r && r.total != null ? Number(r.total).toFixed(3) + (r.counted ? `<br><span class="small muted">${esc(t('s_team_counted'))}</span>` : '') : ''}
            ${R && R.trophy && m.cert_code ? `<br><button class="btn btn-ghost btn-sm" style="margin-top:6px" data-tcert="${m.athlete_id}">${esc(t('s_team_cert'))}</button>` : ''}</td></tr>`; }).join('')}
      </tbody></table></div>
      ${T.members.some((m) => !m.team_only) ? `<p class="small muted" style="margin:10px 0 0">${esc(t('s_team_ind_note'))}</p>` : ''}
    </section>`;
  }
  async function downloadTeamCert(btn) {
    const T = D.team; const m = T.members.find((x) => x.athlete_id === btn.dataset.tcert);
    const old = btn.textContent; btn.disabled = true; btn.textContent = t('s_making');
    try {
      const doc = await JO.certificatePdf({
        team: true, name: m.name, club: D.club ? D.club.name : '', discipline: D.discipline,
        category: `Beregu ${JO.DISC_NAME[D.discipline] || D.discipline} ${T.level}, tim ${T.name}`, rank: T.result.rank,
        cert_code: m.cert_code, signatories: D.signatories,
      });
      doc.save(`sertifikat-beregu-${m.athlete_no}-${m.name.replace(/[^a-z0-9]+/gi, '-')}.pdf`);
    } catch (err) { JO.toast(err.message, 'bad'); }
    finally { btn.disabled = false; btn.textContent = old; }
  }

  async function downloadTicket(btn) {
    const a = D.athletes.find((x) => x.id === btn.dataset.ticket);
    const ents = D.entries.filter((e) => (e.athlete_ids || []).includes(a.id));
    const old = btn.textContent; btn.disabled = true; btn.textContent = t('s_making');
    try {
      const doc = await JO.ticketPdf({
        discipline: D.discipline, athlete_no: a.athlete_no, name: a.full_name, club: D.club ? D.club.name : 'Perorangan',
        categories: ents.map((e) => e.category_name_id + (e.team_only && D.team ? ` (khusus beregu, tim ${D.team.name})` : '')),
        bpjs_missing: a.nationality === 'WNI' && !a.has_bpjs,
        photo: a.photo_thumb, registered_by: D.contact ? D.contact.name : '',
        start: ents.map((e) => startText(e.start)).filter(Boolean).join(' / '),
        ticket_code: a.ticket_code, submission_code: D.code,
      });
      doc.save(`AIC-JabarOpen2026-${a.athlete_no}-${a.full_name.replace(/[^a-z0-9]+/gi, '-')}.pdf`);
    } catch (e) { JO.toast(e.message, 'bad'); }
    finally { btn.disabled = false; btn.textContent = old; }
  }
  async function downloadCert(btn) {
    const e = D.entries.find((x) => x.id === btn.dataset.cert);
    const a = D.athletes.find((x) => x.id === btn.dataset.ath);
    const cert = (e.certificates || []).find((c) => c.athlete_id === a.id);
    const app = btn.dataset.app;
    const old = btn.textContent; btn.disabled = true; btn.textContent = t('s_making');
    try {
      const doc = await JO.certificatePdf(app ? {
        name: a.full_name, club: D.club ? D.club.name : 'Perorangan', discipline: D.discipline,
        apparatus: (D.apparatus_names && D.apparatus_names[app] ? D.apparatus_names[app].id : app), medal: e.result.app_medals[app],
        category: e.category_name_id, cert_code: cert.cert_code + '-' + app, signatories: D.signatories,
      } : {
        name: a.full_name, club: D.club ? D.club.name : 'Perorangan', discipline: D.discipline,
        category: e.category_name_id, rank: e.result.award_rank, medal: e.result.medal, mini: e.result.mini,
        priangan_rank: e.result.priangan_rank, priangan_medal: e.result.priangan_medal,
        cert_code: cert.cert_code, signatories: D.signatories,
      });
      doc.save(`sertifikat-${a.athlete_no}${app ? '-' + app : ''}-${a.full_name.replace(/[^a-z0-9]+/gi, '-')}.pdf`);
    } catch (err) { JO.toast(err.message, 'bad'); }
    finally { btn.disabled = false; btn.textContent = old; }
  }

  async function init() {
    JO.header('status.html'); JO.footer(); JO.applyI18n();
    // kamus dari halaman daftar dipakai ulang
    JO.addDict({
      q_disc: ['Disiplin', 'Discipline'], uploading: ['Mengunggah…', 'Uploading…'],
      proof_title: ['Unggah bukti pembayaran', 'Upload payment proof'],
      proof_done: ['Bukti terkirim. Panitia akan memverifikasi dan mengirim AIC lewat email.', 'Proof received. The committee will verify it and email the AIC.'],
      pay_exact: ['Ketik nominal persis, termasuk tiga digit terakhir.', 'Type the exact amount, including the last three digits.'],
      pay_why: ['Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Transfer dengan nominal berbeda akan memperlambat verifikasi.', 'The last three digits are a unique code that matches your payment to this registration. A different amount slows down verification.'],
      pay_noqris: ['Gambar QRIS sedang disiapkan panitia. Buka halaman ini lagi nanti.', 'The QRIS image is being prepared. Check this page again later.'],
      pay_deadline: ['Batas pembayaran: {d}', 'Payment deadline: {d}'],
      pay_intl: ['Atlet internasional membayar terpisah. Panitia akan menghubungi {e} dengan instruksi pembayaran.', 'International athletes pay separately. The committee will contact {e} with payment instructions.'],
      sum_fees: ['Biaya pendaftaran', 'Entry fees'], sum_team: ['Biaya beregu', 'Team fee'], sum_pri: ['Kategori Priangan', 'Priangan category'], sum_uc: ['Kode unik', 'Unique code'],
    });
    if (!code || !token) return finder();
    try { D = await rpc('public_get_submission', { p_code: code, p_token: token }); }
    catch (e) { return finder(e.hint === 'ERR_NOT_FOUND' ? t('s_notfound') : e.message); }
    render();
    JO.onLang(render);
  }
  init();
})();
