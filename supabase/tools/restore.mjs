#!/usr/bin/env node
/* =====================================================================
   Jabar Open 2026 — pemulihan dari "Backup darurat" konsol.

   Data (setelah setup.sql dijalankan di proyek Supabase BARU):
     cd supabase/tools && npm install pg
     DATABASE_URL="postgresql://postgres.xxxx:PASSWORD@aws-0-...pooler.supabase.com:5432/postgres" \
       node restore.mjs /path/ke/data.json

   Berkas (isi ZIP "berkas" diekstrak ke satu folder berisi dokumen/, bukti/, publik/):
     SUPABASE_URL="https://xxxx.supabase.co" SUPABASE_SERVICE_KEY="..." \
       node restore.mjs --files /path/ke/folder-berkas

   Yang dilakukan bagian data:
   * Semua tabel jo.* yang ada di backup dikosongkan lalu diisi ulang dari
     data.json (urutan mengikuti relasi antartabel).
   * Kode owner baru dari setup.sql tetap berlaku. Kode akses lama TIDAK ikut
     backup: baris staff lama dipulihkan dalam keadaan nonaktif (agar riwayat
     tetap tersambung); buat kode baru di Konsol > Kode akses.
   * Pengaturan rahasia hasil setup baru (secret email) dipertahankan.
   * Nomor urut (sequence) disetel ke nilai tertinggi.
   Semua dalam satu transaksi: gagal di tengah = tidak ada yang berubah.
   Service key hanya diketik di Terminal sendiri. Jangan disimpan di repo.
   ===================================================================== */
import fs from 'node:fs';
import path from 'node:path';

const SKIP = new Set(['staff_sessions', 'login_attempts', 'rate_events']);
const SECRET = /secret|hash|token/i;

async function restoreData(file) {
  const { default: pg } = await import('pg');
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (data.format !== 'jabar-open-backup') throw new Error('Ini bukan data.json dari Backup darurat.');
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('Isi DATABASE_URL (Supabase > Connect > Session pooler).');
  const db = new pg.Client({ connectionString: url, ssl: /localhost|127\.0\.0\.1/.test(url) ? false : { rejectUnauthorized: false } });
  await db.connect();
  const q = (sql, params) => db.query(sql, params);
  try {
    const live = (await q(`select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'jo' and c.relkind = 'r'`)).rows.map((r) => r.relname);
    const tables = Object.keys(data.tables).filter((t) => live.includes(t) && !SKIP.has(t));
    const unknown = Object.keys(data.tables).filter((t) => !live.includes(t));
    if (unknown.length) console.warn('Tabel di backup tapi tidak ada di database (dilewati):', unknown.join(', '));

    // urutan isi: induk dulu (relasi foreign key di skema jo)
    const fk = (await q(`select c.conrelid::regclass::text child, c.confrelid::regclass::text parent
                           from pg_constraint c join pg_namespace n on n.oid = c.connamespace
                          where c.contype = 'f' and n.nspname = 'jo'`)).rows
      .map((r) => ({ child: r.child.replace(/^jo\./, ''), parent: r.parent.replace(/^jo\./, '') }));
    const order = []; const seen = new Set();
    const visit = (t, stack = new Set()) => {
      if (seen.has(t) || stack.has(t)) return; stack.add(t);
      fk.filter((e) => e.child === t && e.parent !== t).forEach((e) => tables.includes(e.parent) && visit(e.parent, stack));
      seen.add(t); order.push(t);
    };
    tables.forEach((t) => visit(t));

    await q('begin');
    await q('savepoint rr');
    try { await q('set local session_replication_role = replica'); await q('release savepoint rr'); }
    catch { await q('rollback to savepoint rr'); /* tanpa hak ini, urutan relasi tetap menjaga */ }
    // simpan yang dibuat setup baru: owner baru & pengaturan rahasia
    const keepStaff = (await q('select * from jo.staff')).rows;
    const keepSecret = (await q('select * from jo.settings')).rows.filter((r) => SECRET.test(r.key));

    await q(`truncate ${[...new Set([...order, 'staff'])].map((t) => `jo."${t}"`).join(', ')} cascade`);

    for (const t of order) {
      let rows = data.tables[t] || [];
      if (!rows.length) { console.log(`  ${t}: 0`); continue; }
      if (t === 'staff') {
        rows = rows.filter((r) => !keepStaff.some((k) => k.id === r.id))
          .map((r) => ({ ...r, code_hash: 'dipulihkan-' + r.id, code_hint: null, active: false }));
      }
      const meta = (await q(`select attname, attnotnull, format_type(atttypid, atttypmod) typ from pg_attribute
                               where attrelid = $1::regclass and attnum > 0 and not attisdropped and attgenerated = ''`, [`jo."${t}"`])).rows;
      const cols = meta.map((r) => `"${r.attname}"`);
      // kolom json/jsonb diambil apa adanya (termasuk nilai JSON null), kolom lain lewat populate_record
      const sel = meta.map((r) => (/^jsonb?$/.test(r.typ) ? (r.attnotnull ? `coalesce(x->'${r.attname}', 'null'::jsonb)::${r.typ}` : `nullif(x->'${r.attname}', 'null'::jsonb)::${r.typ}`) : `r."${r.attname}"`));
      for (let i = 0; i < rows.length; i += 500) {
        await q(`insert into jo."${t}" (${cols.join(', ')}) overriding system value
                 select ${sel.join(', ')} from jsonb_array_elements($1::jsonb) x, jsonb_populate_record(null::jo."${t}", x) r`, [JSON.stringify(rows.slice(i, i + 500))]);
      }
      console.log(`  ${t}: ${rows.length}`);
    }
    // kembalikan owner baru & rahasia baru
    for (const s of keepStaff) {
      await q(`insert into jo.staff select * from jsonb_populate_record(null::jo.staff, $1::jsonb) on conflict (id) do nothing`, [JSON.stringify(s)]);
    }
    for (const s of keepSecret) {
      await q(`insert into jo.settings (key, value) values ($1, $2::jsonb) on conflict (key) do update set value = excluded.value`, [s.key, JSON.stringify(s.value)]);
    }
    // sequence
    const seqs = (await q(`select c.relname tbl, a.attname col, pg_get_serial_sequence('jo.' || quote_ident(c.relname), a.attname) seq
                             from pg_class c join pg_namespace n on n.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid
                            where n.nspname = 'jo' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped`)).rows.filter((r) => r.seq);
    for (const s of seqs) {
      await q(`select setval($1, greatest(coalesce((select max("${s.col}") from jo."${s.tbl}"), 0), 1))`, [s.seq]);
    }
    await q('commit');
    console.log(`\nSelesai: ${order.length} tabel dipulihkan dari backup ${data.generated_at}.`);
    console.log('Langkah berikut: masuk konsol dengan kode owner baru, buat ulang kode akses, lanjutkan dari TITIK-LANJUT.txt.');
  } catch (e) {
    await q('rollback').catch(() => {});
    throw e;
  } finally { await db.end(); }
}

