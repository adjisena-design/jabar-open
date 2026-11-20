-- =====================================================================
--  Bukti transfer pendaftaran massal yang dikirim klub langsung ke Inda (20 Nov 2026)
--  Inda/owner mengunggah bukti atas nama klub di konsol, lalu (opsional) langsung menandai cocok.
-- =====================================================================
create or replace function public.console_bulk_batch_brief(p_batch uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into bt from jo.bulk_batches where id = p_batch;
  if bt.id is null then raise exception 'Batch tidak ditemukan.'; end if;
  return jsonb_build_object('id', bt.id, 'code', bt.code, 'bulk_id', bt.bulk_id, 'status', bt.status, 'total', bt.total,
    'created_at', bt.created_at, 'manager', jo.bulk_is_manager(st),
    'club', (select coalesce(c.name, b.label) from jo.bulk_accounts b left join jo.clubs c on c.id = b.club_id where b.id = bt.bulk_id),
    'paid_verified', (select coalesce(sum(amount),0) from jo.bulk_payments where batch_id = bt.id and status = 'cocok'),
    'paid_pending', (select coalesce(sum(amount),0) from jo.bulk_payments where batch_id = bt.id and status = 'menunggu'));
end $$;

create or replace function public.console_bulk_add_payment(p_batch uuid, p_amount integer, p_date date, p_path text, p_note text, p_verify boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches; v_id bigint; v_note text := nullif(trim(coalesce(p_note,'')),''); v_uid uuid := auth.uid();
begin
  st := jo.bulk_manager();
  select * into bt from jo.bulk_batches where id = p_batch for update;
  if bt.id is null then raise exception 'Batch tidak ditemukan.'; end if;
  if bt.status <> 'menunggu' then raise exception 'Batch ini sudah %.', case when bt.status = 'lunas' then 'lunas' else 'dibatalkan' end; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Isi nominal transfer.'; end if;
  if p_date is null or p_date > (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal transfer tidak valid.'; end if;
  if coalesce(p_path,'') = '' or split_part(p_path, '/', 1) <> v_uid::text then raise exception 'Unggah bukti transfer.'; end if;
  insert into jo.bulk_payments (batch_id, amount, transfer_date, proof_path, person, note)
  values (bt.id, p_amount, p_date, p_path, st.name || ' (panitia, bukti dari klub)', v_note)
  returning id into v_id;
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'bukti_transfer_panitia', jsonb_build_object('code', bt.code, 'amount', p_amount, 'date', p_date, 'note', v_note));
  perform jo.log(st.id, 'massal_bukti_transfer_panitia', 'bulk', bt.bulk_id::text, jsonb_build_object('code', bt.code, 'amount', p_amount, 'date', p_date, 'note', v_note));
  if coalesce(p_verify, false) then
    return public.console_bulk_verify(v_id, true, coalesce(v_note, 'Bukti dikirim klub langsung ke panitia; dicek di mutasi'));
  end if;
  return public.console_bulk(bt.bulk_id);
end $$;

revoke all on function public.console_bulk_batch_brief(uuid) from public, anon;
grant execute on function public.console_bulk_batch_brief(uuid) to authenticated;
revoke all on function public.console_bulk_add_payment(uuid, integer, date, text, text, boolean) from public, anon;
grant execute on function public.console_bulk_add_payment(uuid, integer, date, text, text, boolean) to authenticated;
