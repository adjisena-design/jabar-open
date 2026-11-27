-- 27/11/2026: penutupan awal per disiplin & batas bayar.
--  * jo.disciplines.close_at  : pendaftaran disiplin ditutup otomatis pada waktu ini (sakelar registration_open dimatikan).
--  * jo.disciplines.pay_until : pendaftaran biasa (bukan massal, QRIS) disiplin ini yang belum mengunggah bukti bayar
--                               dibatalkan otomatis (status Dibatalkan, data tetap; bisa dipulihkan panitia).
--  * setting bulk_pay_until   : batch pendaftaran massal yang belum ada pembayaran dibatalkan (mode draf; bisa dipulihkan).
--  Dijalankan oleh jo.deadline_tick(), dipanggil dari jo.expire_unpaid() (setiap kunjungan situs, pendaftaran,
--  konsol, dan poll email setiap menit).

alter table jo.disciplines add column if not exists close_at timestamptz;
alter table jo.disciplines add column if not exists pay_until timestamptz;

create or replace function jo.deadline_tick() returns integer
language plpgsql set search_path = '' as $$
declare r record; n integer := 0; v_bulk timestamptz := nullif(jo.setting_text('bulk_pay_until'), '')::timestamptz;
begin
  -- 1) tutup disiplin yang sudah lewat jadwal
  for r in select code, close_at from jo.disciplines
            where registration_open and close_at is not null and now() >= close_at for update skip locked loop
    update jo.disciplines set registration_open = false where code = r.code;
    perform jo.log(null, 'disiplin_ditutup_terjadwal', 'discipline', r.code, jsonb_build_object('close_at', r.close_at));
    n := n + 1;
  end loop;

  -- 2) pendaftaran biasa tanpa bukti bayar setelah batas bayar disiplinnya
  for r in select s.id, s.code, s.discipline, s.total_amount, s.contact_name, d.pay_until
             from jo.submissions s join jo.disciplines d on d.code = s.discipline
            where s.status = 'menunggu_pembayaran' and s.bulk_batch_id is null and s.payment_method = 'qris'
              and s.proof_path is null and d.pay_until is not null and now() >= d.pay_until
            for update of s skip locked loop
    update jo.submissions set status = 'dibatalkan', updated_at = now(),
      cancel_reason = 'Otomatis: belum ada bukti bayar sampai batas bayar ' || to_char(r.pay_until at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB'
     where id = r.id;
    update jo.entries set status = 'dibatalkan' where submission_id = r.id;
    perform jo.log(null, 'pendaftaran_dibatalkan_otomatis', 'submission', r.id::text,
      jsonb_build_object('code', r.code, 'discipline', r.discipline, 'contact', r.contact_name, 'total', r.total_amount, 'pay_until', r.pay_until));
    n := n + 1;
  end loop;

  -- 3) batch massal tanpa pembayaran setelah batas bayar massal (portal pemulihan dikecualikan)
  if v_bulk is not null and now() >= v_bulk then
    for r in select bt.id, bt.code, a as acc from jo.bulk_batches bt join jo.bulk_accounts a on a.id = bt.bulk_id
              where bt.status = 'menunggu' and coalesce(a.settings->>'mode', '') <> 'pulih' and jo.bulk_batch_free(bt.id)
              for update of bt skip locked loop
      perform jo.bulk_cancel(r.acc, r.id, 'draf', 'Sistem', null,
        'Otomatis: belum ada pembayaran sampai batas bayar ' || to_char(v_bulk at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB');
      perform jo.log(null, 'massal_batch_dibatalkan', 'bulk', (r.acc).id::text,
        jsonb_build_object('club', (r.acc).label, 'batch', r.code, 'mode', 'draf', 'reason', 'otomatis: batas bayar massal'));
      n := n + 1;
    end loop;
  end if;
  return n;
end $$;
revoke all on function jo.deadline_tick() from public, anon, authenticated;

-- jalankan dari expire_unpaid (sebelum pengecekan proof_minutes)
do $do$
declare d text := pg_get_functiondef('jo.expire_unpaid()'::regprocedure);
  a text := 'begin
  if v_min <= 0 then return 0; end if;';
begin
  if position('jo.deadline_tick()' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'expire_unpaid: pola tidak ditemukan'; end if;
  execute replace(d, a, 'begin
  perform jo.deadline_tick();
  if v_min <= 0 then return 0; end if;');
end $do$;

-- konsol: ubah jadwal tutup & batas bayar per disiplin (owner & superadmin)
do $do$
declare d text := pg_get_functiondef('public.console_update_discipline(text,jsonb)'::regprocedure);
  a text := 'date_end = coalesce(nullif(p_patch->>''date_end'','''')::date, date_end)';
begin
  if position('close_at' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'console_update_discipline: pola tidak ditemukan'; end if;
  execute replace(d, a, a || ',
    close_at = case when p_patch ? ''close_at'' then nullif(p_patch->>''close_at'','''')::timestamptz else close_at end,
    pay_until = case when p_patch ? ''pay_until'' then nullif(p_patch->>''pay_until'','''')::timestamptz else pay_until end');
end $do$;

-- situs: kirim jadwal tutup & batas bayar ke formulir
do $do$
declare d text := pg_get_functiondef('public.public_config()'::regprocedure);
  a text := '''registration_open'', d.registration_open) order by d.sort)';
begin
  if position('''close_at'', d.close_at' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'public_config: pola tidak ditemukan'; end if;
  execute replace(d, a, '''registration_open'', d.registration_open, ''close_at'', d.close_at, ''pay_until'', d.pay_until) order by d.sort)');
end $do$;

-- jadwal Jabar Open 2026 (keputusan panitia 27/11/2026: kapasitas penuh)
update jo.disciplines set close_at = '2026-11-27 18:00:00+07', pay_until = '2026-11-27 23:59:59+07' where code in ('MAG','WAG','RG');
insert into jo.settings (key, value, updated_at) values ('bulk_pay_until', to_jsonb('2026-11-30T23:59:59+07:00'::text), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- label batas bayar per pendaftaran (email "Pendaftaran diterima" & halaman status)
create or replace function jo.pay_deadline_label(s jo.submissions) returns text
language sql stable set search_path = '' as $$
  select case
    when s.bulk_batch_id is null and d.pay_until is not null then
      to_char(d.pay_until at time zone 'Asia/Jakarta', 'FMDD') || ' ' ||
      (array['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'])
        [extract(month from d.pay_until at time zone 'Asia/Jakarta')::int] || ' ' ||
      to_char(d.pay_until at time zone 'Asia/Jakarta', 'YYYY') || ' pukul ' ||
      to_char(d.pay_until at time zone 'Asia/Jakarta', 'HH24.MI') || ' WIB'
    else coalesce(jo.setting_text('payment_deadline_label'), '30 November 2026') end
  from jo.disciplines d where d.code = s.discipline
$$;
-- queue_registration_email & submission_public_json: 'payment_deadline_label' diganti jo.pay_deadline_label(s) (string patch, lihat migrasi label_batas_bayar_per_pendaftaran)
-- teks berjalan beranda diperbarui (setting ticker) 27/11/2026 14.4x WIB