async function restoreFiles(dir) {
  const base = process.env.SUPABASE_URL; const key = process.env.SUPABASE_SERVICE_KEY;
  if (!base || !key) throw new Error('Isi SUPABASE_URL dan SUPABASE_SERVICE_KEY.');
  const types = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.pdf': 'application/pdf', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.wav': 'audio/wav' };
  let ok = 0; let bad = 0;
  for (const bucket of ['dokumen', 'bukti', 'publik']) {
    const root = path.join(dir, bucket);
    if (!fs.existsSync(root)) continue;
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
    for (const f of walk(root)) {
      const name = path.relative(root, f).split(path.sep).join('/');
      const r = await fetch(`${base.replace(/\/$/, '')}/storage/v1/object/${bucket}/${name.split('/').map(encodeURIComponent).join('/')}`, {
        method: 'POST', body: fs.readFileSync(f),
        headers: { Authorization: `Bearer ${key}`, apikey: key, 'x-upsert': 'true', 'Content-Type': types[path.extname(f).toLowerCase()] || 'application/octet-stream' },
      });
      if (r.ok) ok++; else { bad++; console.warn(`  gagal ${bucket}/${name}: ${r.status} ${await r.text()}`); }
      if ((ok + bad) % 50 === 0) console.log(`  ${ok + bad} berkas…`);
    }
  }
  console.log(`Selesai: ${ok} berkas terunggah${bad ? `, ${bad} gagal` : ''}.`);
}

const [a, b] = process.argv.slice(2);
(a === '--files' ? restoreFiles(b) : a ? restoreData(a) : Promise.reject(new Error('Pemakaian: node restore.mjs data.json  |  node restore.mjs --files folder')))
  .catch((e) => { console.error('GAGAL:', e.message); process.exit(1); });
