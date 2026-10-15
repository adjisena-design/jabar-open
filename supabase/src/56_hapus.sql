-- =====================================================================
--  v6: hapus data oleh owner & superadmin (tercatat di Log; Log hanya
--      bisa dilihat owner & superadmin). Konsol menghapus berkasnya dari
--      penyimpanan memakai daftar berkas yang dikembalikan fungsi.
-- =====================================================================

create or replace function public.console_delete_submission(p_id uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; v_files jsonb; v_detail jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan penghapusan (masuk Log).'; end if;
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  v_detail := jsonb_build_object('code', s.code, 'status', s.status, 'discipline', s.discipline, 'type', s.registrant_type,
    'contact', s.contact_name, 'email', s.contact_email, 'phone', s.contact_phone, 'total', s.total_amount, 'paid', s.paid_amount,
    'club', (select name from jo.clubs where id = s.club_id),
    'athletes', (select jsonb_agg(a.full_name || coalesce(' (' || a.athlete_no || ')', '') order by a.sort) from jo.athletes a where a.submission_id = s.id),
    'team', (select string_agg(t.name || ' ' || t.level, '; ') from jo.teams t where t.submission_id = s.id),
    'reason', trim(p_reason));
  v_files := jo.purge_submission(s.id);
  perform jo.log(st.id, 'pendaftaran_dihapus', 'submission', s.id::text, v_detail);
  return jsonb_build_object('ok', true, 'files', v_files);
end $$;

create or replace function public.console_delete_athlete(p_athlete uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions; v_files jsonb; v_base integer; v_e uuid[];
begin
  st := jo.require_staff(array['owner','superadmin']);
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan penghapusan (masuk Log).'; end if;
  select * into a from jo.athletes where id = p_athlete for update;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id for update;
  if (select count(*) from jo.athletes x where x.submission_id = s.id) <= 1 then
    raise exception 'Ini satu-satunya atlet di pendaftaran %. Hapus pendaftarannya.', s.code;
  end if;
  select coalesce(jsonb_agg(distinct jsonb_build_object('bucket', 'dokumen', 'path', x)), '[]'::jsonb) into v_files
    from unnest(array[a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path]) x where x is not null;
  -- nomor yang melibatkan atlet ini (termasuk pasangan) ikut dihapus
  v_e := array(select ea.entry_id from jo.entry_athletes ea where ea.athlete_id = a.id);
  delete from jo.score_log where entry_id in (select unnest(v_e));
  delete from jo.scores where entry_id in (select unnest(v_e));
  delete from jo.music_log where entry_id in (select unnest(v_e));
  delete from jo.team_members where athlete_id = a.id or entry_id in (select unnest(v_e));
  delete from jo.entry_athletes where entry_id in (select unnest(v_e));
  delete from jo.entries where id = any(v_e);
  delete from jo.athletes where id = a.id;
  -- tagihan dihitung ulang bila belum lunas (biaya nomor + biaya beregu)
  if s.status <> 'lunas' then
    select coalesce(sum(fee), 0) + s.team_amount into v_base from jo.entries where submission_id = s.id and status <> 'dibatalkan';
    update jo.submissions set base_amount = v_base, priangan_amount = 0,
      total_amount = v_base + unique_code, updated_at = now() where id = s.id;
  end if;
  perform jo.log(st.id, 'atlet_dihapus', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'athlete', a.full_name, 'athlete_no', a.athlete_no, 'birth_date', a.birth_date,
                       'reason', trim(p_reason), 'old_total', s.total_amount));
  return jsonb_build_object('ok', true, 'files', v_files);
end $$;

create or replace function public.console_delete_jury(p_id uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; j jo.jury_applications; v_files jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into j from jo.jury_applications where id = p_id for update;
  if j.id is null then raise exception 'Pendaftar juri tidak ditemukan.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('bucket', 'dokumen', 'path', x)), '[]'::jsonb) into v_files
    from unnest(array[j.ktp_path, j.photo_path, j.cert_path, j.bpjs_path]) x where x is not null;
  delete from jo.jury_applications where id = j.id;
  perform jo.log(st.id, 'juri_dihapus', 'jury', j.id::text,
    jsonb_build_object('name', j.full_name, 'phone', j.phone, 'status', j.status, 'disciplines', j.disciplines,
                       'staff_code_kept', j.staff_id is not null, 'reason', nullif(trim(coalesce(p_reason,'')),'')));
  return jsonb_build_object('ok', true, 'files', v_files);
end $$;

create or replace function public.console_delete_issue(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; i jo.issues;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into i from jo.issues where id = p_id for update;
  if i.id is null then raise exception 'Laporan tidak ditemukan.'; end if;
  delete from jo.issues where id = i.id;
  perform jo.log(st.id, 'laporan_dihapus', 'issue', i.id::text,
    jsonb_build_object('title', i.title, 'reporter', i.reporter_name, 'status', i.status));
  return jsonb_build_object('ok', true, 'files',
    case when i.shot_path is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('bucket', 'dokumen', 'path', i.shot_path)) end);
end $$;

create or replace function public.console_delete_chat_message(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; m jo.chat_messages;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into m from jo.chat_messages where id = p_id for update;
  if m.id is null then raise exception 'Pesan tidak ditemukan.'; end if;
  delete from jo.chat_messages where id = m.id;
  perform jo.log(st.id, 'pesan_dihapus', 'chat', m.id::text,
    jsonb_build_object('room', m.room, 'sender', m.sender_name, 'at', m.created_at, 'body', left(m.body, 300)));
  return jsonb_build_object('ok', true);
end $$;

-- Berkas di penyimpanan yang tidak lagi dipakai data mana pun (mis. pendaftaran kedaluwarsa)
create or replace function public.console_orphan_files() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return (select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'size', (o.metadata->>'size')::bigint, 'at', o.created_at) order by o.created_at), '[]'::jsonb)
    from storage.objects o
    where o.bucket_id in ('dokumen','bukti') and o.created_at < now() - interval '1 hour'
      and not exists (select 1 from jo.submissions s where s.proof_path = o.name)
      and not exists (select 1 from jo.athletes a where o.name in (a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path))
      and not exists (select 1 from jo.jury_applications j where o.name in (j.ktp_path, j.photo_path, j.cert_path, j.bpjs_path))
      and not exists (select 1 from jo.issues i where i.shot_path = o.name));
end $$;

create or replace function public.console_log_files_removed(p_count integer, p_context text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  perform jo.log(st.id, 'berkas_dihapus', 'storage', coalesce(p_context, '-'), jsonb_build_object('count', p_count));
  return jsonb_build_object('ok', true);
end $$;
