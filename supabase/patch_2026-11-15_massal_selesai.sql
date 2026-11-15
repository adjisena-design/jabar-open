-- Patch 15 Nov 2026: tanda "selesai" pendaftaran massal + akses admin cabang
alter table jo.bulk_accounts add column if not exists completed_at timestamptz;
alter table jo.bulk_accounts add column if not exists completed_by uuid references jo.staff(id);
alter table jo.bulk_accounts add column if not exists completed_note text;

create or replace function jo.bulk_console_row(b jo.bulk_accounts) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', b.id, 'code_label', jo.bulk_code_label(b), 'label', b.label, 'status', b.status, 'code_hint', b.code_hint,
    'req_name', b.req_name, 'req_phone', b.req_phone, 'note', b.note,
    'created_at', b.created_at, 'created_by', (select name from jo.staff where id = b.created_by),
    'opened_at', b.opened_at, 'expires_at', b.expires_at, 'extended_days', b.extended_days,
    'extended_by', (select name from jo.staff where id = b.extended_by),
    'locked', (b.expires_at is not null and now() > b.expires_at),
    'owner_name', b.owner_name, 'owner_phone', b.owner_phone, 'owner_email', b.owner_email, 'collaborators', b.collaborators,
    'club', coalesce((select c.name from jo.clubs c where c.id = b.club_id), b.club_new->>'name'),
    'rows', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id),
    'rows_sent', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id and r.batch_id is not null),
    'batches', (select count(*) from jo.bulk_batches bt where bt.bulk_id = b.id and bt.status <> 'dibatalkan'),
    'billed', (select coalesce(sum(total),0) from jo.bulk_batches bt where bt.bulk_id = b.id and bt.status <> 'dibatalkan'),
    'paid', (select coalesce(sum(p.amount),0) from jo.bulk_payments p join jo.bulk_batches bt on bt.id = p.batch_id where bt.bulk_id = b.id and p.status = 'cocok' and bt.status <> 'dibatalkan'),
    'to_verify', (select count(*) from jo.bulk_payments p join jo.bulk_batches bt on bt.id = p.batch_id where bt.bulk_id = b.id and p.status = 'menunggu'),
    'overdue', (select count(*) from jo.bulk_batches bt where bt.bulk_id = b.id and bt.status = 'menunggu' and now() > bt.due_at),
    'last_activity', (select max(at) from jo.bulk_log l where l.bulk_id = b.id),
    'completed_at', b.completed_at, 'completed_by', (select name from jo.staff where id = b.completed_by), 'completed_note', b.completed_note,
    'unpaid_batches', (select count(*) from jo.bulk_batches bt where bt.bulk_id = b.id and bt.status = 'menunggu'),
    'docs_pending', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
                      join jo.bulk_batches bt on bt.id = s.bulk_batch_id
                     where bt.bulk_id = b.id and s.status <> 'dibatalkan' and a.doc_status = 'menunggu'))
$$;

do $do$
declare f regprocedure; def text;
begin
  foreach f in array array['public.console_bulk_list()','public.console_bulk_summary()','public.console_bulk(uuid)']::regprocedure[] loop
    def := pg_get_functiondef(f);
    if position($q$jo.require_staff(array['owner','superadmin'])$q$ in def) = 0 then raise exception 'pola tidak ditemukan di %', f; end if;
    execute replace(def, $q$jo.require_staff(array['owner','superadmin'])$q$, $q$jo.require_staff(array['owner','superadmin','admin'])$q$);
  end loop;
end $do$;

-- Verifikator menandai pendaftaran massal selesai / belum selesai (label saja; kode, pembayaran, dan dokumen tetap berjalan).
create or replace function public.console_bulk_complete(p_id uuid, p_done boolean, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  update jo.bulk_accounts
     set completed_at = case when p_done then now() end,
         completed_by = case when p_done then st.id end,
         completed_note = case when p_done then nullif(btrim(coalesce(p_note, '')), '') end,
         updated_at = now()
   where id = p_id returning * into b;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  perform jo.bulk_add_log(b.id, st.name, case when p_done then 'ditandai_selesai' else 'tanda_selesai_dibatalkan' end,
                          case when nullif(btrim(coalesce(p_note, '')), '') is not null then jsonb_build_object('note', btrim(p_note)) else '{}'::jsonb end);
  perform jo.log(st.id, case when p_done then 'massal_ditandai_selesai' else 'massal_tanda_selesai_dibatalkan' end, 'bulk', b.id::text,
                 jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label, 'note', p_note));
  return jo.bulk_console_row(b);
end $$;
revoke all on function public.console_bulk_complete(uuid, boolean, text) from public, anon;
grant execute on function public.console_bulk_complete(uuid, boolean, text) to authenticated;
