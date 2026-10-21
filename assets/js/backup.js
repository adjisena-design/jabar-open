/* =====================================================================
   Jabar Open 2026 — Backup darurat (hanya owner)
   Modul terpisah: dimuat saat halaman Backup darurat dibuka.
   1) Unduh data lengkap: ZIP berisi data.json (untuk pemulihan), Excel per
      tabel, TITIK-LANJUT.txt, CARA-PULIHKAN.txt.
   2) Unduh berkas: dokumen, pas foto, bukti bayar, tanda tangan, dalam
      beberapa ZIP bertahap (maks. ~250 MB per bagian).
   Database menolak semua peran selain owner; tampilan ini hanya pintu.
   ===================================================================== */
(function () {
  'use strict';
  window.JO_MOD = window.JO_MOD || {};
  const PART_MAX = 250 * 1024 * 1024;

  // tab Excel yang mudah dibaca: nama tabel -> nama tab
  const LABEL = {
    submissions: 'Pendaftaran', athletes: 'Atlet', teams: 'Tim beregu', team_members: 'Anggota tim', entries: 'Nomor lomba',
    entry_athletes: 'Atlet per nomor', clubs: 'Klub', categories: 'Kategori', disciplines: 'Disiplin', sessions: 'Start list sesi',
    scores: 'Nilai', score_log: 'Log koreksi nilai', team_levels: 'Publikasi beregu', mutations: 'Mutasi GoBiz', music_log: 'Riwayat musik',
    jury_applications: 'Pendaftar juri', staff: 'Kode akses (tanpa kode)', chat_messages: 'Chat', chat_reads: 'Chat dibaca',
    issues: 'Laporan masalah', issue_comments: 'Tanggapan laporan', issue_reads: 'Laporan dibaca', faq_categories: 'FAQ kategori',
    faq_items: 'FAQ', settings: 'Pengaturan', audit: 'Log aktivitas', outbox: 'Email', wa_outbox: 'Pesan WhatsApp',
    wa_recipients: 'Penerima WhatsApp', pm_tasks: 'Proyek Gantt', pm_divisions: 'Proyek Divisi', pm_members: 'Proyek Anggota',
    pm_phases: 'Proyek Fase', pm_rab_params: 'Proyek RAB parameter', pm_rab_sections: 'Proyek RAB seksi', pm_rab_items: 'Proyek RAB',
    pm_income_items: 'Proyek Pendapatan',
  };
  const stamp = () => {
    const d = new Date(); const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`;
  };
  const mb = (b) => (b / 1048576).toFixed(b < 10 * 1048576 ? 1 : 0) + ' MB';
  function loadScript(src) {
    return new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = () => rej(new Error('Pustaka ZIP gagal dimuat.')); document.head.appendChild(s); });
  }
  async function zipLib() { if (!window.fflate) await loadScript('../assets/vendor/fflate-0.8.2.min.js'); return window.fflate; }
  function save(bytes, name, type) {
    const blob = bytes instanceof Blob ? bytes : new Blob([bytes], { type: type || 'application/zip' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 60000);
    return blob.size;
  }
  const enc = (s) => new TextEncoder().encode(s);

  function titikLanjut(S, meta) {
    const L = [];
    const w = (s) => L.push(s);
    w('JABAR OPEN 2026 · TITIK LANJUT (di mana kita berhenti)');
    w('Backup dibuat: ' + new Date(meta.generated_at).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' }) + ' WIB');
    w('');
    w('Pendaftaran per status:');
    Object.entries(S.submissions_by_status || {}).forEach(([k, n]) => w(`  - ${k}: ${n}`));
    w('Pendaftaran aktif per disiplin:');
    Object.entries(S.submissions_by_discipline || {}).forEach(([k, n]) => w(`  - ${k}: ${n}`));
    w(`Atlet terdaftar: ${S.athletes} (lunas: ${S.athletes_paid})`);
    w('');
    w('Perlu tindakan saat backup:');
    const A = S.actions || {};
    w(`  - Verifikasi pembayaran: ${A.to_verify || 0} pendaftaran (${A.to_verify_athletes || 0} atlet)`);
    (S.to_verify || []).forEach((x) => w('      ' + x));
    w(`  - Dokumen atlet belum diperiksa: ${A.docs_pending || 0}`);
    w(`  - Priangan menunggu: ${A.priangan_pending || 0}`);
    w(`  - Musik menunggu diperiksa: ${A.music_pending || 0}`);
    w('');
    w(`Mutasi GoBiz: ${S.mutations} baris; impor terakhir: ${S.last_mutation_import ? new Date(S.last_mutation_import).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' }) : 'belum pernah'}`);
    w(`Nilai tersimpan: ${S.scores}`);
    w('Start list terbit: ' + ((S.startlists_published || []).join(', ') || 'belum ada'));
    w('Hasil terbit: ' + ((S.results_published || []).join(', ') || 'belum ada'));
    w('');
    w('Aktivitas terakhir (Log):');
    (S.last_log || []).forEach((x) => w(`  - ${new Date(x.at).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })} · ${x.by || 'sistem'} · ${x.action} · ${x.target}`));
    w('');
    w('Jumlah baris per tabel di backup ini:');
    meta.tables.forEach((t) => w(`  - ${t.name}: ${t.rows}`));
    return L.join('\n') + '\n';
  }
  const CARA = `JABAR OPEN 2026 · CARA MEMULIHKAN DARI BACKUP

Dipakai bila proyek Supabase rusak, terhapus, atau konsol tidak bisa dibuka.
Isi ZIP ini: data.json (seluruh tabel), Excel per tabel (untuk dibaca),
TITIK-LANJUT.txt (di mana kerja berhenti), dan file ini.
Berkas (dokumen, pas foto, bukti bayar) ada di ZIP "berkas" terpisah.

1. Buat proyek Supabase baru (supabase.com > New project, region Tokyo).
2. Buka SQL Editor proyek baru, tempel seluruh isi supabase/setup.sql
   dari repo adjisena-design/jabar-open, tekan Run. Simpan kode owner dan
   secret email yang muncul (kode lama tidak ikut backup).
3. Di Mac: buka Terminal di folder repo jabar-open, lalu jalankan
     cd supabase/tools && npm install pg
     DATABASE_URL="(connection string proyek baru, menu Connect > Session pooler)" \\
       node restore.mjs /path/ke/data.json
   Skrip mengosongkan tabel bawaan setup lalu mengisi semua tabel dari backup.
4. Berkas: buka Storage proyek baru, bucket "dokumen", "bukti", dan "publik"
   sudah dibuat setup. Unggah isi folder dengan nama yang sama dari ZIP
   berkas (struktur folder harus sama persis), atau jalankan
     SUPABASE_URL=... SUPABASE_SERVICE_KEY=... node restore.mjs --files /path/ke/folder-berkas
   (service key hanya diketik di Terminal Mac sendiri, jangan dikirim ke siapa pun).
5. Ubah assets/js/config.js di repo: url dan anonKey proyek baru, lalu push.
   Situs dan konsol hidup lagi di domain yang sama.
6. Masuk konsol dengan kode owner baru, buat ulang kode superadmin, admin,
   TD, juri, bendahara, dan pemantau (Kode akses > Kode baru).
7. Pasang ulang secret email di Google Apps Script (SECRET) dan token
   gateway WhatsApp bila dipakai.
8. Lanjutkan kerja dari TITIK-LANJUT.txt.

Uji pemulihan ini sekali ke proyek kosong sebelum Desember.
Data berisi data pribadi anak (UU PDP): simpan di folder terenkripsi dan
hapus semua salinan sesuai jadwal penghapusan dokumen (Januari 2027).
`;

  async function page(v, C) {
    const { api, esc, dt } = C;
    const meta = await api('console_backup_meta');
    const last = meta.last_backup;
    const files = meta.files || [];
    const fBytes = files.reduce((a, f) => a + (Number(f.size) || 0), 0);
    const rows = meta.tables.reduce((a, t) => a + Number(t.rows), 0);
    v.innerHTML = `<h1>Backup darurat</h1>
      <p class="muted">Hanya owner. Setiap unduhan adalah file baru bertanggal dan berjam, jadi tidak ada yang tertimpa. Disarankan seminggu sekali sampai 4 Desember, lalu setiap hari mulai 5 Desember.</p>
      <div class="bk-grid">
        <section class="card"><h2>1. Data lengkap</h2>
          <p class="small">${meta.tables.length} tabel, ${rows.toLocaleString('id-ID')} baris. Satu ZIP berisi <b>data.json</b> untuk pemulihan, <b>Excel</b> satu tab per tabel untuk dibaca, <b>TITIK-LANJUT.txt</b> (di mana kerja berhenti), dan <b>CARA-PULIHKAN.txt</b>.</p>
          <p class="small muted">${last && last.at ? `Terakhir: ${dt(last.at)} (${mb(Number(last.bytes) || 0)})` : 'Belum pernah diunduh.'}</p>
          <button class="btn btn-primary" id="bk_data">Unduh data lengkap</button>
          <div class="bk-prog small" id="bk_data_p" aria-live="polite"></div></section>
        <section class="card"><h2>2. Berkas</h2>
          <p class="small">${files.length} berkas, ${mb(fBytes)}: dokumen identitas, pas foto, bukti bayar, tanda tangan, gambar QRIS. Diunduh dalam ${Math.max(1, Math.ceil(fBytes / PART_MAX))} ZIP bertahap agar browser tidak berat. Biarkan tab ini terbuka sampai selesai.</p>
          <button class="btn btn-ghost" id="bk_files" ${files.length ? '' : 'disabled'}>Unduh berkas</button>
          <div class="bk-prog small" id="bk_files_p" aria-live="polite"></div></section>
      </div>
      <section class="card"><h2>Yang tidak ikut</h2>
        <p class="small" style="margin:0">Kode akses mentah, secret email, token gateway WhatsApp, dan kunci API tidak pernah diekspor. Setelah pemulihan, kode akses dibuat ulang. Backup harian bawaan Supabase Pro (7 hari, tanpa berkas) tetap menjadi jaring pengaman kedua.</p></section>
      <section class="card"><h2>Menyimpan di Mac</h2>
        <ul class="small" style="margin:0;padding-left:18px">
          <li>Pindahkan ZIP dari Downloads ke satu folder terenkripsi (FileVault aktif), jangan tercecer.</li>
          <li>Salin berkala ke drive eksternal terenkripsi sebagai salinan kedua.</li>
          <li>Isinya data pribadi anak (UU PDP): hapus semua salinan sesuai jadwal penghapusan dokumen, Januari 2027.</li></ul></section>`;
    const css = document.getElementById('bk-css') || Object.assign(document.createElement('style'), { id: 'bk-css' });
    css.textContent = '.bk-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin:16px 0}.bk-grid .card{margin:0}.bk-prog{margin-top:10px;color:var(--muted)}.bk-prog b{color:var(--ink)}';
    document.head.appendChild(css);

    v.querySelector('#bk_data').onclick = async (e) => {
      const btn = e.currentTarget; const P = v.querySelector('#bk_data_p');
      btn.disabled = true;
      try {
        const fl = await zipLib();
        const data = { format: 'jabar-open-backup', version: 1, generated_at: meta.generated_at, site: meta.project_url, tables: {} };
        const total = meta.tables.reduce((a, t) => a + Math.max(1, Math.ceil(Number(t.rows) / 500)), 0);
        let done = 0;
        for (const t of meta.tables) {
          const all = [];
          for (let off = 0; off < Number(t.rows) || off === 0; off += 500) {
            const part = await api('console_backup_rows', { p_table: t.name, p_offset: off, p_limit: 500 });
            all.push(...part); done++;
            P.innerHTML = `Mengambil <b>${esc(t.name)}</b> · ${Math.round((done / total) * 100)}%`;
            if (part.length < 500) break;
          }
          data.tables[t.name] = all;
        }
        P.textContent = 'Menyusun Excel dan ZIP…';
        const status = await api('console_backup_status');
        // Excel terbaca: satu tab per tabel; kolom foto kecil (base64) diganti tanda agar ringan
        const wb = XLSX.utils.book_new(); const used = new Set();
        Object.entries(data.tables).forEach(([name, list]) => {
          let tab = (LABEL[name] || name).slice(0, 31); while (used.has(tab)) tab = tab.slice(0, 28) + '_' + used.size; used.add(tab);
          const rowsX = list.map((r) => { const o = {}; Object.entries(r).forEach(([k, val]) => {
            o[k] = k === 'photo_thumb' ? (val ? '(ada)' : '') : val !== null && typeof val === 'object' ? JSON.stringify(val) : val;
            if (typeof o[k] === 'string' && o[k].length > 32000) o[k] = o[k].slice(0, 32000) + '…'; }); return o; });
          XLSX.utils.book_append_sheet(wb, rowsX.length ? XLSX.utils.json_to_sheet(rowsX) : XLSX.utils.aoa_to_sheet([['(kosong)']]), tab);
        });
        const xbuf = XLSX.write(wb, { type: 'array', bookType: 'xlsx' });
        const st = stamp();
        const zip = fl.zipSync({
          'data.json': enc(JSON.stringify(data)),
          [`jabar-open-data-${st}.xlsx`]: [new Uint8Array(xbuf), { level: 0 }],
          'TITIK-LANJUT.txt': enc(titikLanjut(status, meta)),
          'CARA-PULIHKAN.txt': enc(CARA),
        }, { level: 6 });
        const size = save(zip, `jabar-open-backup-${st}.zip`);
        await api('console_backup_done', { p_kind: 'data', p_bytes: size, p_detail: { tabel: meta.tables.length, baris: rows } });
        P.innerHTML = `<span class="ok-t">Selesai: jabar-open-backup-${st}.zip (${mb(size)}). Pindahkan ke folder backup terenkripsi.</span>`;
      } catch (err) { P.innerHTML = `<span class="bad-t">${esc(err.message)}</span>`; }
      finally { btn.disabled = false; }
    };

    v.querySelector('#bk_files').onclick = async (e) => {
      const btn = e.currentTarget; const P = v.querySelector('#bk_files_p');
      btn.disabled = true;
      try {
        const fl = await zipLib();
        // bagi menjadi bagian <= PART_MAX
        const parts = []; let cur = []; let curB = 0;
        files.forEach((f) => { const s = Number(f.size) || 0; if (cur.length && curB + s > PART_MAX) { parts.push(cur); cur = []; curB = 0; } cur.push(f); curB += s; });
        if (cur.length) parts.push(cur);
        const st = stamp(); let total = 0; let failed = 0; let n = 0;
        for (let i = 0; i < parts.length; i++) {
          const entries = {};
          for (const f of parts[i]) {
            n++;
            P.innerHTML = `Bagian <b>${i + 1}/${parts.length}</b> · berkas ${n}/${files.length}`;
            try {
              let url;
              if (f.bucket === 'publik') url = JO.sb.storage.from('publik').getPublicUrl(f.name).data.publicUrl;
              else url = await C.signed(f.bucket, f.name);
              const r = await fetch(url); if (!r.ok) throw new Error(r.status);
              entries[`${f.bucket}/${f.name}`] = [new Uint8Array(await r.arrayBuffer()), { level: 0 }];
            } catch (x) { failed++; entries[`GAGAL/${f.bucket}/${f.name}.txt`] = enc('Gagal diunduh: ' + x.message); }
          }
          const zip = fl.zipSync(entries);
          total += save(zip, `jabar-open-berkas-${st}-bagian-${i + 1}-dari-${parts.length}.zip`);
          await new Promise((r) => setTimeout(r, 800));
        }
        await api('console_backup_done', { p_kind: 'berkas', p_bytes: total, p_detail: { berkas: files.length, gagal: failed, bagian: parts.length } });
        P.innerHTML = `<span class="${failed ? 'bad-t' : 'ok-t'}">Selesai: ${parts.length} ZIP, ${mb(total)}${failed ? `, ${failed} berkas gagal (lihat folder GAGAL di ZIP)` : ''}.</span>`;
      } catch (err) { P.innerHTML = `<span class="bad-t">${esc(err.message)}</span>`; }
      finally { btn.disabled = false; }
    };
  }

  window.JO_MOD.backup = { page };
})();
