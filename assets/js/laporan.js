/* =====================================================================
   Jabar Open 2026 — Laporan pendaftaran (owner & superadmin)
   Modul terpisah: dimuat saat halaman Laporan pendaftaran dibuka.
   Satu panggilan console_report() -> PDF (grafik + temuan otomatis) dan
   Excel (semua tabel + daftar atlet lengkap). Data sampai saat diunduh.
   Fungsi pembangun (insights, buildPdf, buildXlsx) murni agar bisa diuji.
   ===================================================================== */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- label
  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };
  const ST = { lunas: 'Lunas', menunggu_verifikasi: 'Menunggu verifikasi', perlu_perbaikan: 'Bukti perlu diperbaiki', menunggu_pembayaran: 'Belum bayar', dibatalkan: 'Dibatalkan' };
  const PM = { qris: 'QRIS', transfer: 'Transfer massal', manual: 'Manual (WNA/khusus)' };
  const DOC = { valid: 'Valid', menunggu: 'Belum diperiksa', tidak_valid: 'Tidak valid' };
  const BLN = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
  const BLS = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  // ---------------------------------------------------------------- warna
  const C = {
    navy: [19, 40, 74], ink2: [52, 71, 106], muted: [91, 107, 136], faint: [138, 151, 173],
    line: [226, 232, 241], paper: [244, 246, 250], white: [255, 255, 255],
    gold: [228, 200, 125], goldD: [138, 106, 31],
    s1: [53, 99, 176],     // seri utama / putra / lunas
    s2: [224, 102, 47],    // putri
    s3: [212, 160, 32],    // menunggu / belum lunas
    ok: [27, 127, 71], warn: [154, 98, 0], bad: [180, 35, 24], info: [44, 76, 123],
    okL: [230, 245, 236], warnL: [253, 243, 220], badL: [253, 236, 234], infoL: [233, 239, 248],
  };

  // ---------------------------------------------------------------- format
  const n0 = (v) => Number(v || 0).toLocaleString('id-ID');
  const rp = (v) => 'Rp' + n0(Math.round(Number(v || 0)));
  const rpShort = (v) => {
    const x = Number(v || 0);
    if (x >= 1e9) return 'Rp' + (x / 1e9).toFixed(2).replace('.', ',') + ' M';
    if (x >= 1e6) return 'Rp' + (x / 1e6).toFixed(1).replace('.', ',') + ' jt';
    return rp(x);
  };
  const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
  const pct1 = (a, b) => (b ? ((a / b) * 100).toFixed(1).replace('.', ',') : '0');
  const wib = (d) => new Date(new Date(d).getTime() + 7 * 3600000);       // jam dinding WIB (dibaca dengan getUTC*)
  const fDate = (d) => { const x = wib(d); return `${x.getUTCDate()} ${BLN[x.getUTCMonth()]} ${x.getUTCFullYear()}`; };
  const fDateS = (d) => { const x = typeof d === 'string' && d.length === 10 ? new Date(d + 'T00:00:00Z') : wib(d); return `${x.getUTCDate()} ${BLS[x.getUTCMonth()]}`; };
  const fTime = (d) => { const x = wib(d); return String(x.getUTCHours()).padStart(2, '0') + '.' + String(x.getUTCMinutes()).padStart(2, '0'); };
  const fDT = (d) => (d ? `${fDate(d)}, ${fTime(d)} WIB` : '-');
  const stamp = (d) => { const x = wib(d); const p = (k) => String(k).padStart(2, '0'); return `${x.getUTCFullYear()}-${p(x.getUTCMonth() + 1)}-${p(x.getUTCDate())}-${p(x.getUTCHours())}${p(x.getUTCMinutes())}`; };
  const dayDiff = (from, to) => Math.ceil((new Date(to) - new Date(from)) / 86400000);
  const titleCase = (s) => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim().replace(/(^|[\s(/-])(\p{L})/gu, (m, a, b) => a + b.toUpperCase()).replace(/\bDki\b/g, 'DKI').replace(/\bDi\b/g, 'DI');
  const sum = (arr, k) => arr.reduce((a, x) => a + (Number(typeof k === 'function' ? k(x) : x[k]) || 0), 0);
  // nama klub untuk deteksi kemungkinan duplikat
  const clubKey = (s) => String(s || '').toLowerCase()
    .replace(/\b(gymnastics?|gymnastik|gimnastik|gymnastic|gym|club|klub|gc|academy|akademi)\b/g, ' ')
    .replace(/[^a-z0-9]/g, '');

  // ---------------------------------------------------------------- olah data
  function prepare(R) {
    const T = R.totals || {};
    const now = new Date(R.generated_at || Date.now());
    const daily = R.daily || [];
    const last7 = sum(daily.slice(-7), 'athletes');
    const prev7 = sum(daily.slice(-14, -7), 'athletes');
    const daysToDeadline = Math.max(0, dayDiff(now, R.deadline));
    const daysToEvent = Math.max(0, dayDiff(now, (R.event_start || '2026-12-12') + 'T00:00:00+07:00'));
    const perDay = last7 / 7;
    const projected = Math.round((T.athletes || 0) + perDay * daysToDeadline);
    const open = (R.payment && R.payment.open) || [];
    const pendingAthletes = sum(open, 'athletes');
    const oldestProofH = open.filter((o) => o.proof_at).reduce((m, o) => Math.max(m, (now - new Date(o.proof_at)) / 3600000), 0);
    const cats = R.categories || [];
    const used = cats.filter((c) => c.entries > 0);
    const empty = cats.filter((c) => !c.entries);
    const low = cats.filter((c) => c.entries > 0 && c.entries < 3);
    const aerRisk = cats.filter((c) => c.discipline === 'AER' && c.entries > 0 && (c.entries < 4 || c.clubs < 3));
    const capFull = cats.filter((c) => c.max_per_club && c.top_club >= c.max_per_club);
    const clubs = (R.clubs || []).filter((c) => c.name !== 'Tanpa klub');
    // kemungkinan klub ganda
    const groups = {};
    clubs.forEach((c) => { const k = clubKey(c.name); if (k.length >= 2) (groups[k] = groups[k] || []).push(c); });
    const dupes = Object.values(groups).filter((g) => g.length > 1);
    // provinsi
    const byProv = {};
    (R.regions || []).forEach((r) => { const p = titleCase(r.province); byProv[p] = (byProv[p] || 0) + r.athletes; });
    const provs = Object.entries(byProv).map(([province, athletes]) => ({ province, athletes })).sort((a, b) => b.athletes - a.athletes);
    const clubProv = {};
    clubs.forEach((c) => { const p = titleCase(c.province || (c.country && c.country !== 'Indonesia' ? 'Luar negeri' : 'Tidak diisi')); clubProv[p] = (clubProv[p] || 0) + 1; });
    // kab/kota digabung tanpa membedakan huruf besar/kecil
    const byKab = {};
    (R.regions || []).forEach((r) => {
      const k = titleCase(r.kab_kota) + '|' + titleCase(r.province);
      byKab[k] = byKab[k] || { kab_kota: titleCase(r.kab_kota), province: titleCase(r.province), athletes: 0 };
      byKab[k].athletes += r.athletes;
    });
    const kabs = Object.values(byKab).sort((a, b) => b.athletes - a.athletes);
    const jabar = byProv['Jawa Barat'] || 0;
    const top5 = sum(clubs.slice(0, 5), 'athletes');
    const comp = R.compliance || [];
    const bulk = R.bulk || [];
    return { T, now, last7, prev7, daysToDeadline, daysToEvent, perDay, projected, open, pendingAthletes, oldestProofH,
      cats, used, empty, low, aerRisk, capFull, clubs, dupes, provs, clubProv, kabs, jabar, top5, comp, bulk,
      docsWaiting: sum(comp, 'docs_waiting'), docsInvalid: sum(comp, 'docs_invalid'), noBpjs: sum(comp, 'no_bpjs'),
      musicOpen: sum(comp, (c) => c.music_waiting + c.music_missing + c.music_broken), prianganWaiting: sum(comp, 'priangan_waiting') };
  }

  // ---------------------------------------------------------------- temuan otomatis
  // level: ok | info | warn | bad. Setiap temuan boleh membawa tindak lanjut (act).
  function insights(R, P) {
    P = P || prepare(R);
    const T = P.T, out = [];
    const add = (level, text, act) => out.push({ level, text, act });
    const discs = R.by_discipline || [];

    // laju & proyeksi
    if (P.prev7 > 0) {
      const ch = Math.round(((P.last7 - P.prev7) / P.prev7) * 100);
      add(ch >= 0 ? 'ok' : 'warn', `${n0(P.last7)} atlet baru dalam 7 hari terakhir (termasuk hari ini), ${ch >= 0 ? 'naik' : 'turun'} ${Math.abs(ch)}% dibanding 7 hari sebelumnya (${n0(P.prev7)} atlet).`,
        ch < 0 && P.daysToDeadline > 0 ? `Dorong pendaftaran di sisa ${P.daysToDeadline} hari: unggahan pengingat batas ${fDate(R.deadline)} di Instagram dan pesan ke klub yang belum mendaftar.` : null);
    } else add('info', `${n0(P.last7)} atlet baru dalam 7 hari terakhir.`);
    if (P.daysToDeadline > 0) {
      add('info', `Pendaftaran ditutup dalam ${P.daysToDeadline} hari (${fDate(R.deadline)}, 23.59 WIB). Dengan laju 7 hari terakhir (sekitar ${P.perDay.toFixed(1).replace('.', ',')} atlet per hari), jumlah atlet diperkirakan mencapai sekitar ${n0(P.projected)} saat pendaftaran ditutup, belum termasuk draf pendaftaran massal.`);
    } else add('info', 'Masa pendaftaran sudah berakhir. Angka di laporan ini adalah angka akhir pendaftaran, kecuali ada koreksi panitia.');

    // pembayaran
    const paidPct = pct(T.athletes_paid, T.athletes);
    add(paidPct >= 95 ? 'ok' : paidPct >= 85 ? 'warn' : 'bad',
      `${paidPct}% atlet sudah lunas (${n0(T.athletes_paid)} dari ${n0(T.athletes)}). Dana masuk ${rp(T.paid_amount)}; tagihan yang belum lunas ${rp(T.outstanding)}.`);
    if (P.open.length) {
      const waitV = P.open.filter((o) => o.status === 'menunggu_verifikasi');
      const fix = P.open.filter((o) => o.status === 'perlu_perbaikan');
      const unpaid = P.open.filter((o) => o.status === 'menunggu_pembayaran');
      if (waitV.length) add(P.oldestProofH > 48 ? 'bad' : 'warn',
        `${waitV.length} pendaftaran (${n0(sum(waitV, 'athletes'))} atlet, ${rp(sum(waitV, 'amount'))}) menunggu verifikasi pembayaran. Bukti terlama sudah menunggu ${Math.round(P.oldestProofH)} jam.`,
        `Bendahara memverifikasi ${waitV.length} pembayaran di Konsol → Pendaftaran (filter Menunggu verifikasi)${P.oldestProofH > 48 ? '; ada yang melewati janji "1–2 hari kerja" di FAQ' : ''}.`);
      if (fix.length) add('warn', `${fix.length} pendaftaran (${n0(sum(fix, 'athletes'))} atlet) bukti bayarnya ditolak dan belum diperbaiki.`,
        `Hubungi penanggung jawab ${fix.map((o) => o.club).slice(0, 4).join(', ')}${fix.length > 4 ? ' dan lainnya' : ''} agar mengunggah ulang bukti bayar.`);
      if (unpaid.length) add('warn', `${unpaid.length} pendaftaran belum membayar sama sekali (${rp(sum(unpaid, 'amount'))}).`);
    }
    if (R.payment && R.payment.verify_hours != null) {
      const h = Number(R.payment.verify_hours);
      add(h <= 48 ? 'ok' : 'warn', `Rata-rata waktu verifikasi pembayaran ${String(h).replace('.', ',')} jam sejak bukti diunggah, ${h <= 48 ? 'masih sesuai' : 'melewati'} janji "1–2 hari kerja" di FAQ.`);
    }
    if (R.payment && R.payment.refund_due > 0) add('warn', `Ada dana yang perlu dikembalikan ke klub sebesar ${rp(R.payment.refund_due)} (penarikan atlet setelah lunas).`, 'Bendahara memproses pengembalian dana dan mencatatnya di Ledger.');

    // pendaftaran massal
    P.bulk.filter((b) => b.draft_rows > 0).forEach((b) => add('warn',
      `${b.label} punya ${n0(b.draft_rows)} atlet di lembar pendaftaran massal yang belum dikirim${b.expires_at ? `; kode berlaku sampai ${fDateS(b.expires_at)}` : ''}. Atlet ini belum terhitung di laporan.`,
      `Bendahara menghubungi ${b.label} agar mengirim lembar massal sebelum ${b.expires_at && new Date(b.expires_at) < new Date(R.deadline) ? fDateS(b.expires_at) : fDate(R.deadline)}, atau memperpanjang kodenya bila perlu.`));
    const notOpened = P.bulk.filter((b) => !b.opened_at);
    if (notOpened.length) add('info', `${notOpened.length} kode pendaftaran massal belum pernah dibuka klub: ${notOpened.map((b) => b.label).join(', ')}.`,
      `Tanyakan kepada ${notOpened.map((b) => b.label).join(', ')} apakah masih berencana mendaftar lewat jalur massal.`);
    const bulkOpen = P.bulk.filter((b) => b.batches_open > 0);
    if (bulkOpen.length) add('warn', `${bulkOpen.length} klub massal punya batch yang belum lunas (${rp(sum(bulkOpen, 'amount_open'))}).`, 'Bendahara menagih bukti transfer batch yang belum lunas (lebih dari 2×24 jam ditandai untuk ditindaklanjuti).');

    // disiplin & putra/putri
    const top = [...discs].sort((a, b) => b.athletes - a.athletes)[0];
    if (top && T.athletes) add('info', `${top.name} mendominasi dengan ${n0(top.athletes)} atlet (${pct(top.athletes, T.athletes)}% dari total). ${discs.filter((d) => d !== top).map((d) => `${d.name} ${n0(d.athletes)}`).join(', ')}.`);
    if (T.athletes) add('info', `Komposisi atlet: ${n0(T.female)} putri (${pct(T.female, T.athletes)}%) dan ${n0(T.male)} putra (${pct(T.male, T.athletes)}%). Putra hanya bertanding di Artistik Putra dan Aerobik.`);

    // kategori
    if (P.low.length) add('warn', `${P.low.length} kategori berisi kurang dari 3 peserta dan berisiko digabung: ${P.low.slice(0, 6).map((c) => `${c.name} (${c.entries})`).join('; ')}${P.low.length > 6 ? '; dan lainnya (lihat halaman Kategori)' : ''}.`,
      'Admin disiplin dan TD meninjau penggabungan kategori (Konsol → Pendaftaran → Pindah kategori) setelah pendaftaran ditutup.');
    if (P.aerRisk.length) add('warn', `${P.aerRisk.length} kategori Aerobik belum memenuhi syarat minimal 4 peserta dari 3 delegasi dan bisa menjadi eksibisi.`, 'Admin Aerobik menandai Eksibisi di Konsol → Kategori bila sampai batas pendaftaran tetap kurang.');
    if (P.empty.length) add('info', `${P.empty.length} dari ${P.cats.length} kategori aktif belum punya peserta: ${P.empty.map((c) => c.name).slice(0, 6).join('; ')}${P.empty.length > 6 ? '; dan lainnya' : ''}.`);
    if (P.capFull.length) add('info', `${P.capFull.length} kategori sudah mencapai batas atlet per klub untuk setidaknya satu klub (${P.capFull.slice(0, 3).map((c) => c.name).join('; ')}).`);

    // klub & wilayah
    if (P.clubs.length) {
      add('info', `${n0(P.clubs.length)} klub dari ${P.provs.filter((p) => p.province !== 'Tidak Diisi').length} provinsi. Lima klub terbesar menyumbang ${pct(P.top5, T.athletes)}% atlet; terbesar ${P.clubs[0].name} (${n0(P.clubs[0].athletes)} atlet).`);
      add('info', `${pct(P.jabar, T.athletes)}% atlet berdomisili di Jawa Barat (${n0(P.jabar)}); sisanya dari luar Jawa Barat, terbanyak ${P.provs.filter((p) => p.province !== 'Jawa Barat')[0] ? P.provs.filter((p) => p.province !== 'Jawa Barat')[0].province : '-'}.`);
    }
    if (P.dupes.length) add('warn', `Kemungkinan klub tercatat ganda: ${P.dupes.map((g) => g.map((c) => c.name).join(' / ')).join('; ')}. Hitungan per klub dan tabel medali bisa terpecah.`,
      'Admin memeriksa dan menggabungkan klub ganda di Konsol → Klub → "…" → Gabungkan ke klub lain.');
    const pending = P.clubs.filter((c) => c.pending > 0).sort((a, b) => b.outstanding - a.outstanding);
    if (pending.length) add('warn', `Klub dengan atlet belum lunas: ${pending.slice(0, 5).map((c) => `${c.name} (${c.pending} atlet, ${rp(c.outstanding)})`).join('; ')}.`);

    // dokumen & data anak
    if (P.docsWaiting) add('warn', `${n0(P.docsWaiting)} atlet dokumennya belum diperiksa.`, `Admin disiplin memeriksa dokumen ${n0(P.docsWaiting)} atlet (Ringkasan → Perlu tindakan).`);
    if (P.docsInvalid) add('bad', `${n0(P.docsInvalid)} atlet dokumennya ditandai tidak valid.`, 'Hubungi klub terkait untuk mengganti dokumen.');
    if (P.noBpjs) add('info', `${n0(P.noBpjs)} atlet (${pct(P.noBpjs, T.athletes)}%) belum mengunggah BPJS Ketenagakerjaan dan wajib membawanya ke meja panitia di venue.`,
      `Siapkan meja pemeriksaan BPJS di pintu sayap barat dengan daftar ${n0(P.noBpjs)} atlet (tab Atlet di Excel, kolom BPJS TK).`);
    if (P.musicOpen) add('warn', `${n0(P.musicOpen)} nomor Ritmik tautan musiknya belum beres.`, 'Admin Ritmik memeriksa tautan di Konsol → Musik Ritmik.');
    if (P.prianganWaiting) add('warn', `${n0(P.prianganWaiting)} nomor Priangan menunggu pemeriksaan syarat domisili.`);
    if (T.under10) add('info', `${n0(T.under10)} atlet (${pct(T.under10, T.athletes)}%) berusia di bawah 10 tahun. Foto mereka tidak ditampilkan di direktori atlet publik.`);
    if (T.people && T.people < T.athletes) add('info', `${n0(T.athletes - T.people)} atlet terdaftar di lebih dari satu disiplin (${n0(T.people)} orang unik).`);
    if (T.wna) add('info', `${n0(T.wna)} atlet WNA terdaftar.`);
    if (T.teams) add(T.teams_paid === T.teams ? 'ok' : 'warn', `${n0(T.teams)} tim beregu Artistik Putri, ${n0(T.teams_paid)} sudah lunas.`);
    return out;
  }

  // =====================================================================
  //  PDF
  // =====================================================================
  const PW = 210, PH = 297, M = 14, CW = PW - 2 * M, BOTTOM = PH - 16;

  function makePdf(jsPDF, R, logos) {
    const P = prepare(R);
    const INS = insights(R, P);
    const doc = new jsPDF({ unit: 'mm', format: 'a4', orientation: 'portrait', compress: true });
    let y = 0;
    const fill = (c) => doc.setFillColor(c[0], c[1], c[2]);
    const stroke = (c) => doc.setDrawColor(c[0], c[1], c[2]);
    const ink = (c) => doc.setTextColor(c[0], c[1], c[2]);
    const font = (style, size) => { doc.setFont('helvetica', style); doc.setFontSize(size); };
    const clean = (s) => String(s == null ? '' : s).replace(/→/g, '>').replace(/≈/g, '±');
    const text = (s, x, yy, o) => doc.text(Array.isArray(s) ? s.map(clean) : clean(s), x, yy, o);
    const wrap = (s, w) => doc.splitTextToSize(clean(s), w);
    const lh = (size) => size * 0.42;

    // ---- kerangka halaman
    function header(title, sub) {
      fill(C.navy); doc.rect(0, 0, PW, 15, 'F');
      fill(C.gold); doc.rect(0, 15, PW, 0.9, 'F');
      if (logos && logos.jo) { const h = 9, w = h * logos.jo.w / logos.jo.h; doc.addImage(logos.jo.data, 'PNG', M, 3, w, h, 'jo', 'FAST'); }
      font('bold', 10.5); ink(C.white); text(title, PW - M, 7.4, { align: 'right' });
      font('normal', 7.2); doc.setTextColor(168, 191, 224); text(sub || `Laporan pendaftaran · per ${fDT(R.generated_at)}`, PW - M, 11.6, { align: 'right' });
      y = 24;
    }
    function page(title, sub) { doc.addPage('a4', 'portrait'); header(title, sub); }
    function need(h, title) { if (y + h > BOTTOM) page(title || curTitle); }
    let curTitle = '';
    function section(t, intro) {
      need(16 + (intro ? 8 : 0));
      font('bold', 12.5); ink(C.navy); text(t, M, y + 4); y += 7;
      fill(C.gold); doc.rect(M, y, 14, 0.8, 'F'); y += 4;
      if (intro) { font('normal', 8.4); ink(C.muted); const L = wrap(intro, CW); text(L, M, y + 2.6); y += L.length * lh(8.4) + 3; }
    }

    // ---- komponen
    function kpi(x, yy, w, h, label, value, sub, tone) {
      fill(C.paper); doc.roundedRect(x, yy, w, h, 2, 2, 'F');
      fill(tone || C.s1); doc.rect(x, yy + 2, 1, h - 4, 'F');
      font('normal', 7.4); ink(C.muted); text(label, x + 4, yy + 5.6);
      font('bold', 15); ink(C.navy); text(value, x + 4, yy + 13.4);
      if (sub) { font('normal', 7); ink(C.muted); text(wrap(sub, w - 7)[0], x + 4, yy + h - 3); }
    }
    // tabel sederhana dengan pemutusan halaman dan baris kepala berulang
    function table(cols, rows, o) {
      o = o || {};
      const fs = o.fs || 7.6, pad = 1.6, rowH0 = lh(fs) + 2 * pad + 0.6;
      const tw = sum(cols, 'w'); const scale = (o.width || CW) / tw;
      cols = cols.map((c) => ({ ...c, w: c.w * scale }));
      const head = () => {
        font('bold', fs - 0.2);
        const HL = cols.map((c) => wrap(c.h, c.w - 2 * pad));
        const hh = Math.max(...HL.map((L) => L.length)) * lh(fs) + 2 * pad + 1.2;
        fill(C.navy); doc.rect(M, y, o.width || CW, hh, 'F');
        ink(C.white);
        let x = M; cols.forEach((c, j) => { text(HL[j], c.align === 'right' ? x + c.w - pad : x + pad, y + pad + lh(fs) + 0.3, { align: c.align === 'right' ? 'right' : 'left', lineHeightFactor: 1.15 }); x += c.w; });
        y += hh;
      };
      need(rowH0 * 3); head();
      rows.forEach((r, i) => {
        const cells = cols.map((c) => { const v = c.fn ? c.fn(r) : r[c.k]; return c.wrap ? wrap(v == null ? '' : v, c.w - 2 * pad) : [String(v == null ? '' : v)]; });
        const lines = Math.max(...cells.map((L) => L.length));
        const h = lines * lh(fs) + 2 * pad + 0.6;
        if (y + h > BOTTOM) { page(curTitle); head(); }
        if (r && r._fill) { fill(r._fill); doc.rect(M, y, o.width || CW, h, 'F'); }
        else if (i % 2 === 1) { fill(C.paper); doc.rect(M, y, o.width || CW, h, 'F'); }
        font(r && r._bold ? 'bold' : 'normal', fs); ink(C.navy);
        let x = M;
        cols.forEach((c, j) => {
          const L = cells[j].map((s) => (c.wrap ? s : (doc.getTextWidth(s) > c.w - 2 * pad ? fitText(s, c.w - 2 * pad) : s)));
          if (c.bar) {
            const [bv, bm] = c.bar(r); const bw = c.w - 2 * pad, by = y + pad + lh(fs) - 2.3;
            fill(C.line); doc.rect(x + pad, by, bw, 2.6, 'F');
            if (bv > 0) { fill(C.s1); doc.rect(x + pad, by, Math.max(0.6, (bv / bm) * bw), 2.6, 'F'); }
            x += c.w; return;
          }
          if (c.color) { const col = c.color(r); if (col) ink(col); }
          text(L, c.align === 'right' ? x + c.w - pad : x + pad, y + pad + lh(fs), { align: c.align === 'right' ? 'right' : 'left', lineHeightFactor: 1.15 });
          ink(C.navy); x += c.w;
        });
        y += h;
      });
      stroke(C.line); doc.setLineWidth(0.2); doc.line(M, y, M + (o.width || CW), y);
      y += 4;
    }
    function fitText(s, w) { let t = s; while (t.length > 1 && doc.getTextWidth(t + '…') > w) t = t.slice(0, -1); return t + '…'; }
    function legend(items, x, yy) {
      font('normal', 7.4);
      items.forEach(([label, col]) => { fill(col); doc.roundedRect(x, yy - 2.4, 3, 3, 0.6, 0.6, 'F'); ink(C.ink2); text(label, x + 4.2, yy); x += 4.2 + doc.getTextWidth(label) + 6; });
    }
    // grafik batang vertikal (satu seri, atau dua seri bertumpuk: [nilai bawah, nilai atas])
    function vbars(x, yy, w, h, data, o) {
      o = o || {};
      const max = Math.max(1, ...data.map((d) => (d.v2 || 0) + d.v)) * 1.15;
      stroke(C.line); doc.setLineWidth(0.2);
      for (let g = 0; g <= 3; g++) { const gy = yy + h - (h * g) / 3; doc.line(x, gy, x + w, gy); }
      const slot = w / data.length, bw = Math.min(o.maxBar || 14, slot * 0.62);
      data.forEach((d, i) => {
        const bx = x + i * slot + (slot - bw) / 2;
        const h1 = (d.v / max) * h, h2 = ((d.v2 || 0) / max) * h;
        if (h1 > 0) { fill(o.c1 || C.s1); doc.rect(bx, yy + h - h1, bw, h1, 'F'); }
        if (h2 > 0) { fill(o.c2 || C.s3); doc.rect(bx, yy + h - h1 - h2 - 0.5, bw, h2, 'F'); }
        const tot = d.v + (d.v2 || 0);
        font('bold', 6.8); ink(C.navy); if (tot > 0 || o.zero) text(n0(tot), bx + bw / 2, yy + h - h1 - h2 - 1.5, { align: 'center' });
        font('normal', 6.4); ink(C.muted); text(wrap(d.label, slot - 0.5), bx + bw / 2, yy + h + 3.4, { align: 'center' });
      });
    }
    // batang horizontal bertumpuk: rows [{label, parts:[v1,v2], right}]
    function hbars(x, yy, w, rows, o) {
      o = o || {};
      const labelW = o.labelW || 52, barW = w - labelW - (o.rightW || 22), rowH = o.rowH || 6.2;
      const max = Math.max(1, ...rows.map((r) => sum(r.parts, (v) => v)));
      rows.forEach((r, i) => {
        const ry = yy + i * rowH;
        font('normal', 7.4); ink(C.navy); text(fitText2(r.label, labelW - 2), x, ry + rowH / 2 + 1.2);
        let bx = x + labelW;
        r.parts.forEach((v, j) => { const bw = (v / max) * barW; if (bw > 0) { fill((o.colors || [C.s1, C.s3])[j]); doc.rect(bx, ry + 1, bw, rowH - 2.2, 'F'); bx += bw + (bw > 0.6 ? 0.5 : 0); } });
        font('bold', 7.2); ink(C.navy); text(r.right != null ? String(r.right) : n0(sum(r.parts, (v) => v)), bx + 1.6, ry + rowH / 2 + 1.2);
      });
      return yy + rows.length * rowH;
    }
    function fitText2(s, w) { return doc.getTextWidth(s) > w ? fitText(s, w) : s; }
    // donat dua bagian (kipas segitiga)
    function donut(cx, cy, r, parts, centerTop, centerSub) {
      const total = sum(parts, (p) => p.v) || 1; let a0 = -Math.PI / 2;
      parts.forEach((p) => {
        const a1 = a0 + (p.v / total) * Math.PI * 2; fill(p.c);
        const steps = Math.max(2, Math.ceil(((a1 - a0) / (Math.PI * 2)) * 120));
        for (let s = 0; s < steps; s++) {
          const t0 = a0 + ((a1 - a0) * s) / steps, t1 = a0 + ((a1 - a0) * (s + 1)) / steps + 0.004;
          doc.triangle(cx, cy, cx + r * Math.cos(t0), cy + r * Math.sin(t0), cx + r * Math.cos(t1), cy + r * Math.sin(t1), 'F');
        }
        a0 = a1;
      });
      fill(C.white); doc.circle(cx, cy, r * 0.62, 'F');
      font('bold', 12); ink(C.navy); text(centerTop, cx, cy + 1, { align: 'center' });
      if (centerSub) { font('normal', 6.6); ink(C.muted); text(centerSub, cx, cy + 4.6, { align: 'center' }); }
    }
    const toneOf = (lv) => ({ ok: [C.ok, C.okL, 'Baik'], info: [C.info, C.infoL, 'Info'], warn: [C.warn, C.warnL, 'Perhatian'], bad: [C.bad, C.badL, 'Mendesak'] }[lv]);
    function insightList(list, withActs) {
      list.forEach((it) => {
        const [col, bg, tag] = toneOf(it.level);
        font('normal', 8.3);
        const L = wrap(it.text, CW - 26);
        const h = L.length * lh(8.3) + 4;
        need(h + 2);
        fill(bg); doc.roundedRect(M, y, CW, h, 1.6, 1.6, 'F');
        fill(col); doc.rect(M, y, 1.1, h, 'F');
        font('bold', 6.8); ink(col); text(tag.toUpperCase(), M + 3.5, y + 4.3);
        font('normal', 8.3); ink(C.navy); text(L, M + 23, y + 4.3, { lineHeightFactor: 1.15 });
        y += h + 1.6;
      });
    }

    // ================================================================ HALAMAN 1: RINGKASAN
    curTitle = 'Ringkasan eksekutif';
    fill(C.navy); doc.rect(0, 0, PW, 62, 'F');
    fill(C.gold); doc.rect(0, 62, PW, 1.4, 'F');
    // titik halftone dekoratif
    fill([38, 62, 102]);
    for (let r = 0; r < 9; r++) for (let c = 0; c < 16; c++) { const rr = 0.25 + (c / 16) * 0.75; doc.circle(PW - 80 + c * 5, 6 + r * 5.6, rr, 'F'); }
    let lx = M;
    if (logos && logos.jo) { const h = 20, w = h * logos.jo.w / logos.jo.h; doc.addImage(logos.jo.data, 'PNG', lx, 9, w, h, 'jo', 'FAST'); lx += w + 4; }
    if (logos && logos.gi) { stroke([90, 115, 160]); doc.setLineWidth(0.35); doc.line(lx, 11, lx, 27); const w = 26, h = w * logos.gi.h / logos.gi.w; doc.addImage(logos.gi.data, 'PNG', lx + 4, 19 - h / 2, w, h, 'gi', 'FAST'); }
    font('normal', 8); doc.setTextColor(168, 191, 224); text('LAPORAN PENDAFTARAN ATLET', M, 39);
    font('bold', 19); ink(C.white); text('Jabar Open 2026', M, 47.5);
    font('normal', 8.6); doc.setTextColor(214, 224, 240);
    text(`Data sampai ${fDT(R.generated_at)} · Gymnasium Arcamanik, 12–20 Desember 2026`, M, 54);
    font('normal', 7.2); doc.setTextColor(168, 191, 224); text(`Diunduh dari Konsol Panitia oleh ${R.generated_by || '-'}`, M, 58.6);
    // hitung mundur
    const cd = [[P.daysToDeadline ? `H-${P.daysToDeadline}` : 'Ditutup', `batas pendaftaran ${fDateS(R.deadline)}`], [P.daysToEvent ? `H-${P.daysToEvent}` : 'Berjalan', 'kejuaraan dimulai 12 Des']];
    cd.forEach(([a, b], i) => {
      const bx = PW - M - 36, by = 30 + i * 15;
      fill([34, 58, 98]); doc.roundedRect(bx, by, 36, 12.5, 1.6, 1.6, 'F');
      font('bold', 12); ink(C.gold); text(a, bx + 3, by + 6.8);
      font('normal', 6.4); doc.setTextColor(214, 224, 240); text(b, bx + 3, by + 10.6);
    });
    y = 70;
    const T = P.T, kw = (CW - 9) / 4;
    kpi(M, y, kw, 21, 'Atlet terdaftar', n0(T.athletes), `${n0(T.submissions)} pendaftaran · ${n0(T.entries)} nomor`);
    kpi(M + (kw + 3), y, kw, 21, 'Atlet lunas', n0(T.athletes_paid), `${pct1(T.athletes_paid, T.athletes)}% dari terdaftar`, C.ok);
    kpi(M + 2 * (kw + 3), y, kw, 21, 'Belum lunas', n0(T.athletes - T.athletes_paid), `${P.open.length} pendaftaran terbuka`, C.s3);
    kpi(M + 3 * (kw + 3), y, kw, 21, 'Klub', n0(P.clubs.length), `${P.provs.length} provinsi asal atlet`, C.info);
    y += 24;
    kpi(M, y, kw, 21, 'Dana masuk (lunas)', rpShort(T.paid_amount), rp(T.paid_amount), C.ok);
    kpi(M + (kw + 3), y, kw, 21, 'Tagihan belum lunas', rpShort(T.outstanding), rp(T.outstanding), C.s3);
    kpi(M + 2 * (kw + 3), y, kw, 21, 'Putri / Putra', `${n0(T.female)} / ${n0(T.male)}`, `${pct(T.female, T.athletes)}% putri`, C.s2);
    kpi(M + 3 * (kw + 3), y, kw, 21, 'Tim beregu', n0(T.teams), `${n0(T.teams_paid)} lunas`, C.info);
    y += 28;
    section('Temuan utama', 'Ditulis otomatis dari data konsol saat laporan diunduh.');
    const order = { bad: 0, warn: 1, ok: 2, info: 3 };
    const sorted = [...INS].sort((a, b) => order[a.level] - order[b.level]);
    insightList(sorted);
    const acts = sorted.filter((x) => x.act);
    if (acts.length) {
      y += 2; section('Tindak lanjut yang disarankan');
      acts.forEach((a, i) => {
        font('normal', 8.3); const L = wrap(a.act, CW - 9); const h = L.length * lh(8.3) + 2.4;
        need(h);
        fill(C.navy); doc.circle(M + 2.4, y + 1.9, 2.3, 'F'); font('bold', 7); ink(C.white); text(String(i + 1), M + 2.4, y + 3, { align: 'center' });
        font('normal', 8.3); ink(C.navy); text(L, M + 7.5, y + 3, { lineHeightFactor: 1.15 }); y += h + 1.4;
      });
    }

    // ================================================================ TREN & DISIPLIN
    curTitle = 'Tren pendaftaran & disiplin';
    page(curTitle);
    section('Tren pendaftaran', 'Atlet dihitung pada tanggal pendaftarannya dikirim (WIB). Batang biru = sudah lunas; batang kuning = belum lunas.');
    const wk = (R.weekly || []).map((w) => ({ label: `${fDateS(w.week)}`, v: w.paid, v2: w.athletes - w.paid }));
    font('bold', 8.4); ink(C.navy); text('Atlet per minggu (Senin–Minggu)', M, y + 2);
    legend([['Lunas', C.s1], ['Belum lunas', C.s3]], M + CW - 52, y + 2);
    vbars(M, y + 6, CW, 46, wk, { maxBar: 16 });
    y += 62;
    const dd = (R.daily || []).map((d) => ({ label: fDateS(d.day), v: d.athletes }));
    font('bold', 8.4); ink(C.navy); text('Atlet per hari, 14 hari terakhir', M, y + 2);
    font('normal', 7.4); ink(C.muted); text(`7 hari terakhir: ${n0(P.last7)} atlet · 7 hari sebelumnya: ${n0(P.prev7)} atlet`, M + CW, y + 2, { align: 'right' });
    vbars(M, y + 6, CW, 38, dd, { maxBar: 8, zero: true });
    y += 54;

    section('Per disiplin');
    const discs = R.by_discipline || [];
    font('bold', 8.4); ink(C.navy); text('Atlet per disiplin', M, y + 2);
    legend([['Lunas', C.s1], ['Belum lunas', C.s3]], M + CW - 52, y + 2); y += 5;
    y = hbars(M, y, CW, discs.map((d) => ({ label: d.name, parts: [d.athletes_paid, d.athletes_pending], right: `${n0(d.athletes)} (${pct(d.athletes, T.athletes)}%)` })), { labelW: 34, rightW: 24 }) + 5;
    const totRow = { name: 'Total', submissions: T.submissions, athletes: T.athletes, athletes_paid: T.athletes_paid, athletes_pending: T.athletes - T.athletes_paid, male: T.male, female: T.female, entries: T.entries, teams: T.teams, clubs: P.clubs.length, categories_used: P.used.length, categories_total: P.cats.length, paid_amount: T.paid_amount, outstanding: T.outstanding, _bold: true, _fill: C.infoL };
    table([
      { h: 'Disiplin', w: 26, k: 'name' }, { h: 'Pendaftaran', w: 15, k: 'submissions', align: 'right' }, { h: 'Atlet', w: 11, k: 'athletes', align: 'right' },
      { h: 'Lunas', w: 11, k: 'athletes_paid', align: 'right' }, { h: 'Belum', w: 11, k: 'athletes_pending', align: 'right' },
      { h: 'Putri', w: 10, k: 'female', align: 'right' }, { h: 'Putra', w: 10, k: 'male', align: 'right' }, { h: 'Nomor', w: 11, k: 'entries', align: 'right' },
      { h: 'Tim', w: 8, k: 'teams', align: 'right' }, { h: 'Klub', w: 9, k: 'clubs', align: 'right' }, { h: 'Kategori terisi', w: 16, fn: (r) => `${r.categories_used}/${r.categories_total}`, align: 'right' },
      { h: 'Dana masuk (Rp)', w: 22, fn: (r) => n0(r.paid_amount), align: 'right' }, { h: 'Belum lunas (Rp)', w: 20, fn: (r) => n0(r.outstanding), align: 'right' },
    ], [...discs, totRow], { fs: 7.2 });
    font('normal', 7); ink(C.muted);
    text(wrap('Satu atlet yang mendaftar di dua disiplin dihitung sekali di setiap disiplin. "Nomor" = jumlah nomor lomba aktif (pasangan Aerobik dihitung satu nomor).', CW), M, y); y += 8;

    // ================================================================ PUTRA/PUTRI & USIA
    curTitle = 'Putra & putri, usia';
    page(curTitle);
    section('Putra dan putri');
    donut(M + 24, y + 22, 20, [{ v: T.female, c: C.s2 }, { v: T.male, c: C.s1 }], n0(T.athletes), 'atlet');
    legend([[`Putri ${n0(T.female)} (${pct(T.female, T.athletes)}%)`, C.s2]], M + 2, y + 50);
    legend([[`Putra ${n0(T.male)} (${pct(T.male, T.athletes)}%)`, C.s1]], M + 2, y + 55);
    const gx = M + 58;
    font('bold', 8.4); ink(C.navy); text('Per disiplin', gx, y + 2);
    legend([['Putri', C.s2], ['Putra', C.s1]], gx + 70, y + 2);
    hbars(gx, y + 6, CW - 58, discs.map((d) => ({ label: d.name, parts: [d.female, d.male], right: `${n0(d.female)} / ${n0(d.male)}` })), { labelW: 30, rightW: 18, colors: [C.s2, C.s1], rowH: 8 });
    y += 64;
    section('Usia atlet', 'Usia kompetisi = 2026 dikurangi tahun lahir.');
    const ages = R.ages || [];
    legend([['Putri', C.s2], ['Putra', C.s1]], M + CW - 40, y - 2);
    vbars(M, y + 2, CW, 48, ages.map((a) => ({ label: `${a.age} th`, v: a.female, v2: a.male })), { c1: C.s2, c2: C.s1, maxBar: 9 });
    y += 60;
    const bands = [['4 th ke bawah', (a) => a <= 4], ['5–6 th', (a) => a >= 5 && a <= 6], ['7–8 th', (a) => a >= 7 && a <= 8], ['9–10 th', (a) => a >= 9 && a <= 10], ['11–12 th', (a) => a >= 11 && a <= 12], ['13–15 th', (a) => a >= 13 && a <= 15], ['16 th ke atas', (a) => a >= 16]];
    table([{ h: 'Kelompok usia', w: 30, k: 'b' }, { h: 'Putri', w: 14, k: 'f', align: 'right' }, { h: 'Putra', w: 14, k: 'm', align: 'right' }, { h: 'Total', w: 14, k: 't', align: 'right' }, { h: '% dari atlet', w: 16, k: 'p', align: 'right' }],
      bands.map(([b, fn]) => { const f = sum(ages.filter((a) => fn(a.age)), 'female'), m = sum(ages.filter((a) => fn(a.age)), 'male'); return { b, f, m, t: f + m, p: pct1(f + m, T.athletes) + '%' }; }), { width: CW * 0.62 });

    // ================================================================ PEMBAYARAN
    curTitle = 'Pembayaran';
    page(curTitle);
    section('Status pembayaran', 'Lunas = sudah diverifikasi bendahara. Menunggu verifikasi = bukti sudah diunggah. Bukti perlu diperbaiki = bukti ditolak. Belum bayar = tagihan tanpa bukti (pendaftaran QRIS tanpa bukti terhapus otomatis setelah 15 menit).');
    donut(M + 24, y + 22, 20, [{ v: T.athletes_paid, c: C.s1 }, { v: T.athletes - T.athletes_paid, c: C.s3 }], pct(T.athletes_paid, T.athletes) + '%', 'atlet lunas');
    legend([[`Lunas ${n0(T.athletes_paid)} atlet`, C.s1]], M + 2, y + 50);
    legend([[`Belum lunas ${n0(T.athletes - T.athletes_paid)} atlet`, C.s3]], M + 2, y + 55);
    const sy = y; y += 1;
    const bs = ((R.payment && R.payment.by_status) || []).slice().sort((a, b) => (a.status === 'lunas' ? 0 : 1) - (b.status === 'lunas' ? 0 : 1) || b.amount - a.amount);
    const saveM = y;
    // tabel status di kolom kanan
    const tx0 = M + 58;
    (function () {
      const cols = [{ h: 'Status', w: 34, fn: (r) => ST[r.status] || r.status }, { h: 'Metode', w: 26, fn: (r) => PM[r.method] || r.method }, { h: 'Daftar', w: 12, k: 'submissions', align: 'right' }, { h: 'Atlet', w: 11, k: 'athletes', align: 'right' }, { h: 'Nilai (Rp)', w: 24, fn: (r) => n0(r.amount), align: 'right' }];
      const ow = CW - 58; const scale = ow / sum(cols, 'w');
      let yy = saveM; fill(C.navy); doc.rect(tx0, yy, ow, 6, 'F'); font('bold', 7.2); ink(C.white);
      let x = tx0; cols.forEach((c) => { const w = c.w * scale; text(c.h, c.align === 'right' ? x + w - 1.6 : x + 1.6, yy + 4.1, { align: c.align === 'right' ? 'right' : 'left' }); x += w; }); yy += 6;
      [...bs, { status: 'Total', method: '', submissions: sum(bs, 'submissions'), athletes: sum(bs, 'athletes'), amount: sum(bs, 'amount'), _t: true }].forEach((r, i) => {
        if (r._t) { fill(C.infoL); doc.rect(tx0, yy, ow, 6, 'F'); } else if (i % 2) { fill(C.paper); doc.rect(tx0, yy, ow, 6, 'F'); }
        font(r._t ? 'bold' : 'normal', 7.2); ink(C.navy); x = tx0;
        cols.forEach((c) => { const w = c.w * scale; const v = r._t && c.h === 'Status' ? 'Total' : r._t && c.h === 'Metode' ? '' : (c.fn ? c.fn(r) : r[c.k]); text(String(v), c.align === 'right' ? x + w - 1.6 : x + 1.6, yy + 4.1, { align: c.align === 'right' ? 'right' : 'left' }); x += w; });
        yy += 6;
      });
      if (R.payment && R.payment.verify_hours != null) { font('normal', 7.2); ink(C.muted); text(`Rata-rata waktu verifikasi: ${String(R.payment.verify_hours).replace('.', ',')} jam sejak bukti diunggah.`, tx0, yy + 4); yy += 6; }
      if (R.payment && R.payment.refund_due > 0) { font('bold', 7.2); ink(C.bad); text(`Dana perlu dikembalikan: ${rp(R.payment.refund_due)}`, tx0, yy + 4); yy += 6; }
      y = Math.max(sy + 60, yy + 4);
    })();
    section('Per disiplin');
    table([{ h: 'Disiplin', w: 30, k: 'name' }, { h: 'Atlet lunas', w: 18, k: 'athletes_paid', align: 'right' }, { h: 'Atlet belum', w: 18, k: 'athletes_pending', align: 'right' }, { h: '% lunas', w: 14, fn: (r) => pct(r.athletes_paid, r.athletes) + '%', align: 'right' }, { h: 'Dana masuk (Rp)', w: 28, fn: (r) => n0(r.paid_amount), align: 'right' }, { h: 'Belum lunas (Rp)', w: 28, fn: (r) => n0(r.outstanding), align: 'right' }], discs, { fs: 7.4 });
    section('Pendaftaran yang belum lunas', P.open.length ? 'Urut dari yang paling lama. Jam tunggu dihitung sejak bukti bayar diunggah.' : null);
    if (P.open.length) {
      table([{ h: 'Kode', w: 24, k: 'code' }, { h: 'Klub', w: 34, k: 'club', wrap: true }, { h: 'Penanggung jawab', w: 28, k: 'contact', wrap: true }, { h: 'Disiplin', w: 12, k: 'discipline' }, { h: 'Atlet', w: 9, k: 'athletes', align: 'right' }, { h: 'Tagihan (Rp)', w: 18, fn: (r) => n0(r.amount), align: 'right' }, { h: 'Status', w: 24, fn: (r) => ST[r.status] || r.status, wrap: true }, { h: 'Menunggu', w: 17, fn: (r) => (r.proof_at ? Math.round((P.now - new Date(r.proof_at)) / 3600000) + ' jam' : '-'), align: 'right', color: (r) => (r.proof_at && (P.now - new Date(r.proof_at)) / 3600000 > 48 ? C.bad : null) }], P.open, { fs: 7.2 });
    } else { font('normal', 8.4); ink(C.ok); text('Semua pendaftaran sudah lunas.', M, y + 2); y += 8; }
    section('Pendaftaran massal', 'Klub dengan kode pendaftaran massal (minimal 30 atlet). "Draf belum dikirim" = atlet yang sudah diisi di lembar massal tetapi belum dikirim sebagai batch, belum terhitung di laporan ini.');
    table([{ h: 'Klub', w: 40, k: 'label', wrap: true }, { h: 'Kode dibuka', w: 18, fn: (r) => (r.opened_at ? fDateS(r.opened_at) : 'Belum') }, { h: 'Berlaku sampai', w: 18, fn: (r) => (r.expires_at ? fDateS(r.expires_at) : '-') }, { h: 'Atlet terkirim', w: 16, k: 'athletes_submitted', align: 'right' }, { h: 'Draf belum dikirim', w: 18, k: 'draft_rows', align: 'right', color: (r) => (r.draft_rows > 0 ? C.bad : null) }, { h: 'Batch lunas / belum', w: 18, fn: (r) => `${r.batches_paid} / ${r.batches_open}`, align: 'right' }, { h: 'Status', w: 18, fn: (r) => (r.completed ? 'Selesai' : r.draft_rows > 0 ? 'Draf menunggu' : r.opened_at ? 'Berjalan' : 'Belum dibuka') }], P.bulk, { fs: 7.2 });

    // ================================================================ KATEGORI
    curTitle = 'Kategori';
    page(curTitle);
    section('Keterisian kategori', 'Status: Kosong = belum ada peserta; Risiko gabung = kurang dari 3 peserta; Risiko eksibisi (Aerobik) = kurang dari 4 peserta atau kurang dari 3 klub; Kuota klub penuh = ada klub yang mencapai batas atlet per klub.');
    const catStatus = (c) => (!c.entries ? 'Kosong' : c.entries < 3 ? 'Risiko gabung' : c.discipline === 'AER' && (c.entries < 4 || c.clubs < 3) ? 'Risiko eksibisi' : c.max_per_club && c.top_club >= c.max_per_club ? 'Kuota klub penuh' : 'Aman');
    const catTone = (c) => ({ Kosong: C.faint, 'Risiko gabung': C.bad, 'Risiko eksibisi': C.warn, 'Kuota klub penuh': C.info, Aman: C.ok }[catStatus(c)]);
    ['MAG', 'WAG', 'RG', 'AER'].forEach((d) => {
      const list = P.cats.filter((c) => c.discipline === d);
      if (!list.length) return;
      need(40);
      font('bold', 9.4); ink(C.navy); text(`${DN[d]} · ${list.filter((c) => c.entries).length} dari ${list.length} kategori terisi · ${n0(sum(list, 'entries'))} nomor`, M, y + 3); y += 6;
      const maxE = Math.max(1, ...list.map((c) => c.entries));
      table([{ h: 'Kategori', w: 66, k: 'name', wrap: true }, { h: 'Peserta', w: 13, k: 'entries', align: 'right' }, { h: 'Lunas', w: 11, k: 'entries_paid', align: 'right' }, { h: 'Klub', w: 10, k: 'clubs', align: 'right' }, { h: 'Terbanyak / batas per klub', w: 22, fn: (r) => `${r.top_club} / ${r.max_per_club || '-'}`, align: 'right' }, { h: 'Keterisian', w: 30, fn: () => '', bar: (r) => [r.entries, maxE] }, { h: 'Status', w: 22, fn: catStatus, color: catTone }], list, { fs: 7.1, bar: true });
    });

    // ================================================================ KLUB
    curTitle = 'Klub';
    page(curTitle);
    section('Klub terbesar', 'Lima belas klub dengan atlet terbanyak. Biru = lunas, kuning = belum lunas.');
    legend([['Lunas', C.s1], ['Belum lunas', C.s3]], M + CW - 52, y - 2);
    y = hbars(M, y + 1, CW, P.clubs.slice(0, 15).map((c) => ({ label: c.name, parts: [c.paid, c.pending] })), { labelW: 62, rightW: 12, rowH: 5.6 }) + 6;
    section('Asal provinsi', 'Berdasarkan domisili atlet di data pendaftaran.');
    const provRows = P.provs.slice(0, 12);
    y = hbars(M, y, CW * 0.62, provRows.map((p) => ({ label: p.province, parts: [p.athletes], right: `${n0(p.athletes)} (${pct(p.athletes, T.athletes)}%)` })), { labelW: 40, rightW: 22, rowH: 5.6 }) + 6;
    section('Data klub lengkap', 'Asal klub dari data klub; bila kosong, diambil dari domisili mayoritas atletnya.');
    table([
      { h: 'No', w: 7, fn: (r) => r._i, align: 'right' }, { h: 'Klub', w: 42, k: 'name', wrap: true }, { h: 'Asal', w: 32, fn: (r) => [titleCase(r.kab_kota), titleCase(r.province)].filter(Boolean).join(', ') || (r.country || '-'), wrap: true },
      { h: 'Disiplin', w: 26, fn: (r) => Object.entries(r.disciplines || {}).map(([k, v]) => `${k} ${v}`).join(', '), wrap: true },
      { h: 'Atlet', w: 10, k: 'athletes', align: 'right' }, { h: 'Lunas', w: 12, k: 'paid', align: 'right' }, { h: 'Belum', w: 12, k: 'pending', align: 'right', color: (r) => (r.pending ? C.bad : null) },
      { h: 'Pi / Pa', w: 13, fn: (r) => `${r.female} / ${r.male}`, align: 'right' }, { h: 'Dana masuk (Rp)', w: 21, fn: (r) => n0(r.paid_amount), align: 'right' }, { h: 'Belum lunas (Rp)', w: 20, fn: (r) => (r.outstanding ? n0(r.outstanding) : '-'), align: 'right' },
    ], P.clubs.map((c, i) => ({ ...c, _i: i + 1 })), { fs: 6.9 });

    // ================================================================ WILAYAH
    curTitle = 'Wilayah';
    page(curTitle);
    section('Atlet per kabupaten/kota', 'Penulisan kab/kota digabung tanpa membedakan huruf besar/kecil. Penulisan yang berbeda (mis. "Jakarta" dan "Jakarta Timur") tetap terpisah karena berasal dari isian pendaftar.');
    table([{ h: 'Kabupaten/kota', w: 50, k: 'kab_kota' }, { h: 'Provinsi', w: 40, k: 'province' }, { h: 'Atlet', w: 14, k: 'athletes', align: 'right' }, { h: '% atlet', w: 14, fn: (r) => pct1(r.athletes, T.athletes) + '%', align: 'right' }], P.kabs, { fs: 7.2, width: CW * 0.8 });
    section('Klub per provinsi');
    table([{ h: 'Provinsi', w: 50, k: 'p' }, { h: 'Klub', w: 14, k: 'n', align: 'right' }], Object.entries(P.clubProv).sort((a, b) => b[1] - a[1]).map(([p, n]) => ({ p, n })), { fs: 7.2, width: CW * 0.5 });

    // ================================================================ DOKUMEN & KEPATUHAN
    curTitle = 'Dokumen & kepatuhan';
    page(curTitle);
    section('Dokumen atlet', 'Atlet tanpa BPJS Ketenagakerjaan wajib membawa kartunya ke meja panitia di venue (tanpa unggah susulan).');
    const comp = P.comp.map((c) => ({ ...c, name: DN[c.code], athletes: (discs.find((d) => d.code === c.code) || {}).athletes || 0 }));
    table([{ h: 'Disiplin', w: 28, k: 'name' }, { h: 'Atlet', w: 12, k: 'athletes', align: 'right' }, { h: 'Dokumen valid', w: 18, k: 'docs_valid', align: 'right' }, { h: 'Belum diperiksa', w: 18, k: 'docs_waiting', align: 'right', color: (r) => (r.docs_waiting ? C.warn : null) }, { h: 'Tidak valid', w: 15, k: 'docs_invalid', align: 'right', color: (r) => (r.docs_invalid ? C.bad : null) }, { h: 'Tanpa BPJS TK', w: 18, k: 'no_bpjs', align: 'right' }, { h: '% tanpa BPJS', w: 16, fn: (r) => pct(r.no_bpjs, r.athletes) + '%', align: 'right' }, { h: 'Tanpa pas foto', w: 18, k: 'no_photo', align: 'right' }],
      [...comp, { name: 'Total', athletes: T.athletes, docs_valid: sum(comp, 'docs_valid'), docs_waiting: P.docsWaiting, docs_invalid: P.docsInvalid, no_bpjs: P.noBpjs, no_photo: sum(comp, 'no_photo'), _bold: true, _fill: C.infoL }], { fs: 7.3 });
    const rg = P.comp.find((c) => c.code === 'RG');
    if (rg) {
      section('Ritmik: Priangan & musik');
      table([{ h: 'Pemeriksaan', w: 50, k: 'a' }, { h: 'Jumlah nomor', w: 20, k: 'b', align: 'right' }], [
        { a: 'Priangan disetujui', b: rg.priangan_ok }, { a: 'Priangan menunggu pemeriksaan', b: rg.priangan_waiting }, { a: 'Priangan ditolak', b: rg.priangan_rejected },
        { a: 'Musik bisa dibuka', b: rg.music_ok }, { a: 'Musik menunggu diperiksa', b: rg.music_waiting }, { a: 'Musik belum diisi', b: rg.music_missing }, { a: 'Musik tidak bisa dibuka', b: rg.music_broken },
      ], { fs: 7.4, width: CW * 0.55 });
    }
    section('Catatan data');
    font('normal', 7.8); ink(C.ink2);
    const notes = [
      `Hitungan atlet sama dengan Ringkasan konsol: atlet di pendaftaran yang tidak dibatalkan. ${n0(T.cancelled_submissions)} pendaftaran dibatalkan tidak dihitung.`,
      'Dana masuk memakai nominal yang dicatat bendahara saat menandai lunas (termasuk kode unik QRIS).',
      'Daftar atlet lengkap (nama, tanggal lahir, klub, kategori, status bayar, dokumen) ada di file Excel yang diunduh bersama laporan ini.',
      'Laporan ini berisi data pribadi peserta, sebagian besar anak (UU PDP). Bagikan hanya di lingkungan panitia.',
    ];
    notes.forEach((s) => { const L = wrap('• ' + s, CW); need(L.length * lh(7.8) + 2); text(L, M, y + 2.6); y += L.length * lh(7.8) + 1.8; });

    // kaki halaman
    const N = doc.getNumberOfPages();
    for (let i = 1; i <= N; i++) {
      doc.setPage(i);
      stroke(C.line); doc.setLineWidth(0.2); doc.line(M, PH - 11, PW - M, PH - 11);
      font('normal', 6.8); ink(C.faint);
      text(`Jabar Open 2026 · Laporan pendaftaran · ${fDT(R.generated_at)} · Rahasia panitia: berisi data peserta (UU PDP)`, M, PH - 7);
      text(`Halaman ${i} dari ${N}`, PW - M, PH - 7, { align: 'right' });
    }
    return doc;
  }

  // =====================================================================
  //  EXCEL
  // =====================================================================
  function buildXlsx(XLSX, R) {
    const P = prepare(R); const INS = insights(R, P); const T = P.T;
    const wb = XLSX.utils.book_new();
    const sheet = (name, rows, widths) => {
      const ws = XLSX.utils.aoa_to_sheet(rows);
      ws['!cols'] = (widths || rows[0].map(() => 14)).map((w) => ({ wch: w }));
      XLSX.utils.book_append_sheet(wb, ws, name);
      return ws;
    };
    const dOnly = (d) => (d ? (typeof d === 'string' && d.length === 10 ? d : stamp(d).slice(0, 10)) : '');
    const dtWib = (d) => (d ? `${stamp(d).slice(0, 10)} ${fTime(d)}` : '');
    const discs = R.by_discipline || [];
    // Ringkasan
    const sum1 = [
      ['Laporan pendaftaran Jabar Open 2026'], [`Data sampai ${fDT(R.generated_at)} · diunduh oleh ${R.generated_by || '-'}`], [],
      ['Indikator', 'Nilai'],
      ['Atlet terdaftar', T.athletes], ['Orang unik', T.people], ['Atlet lunas', T.athletes_paid], ['Atlet belum lunas', T.athletes - T.athletes_paid],
      ['% atlet lunas', T.athletes ? T.athletes_paid / T.athletes : 0], ['Pendaftaran', T.submissions], ['Nomor lomba aktif', T.entries], ['Tim beregu', T.teams], ['Tim beregu lunas', T.teams_paid],
      ['Klub', P.clubs.length], ['Putri', T.female], ['Putra', T.male], ['Atlet WNA', T.wna], ['Atlet di bawah 10 tahun', T.under10],
      ['Dana masuk (Rp)', T.paid_amount], ['Tagihan belum lunas (Rp)', T.outstanding], ['Atlet baru 7 hari terakhir', P.last7], ['Atlet baru 7 hari sebelumnya', P.prev7],
      ['Hari menuju batas pendaftaran', P.daysToDeadline], ['Proyeksi atlet saat ditutup (laju 7 hari)', P.projected], ['Pendaftaran dibatalkan (tidak dihitung)', T.cancelled_submissions],
      [], ['Temuan', 'Tingkat', 'Tindak lanjut'],
      ...INS.map((i) => [i.text, { ok: 'Baik', info: 'Info', warn: 'Perhatian', bad: 'Mendesak' }[i.level], i.act || '']),
    ];
    const ws1 = sheet('Ringkasan', sum1, [62, 16, 70]);
    if (ws1['B9']) ws1['B9'].z = '0.0%';
    sheet('Disiplin', [['Disiplin', 'Kode', 'Pendaftaran', 'Atlet', 'Atlet lunas', 'Atlet belum lunas', 'Putri', 'Putra', 'Nomor lomba', 'Tim beregu', 'Klub', 'Kategori terisi', 'Kategori aktif', 'Dana masuk (Rp)', 'Belum lunas (Rp)'],
      ...discs.map((d) => [d.name, d.code, d.submissions, d.athletes, d.athletes_paid, d.athletes_pending, d.female, d.male, d.entries, d.teams, d.clubs, d.categories_used, d.categories_total, d.paid_amount, d.outstanding])],
      [18, 7, 12, 9, 11, 14, 8, 8, 12, 10, 8, 14, 14, 16, 16]);
    sheet('Pembayaran', [['Status', 'Metode', 'Pendaftaran', 'Atlet', 'Nilai (Rp)'], ...((R.payment && R.payment.by_status) || []).map((r) => [ST[r.status] || r.status, PM[r.method] || r.method, r.submissions, r.athletes, r.amount])], [24, 20, 12, 10, 16]);
    sheet('Belum lunas', [['Kode', 'Klub', 'Penanggung jawab', 'Disiplin', 'Atlet', 'Tagihan (Rp)', 'Status', 'Metode', 'Didaftarkan (WIB)', 'Bukti diunggah (WIB)', 'Menunggu (jam)', 'Catatan'],
      ...P.open.map((o) => [o.code, o.club, o.contact, DN[o.discipline] || o.discipline, o.athletes, o.amount, ST[o.status] || o.status, PM[o.method] || o.method, dtWib(o.created_at), dtWib(o.proof_at), o.proof_at ? Math.round((P.now - new Date(o.proof_at)) / 3600000) : '', o.note || ''])],
      [16, 28, 22, 14, 7, 14, 22, 14, 18, 18, 12, 30]);
    sheet('Massal', [['Klub', 'Kode dibuka (WIB)', 'Berlaku sampai (WIB)', 'Atlet terkirim', 'Draf belum dikirim', 'Batch lunas', 'Batch belum lunas', 'Nilai batch belum lunas (Rp)', 'Dana perlu dikembalikan (Rp)', 'Selesai'],
      ...P.bulk.map((b) => [b.label, dtWib(b.opened_at), dtWib(b.expires_at), b.athletes_submitted, b.draft_rows, b.batches_paid, b.batches_open, b.amount_open, b.refund_due, b.completed ? 'Ya' : 'Tidak'])],
      [30, 18, 18, 12, 14, 10, 14, 20, 20, 8]);
    const catStatus = (c) => (!c.entries ? 'Kosong' : c.entries < 3 ? 'Risiko gabung' : c.discipline === 'AER' && (c.entries < 4 || c.clubs < 3) ? 'Risiko eksibisi' : c.max_per_club && c.top_club >= c.max_per_club ? 'Kuota klub penuh' : 'Aman');
    sheet('Kategori', [['Disiplin', 'Kategori', 'Level', 'Usia', 'Jenis kelamin', 'Jenis', 'Peserta (nomor)', 'Peserta lunas', 'Atlet', 'Klub', 'Terbanyak dari satu klub', 'Batas per klub', 'Eksibisi', 'Status'],
      ...P.cats.map((c) => [DN[c.discipline], c.name, c.level, c.age || '', { M: 'Putra', F: 'Putri', X: 'Campuran' }[c.gender], c.type === 'pair' ? 'Pasangan' : 'Perorangan', c.entries, c.entries_paid, c.athletes, c.clubs, c.top_club, c.max_per_club == null ? '' : c.max_per_club, c.exhibition ? 'Ya' : 'Tidak', catStatus(c)])],
      [16, 52, 22, 20, 12, 12, 14, 12, 8, 8, 18, 12, 9, 16]);
    sheet('Klub', [['No', 'Klub', 'Jenis', 'Kab/kota', 'Provinsi', 'Negara', 'Pendaftaran', 'Atlet', 'Lunas', 'Belum lunas', 'Putri', 'Putra', 'Nomor lomba', 'Tim beregu', 'MAG', 'WAG', 'RG', 'AER', 'Dana masuk (Rp)', 'Belum lunas (Rp)', 'Pertama mendaftar (WIB)'],
      ...P.clubs.map((c, i) => [i + 1, c.name, c.kind || '', titleCase(c.kab_kota), titleCase(c.province), c.country || '', c.submissions, c.athletes, c.paid, c.pending, c.female, c.male, c.entries, c.teams, ...['MAG', 'WAG', 'RG', 'AER'].map((d) => (c.disciplines || {})[d] || 0), c.paid_amount, c.outstanding, dtWib(c.first_at)])],
      [5, 34, 9, 20, 18, 11, 11, 8, 8, 11, 7, 7, 11, 10, 6, 6, 6, 6, 16, 16, 20]);
    sheet('Wilayah', [['Kabupaten/kota', 'Provinsi', 'Atlet'], ...P.kabs.map((k) => [k.kab_kota, k.province, k.athletes]), [], ['Provinsi', 'Atlet', 'Klub'], ...P.provs.map((p) => [p.province, p.athletes, P.clubProv[p.province] || 0])], [26, 22, 10]);
    sheet('Usia', [['Usia (2026 − tahun lahir)', 'Putri', 'Putra', 'Total'], ...(R.ages || []).map((a) => [a.age, a.female, a.male, a.female + a.male])], [24, 10, 10, 10]);
    sheet('Kepatuhan', [['Disiplin', 'Dokumen valid', 'Dokumen belum diperiksa', 'Dokumen tidak valid', 'Tanpa BPJS TK', 'Tanpa pas foto', 'Tanpa akte (WNI)', 'Priangan disetujui', 'Priangan menunggu', 'Priangan ditolak', 'Musik ok', 'Musik menunggu', 'Musik belum diisi', 'Musik tidak bisa dibuka'],
      ...P.comp.map((c) => [DN[c.code], c.docs_valid, c.docs_waiting, c.docs_invalid, c.no_bpjs, c.no_photo, c.no_akte, c.priangan_ok, c.priangan_waiting, c.priangan_rejected, c.music_ok, c.music_waiting, c.music_missing, c.music_broken])],
      [16, 12, 20, 16, 13, 13, 14, 16, 16, 14, 9, 13, 15, 20]);
    sheet('Tren', [['Minggu mulai (Senin)', 'Pendaftaran', 'Atlet', 'Atlet lunas'], ...(R.weekly || []).map((w) => [w.week, w.submissions, w.athletes, w.paid]), [], ['Tanggal', 'Atlet baru'], ...(R.daily || []).map((d) => [d.day, d.athletes])], [20, 12, 10, 12]);
    sheet('Atlet', [['No atlet', 'Nama', 'Jenis kelamin', 'Tanggal lahir', 'Usia 2026', 'Kewarganegaraan', 'Kab/kota', 'Provinsi', 'Negara', 'Klub', 'Disiplin', 'Kategori', 'Tim beregu', 'Kode pendaftaran', 'Status bayar', 'Metode bayar', 'Dokumen', 'BPJS TK', 'Didaftarkan (WIB)', 'Lunas (WIB)'],
      ...(R.athletes || []).map((a) => [a.no || '', a.name, a.gender === 'M' ? 'Putra' : 'Putri', dOnly(a.birth_date), a.age, a.nationality, titleCase(a.kab_kota), titleCase(a.province), a.country || '', a.club, DN[a.discipline] || a.discipline, a.categories || '', a.team || '', a.submission, ST[a.status] || a.status, PM[a.method] || a.method, DOC[a.doc_status] || a.doc_status, a.bpjs ? 'Ada' : 'Bawa ke venue', dtWib(a.registered_at), dtWib(a.paid_at)])],
      [10, 30, 11, 12, 9, 13, 20, 16, 11, 28, 14, 48, 22, 16, 18, 14, 14, 14, 18, 18]);
    const last = wb.Sheets['Atlet']; if (last['!ref']) last['!autofilter'] = { ref: last['!ref'] };
    return wb;
  }

  // =====================================================================
  //  HALAMAN KONSOL
  // =====================================================================
  async function imgData(src) {
    const res = await fetch(src); if (!res.ok) throw new Error('logo');
    const blob = await res.blob();
    const data = await new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(blob); });
    const dims = await new Promise((r) => { const i = new Image(); i.onload = () => r({ w: i.naturalWidth, h: i.naturalHeight }); i.src = data; });
    return { data, ...dims };
  }
  function saveBlob(blob, name) {
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  }

  async function page(v, X) {
    const { esc } = X;
    v.innerHTML = `<h1>Laporan pendaftaran</h1>
      <p class="muted" style="max-width:720px">PDF berisi grafik, temuan, dan tindak lanjut untuk rapat panitia. Excel berisi semua tabel dan daftar atlet lengkap. Data diambil saat tombol ditekan.</p>
      <div class="row" style="display:flex;gap:10px;flex-wrap:wrap;margin:14px 0 18px">
        <button class="btn btn-primary" id="rp-both" type="button">Unduh laporan (PDF + Excel)</button>
        <button class="btn btn-ghost" id="rp-pdf" type="button">PDF saja</button>
        <button class="btn btn-ghost" id="rp-xlsx" type="button">Excel saja</button>
      </div>
      <p class="note warn small" style="max-width:720px">Berisi data pribadi peserta, sebagian besar anak (UU PDP). Bagikan hanya di lingkungan panitia. Setiap unduhan tercatat di Log.</p>
      <div id="rp-out" style="margin-top:18px"></div>`;
    const out = v.querySelector('#rp-out');
    const btns = [...v.querySelectorAll('button')];
    const run = async (kind) => {
      btns.forEach((b) => { b.disabled = true; });
      out.innerHTML = '<div class="empty"><span class="spinner"></span><p class="small muted">Menyusun laporan…</p></div>';
      try {
        const R = await X.api('console_report');
        const name = `Laporan-Pendaftaran-JabarOpen2026-${stamp(R.generated_at)}`;
        if (kind !== 'xlsx') {
          const { jsPDF } = window.jspdf;
          let logos = null;
          try { logos = { jo: await imgData('../assets/img/brand/jabar-open-white.png'), gi: await imgData('../assets/img/brand/gi-jabar-white.png') }; } catch (e) { logos = null; }
          saveBlob(makePdf(jsPDF, R, logos).output('blob'), name + '.pdf');
        }
        if (kind !== 'pdf') XLSX.writeFile(buildXlsx(XLSX, R), name + '.xlsx');
        const P = prepare(R); const INS = insights(R, P);
        const tone = { ok: 'ok', info: 'info', warn: 'warn', bad: 'bad' };
        out.innerHTML = `<h2 style="font-size:1.1rem">Temuan per ${esc(fDT(R.generated_at))}</h2>
          <div class="kpis" style="margin:10px 0 14px">
            <div class="kpi"><div><small>Atlet terdaftar</small><b>${n0(P.T.athletes)}</b><small>${n0(P.T.submissions)} pendaftaran</small></div></div>
            <div class="kpi ok"><div><small>Atlet lunas</small><b>${n0(P.T.athletes_paid)}</b><small>${pct1(P.T.athletes_paid, P.T.athletes)}%</small></div></div>
            <div class="kpi warn"><div><small>Belum lunas</small><b>${n0(P.T.athletes - P.T.athletes_paid)}</b><small>${esc(rp(P.T.outstanding))}</small></div></div>
            <div class="kpi"><div><small>Klub</small><b>${n0(P.clubs.length)}</b><small>${P.provs.length} provinsi</small></div></div>
          </div>
          ${INS.map((i) => `<p class="note ${tone[i.level]}" style="margin:6px 0">${esc(i.text)}${i.act ? `<br><b>Tindak lanjut:</b> ${esc(i.act)}` : ''}</p>`).join('')}`;
        X.toast(kind === 'both' ? 'Laporan PDF dan Excel diunduh' : kind === 'pdf' ? 'Laporan PDF diunduh' : 'Laporan Excel diunduh');
      } catch (e) {
        if (e.hint === 'ERR_SESSION') throw e;
        out.innerHTML = `<p class="note bad">Laporan gagal disusun: ${esc(e.message)}</p>`;
      } finally { btns.forEach((b) => { b.disabled = false; }); }
    };
    v.querySelector('#rp-both').onclick = () => run('both');
    v.querySelector('#rp-pdf').onclick = () => run('pdf');
    v.querySelector('#rp-xlsx').onclick = () => run('xlsx');
  }

  const API = { page, prepare, insights, makePdf, buildXlsx };
  if (typeof window !== 'undefined') { window.JO_MOD = window.JO_MOD || {}; window.JO_MOD.laporan = API; }
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
})(typeof window !== 'undefined' ? window : globalThis);
