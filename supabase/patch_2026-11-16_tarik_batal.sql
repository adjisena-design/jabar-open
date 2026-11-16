-- =====================================================================
--  Pendaftaran massal: tarik atlet, batalkan batch, pulihkan, hapus permanen
--  - Klub (pemilik/kolaborator) boleh menarik atlet / membatalkan batch selama
--    batch belum ada pembayaran (tidak ada bukti transfer menunggu/terverifikasi).
--  - Owner & superadmin boleh kapan saja, termasuk batch lunas (tagihan tetap,
--    selisih dicatat sebagai dana yang perlu dikembalikan).
--  - Setiap tindakan disimpan lengkap di jo.bulk_actions sehingga owner/superadmin
--    bisa memulihkan, sampai ditekan "Hapus permanen".
-- =====================================================================

alter table jo.athletes add column if not exists bulk_row_id uuid;
create index if not exists athletes_bulk_row_idx on jo.athletes(bulk_row_id);
alter table jo.bulk_batches add column if not exists refund_due integer not null default 0;

create table if not exists jo.bulk_actions (
  id          bigserial primary key,
  bulk_id     uuid not null references jo.bulk_accounts(id) on delete cascade,
  batch_id    uuid references jo.bulk_batches(id) on delete set null,
  kind        text not null check (kind in ('atlet_ditarik','baris_dihapus','batch_dibatalkan')),
  mode        text,                                   -- batch: 'draf' | 'hapus'
  label       text,                                   -- nama atlet / kode batch
  row_nos     integer[] not null default '{}',
  amount      integer not null default 0,             -- biaya yang keluar dari tagihan (atau yang perlu dikembalikan)
  refund      integer not null default 0,             -- dana yang perlu dikembalikan (batch sudah lunas / terverifikasi)
  snap        jsonb not null,
  person      text,
  staff_id    uuid references jo.staff(id),
  reason      text,
  created_at  timestamptz not null default now(),
  restored_at timestamptz, restored_by uuid references jo.staff(id),
  purged_at   timestamptz, purged_by uuid references jo.staff(id)
);
create index if not exists bulk_actions_bulk_idx on jo.bulk_actions(bulk_id, created_at desc);
alter table jo.bulk_actions enable row level security;

-- jo.norm_name (sudah ada): huruf kecil, hanya huruf/angka

-- tautkan atlet batch ke baris lembarnya (dipanggil saat batch dikirim, dan sekali untuk data lama)
create or replace function jo.bulk_link_rows(p_batch uuid) returns void
language sql volatile set search_path = '' as $$
  update jo.athletes a set bulk_row_id = r.id
    from jo.bulk_rows r, jo.submissions s
   where s.bulk_batch_id = p_batch and a.submission_id = s.id and a.bulk_row_id is null
     and r.batch_id = p_batch and r.data->>'discipline' = s.discipline
     and jo.norm_name(a.full_name) = jo.norm_name(r.data->>'full_name')
     and a.birth_date::text = r.data->>'birth_date'
     and not exists (select 1 from jo.athletes x where x.bulk_row_id = r.id);
$$;

-- isi ulang baris dari cuplikan; bila nomor barisnya sudah terpakai, pakai nomor kosong berikutnya
create or replace function jo.bulk_put_row(p_row jsonb, p_batch uuid) returns integer
language plpgsql volatile set search_path = '' as $$
declare r jo.bulk_rows; v_no integer; v_max integer := coalesce(jo.setting_int('bulk_max'), 250);
begin
  r := jsonb_populate_record(null::jo.bulk_rows, p_row);
  v_no := r.row_no;
  if exists (select 1 from jo.bulk_rows x where x.bulk_id = r.bulk_id and x.row_no = v_no and x.id <> r.id) then
    select min(g) into v_no from generate_series(1, v_max) g
     where not exists (select 1 from jo.bulk_rows x where x.bulk_id = r.bulk_id and x.row_no = g);
    if v_no is null then raise exception 'Lembar klub sudah penuh (% baris). Kosongkan satu baris dulu.', v_max; end if;
  end if;
  insert into jo.bulk_rows (id, bulk_id, row_no, data, photo_thumb, batch_id, updated_at, updated_by)
  values (r.id, r.bulk_id, v_no, r.data, r.photo_thumb, p_batch, now(), 'Panitia (dipulihkan)')
  on conflict (id) do update set row_no = excluded.row_no, data = excluded.data, photo_thumb = excluded.photo_thumb,
    batch_id = excluded.batch_id, updated_at = now(), updated_by = excluded.updated_by;
  return v_no;
end $$;

