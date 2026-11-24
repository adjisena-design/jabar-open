/* =====================================================================
   Jabar Open 2026 — Data final (owner & superadmin)
   Modul terpisah: dimuat saat halaman Data final dibuka.
   Satu panggilan console_final_data() -> Excel (Ringkasan, Pendaftaran,
   Atlet, Nomor lomba, Klub, Kategori) dan PDF daftar atlet per disiplin
   dan kategori. Semua pendaftaran ikut, termasuk yang dibatalkan (ditandai).
   ===================================================================== */
(function () {
  'use strict';

  const DN = { MAG: 'Artistik Putra', WAG: 'Artistik Putri', RG: 'Ritmik', AER: 'Aerobik' };
  const DORDER = ['MAG', 'WAG', 'RG', 'AER'];
  const ST = { lunas: 'Lunas', menunggu_verifikasi: 'Menunggu verifikasi', perlu_perbaikan: 'Bukti perlu diperbaiki', menunggu_pembayaran: 'Belum bayar', kedaluwarsa: 'Kedaluwarsa', dibatalkan: 'Dibatalkan' };
  const PM = { qris: 'QRIS', transfer: 'Transfer massal', manual: 'Manual (WNA/khusus)' };
  const DOC = { valid: 'Valid', menunggu: 'Belum diperiksa', tidak_valid: 'Tidak valid' };
  const PRI = { tidak: '', menunggu: 'Menunggu', disetujui: 'Disetujui', ditolak: 'Ditolak' };
  const NAVY = [19, 40, 74], MUTED = [91, 107, 136], LINE = [226, 232, 241], PAPER = [244, 246, 250];

  const st = (s) => ST[s] || s || '';
  const gL = (g) => (g === 'M' ? 'L' : g === 'F' ? 'P' : '');
  const wib = (d) => new Date(new Date(d).getTime() + 7 * 3600 * 1000);
  const p2 = (k) => String(k).padStart(2, '0');
  const dOnly = (d) => { if (!d) return ''; if (typeof d === 'string' && d.length === 10) return d; const x = wib(d); return `${x.getUTCFullYear()}-${p2(x.getUTCMonth() + 1)}-${p2(x.getUTCDate())}`; };
  const dtW = (d) => { if (!d) return ''; const x = wib(d); return `${dOnly(d)} ${p2(x.getUTCHours())}.${p2(x.getUTCMinutes())}`; };
  const stamp = (d) => { const x = wib(d); return `${dOnly(d)}-${p2(x.getUTCHours())}${p2(x.getUTCMinutes())}`; };
  const fDate = (d) => { if (!d) return ''; const [y, m, dd] = dOnly(d).split('-'); return `${dd}/${m}/${y}`; };
  const region = (o) => [o.kab_kota, o.province].filter(Boolean).join(', ') || o.country || '';
  const live = (e) => e.status !== 'dibatalkan' && e.entry_status === 'aktif';

  // ---------------------------------------------------------------- Excel
  function buildXlsx(XLSX, R) {
    const wb = XLSX.utils.book_new();
    const sheet = (name, head, rows, widths) => {
      const ws = XLSX.utils.aoa_to_sheet([head, ...rows]);
      ws['!cols'] = widths.map((w) => ({ wch: w }));
      if (rows.length) ws['!autofilter'] = { ref: XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: rows.length, c: head.length - 1 } }) };
      XLSX.utils.book_append_sheet(wb, ws, name);
    };
    const S = R.submissions, A = R.athletes, E = R.entries;

    // Ringkasan
    const sumRows = [['Data final Jabar Open 2026'], ['Diambil', dtW(R.generated_at) + ' WIB'], ['Oleh', R.generated_by], [],
      ['Status pendaftaran', 'Pendaftaran', 'Atlet', 'Tagihan (Rp)']];
    Object.keys(ST).forEach((k) => { const xs = S.filter((s) => s.status === k); if (xs.length) sumRows.push([ST[k], xs.length, xs.reduce((a, s) => a + s.athletes, 0), xs.reduce((a, s) => a + (s.total || 0), 0)]); });
    sumRows.push(['Total', S.length, A.length, S.reduce((a, s) => a + (s.total || 0), 0)], [], ['Disiplin', 'Pendaftaran (tidak batal)', 'Atlet (tidak batal)', 'Atlet lunas']);
    DORDER.forEach((d) => { const xs = S.filter((s) => s.discipline === d && s.status !== 'dibatalkan'); const as = A.filter((a) => a.discipline === d && a.status !== 'dibatalkan');
      sumRows.push([DN[d], xs.length, as.length, as.filter((a) => a.status === 'lunas').length]); });
    sumRows.push([], ['Berisi data pribadi peserta, sebagian besar anak (UU PDP). Hanya untuk panitia.']);
    const ws0 = XLSX.utils.aoa_to_sheet(sumRows); ws0['!cols'] = [{ wch: 34 }, { wch: 24 }, { wch: 20 }, { wch: 16 }];
    XLSX.utils.book_append_sheet(wb, ws0, 'Ringkasan');

    sheet('Pendaftaran', ['Kode', 'Didaftarkan (WIB)', 'Disiplin', 'Jenis', 'Klub', 'Kab/kota', 'Provinsi', 'Negara', 'Penanggung jawab', 'Peran', 'WhatsApp', 'Email',
      'Atlet', 'Nomor lomba aktif', 'Metode bayar', 'Batch massal', 'Tagihan (Rp)', 'Dibayar (Rp)', 'Status', 'Bukti diunggah (WIB)', 'Lunas (WIB)', 'Catatan verifikasi', 'Alasan batal'],
      S.map((s) => [s.code, dtW(s.created_at), DN[s.discipline] || s.discipline, s.type || '', s.club, s.kab_kota || '', s.province || '', s.country || '', s.contact_name || '', s.contact_role || '',
        s.contact_phone || '', s.contact_email || '', s.athletes, s.entries, PM[s.method] || s.method || '', s.batch || '', s.total || 0, s.paid || 0, st(s.status),
        dtW(s.proof_at), dtW(s.paid_at), s.note || '', s.cancel_reason || '']),
      [16, 17, 14, 11, 28, 18, 16, 10, 24, 14, 16, 26, 7, 9, 15, 17, 13, 13, 18, 17, 17, 28, 28]);

    sheet('Atlet', ['No atlet', 'Nama', 'L/P', 'Tanggal lahir', 'Usia 2026', 'WNI/WNA', 'Kab/kota', 'Provinsi', 'Negara', 'Klub', 'Disiplin', 'Kategori', 'Tim beregu',
      'Kode pendaftaran', 'Status bayar', 'Metode bayar', 'Dokumen', 'BPJS TK', 'Pas foto', 'Orang tua/wali', 'Hubungan', 'WA wali', 'Email wali', 'Didaftarkan (WIB)', 'Lunas (WIB)'],
      A.map((a) => [a.no || '', a.name, gL(a.gender), dOnly(a.birth_date), a.birth_date ? 2026 - Number(String(a.birth_date).slice(0, 4)) : '', a.nationality || '', a.kab_kota || '', a.province || '', a.country || '',
        a.club, DN[a.discipline] || a.discipline, a.categories || '', a.team || '', a.submission, st(a.status), PM[a.method] || a.method || '', DOC[a.doc_status] || a.doc_status || '',
        a.bpjs ? 'Ada' : 'Belum', a.photo ? 'Ada' : 'Belum', a.guardian_name || '', a.guardian_relation || '', a.guardian_phone || '', a.guardian_email || '', dtW(a.registered_at), dtW(a.paid_at)]),
      [11, 30, 5, 12, 8, 8, 18, 16, 10, 28, 14, 40, 22, 16, 18, 15, 14, 8, 8, 24, 11, 16, 26, 17, 17]);

    sheet('Nomor lomba', ['Disiplin', 'Kode kategori', 'Kategori', 'No atlet', 'Nama', 'L/P', 'Tanggal lahir', 'Klub', 'Kab/kota / negara', 'Kode pendaftaran', 'Status bayar', 'Status nomor', 'Khusus beregu', 'Priangan', 'Biaya (Rp)'],
      E.map((e) => { const as = e.athletes || [];
        return [DN[e.discipline] || e.discipline, e.cat_code, e.category, as.map((a) => a.no || '').join(' & '), as.map((a) => a.name).join(' & '), as.map((a) => gL(a.gender)).join('/'),
          as.map((a) => dOnly(a.birth_date)).join(' & '), e.club, as.map(region).filter(Boolean)[0] || '', e.submission, st(e.status), e.entry_status === 'aktif' ? 'Aktif' : st(e.entry_status),
          e.team_only ? 'Ya' : '', PRI[e.priangan] || e.priangan || '', e.fee || 0]; }),
      [14, 14, 36, 13, 34, 6, 22, 28, 24, 16, 18, 12, 9, 11, 11]);

    // Klub: dari pendaftaran yang tidak dibatalkan
    const K = new Map();
    S.forEach((s) => { const k = K.get(s.club) || { club: s.club, kind: s.club_kind || '', kab: s.kab_kota || '', prov: s.province || '', country: s.country || '', subs: 0, cancel: 0, ath: 0, athPaid: 0, disc: new Set(), bill: 0, contacts: new Set() };
      if (s.status === 'dibatalkan') k.cancel++; else { k.subs++; k.ath += s.athletes; if (s.status === 'lunas') k.athPaid += s.athletes; k.disc.add(DN[s.discipline] || s.discipline); k.bill += s.total || 0; }
      if (s.contact_name) k.contacts.add(`${s.contact_name}${s.contact_phone ? ' (' + s.contact_phone + ')' : ''}`); K.set(s.club, k); });
    const KL = [...K.values()].sort((a, b) => b.ath - a.ath || a.club.localeCompare(b.club));
    sheet('Klub', ['No', 'Klub', 'Jenis', 'Kab/kota', 'Provinsi', 'Negara', 'Pendaftaran', 'Dibatalkan', 'Atlet', 'Atlet lunas', 'Disiplin', 'Tagihan (Rp)', 'Kontak'],
      KL.map((k, i) => [i + 1, k.club, k.kind, k.kab, k.prov, k.country, k.subs, k.cancel, k.ath, k.athPaid, [...k.disc].join(', '), k.bill, [...k.contacts].join('; ')]),
      [5, 30, 10, 18, 16, 10, 11, 10, 8, 10, 30, 14, 50]);

    sheet('Kategori', ['Disiplin', 'Kode', 'Kategori', 'Level', 'Tahun lahir', 'Biaya (Rp)', 'Peserta', 'Peserta lunas', 'Klub', 'Aktif', 'Eksibisi', 'Catatan'],
      R.categories.map((c) => { const xs = E.filter((e) => e.cat_id === c.id && live(e)); const n = xs.length;
        return [DN[c.discipline] || c.discipline, c.code, c.name, c.level || '', `${c.birth_year_min || '…'}–${c.birth_year_max || '…'}`, c.fee || 0, n, xs.filter((e) => e.status === 'lunas').length,
          new Set(xs.map((e) => e.club)).size, c.active ? 'Ya' : 'Tidak', c.exhibition ? 'Ya' : '', n > 0 && n < 3 && c.discipline !== 'AER' ? 'Kurang dari 3: gabungkan' : '']; }),
      [14, 13, 38, 8, 12, 11, 8, 11, 6, 6, 8, 24]);
    return wb;
  }

  // ---------------------------------------------------------------- PDF
  function buildPdf(jsPDF, R) {
    const doc = new jsPDF({ unit: 'mm', format: 'a4', orientation: 'landscape', compress: true });
    const W = 297, H = 210, M = 12;
    const cols = [['#', 8], ['No atlet', 20], ['Nama', 62], ['L/P', 9], ['Lahir', 20], ['Klub', 60], ['Kab/kota / negara', 44], ['Pendaftaran', 26], ['Status', 24]];
    const E = R.entries;
    let y = M;
    const fit = (t, w) => { t = String(t == null ? '' : t); if (doc.getTextWidth(t) <= w) return t; while (t.length > 1 && doc.getTextWidth(t + '…') > w) t = t.slice(0, -1); return t + '…'; };
    const newPage = () => { doc.addPage(); y = M; };
    const need = (h) => { if (y + h > H - 14) { newPage(); return true; } return false; };
    const head = () => {
      doc.setFillColor(...PAPER); doc.rect(M, y, W - 2 * M, 6.5, 'F');
      doc.setFont('helvetica', 'bold'); doc.setFontSize(7.5); doc.setTextColor(...MUTED);
      let x = M + 1.5; cols.forEach(([l, w]) => { doc.text(l, x, y + 4.4); x += w; }); y += 6.5;
    };
    // sampul
    doc.setFillColor(...NAVY); doc.rect(0, 0, W, 40, 'F');
    doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(20); doc.text('Data final peserta Jabar Open 2026', M, 20);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.text(`Daftar atlet per disiplin dan kategori · diambil ${dtW(R.generated_at)} WIB oleh ${R.generated_by}`, M, 30);
    y = 52; doc.setTextColor(...NAVY); doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.text('Ringkasan', M, y); y += 8;
    doc.setFontSize(9.5);
    const tot = [['Disiplin', 'Kategori terisi', 'Nomor lomba', 'Lunas', 'Belum lunas', 'Dibatalkan']];
    DORDER.forEach((d) => { const xs = E.filter((e) => e.discipline === d); const lv = xs.filter(live);
      tot.push([DN[d], new Set(lv.map((e) => e.cat_id)).size, lv.length, lv.filter((e) => e.status === 'lunas').length, lv.filter((e) => e.status !== 'lunas').length, xs.length - lv.length]); });
    tot.forEach((r, i) => { doc.setFont('helvetica', i ? 'normal' : 'bold'); doc.setTextColor(...(i ? NAVY : MUTED)); let x = M; r.forEach((c, j) => { doc.text(String(c), x, y); x += j ? 32 : 50; }); y += 6.5; });
    y += 4; doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...MUTED);
    doc.text('Semua pendaftaran ikut, termasuk yang belum bayar dan dibatalkan (ditandai di kolom Status, diletakkan di akhir tiap kategori).', M, y); y += 5;
    doc.text('Berisi data pribadi peserta, sebagian besar anak (UU PDP). Hanya untuk panitia; jangan disebarkan.', M, y);

    DORDER.forEach((d) => {
      const cats = R.categories.filter((c) => c.discipline === d && E.some((e) => e.cat_id === c.id));
      if (!cats.length) return;
      newPage();
      doc.setFillColor(...NAVY); doc.rect(M, y, W - 2 * M, 10, 'F'); doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(13);
      doc.text(DN[d] || d, M + 3, y + 7); y += 15;
      cats.forEach((c) => {
        const xs = E.filter((e) => e.cat_id === c.id).sort((a, b) => (live(b) - live(a)) || (a.status === 'lunas' ? 0 : 1) - (b.status === 'lunas' ? 0 : 1) || a.club.localeCompare(b.club) || String((a.athletes[0] || {}).name).localeCompare(String((b.athletes[0] || {}).name)));
        const lv = xs.filter(live);
        need(20);
        doc.setTextColor(...NAVY); doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5); doc.text(fit(`${c.name}  (${c.code})`, 190), M, y + 4);
        doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...MUTED);
        doc.text(`${lv.length} peserta · ${lv.filter((e) => e.status === 'lunas').length} lunas${xs.length > lv.length ? ` · ${xs.length - lv.length} dibatalkan` : ''}${!c.active ? ' · kategori nonaktif' : ''}${c.exhibition ? ' · eksibisi' : ''}`, W - M, y + 4, { align: 'right' });
        y += 7; head();
        let i = 0;
        xs.forEach((e) => {
          if (need(6)) { doc.setTextColor(...NAVY); doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.text(fit(`${c.name} (lanjutan)`, 200), M, y + 4); y += 6; head(); }
          const as = e.athletes || [];
          const off = !live(e);
          const vals = [off ? '–' : String(++i), as.map((a) => a.no || '').join(' & '), as.map((a) => a.name).join(' & ') + (e.team_only ? ' (beregu)' : ''), as.map((a) => gL(a.gender)).join('/'),
            as.map((a) => fDate(a.birth_date)).join(' & '), e.club, as.map(region).filter(Boolean)[0] || '', e.submission, e.entry_status !== 'aktif' ? 'Nomor batal' : st(e.status)];
          doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...(off ? [150, 150, 150] : e.status === 'lunas' ? NAVY : [154, 98, 0]));
          let x = M + 1.5; cols.forEach(([, w], j) => { doc.text(fit(vals[j], w - 2), x, y + 4); x += w; });
          doc.setDrawColor(...LINE); doc.line(M, y + 6, W - M, y + 6); y += 6;
        });
        y += 6;
      });
    });
    const n = doc.getNumberOfPages();
    for (let p = 1; p <= n; p++) { doc.setPage(p); doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...MUTED);
      doc.text(`Jabar Open 2026 · Data final ${dtW(R.generated_at)} WIB · rahasia panitia (UU PDP)`, M, H - 6); doc.text(`Halaman ${p} dari ${n}`, W - M, H - 6, { align: 'right' }); }
    return doc;
  }

  function saveBlob(blob, name) {
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  }

  async function page(v, X) {
    const { esc } = X;
    v.innerHTML = `<h1>Data final</h1>
      <p class="muted" style="max-width:720px">Semua pendaftaran dan semua atlet, termasuk yang belum bayar dan dibatalkan (ada kolom status untuk menyaring). Data diambil saat tombol ditekan.</p>
      <div class="row" style="display:flex;gap:10px;flex-wrap:wrap;margin:14px 0 18px">
        <button class="btn btn-primary" id="df-both" type="button">Unduh data final (Excel + PDF)</button>
        <button class="btn btn-ghost" id="df-xlsx" type="button">Excel saja</button>
        <button class="btn btn-ghost" id="df-pdf" type="button">PDF saja</button></div>
      <div class="card small" style="max-width:720px"><p style="margin:0 0 6px"><b>Excel</b>: Ringkasan · Pendaftaran (satu baris per pendaftaran) · Atlet (satu baris per atlet, dengan kontak wali) · Nomor lomba (satu baris per atlet per kategori) · Klub · Kategori. Setiap tab sudah diberi filter.</p>
        <p style="margin:0"><b>PDF</b>: daftar atlet per disiplin lalu per kategori (lanskap A4), untuk TD dan pengecekan start list.</p></div>
      <p class="note warn small" style="max-width:720px;margin-top:12px">Berisi data pribadi peserta, sebagian besar anak (UU PDP). Bagikan hanya di lingkungan panitia. Setiap unduhan tercatat di Log.</p>
      <div id="df-out" style="margin-top:12px"></div>`;
    const out = v.querySelector('#df-out'); const btns = [...v.querySelectorAll('button')];
    const run = async (kind) => {
      btns.forEach((b) => { b.disabled = true; });
      out.innerHTML = '<div class="empty"><span class="spinner"></span><p class="small muted">Menyusun data…</p></div>';
      try {
        const R = await X.api('console_final_data');
        const name = `Data-Final-JabarOpen2026-${stamp(R.generated_at)}`;
        if (kind !== 'pdf') XLSX.writeFile(buildXlsx(XLSX, R), name + '.xlsx', { compression: true });
        if (kind !== 'xlsx') saveBlob(buildPdf(window.jspdf.jsPDF, R).output('blob'), name + '.pdf');
        out.innerHTML = `<p class="note ok small">Selesai: ${R.submissions.length} pendaftaran, ${R.athletes.length} atlet, ${R.entries.length} nomor lomba (${esc(dtW(R.generated_at))} WIB).</p>`;
        X.toast('Data final diunduh');
      } catch (e) {
        if (e.hint === 'ERR_SESSION') throw e;
        out.innerHTML = `<p class="note bad">Gagal menyusun data: ${esc(e.message)}</p>`;
      } finally { btns.forEach((b) => { b.disabled = false; }); }
    };
    v.querySelector('#df-both').onclick = () => run('both');
    v.querySelector('#df-xlsx').onclick = () => run('xlsx');
    v.querySelector('#df-pdf').onclick = () => run('pdf');
  }

  window.JO_MOD = window.JO_MOD || {};
  window.JO_MOD.datafinal = { page, buildXlsx, buildPdf };
})();
