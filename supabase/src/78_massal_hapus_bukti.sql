-- =====================================================================
--  24/11/2026: hapus bukti transfer ganda di pendaftaran massal
--  Sejak batas 15 menit dimatikan, klub yang gagal sekali lalu mengulang
--  bisa meninggalkan bukti ganda berstatus "Menunggu"/"Tidak cocok".
--  Owner & superadmin bisa menghapusnya. Bukti yang sudah "Cocok" tidak
--  bisa dihapus (uang terverifikasi). Rincian bukti tetap tercatat di
--  Riwayat dan Log; berkas gambar tetap disimpan di Storage.
-- =====================================================================
create or replace function public.console_bulk_payment_delete(p_payment bigint, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; p jo.bulk_payments; bt jo.bulk_batches; v_detail jsonb;
begin
  st := jo.bulk_admin();
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Tulis alasan yang jelas.'; end if;
  select * into p from jo.bulk_payments where id = p_payment for update;
  if p.id is null then raise exception 'Bukti transfer tidak ditemukan.'; end if;
  if p.status = 'cocok' then raise exception 'Bukti yang sudah cocok tidak bisa dihapus.'; end if;
  select * into bt from jo.bulk_batches where id = p.batch_id;
  v_detail := jsonb_build_object('code', bt.code, 'amount', p.amount, 'transfer_date', p.transfer_date, 'person', p.person,
    'uploaded_at', p.uploaded_at, 'status', p.status, 'proof_path', p.proof_path, 'note', btrim(p_reason));
  delete from jo.bulk_payments where id = p.id;
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'bukti_transfer_dihapus', v_detail);
  perform jo.log(st.id, 'massal_bukti_dihapus', 'bulk', bt.bulk_id::text, v_detail);
  return public.console_bulk(bt.bulk_id);
end $$;
revoke all on function public.console_bulk_payment_delete(bigint, text) from public, anon;
grant execute on function public.console_bulk_payment_delete(bigint, text) to authenticated;