-- isi ulang baris tabel dari cuplikan jsonb
create or replace function jo.snap_put(p_table text, p_rows jsonb) returns void
language plpgsql volatile set search_path = '' as $$
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return; end if;
  execute format('insert into %s select * from jsonb_populate_recordset(null::%s, $1)', p_table, p_table) using p_rows;
end $$;

-- hitung ulang jumlah atlet & tagihan batch (tagihan hanya bila belum lunas)
create or replace function jo.bulk_batch_recalc(p_batch uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare bt jo.bulk_batches; v_total integer; v_sum integer;
begin
  select * into bt from jo.bulk_batches where id = p_batch for update;
  update jo.bulk_batches set athletes = (select count(*) from jo.bulk_rows r where r.batch_id = bt.id) where id = bt.id;
  if bt.status = 'menunggu' then
    select coalesce(sum(total_amount), 0) into v_total from jo.submissions where bulk_batch_id = bt.id and status <> 'dibatalkan';
    select coalesce(sum((x)::text::integer), 0) into v_sum from jsonb_array_elements(coalesce(bt.split->'amounts', '[]'::jsonb)) x;
    update jo.bulk_batches set total = v_total,
      split = case when v_sum = v_total then split else jsonb_build_object('mode', 'penuh', 'amounts', jsonb_build_array(v_total)) end
     where id = bt.id;
  end if;
end $$;

-- batch boleh diubah klub sendiri? (belum ada pembayaran sama sekali)
create or replace function jo.bulk_batch_free(p_batch uuid) returns boolean
language sql stable set search_path = '' as $$
  select bt.status = 'menunggu' and not exists (select 1 from jo.bulk_payments p where p.batch_id = bt.id and p.status in ('menunggu','cocok'))
    from jo.bulk_batches bt where bt.id = p_batch
$$;

-- ---------------------------------------------------------------------
-- Tarik satu atlet (baris terkirim) atau hapus baris draf
-- ---------------------------------------------------------------------
create or replace function jo.bulk_withdraw(b jo.bulk_accounts, p_row integer, p_person text, p_staff uuid, p_reason text) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare r jo.bulk_rows; bt jo.bulk_batches; a jo.athletes; s jo.submissions; v_e uuid[]; v_snap jsonb; v_teams uuid[]; v_empty uuid[];
        v_tfee integer := coalesce(jo.setting_int('team_fee'), 650000); v_fee integer := 0; v_amount integer := 0; v_refund integer := 0;
        v_paid boolean; v_kind text; v_label text; v_id bigint; v_n integer;
begin
  select * into r from jo.bulk_rows where bulk_id = b.id and row_no = p_row for update;
  if r.id is null then raise exception 'Baris % tidak ditemukan (mungkin sudah dihapus). Muat ulang.', p_row using hint = 'ERR_BULK_ROWS'; end if;
  v_label := coalesce(nullif(btrim(r.data->>'full_name'), ''), 'Baris ' || lpad(p_row::text, 3, '0'));

  if r.batch_id is null then
    v_kind := 'baris_dihapus';
    v_snap := jsonb_build_object('row', to_jsonb(r));
    delete from jo.bulk_rows where id = r.id;
  else
    v_kind := 'atlet_ditarik';
    select * into bt from jo.bulk_batches where id = r.batch_id for update;
    if bt.status = 'dibatalkan' then raise exception 'Batch % sudah dibatalkan.', bt.code using hint = 'ERR_BULK_BATCH'; end if;
    if p_staff is null and not jo.bulk_batch_free(bt.id) then
      raise exception 'Batch % sudah ada pembayaran. Untuk menarik atlet, hubungi Inda.', bt.code using hint = 'ERR_BULK_PAID';
    end if;
    if (select count(*) from jo.bulk_rows x where x.batch_id = bt.id) <= 1 then
      raise exception 'Ini atlet terakhir di batch %. Batalkan batchnya.', bt.code using hint = 'ERR_BULK_LAST';
    end if;
    v_paid := bt.status = 'lunas';
    perform jo.bulk_link_rows(bt.id);
    select a2.* into a from jo.athletes a2 where a2.bulk_row_id = r.id;
    if a.id is null and p_staff is null then
      raise exception 'Atlet baris % (%) tidak ditemukan di pendaftaran batch %. Hubungi panitia.', lpad(p_row::text, 3, '0'), v_label, bt.code using hint = 'ERR_BULK_LINK';
    end if;
    if a.id is null then
      -- data atlet sudah dihapus lewat halaman Pendaftaran; rapikan barisnya saja
      v_snap := jsonb_build_object('row', to_jsonb(r), 'orphan', true);
      delete from jo.bulk_rows where id = r.id;
      perform jo.bulk_batch_recalc(bt.id);
      insert into jo.bulk_actions (bulk_id, batch_id, kind, label, row_nos, amount, refund, snap, person, staff_id, reason)
      values (b.id, r.batch_id, 'atlet_ditarik', v_label, array[p_row], 0, 0, v_snap, p_person, p_staff, nullif(btrim(coalesce(p_reason, '')), ''))
      returning id into v_id;
      perform jo.bulk_add_log(b.id, p_person, 'atlet_ditarik', jsonb_build_object('row_no', p_row, 'name', v_label, 'code', bt.code, 'amount', 0,
        'deleted_rows', jsonb_build_array(p_row), 'note', nullif(btrim(coalesce(p_reason, '')), '')));
      return jsonb_build_object('ok', true, 'action', v_id, 'kind', 'atlet_ditarik', 'amount', 0, 'refund', 0, 'orphan', true);
    end if;
    select * into s from jo.submissions where id = a.submission_id for update;
    if s.status = 'dibatalkan' then raise exception 'Pendaftaran % sudah dibatalkan.', s.code; end if;
    v_e := array(select ea.entry_id from jo.entry_athletes ea where ea.athlete_id = a.id
                 union select m.entry_id from jo.team_members m where m.athlete_id = a.id and m.team_only);
    if exists (select 1 from jo.scores sc where sc.entry_id = any(v_e)) or exists (select 1 from jo.jscores j where j.entry_id = any(v_e)) then
      raise exception '% sudah punya nilai, tidak bisa ditarik. Tandai "Tidak tampil (DNS)".', v_label;
    end if;

    if not exists (select 1 from jo.athletes x where x.submission_id = s.id and x.id <> a.id) then
      -- satu-satunya atlet di pendaftaran ini: batalkan pendaftarannya (bisa dipulihkan)
      v_snap := jsonb_build_object('row', to_jsonb(r), 'sub', jsonb_build_object('id', s.id, 'code', s.code, 'status', s.status, 'cancel_reason', s.cancel_reason),
        'entries', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'status', e.status)), '[]'::jsonb) from jo.entries e where e.submission_id = s.id));
      v_amount := s.total_amount;
      update jo.submissions set status = 'dibatalkan', cancel_reason = coalesce(nullif(btrim(p_reason), ''), 'Atlet ditarik dari pendaftaran massal'), updated_at = now() where id = s.id;
      update jo.entries set status = 'dibatalkan' where submission_id = s.id;
    else
      v_teams := array(select distinct m.team_id from jo.team_members m where m.athlete_id = a.id or m.entry_id = any(v_e));
      v_snap := jsonb_build_object('row', to_jsonb(r), 'sub_id', s.id,
        'athlete', to_jsonb(a),
        'entries', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) from jo.entries e where e.id = any(v_e)),
        'entry_athletes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from jo.entry_athletes x where x.entry_id = any(v_e)),
        'music_log', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from jo.music_log x where x.entry_id = any(v_e)),
        'sim_order', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from jo.sim_order x where x.entry_id = any(v_e)),
        'team_members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from jo.team_members x where x.athlete_id = a.id or x.entry_id = any(v_e)),
        'file_log', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from jo.athlete_file_log x where x.athlete_id = a.id));
      select coalesce(sum(fee), 0) into v_fee from jo.entries where id = any(v_e) and status <> 'dibatalkan';
      delete from jo.team_members where athlete_id = a.id or entry_id = any(v_e);
      v_empty := array(select t.id from jo.teams t where t.id = any(v_teams) and not exists (select 1 from jo.team_members m where m.team_id = t.id));
      v_snap := v_snap || jsonb_build_object('teams', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from jo.teams t where t.id = any(v_empty)), 'team_fee', v_tfee);
      delete from jo.teams where id = any(v_empty);
      delete from jo.sim_order where entry_id = any(v_e);
      delete from jo.music_log where entry_id = any(v_e);
      delete from jo.entry_athletes where entry_id = any(v_e);
      delete from jo.entries where id = any(v_e);
      delete from jo.athlete_file_log where athlete_id = a.id;
      delete from jo.athletes where id = a.id;
      v_n := coalesce(array_length(v_empty, 1), 0);
      v_amount := v_fee + v_tfee * v_n;
      if not v_paid then
        update jo.submissions set team_amount = greatest(team_amount - v_tfee * v_n, 0) where id = s.id;
        perform jo.recalc_bill(s.id);
      end if;
    end if;
    delete from jo.bulk_rows where id = r.id;
    perform jo.bulk_batch_recalc(bt.id);
    if v_paid then
      v_refund := v_amount;
      update jo.bulk_batches set refund_due = refund_due + v_refund where id = bt.id;
    end if;
  end if;

  insert into jo.bulk_actions (bulk_id, batch_id, kind, label, row_nos, amount, refund, snap, person, staff_id, reason)
  values (b.id, r.batch_id, v_kind, v_label, array[p_row], v_amount, v_refund, v_snap, p_person, p_staff, nullif(btrim(coalesce(p_reason, '')), ''))
  returning id into v_id;
  perform jo.bulk_add_log(b.id, p_person, case when v_kind = 'baris_dihapus' then 'baris_dihapus' else 'atlet_ditarik' end,
    jsonb_build_object('row_no', p_row, 'name', v_label, 'code', bt.code, 'amount', v_amount, 'refund', v_refund,
                       'deleted_rows', jsonb_build_array(p_row), 'note', nullif(btrim(coalesce(p_reason, '')), '')));
  update jo.bulk_accounts set updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true, 'action', v_id, 'kind', v_kind, 'amount', v_amount, 'refund', v_refund);
