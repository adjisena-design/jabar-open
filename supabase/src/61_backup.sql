-- =====================================================================
--  Backup darurat (v10, 21/10/2026) — hanya OWNER
--  Konsol mengunduh seluruh isi tabel jo.* per bagian (console_backup_rows),
--  menyusun ZIP di browser, lalu mencatat unduhan (console_backup_done).
--  Tidak pernah diekspor: hash kode akses, secret email, sesi login,
--  catatan percobaan login, dan batas laju.
-- =====================================================================

-- tabel yang tidak ikut backup sama sekali (sementara / rahasia)
create or replace function jo.backup_skip() returns text[]
language sql immutable set search_path = '' as $$
  select array['staff_sessions','login_attempts','rate_events']
$$;

create or replace function public.console_backup_meta() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_tables jsonb := '[]'::jsonb; t record; v_n bigint;
begin
  st := jo.require_staff(array['owner']);
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'jo' and c.relkind = 'r' and not (c.relname = any(jo.backup_skip()))
     order by c.relname
  loop
    execute format('select count(*) from jo.%I', t.relname) into v_n;
    v_tables := v_tables || jsonb_build_object('name', t.relname, 'rows', v_n);
  end loop;
  return jsonb_build_object(
    'generated_at', now(),
    'project_url', jo.site_url(),
    'tables', v_tables,
    'files', (select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'name', o.name,
                'size', coalesce((o.metadata->>'size')::bigint, 0)) order by o.bucket_id, o.name), '[]'::jsonb)
                from storage.objects o where o.bucket_id in ('dokumen','bukti','publik')),
    'last_backup', jo.setting('backup_last'));
end $$;

create or replace function public.console_backup_rows(p_table text, p_offset integer default 0, p_limit integer default 500)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_pk text; r jsonb;
begin
  st := jo.require_staff(array['owner']);
  if p_table = any(jo.backup_skip())
     or not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'jo' and c.relkind = 'r' and c.relname = p_table) then
    raise exception 'Tabel tidak dikenal: %', p_table;
  end if;
  -- urutan stabil: kunci primer bila ada
  select string_agg(quote_ident(a.attname), ', ' order by array_position(i.indkey, a.attnum))
    into v_pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
   where i.indrelid = ('jo.' || quote_ident(p_table))::regclass and i.indisprimary;
  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from jo.%I order by %s offset %s limit %s) t',
                 p_table, coalesce(v_pk, '1'), greatest(coalesce(p_offset, 0), 0), least(greatest(coalesce(p_limit, 500), 1), 2000))
    into r;
  -- buang nilai rahasia
  if p_table = 'staff' then
    select coalesce(jsonb_agg(x - 'code_hash' - 'code_hint'), '[]'::jsonb) into r from jsonb_array_elements(r) x;
  elsif p_table = 'settings' then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into r from jsonb_array_elements(r) x
     where not (x->>'key' ilike '%secret%' or x->>'key' ilike '%hash%' or x->>'key' ilike '%token%');
  end if;
  return r;
end $$;

-- ringkasan "di mana kita berhenti" untuk TITIK-LANJUT.txt
create or replace function public.console_backup_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner']);
  return jsonb_build_object(
    'at', now(),
    'submissions_by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from jo.submissions group by status) x),
    'submissions_by_discipline', (select coalesce(jsonb_object_agg(discipline, n), '{}'::jsonb) from (select discipline, count(*) n from jo.submissions where status <> 'dibatalkan' group by discipline) x),
    'athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status <> 'dibatalkan'),
    'athletes_paid', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status = 'lunas'),
    'actions', jo.action_counts(null),
    'to_verify', (select coalesce(jsonb_agg(s.code || ' (' || coalesce(k.name, s.contact_name) || ', bukti ' ||
                    to_char(s.proof_uploaded_at at time zone 'Asia/Jakarta', 'DD/MM HH24.MI') || ')' order by s.proof_uploaded_at), '[]'::jsonb)
                    from jo.submissions s left join jo.clubs k on k.id = s.club_id where s.status = 'menunggu_verifikasi'),
    'last_mutation_import', (select max(imported_at) from jo.mutations),
    'mutations', (select count(*) from jo.mutations),
    'startlists_published', (select coalesce(jsonb_agg(c.name_id order by c.sort), '[]'::jsonb) from jo.categories c where c.startlist_published),
    'results_published', (select coalesce(jsonb_agg(c.name_id order by c.sort), '[]'::jsonb) from jo.categories c where c.results_published),
    'scores', (select count(*) from jo.scores),
    'last_log', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
        select jsonb_build_object('at', a.at, 'action', a.action, 'by', (select name from jo.staff where id = a.staff_id), 'target', a.target_type || ' ' || coalesce(a.target_id, '')) x
          from jo.audit a order by a.at desc limit 15) y));
end $$;

create or replace function public.console_backup_done(p_kind text, p_bytes bigint, p_detail jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner']);
  if p_kind not in ('data','berkas') then raise exception 'Jenis backup tidak dikenal.'; end if;
  perform jo.log(st.id, 'backup_' || p_kind, 'backup', p_kind, coalesce(p_detail, '{}'::jsonb) || jsonb_build_object('bytes', p_bytes));
  if p_kind = 'data' then
    insert into jo.settings (key, value) values ('backup_last', jsonb_build_object('at', now(), 'bytes', p_bytes, 'by', st.name))
      on conflict (key) do update set value = excluded.value, updated_at = now();
  else
    insert into jo.settings (key, value) values ('backup_files_last', jsonb_build_object('at', now(), 'bytes', p_bytes, 'by', st.name))
      on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- untuk Ringkasan owner: kapan backup terakhir
create or replace function public.console_backup_last() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner']);
  return jsonb_build_object('data', jo.setting('backup_last'), 'files', jo.setting('backup_files_last'));
end $$;