end $$;

-- ---------------------------------------------------------------------
-- Batalkan seluruh batch. p_mode: 'draf' (atlet kembali ke lembar sebagai draf) | 'hapus' (atlet dihapus dari lembar)
-- ---------------------------------------------------------------------
create or replace function jo.bulk_cancel(b jo.bulk_accounts, p_batch uuid, p_mode text, p_person text, p_staff uuid, p_reason text) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare bt jo.bulk_batches; v_snap jsonb; v_rows integer[]; v_refund integer; v_id bigint;
begin
  if p_mode not in ('draf', 'hapus') then raise exception 'Pilihan tidak dikenal.'; end if;
  select * into bt from jo.bulk_batches where id = p_batch and bulk_id = b.id for update;
  if bt.id is null then raise exception 'Batch tidak ditemukan.' using hint = 'ERR_BULK_BATCH'; end if;
  if bt.status = 'dibatalkan' then raise exception 'Batch % sudah dibatalkan.', bt.code using hint = 'ERR_BULK_BATCH'; end if;
  if p_staff is null and not jo.bulk_batch_free(bt.id) then
    raise exception 'Batch % sudah ada pembayaran. Untuk membatalkannya, hubungi Inda.', bt.code using hint = 'ERR_BULK_PAID';
  end if;
  if exists (select 1 from jo.scores sc join jo.entries e on e.id = sc.entry_id join jo.submissions s on s.id = e.submission_id where s.bulk_batch_id = bt.id)
     or exists (select 1 from jo.jscores j join jo.entries e on e.id = j.entry_id join jo.submissions s on s.id = e.submission_id where s.bulk_batch_id = bt.id) then
    raise exception 'Sebagian atlet batch % sudah punya nilai. Batch tidak bisa dibatalkan.', bt.code;
  end if;
  v_rows := array(select row_no from jo.bulk_rows where batch_id = bt.id order by row_no);
  select coalesce(sum(amount), 0) into v_refund from jo.bulk_payments where batch_id = bt.id and status = 'cocok';
  v_snap := jsonb_build_object(
    'batch', jsonb_build_object('status', bt.status, 'due_at', bt.due_at, 'paid_at', bt.paid_at),
    'subs', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'status', s.status, 'cancel_reason', s.cancel_reason)), '[]'::jsonb)
               from jo.submissions s where s.bulk_batch_id = bt.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'status', e.status)), '[]'::jsonb)
                  from jo.entries e join jo.submissions s on s.id = e.submission_id where s.bulk_batch_id = bt.id),
    'rows', (select coalesce(jsonb_agg(to_jsonb(r) order by r.row_no), '[]'::jsonb) from jo.bulk_rows r where r.batch_id = bt.id));
  update jo.entries e set status = 'dibatalkan' from jo.submissions s where s.id = e.submission_id and s.bulk_batch_id = bt.id;
  update jo.submissions set status = 'dibatalkan', updated_at = now(),
    cancel_reason = coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Batch ' || bt.code || ' dibatalkan')
   where bulk_batch_id = bt.id and status <> 'dibatalkan';
  if p_mode = 'draf' then
    update jo.bulk_rows set batch_id = null, updated_at = now(), updated_by = coalesce(p_person, 'Panitia') where batch_id = bt.id;
  else
    delete from jo.bulk_rows where batch_id = bt.id;
  end if;
  update jo.bulk_batches set status = 'dibatalkan', refund_due = refund_due + v_refund where id = bt.id;

  insert into jo.bulk_actions (bulk_id, batch_id, kind, mode, label, row_nos, amount, refund, snap, person, staff_id, reason)
  values (b.id, bt.id, 'batch_dibatalkan', p_mode, bt.code, v_rows, bt.total, v_refund, v_snap, p_person, p_staff, nullif(btrim(coalesce(p_reason, '')), ''))
  returning id into v_id;
  perform jo.bulk_add_log(b.id, p_person, 'batch_dibatalkan',
    jsonb_build_object('code', bt.code, 'mode', p_mode, 'athletes', coalesce(array_length(v_rows, 1), 0), 'total', bt.total, 'refund', v_refund,
                       'deleted_rows', case when p_mode = 'hapus' then to_jsonb(v_rows) else '[]'::jsonb end, 'note', nullif(btrim(coalesce(p_reason, '')), '')));
  update jo.bulk_accounts set updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true, 'action', v_id, 'rows', coalesce(array_length(v_rows, 1), 0), 'refund', v_refund);
end $$;

-- ---------------------------------------------------------------------
-- Portal klub
-- ---------------------------------------------------------------------
create or replace function public.public_bulk_withdraw(p_code text, p_person text, p_row integer, p_reason text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts;
begin
  b := jo.bulk_auth(p_code, p_person, true);
  return jo.bulk_withdraw(b, p_row, jo.bulk_person_name(b, p_person), null, p_reason);
end $$;

create or replace function public.public_bulk_cancel_batch(p_code text, p_person text, p_batch uuid, p_mode text, p_reason text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts;
begin
  b := jo.bulk_auth(p_code, p_person, true);
  return jo.bulk_cancel(b, p_batch, p_mode, jo.bulk_person_name(b, p_person), null, p_reason);
end $$;

-- ---------------------------------------------------------------------
-- Konsol (owner & superadmin)
-- ---------------------------------------------------------------------
create or replace function public.console_bulk_withdraw(p_id uuid, p_row integer, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v_res jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  v_res := jo.bulk_withdraw(b, p_row, st.name, st.id, jo.need_reason(p_reason));
  perform jo.log(st.id, 'massal_' || (v_res->>'kind'), 'bulk', b.id::text,
    jsonb_build_object('club', b.label, 'row_no', p_row, 'amount', v_res->'amount', 'refund', v_res->'refund', 'reason', p_reason));
  return v_res;
end $$;

create or replace function public.console_bulk_cancel_batch(p_batch uuid, p_mode text, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v_res jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select a.* into b from jo.bulk_accounts a join jo.bulk_batches bt on bt.bulk_id = a.id where bt.id = p_batch;
  if b.id is null then raise exception 'Batch tidak ditemukan.'; end if;
  v_res := jo.bulk_cancel(b, p_batch, p_mode, st.name, st.id, jo.need_reason(p_reason));
  perform jo.log(st.id, 'massal_batch_dibatalkan', 'bulk', b.id::text,
    jsonb_build_object('club', b.label, 'batch', (select code from jo.bulk_batches where id = p_batch), 'mode', p_mode, 'refund', v_res->'refund', 'reason', p_reason));
  return v_res;
end $$;

create or replace function public.console_bulk_restore(p_action bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.bulk_actions; b jo.bulk_accounts; bt jo.bulk_batches; s jo.submissions; v_row jsonb; ex jo.bulk_rows; v_n integer; v_no integer;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into x from jo.bulk_actions where id = p_action for update;
  if x.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if x.restored_at is not null then raise exception 'Sudah dipulihkan.'; end if;
  if x.purged_at is not null then raise exception 'Sudah dihapus permanen, tidak bisa dipulihkan.'; end if;
  select * into b from jo.bulk_accounts where id = x.bulk_id for update;

  if x.kind = 'baris_dihapus' then
    v_no := jo.bulk_put_row(x.snap->'row', null);

  elsif x.kind = 'atlet_ditarik' then
    select * into bt from jo.bulk_batches where id = x.batch_id for update;
    if bt.id is null or bt.status = 'dibatalkan' then raise exception 'Batch atlet ini sudah dibatalkan. Pulihkan batchnya dulu.'; end if;
    if bt.status = 'lunas' and x.refund = 0 then
      raise exception 'Batch % sudah lunas setelah atlet ini ditarik. Daftarkan atlet ini di batch baru.', bt.code;
    end if;
    if exists (select 1 from jo.bulk_rows r where r.id = (x.snap->'row'->>'id')::uuid) then
      raise exception 'Baris atlet ini sudah ada lagi di lembar klub.';
    end if;
    if x.snap ? 'orphan' then
      raise exception 'Data pendaftaran atlet ini sudah dihapus sebelumnya lewat halaman Pendaftaran, jadi tidak bisa dipulihkan. Daftarkan lagi di batch baru.';
    end if;
    if x.snap ? 'sub' then
      select * into s from jo.submissions where id = (x.snap->'sub'->>'id')::uuid for update;
      if s.id is null then raise exception 'Pendaftaran % sudah dihapus permanen.', x.snap->'sub'->>'code'; end if;
      update jo.submissions set status = x.snap->'sub'->>'status', cancel_reason = x.snap->'sub'->>'cancel_reason', updated_at = now() where id = s.id;
      update jo.entries e set status = z->>'status' from jsonb_array_elements(x.snap->'entries') z where e.id = (z->>'id')::uuid;
    else
      select * into s from jo.submissions where id = (x.snap->>'sub_id')::uuid for update;
      if s.id is null or s.status = 'dibatalkan' then raise exception 'Pendaftaran atlet ini sudah dibatalkan atau dihapus.'; end if;
      perform jo.snap_put('jo.teams', x.snap->'teams');
      perform jo.snap_put('jo.athletes', jsonb_build_array(x.snap->'athlete'));
      perform jo.snap_put('jo.entries', x.snap->'entries');
      perform jo.snap_put('jo.entry_athletes', x.snap->'entry_athletes');
      perform jo.snap_put('jo.team_members', x.snap->'team_members');
      perform jo.snap_put('jo.music_log', x.snap->'music_log');
      perform jo.snap_put('jo.sim_order', x.snap->'sim_order');
      perform jo.snap_put('jo.athlete_file_log', x.snap->'file_log');
      if x.refund = 0 then
        v_n := jsonb_array_length(coalesce(x.snap->'teams', '[]'::jsonb));
        update jo.submissions set team_amount = team_amount + coalesce((x.snap->>'team_fee')::integer, 0) * v_n where id = s.id;
        perform jo.recalc_bill(s.id);
      end if;
    end if;
    v_no := jo.bulk_put_row(x.snap->'row', bt.id);
    perform jo.bulk_batch_recalc(bt.id);
    if x.refund > 0 then update jo.bulk_batches set refund_due = greatest(refund_due - x.refund, 0) where id = bt.id; end if;

  else  -- batch_dibatalkan
    select * into bt from jo.bulk_batches where id = x.batch_id for update;
    if bt.id is null then raise exception 'Batch sudah tidak ada.'; end if;
    for v_row in select * from jsonb_array_elements(x.snap->'rows') loop
      select * into ex from jo.bulk_rows where id = (v_row->>'id')::uuid;
      if ex.id is not null and ex.batch_id is not null and ex.batch_id <> bt.id then
        raise exception 'Baris % (%) sudah dikirim lagi di batch lain. Batch ini tidak bisa dipulihkan; tarik dulu atlet di batch baru bila perlu.',
          lpad(ex.row_no::text, 3, '0'), ex.data->>'full_name';
      end if;
    end loop;
    if exists (select 1 from jsonb_array_elements(x.snap->'subs') z where not exists (select 1 from jo.submissions s2 where s2.id = (z->>'id')::uuid)) then
      raise exception 'Sebagian pendaftaran batch ini sudah dihapus permanen.';
    end if;
    for v_row in select * from jsonb_array_elements(x.snap->'rows') loop
      perform jo.bulk_put_row(v_row, bt.id);
    end loop;
    update jo.submissions sb set status = z->>'status', cancel_reason = z->>'cancel_reason', updated_at = now()
      from jsonb_array_elements(x.snap->'subs') z where sb.id = (z->>'id')::uuid;
    update jo.entries e set status = z->>'status' from jsonb_array_elements(x.snap->'entries') z where e.id = (z->>'id')::uuid;
    update jo.bulk_batches set status = x.snap->'batch'->>'status', refund_due = greatest(refund_due - x.refund, 0),
      due_at = case when x.snap->'batch'->>'status' = 'menunggu' then greatest(due_at, now() + interval '48 hours') else due_at end
     where id = bt.id;
    perform jo.bulk_link_rows(bt.id);
  end if;

  update jo.bulk_actions set restored_at = now(), restored_by = st.id where id = x.id;
  perform jo.bulk_add_log(b.id, st.name, 'dipulihkan', jsonb_build_object('what', x.kind, 'label', x.label, 'code', (select code from jo.bulk_batches where id = x.batch_id)));
  perform jo.log(st.id, 'massal_dipulihkan', 'bulk', b.id::text, jsonb_build_object('club', b.label, 'what', x.kind, 'label', x.label));
  update jo.bulk_accounts set updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true);
end $$;

-- Hapus permanen: data pendaftaran yang dibatalkan ikut dihapus; berkas yang tidak dipakai lagi dikembalikan untuk dihapus dari penyimpanan.
create or replace function public.console_bulk_purge(p_action bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.bulk_actions; v_files jsonb := '[]'::jsonb; z jsonb; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into x from jo.bulk_actions where id = p_action for update;
  if x.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if x.restored_at is not null then raise exception 'Sudah dipulihkan; tidak ada yang perlu dihapus.'; end if;
  if x.purged_at is not null then raise exception 'Sudah dihapus permanen.'; end if;

  if x.kind = 'batch_dibatalkan' or (x.kind = 'atlet_ditarik' and x.snap ? 'sub') then
    for z in select * from jsonb_array_elements(case when x.kind = 'batch_dibatalkan' then x.snap->'subs' else jsonb_build_array(x.snap->'sub') end) loop
      select * into s from jo.submissions where id = (z->>'id')::uuid;
      if s.id is not null and s.status = 'dibatalkan' then v_files := v_files || jo.purge_submission(s.id); end if;
    end loop;
  end if;
  -- berkas dari cuplikan atlet & baris
  select v_files || coalesce(jsonb_agg(jsonb_build_object('bucket', 'dokumen', 'path', p)), '[]'::jsonb) into v_files from (
    select x.snap->'athlete'->>k p from unnest(array['id_doc_path','akte_path','ktp_path','ijazah_path','passport_path','bpjs_path','photo_path']) k
    union select f->>k from jsonb_array_elements(coalesce(x.snap->'file_log', '[]'::jsonb)) f, unnest(array['old_path','new_path']) k
    union select rw->'data'->'docs'->k->>'path' from jsonb_array_elements(coalesce(x.snap->'rows', '[]'::jsonb) || coalesce(jsonb_build_array(x.snap->'row'), '[]'::jsonb)) rw,
          unnest(array['akte','ktp','ijazah','passport','bpjs','photo']) k
  ) q where p is not null and p <> '';
  -- jangan hapus berkas yang masih dipakai baris lembar atau atlet lain
  select coalesce(jsonb_agg(distinct f), '[]'::jsonb) into v_files from jsonb_array_elements(v_files) f
   where not exists (select 1 from jo.bulk_rows r, jsonb_each(coalesce(r.data->'docs', '{}'::jsonb)) d where d.value->>'path' = f->>'path')
     and not exists (select 1 from jo.athletes a where f->>'path' in (a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path));

  update jo.bulk_actions set purged_at = now(), purged_by = st.id, snap = jsonb_build_object('purged', true, 'label', x.label) where id = x.id;
  perform jo.log(st.id, 'massal_hapus_permanen', 'bulk', x.bulk_id::text, jsonb_build_object('what', x.kind, 'label', x.label, 'files', jsonb_array_length(v_files)));
  return jsonb_build_object('ok', true, 'files', v_files);
end $$;

create or replace function jo.bulk_actions_json(p_bulk uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'mode', x.mode, 'label', x.label, 'row_nos', x.row_nos,
      'batch', (select code from jo.bulk_batches where id = x.batch_id), 'amount', x.amount, 'refund', x.refund,
      'person', x.person, 'by_club', x.staff_id is null, 'reason', x.reason, 'at', x.created_at,
      'restored_at', x.restored_at, 'restored_by', (select name from jo.staff where id = x.restored_by),
      'purged_at', x.purged_at, 'purged_by', (select name from jo.staff where id = x.purged_by)) order by x.created_at desc), '[]'::jsonb)
  from jo.bulk_actions x where x.bulk_id = p_bulk
$$;

revoke all on function public.public_bulk_withdraw(text, text, integer, text) from public;
grant execute on function public.public_bulk_withdraw(text, text, integer, text) to anon, authenticated;
revoke all on function public.public_bulk_cancel_batch(text, text, uuid, text, text) from public;
grant execute on function public.public_bulk_cancel_batch(text, text, uuid, text, text) to anon, authenticated;
revoke all on function public.console_bulk_withdraw(uuid, integer, text) from public, anon;
grant execute on function public.console_bulk_withdraw(uuid, integer, text) to authenticated;
revoke all on function public.console_bulk_cancel_batch(uuid, text, text) from public, anon;
grant execute on function public.console_bulk_cancel_batch(uuid, text, text) to authenticated;
revoke all on function public.console_bulk_restore(bigint) from public, anon;
grant execute on function public.console_bulk_restore(bigint) to authenticated;
revoke all on function public.console_bulk_purge(bigint) from public, anon;
grant execute on function public.console_bulk_purge(bigint) to authenticated;


do $do$
declare def text;
begin
  def := pg_get_functiondef('public.public_bulk_sheet(text,text,timestamp with time zone)'::regprocedure);
  if position($q$    'deleted', case when p_since is not null then (select coalesce(jsonb_agg((l.detail->>'row_no')::integer), '[]'::jsonb)
             from jo.bulk_log l where l.bulk_id = b.id and l.action = 'baris_dihapus' and l.at > p_since) end,$q$ in def) = 0 then raise exception 'pola tidak ditemukan: public.public_bulk_sheet(text,text,timestamp with time zone)'; end if;
  execute replace(def, $q$    'deleted', case when p_since is not null then (select coalesce(jsonb_agg((l.detail->>'row_no')::integer), '[]'::jsonb)
             from jo.bulk_log l where l.bulk_id = b.id and l.action = 'baris_dihapus' and l.at > p_since) end,$q$, $q$    'deleted', case when p_since is not null then (select coalesce(jsonb_agg(q.n), '[]'::jsonb) from (
               select (l.detail->>'row_no')::integer n from jo.bulk_log l
                where l.bulk_id = b.id and l.action = 'baris_dihapus' and l.at > p_since and not (l.detail ? 'deleted_rows')
               union all
               select (z)::text::integer from jo.bulk_log l cross join lateral jsonb_array_elements(l.detail->'deleted_rows') z
                where l.bulk_id = b.id and l.at > p_since and l.detail ? 'deleted_rows') q) end,$q$);
  def := pg_get_functiondef('public.public_bulk_submit(text,text,integer[],jsonb,text)'::regprocedure);
  if position($q$  perform set_config('jo.bulk', '', true);$q$ in def) = 0 then raise exception 'pola tidak ditemukan: public.public_bulk_submit(text,text,integer[],jsonb,text)'; end if;
  execute replace(def, $q$  perform set_config('jo.bulk', '', true);$q$, $q$  perform set_config('jo.bulk', '', true);
  perform jo.bulk_link_rows(v_batch.id);$q$);
  def := pg_get_functiondef('jo.bulk_batches_json(uuid)'::regprocedure);
  if position($q$      'overdue', bt.status = 'menunggu' and now() > bt.due_at,$q$ in def) = 0 then raise exception 'pola tidak ditemukan: jo.bulk_batches_json(uuid)'; end if;
  execute replace(def, $q$      'overdue', bt.status = 'menunggu' and now() > bt.due_at,$q$, $q$      'overdue', bt.status = 'menunggu' and now() > bt.due_at,
      'refund_due', bt.refund_due, 'free', bt.status = 'menunggu' and not exists (select 1 from jo.bulk_payments p0 where p0.batch_id = bt.id and p0.status in ('menunggu','cocok')),$q$);
  def := pg_get_functiondef('public.console_bulk(uuid)'::regprocedure);
  if position($q$    'batch_list', jo.bulk_batches_json(b.id),$q$ in def) = 0 then raise exception 'pola tidak ditemukan: public.console_bulk(uuid)'; end if;
  execute replace(def, $q$    'batch_list', jo.bulk_batches_json(b.id),$q$, $q$    'batch_list', jo.bulk_batches_json(b.id),
    'actions', jo.bulk_actions_json(b.id),$q$);
  def := pg_get_functiondef('public.console_delete_athlete(uuid,text)'::regprocedure);
  if position($q$  select * into s from jo.submissions where id = a.submission_id for update;$q$ in def) = 0 then raise exception 'pola tidak ditemukan: public.console_delete_athlete(uuid,text)'; end if;
  execute replace(def, $q$  select * into s from jo.submissions where id = a.submission_id for update;$q$, $q$  select * into s from jo.submissions where id = a.submission_id for update;
  if s.bulk_batch_id is not null then
    raise exception 'Atlet ini dari pendaftaran massal. Tarik lewat halaman Pendaftaran massal (bisa dipulihkan).';
  end if;$q$);
  def := pg_get_functiondef('public.console_delete_submission(uuid,text)'::regprocedure);
  if position($q$  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;$q$ in def) = 0 then raise exception 'pola tidak ditemukan: public.console_delete_submission(uuid,text)'; end if;
  execute replace(def, $q$  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;$q$, $q$  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  if s.bulk_batch_id is not null and s.status <> 'dibatalkan' then
    raise exception 'Pendaftaran ini bagian dari batch pendaftaran massal. Batalkan batchnya lewat halaman Pendaftaran massal (bisa dipulihkan).';
  end if;$q$);
end $do$;

-- tautkan atlet lama ke baris lembarnya
select jo.bulk_link_rows(id) from jo.bulk_batches;
