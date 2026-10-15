-- =====================================================================
--  Fungsi KONSOL PANITIA (nama diawali console_)
--  Semua fungsi memeriksa sesi kode akses & peran:
--   owner      : semua + pengaturan + kode akses superadmin
--   superadmin : semua data, ledger, log, kode akses admin/juri
--   admin      : verifikasi, atlet, start list, nilai, hasil (bisa dibatasi 1 disiplin)
--   juri       : input nilai sesuai disiplin/alat/komponen
-- =====================================================================

-- ---------------------------------------------------------------------
-- Masuk / keluar
-- ---------------------------------------------------------------------
create or replace function public.console_login(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); st jo.staff; v_fail integer;
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  select count(*) into v_fail from jo.login_attempts
   where uid = v_uid and not ok and at > now() - interval '15 minutes';
  if v_fail >= 8 then
    return jsonb_build_object('ok', false, 'message', 'Terlalu banyak percobaan gagal. Tunggu 15 menit lalu coba lagi.');
  end if;
  select * into st from jo.staff where code_hash = jo.sha256(jo.norm_code(p_code)) and active;
  if st.id is null then
    insert into jo.login_attempts (uid, ok) values (v_uid, false);
    return jsonb_build_object('ok', false, 'message', 'Kode akses tidak dikenal atau sudah dinonaktifkan.');
  end if;
  insert into jo.login_attempts (uid, ok) values (v_uid, true);
  insert into jo.staff_sessions (uid, staff_id, expires_at)
  values (v_uid, st.id, now() + interval '14 hours')
  on conflict (uid) do update set staff_id = excluded.staff_id, created_at = now(), expires_at = excluded.expires_at;
  update jo.staff set last_login_at = now() where id = st.id;
  perform jo.log(st.id, 'masuk', 'staff', st.id::text);
  return jsonb_build_object('ok', true, 'staff', jo.staff_json(st));
end $$;

create or replace function public.console_me() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  select * into st from jo.current_staff();
  if st.id is null then return null; end if;
  return jo.staff_json(st);
end $$;

create or replace function public.console_logout() returns jsonb
language sql volatile security definer set search_path = '' as $$
  delete from jo.staff_sessions where uid = auth.uid();
  select jsonb_build_object('ok', true);
$$;

-- ---------------------------------------------------------------------
-- Dasbor
-- ---------------------------------------------------------------------
create or replace function public.console_dashboard() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; d text; is_super boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.expire_unpaid();
  d := st.discipline;
  is_super := st.role in ('owner','superadmin');
  return jsonb_build_object(
    'staff', jo.staff_json(st),
    'by_discipline', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', x.code, 'name', x.name_id,
        'submissions', (select count(*) from jo.submissions s where s.discipline = x.code and s.status <> 'dibatalkan'),
        'athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.discipline = x.code and s.status <> 'dibatalkan'),
        'athletes_paid', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.discipline = x.code and s.status = 'lunas'),
        'to_verify', (select count(*) from jo.submissions s where s.discipline = x.code and s.status = 'menunggu_verifikasi'),
        'unpaid', (select count(*) from jo.submissions s where s.discipline = x.code and s.status in ('menunggu_pembayaran','perlu_perbaikan')),
        'docs_pending', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.discipline = x.code and s.status <> 'dibatalkan' and a.doc_status = 'menunggu'),
        'priangan_pending', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where s.discipline = x.code and s.status <> 'dibatalkan' and e.priangan_status = 'menunggu'),
        'teams', (select count(*) from jo.teams t join jo.submissions s on s.id = t.submission_id where t.discipline = x.code and s.status <> 'dibatalkan'),
        'teams_paid', (select count(*) from jo.teams t join jo.submissions s on s.id = t.submission_id where t.discipline = x.code and s.status = 'lunas'),
        'music_pending', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where s.discipline = x.code and s.status <> 'dibatalkan' and e.status <> 'dibatalkan' and e.music_status in ('menunggu','belum','tidak_bisa'))
      ) order by x.sort), '[]'::jsonb) from jo.disciplines x where d is null or x.code = d),
    'low_categories', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_id, 'discipline', c.discipline, 'paid', n.paid, 'registered', n.reg) order by c.sort), '[]'::jsonb)
        from jo.categories c
        cross join lateral (select count(*) filter (where s.status = 'lunas') as paid,
                                   count(*) filter (where s.status <> 'dibatalkan') as reg
                              from jo.entries e join jo.submissions s on s.id = e.submission_id
                             where e.category_id = c.id and e.status = 'aktif') n
        where c.active and (d is null or c.discipline = d) and n.reg > 0 and n.reg < 3),
    'money', case when is_super then jsonb_build_object(
        'expected', (select coalesce(sum(total_amount),0) from jo.submissions where status <> 'dibatalkan'),
        'paid', (select coalesce(sum(coalesce(paid_amount, total_amount)),0) from jo.submissions where status = 'lunas'),
        'outstanding', (select coalesce(sum(total_amount),0) from jo.submissions where status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan')),
        'mutations_unmatched', (select count(*) from jo.mutations where match_status = 'belum')) end,
    'email', case when is_super then jsonb_build_object(
        'pending', (select count(*) from jo.outbox where status in ('pending','sending')),
        'error', (select count(*) from jo.outbox where status = 'error'),
        'sent', (select count(*) from jo.outbox where status = 'sent'),
        'last_poll', jo.setting('outbox_last_poll')) end,
    'recent', (select coalesce(jsonb_agg(r order by r->>'created_at' desc), '[]'::jsonb) from (
        select jsonb_build_object('id', s.id, 'code', s.code, 'status', s.status, 'created_at', s.created_at,
          'contact_name', s.contact_name, 'discipline', s.discipline, 'total_amount', s.total_amount,
          'club', (select name from jo.clubs where id = s.club_id),
          'n_athletes', (select count(*) from jo.athletes a where a.submission_id = s.id)) r
        from jo.submissions s where d is null or s.discipline = d
        order by s.created_at desc limit 8) q)
  );
end $$;

-- ---------------------------------------------------------------------
-- Pendaftaran: daftar & detail
-- ---------------------------------------------------------------------
create or replace function public.console_submissions(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter, '{}'::jsonb); q text; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.expire_unpaid();
  d := coalesce(st.discipline, nullif(f->>'discipline',''));
  q := '%' || lower(coalesce(f->>'q','')) || '%';
  return (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.created_at desc), '[]'::jsonb) from (
    select s.id, s.code, s.created_at, s.discipline, s.registrant_type, s.contact_name, s.contact_phone, s.contact_email,
      c.name as club, coalesce(c.kab_kota, (select a.kab_kota from jo.athletes a where a.submission_id = s.id order by a.sort limit 1)) as region,
      (select count(*) from jo.athletes a where a.submission_id = s.id) as n_athletes,
      (select string_agg(a.full_name, ', ' order by a.sort) from jo.athletes a where a.submission_id = s.id) as athlete_names,
      (select t.name || ' (' || t.level || ', ' || (select count(*) from jo.team_members m where m.team_id = t.id) || ' pesenam)' from jo.teams t where t.submission_id = s.id) as team_name,
      (select count(*) from jo.entries e where e.submission_id = s.id and e.status <> 'dibatalkan' and e.music_status in ('menunggu','belum','tidak_bisa')) as music_pending,
      s.total_amount, s.unique_code, s.status, s.payment_method, s.proof_uploaded_at, s.paid_at,
      case when s.payment_method = 'qris' and s.status = 'menunggu_pembayaran' and s.proof_path is null
           then s.created_at + interval '15 minutes' end as expires_at,
      (select count(*) from jo.athletes a where a.submission_id = s.id and a.doc_status = 'menunggu') as docs_pending,
      (select count(*) from jo.entries e where e.submission_id = s.id and e.priangan_status = 'menunggu') as priangan_pending,
      exists (select 1 from jo.mutations m where m.submission_id = s.id and m.match_status in ('otomatis','manual')) as mutation_matched
    from jo.submissions s left join jo.clubs c on c.id = s.club_id
    where (d is null or s.discipline = d)
      and (nullif(f->>'status','') is null or s.status = f->>'status')
      and (coalesce(f->>'q','') = '' or lower(s.code) like q or lower(s.contact_name) like q
           or lower(coalesce(c.name,'')) like q or lower(s.contact_email) like q
           or s.total_amount::text like q
           or exists (select 1 from jo.athletes a where a.submission_id = s.id and lower(a.full_name) like q))
      and (coalesce(f->>'flag','') = ''
           or (f->>'flag' = 'docs' and exists (select 1 from jo.athletes a where a.submission_id = s.id and a.doc_status = 'menunggu') and s.status <> 'dibatalkan')
           or (f->>'flag' = 'priangan' and exists (select 1 from jo.entries e where e.submission_id = s.id and e.priangan_status = 'menunggu') and s.status <> 'dibatalkan')
           or (f->>'flag' = 'beregu' and s.registrant_type = 'beregu')
           or (f->>'flag' = 'musik' and exists (select 1 from jo.entries e where e.submission_id = s.id and e.status <> 'dibatalkan' and e.music_status in ('menunggu','belum','tidak_bisa')) and s.status <> 'dibatalkan'))
    order by s.created_at desc
    limit 1000) x);
end $$;

create or replace function public.console_submission(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into s from jo.submissions where id = p_id;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  return jsonb_build_object(
    'submission', (to_jsonb(s) - 'token' - 'auth_uid')
       || jsonb_build_object('verified_by_name', (select name from jo.staff where id = s.verified_by),
                             'discipline_name', (select name_id from jo.disciplines where code = s.discipline)),
    'club', (select to_jsonb(c) from jo.clubs c where c.id = s.club_id),
    'athletes', (select coalesce(jsonb_agg(to_jsonb(a) - 'ticket_code'
        || jsonb_build_object('age', jo.comp_age(a.birth_date), 'minor', jo.is_minor(a.birth_date),
                              'doc_verified_by_name', (select name from jo.staff where id = a.doc_verified_by))
        order by a.sort), '[]'::jsonb) from jo.athletes a where a.submission_id = s.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id, 'category_id', c.id, 'category', c.name_id, 'level', c.level, 'entry_type', c.entry_type,
        'fee', e.fee, 'priangan_requested', e.priangan_requested, 'priangan_fee', e.priangan_fee,
        'priangan_status', e.priangan_status, 'priangan_note', e.priangan_note, 'status', e.status,
        'team_only', e.team_only, 'discipline', c.discipline,
        'music', e.music, 'apparatus', c.apparatus, 'music_status', e.music_status, 'music_note', e.music_note,
        'music_changes', e.music_changes, 'music_updated_at', e.music_updated_at, 'jabar_only', c.jabar_only,
        'music_checked_by', (select name from jo.staff where id = e.music_checked_by), 'music_checked_at', e.music_checked_at,
        'music_log', (select coalesce(jsonb_agg(jsonb_build_object('at', ml.at, 'action', ml.action, 'apparatus', ml.apparatus, 'old_url', ml.old_url, 'new_url', ml.new_url,
            'staff', (select name from jo.staff where id = ml.staff_id), 'note', ml.note) order by ml.at), '[]'::jsonb)
            from jo.music_log ml where ml.entry_id = e.id),
        'in_team', (select jsonb_build_object('team', t.name, 'submission_id', t.submission_id, 'code', ts.code)
                      from jo.team_members m join jo.teams t on t.id = m.team_id join jo.submissions ts on ts.id = t.submission_id
                     where m.entry_id = e.id and ts.status <> 'dibatalkan' limit 1),
        'athletes', jo.entry_athletes_json(e.id),
        'mismatch', (select string_agg(a.full_name || ': ' || jo.category_mismatch(c, a.gender, a.birth_date), '; ')
                       from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id
                      where ea.entry_id = e.id and jo.category_mismatch(c, a.gender, a.birth_date) is not null)
      ) order by c.sort), '[]'::jsonb)
      from jo.entries e join jo.categories c on c.id = e.category_id where e.submission_id = s.id),
    'team', (select jsonb_build_object('id', t.id, 'name', t.name, 'level', t.level,
        'members', (select coalesce(jsonb_agg(jsonb_build_object(
            'athlete_id', a.id, 'name', a.full_name, 'athlete_no', a.athlete_no, 'team_only', m.team_only,
            'category', c2.name_id, 'entry_status', e2.status,
            'submission_id', e2.submission_id, 'submission_code', s2.code, 'submission_status', s2.status) order by m.sort), '[]'::jsonb)
          from jo.team_members m join jo.athletes a on a.id = m.athlete_id join jo.entries e2 on e2.id = m.entry_id
          join jo.categories c2 on c2.id = e2.category_id join jo.submissions s2 on s2.id = e2.submission_id
          where m.team_id = t.id))
      from jo.teams t where t.submission_id = s.id),
    'mutations', (select coalesce(jsonb_agg(to_jsonb(m) - 'raw' order by m.trx_time), '[]'::jsonb)
        from jo.mutations m where m.submission_id = s.id),
    'candidate_mutations', (select coalesce(jsonb_agg(to_jsonb(m) - 'raw' order by m.trx_time), '[]'::jsonb)
        from jo.mutations m where m.match_status = 'belum' and m.amount = s.total_amount),
    'emails', (select coalesce(jsonb_agg(jsonb_build_object('kind', o.kind, 'status', o.status, 'created_at', o.created_at, 'sent_at', o.sent_at, 'to', o.to_email) order by o.id), '[]'::jsonb)
        from jo.outbox o where o.submission_id = s.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action,
        'staff', (select name from jo.staff where id = l.staff_id), 'detail', l.detail) order by l.at), '[]'::jsonb)
        from jo.audit l where (l.target_type = 'submission' and l.target_id = s.id::text)
           or (l.target_type = 'athlete' and l.target_id in (select a.id::text from jo.athletes a where a.submission_id = s.id))
           or (l.target_type = 'entry' and l.target_id in (select e.id::text from jo.entries e where e.submission_id = s.id)))
  );
end $$;

-- ---------------------------------------------------------------------
-- Verifikasi pembayaran, dokumen, Priangan
-- ---------------------------------------------------------------------
create or replace function public.console_verify_payment(p_id uuid, p_approve boolean, p_note text default null, p_amount integer default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions; v_matched boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  if s.status = 'dibatalkan' then raise exception 'Pendaftaran ini sudah dibatalkan.'; end if;

  if p_approve then
    if s.status = 'lunas' then raise exception 'Pendaftaran ini sudah lunas.'; end if;
    v_matched := exists (select 1 from jo.mutations m where m.submission_id = s.id and m.match_status in ('otomatis','manual'));
    if s.payment_method = 'manual' then
      if st.role not in ('owner','superadmin') then
        raise exception 'Pembayaran atlet internasional hanya bisa ditandai lunas oleh superadmin.';
      end if;
      if p_amount is null or p_amount <= 0 then
        raise exception 'Isi nominal yang diterima.';
      end if;
    elsif s.proof_path is null and not v_matched and st.role not in ('owner','superadmin') then
      raise exception 'Belum ada bukti bayar atau mutasi yang cocok. Minta pendaftar mengunggah bukti.';
    end if;
    update jo.submissions set status = 'lunas', paid_amount = coalesce(p_amount, s.total_amount), paid_at = now(),
      verified_by = st.id, verified_at = now(), verify_note = nullif(trim(coalesce(p_note,'')),'')
     where id = s.id;
    perform jo.log(st.id, 'pembayaran_lunas', 'submission', s.id::text,
      jsonb_build_object('code', s.code, 'amount', coalesce(p_amount, s.total_amount), 'note', p_note, 'mutation_match', v_matched));
    perform jo.queue_paid_email(s.id);
  else
    if length(trim(coalesce(p_note,''))) < 5 then
      raise exception 'Tulis alasan penolakan yang jelas (akan dikirim ke pendaftar).';
    end if;
    if s.status = 'lunas' and st.role not in ('owner','superadmin') then
      raise exception 'Membatalkan status lunas hanya bisa dilakukan superadmin.';
    end if;
    update jo.submissions set status = 'perlu_perbaikan', verify_note = trim(p_note),
      verified_by = st.id, verified_at = now(), paid_amount = null, paid_at = null
     where id = s.id;
    perform jo.log(st.id, 'pembayaran_ditolak', 'submission', s.id::text, jsonb_build_object('code', s.code, 'note', p_note, 'was', s.status));
    perform jo.queue_fix_email(s.id);
  end if;
  return public.console_submission(s.id);
end $$;

create or replace function public.console_cancel_submission(p_id uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into s from jo.submissions where id = p_id for update;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'Tulis alasan pembatalan.'; end if;
  if s.status = 'lunas' and st.role not in ('owner','superadmin') then
    raise exception 'Pendaftaran lunas hanya bisa dibatalkan superadmin.';
  end if;
  update jo.submissions set status = 'dibatalkan', cancel_reason = trim(p_reason) where id = s.id;
  update jo.entries set status = 'dibatalkan' where submission_id = s.id;
  perform jo.log(st.id, 'pendaftaran_dibatalkan', 'submission', s.id::text, jsonb_build_object('code', s.code, 'reason', p_reason, 'was', s.status));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_verify_doc(p_athlete uuid, p_valid boolean, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into a from jo.athletes where id = p_athlete;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if not p_valid and length(trim(coalesce(p_note,''))) < 3 then
    raise exception 'Tulis catatan mengapa dokumen tidak valid.';
  end if;
  update jo.athletes set doc_status = case when p_valid then 'valid' else 'tidak_valid' end,
    doc_note = nullif(trim(coalesce(p_note,'')),''), doc_verified_by = st.id, doc_verified_at = now()
   where id = a.id;
  perform jo.log(st.id, case when p_valid then 'dokumen_valid' else 'dokumen_tidak_valid' end, 'athlete', a.id::text,
    jsonb_build_object('name', a.full_name, 'note', p_note));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_set_priangan(p_entry uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into e from jo.entries where id = p_entry;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if not e.priangan_requested then raise exception 'Entri ini tidak mendaftar kategori Priangan.'; end if;
  if not p_approve and length(trim(coalesce(p_note,''))) < 3 then
    raise exception 'Tulis alasan penolakan Priangan.';
  end if;
  update jo.entries set priangan_status = case when p_approve then 'disetujui' else 'ditolak' end,
    priangan_note = nullif(trim(coalesce(p_note,'')),'') where id = e.id;
  perform jo.log(st.id, case when p_approve then 'priangan_disetujui' else 'priangan_ditolak' end, 'entry', e.id::text,
    jsonb_build_object('note', p_note));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_update_athlete(p_athlete uuid, p_patch jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions; b jsonb; k text;
  allowed text[] := array['full_name','gender','birth_date','nationality','country','province','kab_kota',
                          'guardian_name','guardian_phone','guardian_email','guardian_relation'];
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into a from jo.athletes where id = p_athlete for update;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan perubahan data.'; end if;
  for k in select jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) loop
    if not (k = any(allowed)) then raise exception 'Kolom % tidak bisa diubah.', k; end if;
  end loop;
  b := to_jsonb(a);
  update jo.athletes set
    full_name = coalesce(nullif(trim(p_patch->>'full_name'),''), full_name),
    gender = coalesce(nullif(p_patch->>'gender',''), gender),
    birth_date = coalesce(nullif(p_patch->>'birth_date','')::date, birth_date),
    nationality = coalesce(nullif(p_patch->>'nationality',''), nationality),
    country = coalesce(nullif(trim(p_patch->>'country'),''), country),
    province = case when p_patch ? 'province' then nullif(trim(p_patch->>'province'),'') else province end,
    kab_kota = case when p_patch ? 'kab_kota' then nullif(trim(p_patch->>'kab_kota'),'') else kab_kota end,
    guardian_name = case when p_patch ? 'guardian_name' then nullif(trim(p_patch->>'guardian_name'),'') else guardian_name end,
    guardian_phone = case when p_patch ? 'guardian_phone' then nullif(trim(p_patch->>'guardian_phone'),'') else guardian_phone end,
    guardian_email = case when p_patch ? 'guardian_email' then nullif(lower(trim(p_patch->>'guardian_email')),'') else guardian_email end,
    guardian_relation = case when p_patch ? 'guardian_relation' then nullif(trim(p_patch->>'guardian_relation'),'') else guardian_relation end
  where id = a.id;
  perform jo.log(st.id, 'data_atlet_diubah', 'athlete', a.id::text,
    jsonb_build_object('reason', p_reason, 'before', (select jsonb_object_agg(x.key, b->x.key) from jsonb_object_keys(p_patch) x(key)), 'after', p_patch));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_move_entry(p_entry uuid, p_category integer, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions; c_old jo.categories; c_new jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into e from jo.entries where id = p_entry for update;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id;
  perform jo.check_discipline(st, s.discipline);
  select * into c_old from jo.categories where id = e.category_id;
  select * into c_new from jo.categories where id = p_category;
  if c_new.id is null or c_new.discipline <> c_old.discipline then
    raise exception 'Kategori tujuan harus di disiplin yang sama.';
  end if;
  if c_new.entry_type <> c_old.entry_type then
    raise exception 'Tidak bisa memindahkan antara nomor perorangan dan pasangan.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan pemindahan (mis. penggabungan kategori).'; end if;
  update jo.entries set category_id = c_new.id, session_id = null, group_no = null, start_order = null,
    priangan_requested = c_new.jabar_only,
    priangan_status = case when not c_new.jabar_only then 'tidak' when c_old.jabar_only then priangan_status else 'menunggu' end,
    music_status = case when c_new.discipline = 'RG' and exists (select 1 from unnest(c_new.apparatus) x where coalesce(e.music->>x,'') = '')
                        then 'belum' else music_status end
   where id = e.id;
  perform jo.log(st.id, 'pindah_kategori', 'entry', e.id::text,
    jsonb_build_object('from', c_old.name_id, 'to', c_new.name_id, 'reason', p_reason));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_set_entry_status(p_entry uuid, p_status text, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into e from jo.entries where id = p_entry;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = e.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if p_status not in ('aktif','dns','dibatalkan') then raise exception 'Status tidak dikenal.'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan.'; end if;
  update jo.entries set status = p_status where id = e.id;
  perform jo.log(st.id, 'status_entri', 'entry', e.id::text, jsonb_build_object('from', e.status, 'to', p_status, 'reason', p_reason));
  return public.console_submission(s.id);
end $$;

create or replace function public.console_resend_email(p_id uuid, p_kind text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into s from jo.submissions where id = p_id;
  if s.id is null then raise exception 'Pendaftaran tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  if p_kind = 'pendaftaran' then perform jo.queue_registration_email(s.id);
  elsif p_kind = 'lunas' and s.status = 'lunas' then perform jo.queue_paid_email(s.id);
  elsif p_kind = 'tautan' then perform jo.queue_link_email(s.id);
  else raise exception 'Jenis email tidak sesuai dengan status pendaftaran.'; end if;
  perform jo.log(st.id, 'kirim_ulang_email', 'submission', s.id::text, jsonb_build_object('kind', p_kind));
  return public.console_submission(s.id);
end $$;

-- ---------------------------------------------------------------------
-- Data atlet (tabel & ekspor)
-- ---------------------------------------------------------------------
create or replace function public.console_athletes(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter,'{}'::jsonb); d text; q text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.expire_unpaid();
  d := coalesce(st.discipline, nullif(f->>'discipline',''));
  q := '%' || lower(coalesce(f->>'q','')) || '%';
  return (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.athlete_no), '[]'::jsonb) from (
    select a.id, a.athlete_no, a.full_name, a.gender, a.birth_date, jo.comp_age(a.birth_date) as age,
      a.nationality, a.country, a.province, a.kab_kota, coalesce(c.name, 'Perorangan') as club,
      c.kab_kota as club_kab_kota, c.province as club_province,
      s.discipline, s.code as submission_code, s.id as submission_id, s.status as payment_status,
      a.doc_status, a.guardian_name, a.guardian_phone, a.guardian_email, a.guardian_relation,
      s.contact_name, s.contact_phone, s.contact_email,
      (select string_agg(cat.name_id || case when e.team_only then ' [khusus beregu]' else '' end
                         || case when e.priangan_requested then ' [cek Jawa Barat: ' || e.priangan_status || ']' else '' end, '; ' order by cat.sort)
         from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cat on cat.id = e.category_id
        where ea.athlete_id = a.id and e.status <> 'dibatalkan') as categories,
      a.id_doc_path, a.photo_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path,
      a.bpjs_path is not null as has_bpjs
    from jo.athletes a join jo.submissions s on s.id = a.submission_id
    left join jo.clubs c on c.id = s.club_id
    where (d is null or s.discipline = d)
      and (coalesce(f->>'include_cancelled','false') = 'true' or s.status <> 'dibatalkan')
      and (nullif(f->>'status','') is null or s.status = f->>'status')
      and (coalesce(f->>'q','') = '' or lower(a.full_name) like q or lower(coalesce(a.athlete_no,'')) like q
           or lower(coalesce(c.name,'')) like q or lower(coalesce(a.kab_kota,'')) like q)
  ) x);
end $$;

-- ---------------------------------------------------------------------
-- Kategori & disiplin
-- ---------------------------------------------------------------------
create or replace function public.console_categories(p_discipline text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri','td','pemantau']);
  d := coalesce(st.discipline, nullif(p_discipline,''));
  return jsonb_build_object(
    'disciplines', (select coalesce(jsonb_agg(to_jsonb(x) order by x.sort), '[]'::jsonb) from jo.disciplines x where d is null or x.code = d),
    'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb),
    'categories', (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
        'registered', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status <> 'dibatalkan'),
        'paid', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas'),
        'priangan', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas' and e.priangan_status = 'disetujui'),
        'delegations', (select count(distinct coalesce(s.club_id::text, s.id::text)) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas')
      ) order by c.sort, c.id), '[]'::jsonb) from jo.categories c where d is null or c.discipline = d)
  );
end $$;

create or replace function public.console_update_category(p_id integer, p_patch jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; k text;
  allowed text[] := array['name_id','name_en','age_label','birth_year_min','birth_year_max','fee','apparatus',
                          'max_per_club','allow_priangan','medal_rule','exhibition','active','note','sort'];
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_id for update;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  for k in select jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) loop
    if not (k = any(allowed)) then raise exception 'Kolom % tidak bisa diubah.', k; end if;
    if st.role = 'admin' and k not in ('exhibition','note') then
      raise exception 'Admin disiplin hanya bisa mengubah status eksibisi dan catatan. Perubahan lain oleh superadmin.';
    end if;
  end loop;
  update jo.categories set
    name_id = coalesce(p_patch->>'name_id', name_id),
    name_en = coalesce(p_patch->>'name_en', name_en),
    age_label = case when p_patch ? 'age_label' then p_patch->>'age_label' else age_label end,
    birth_year_min = case when p_patch ? 'birth_year_min' then nullif(p_patch->>'birth_year_min','')::integer else birth_year_min end,
    birth_year_max = case when p_patch ? 'birth_year_max' then nullif(p_patch->>'birth_year_max','')::integer else birth_year_max end,
    fee = coalesce((p_patch->>'fee')::integer, fee),
    apparatus = case when p_patch ? 'apparatus' then (select coalesce(array_agg(upper(x)), '{}') from jsonb_array_elements_text(p_patch->'apparatus') x) else apparatus end,
    max_per_club = case when p_patch ? 'max_per_club' then nullif(p_patch->>'max_per_club','')::integer else max_per_club end,
    allow_priangan = coalesce((p_patch->>'allow_priangan')::boolean, allow_priangan),
    medal_rule = coalesce(p_patch->'medal_rule', medal_rule),
    exhibition = coalesce((p_patch->>'exhibition')::boolean, exhibition),
    active = coalesce((p_patch->>'active')::boolean, active),
    note = case when p_patch ? 'note' then p_patch->>'note' else note end,
    sort = coalesce((p_patch->>'sort')::integer, sort)
  where id = c.id;
  perform jo.log(st.id, 'kategori_diubah', 'category', c.id::text,
    jsonb_build_object('before', (select jsonb_object_agg(x.key, to_jsonb(c)->x.key) from jsonb_object_keys(p_patch) x(key)), 'after', p_patch));
  return public.console_categories(c.discipline);
end $$;

create or replace function public.console_update_discipline(p_code text, p_patch jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; d jo.disciplines;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into d from jo.disciplines where code = p_code;
  if d.code is null then raise exception 'Disiplin tidak ditemukan.'; end if;
  update jo.disciplines set
    registration_open = coalesce((p_patch->>'registration_open')::boolean, registration_open),
    contact_name = case when p_patch ? 'contact_name' then p_patch->>'contact_name' else contact_name end,
    contact_phone = case when p_patch ? 'contact_phone' then p_patch->>'contact_phone' else contact_phone end,
    date_start = coalesce(nullif(p_patch->>'date_start','')::date, date_start),
    date_end = coalesce(nullif(p_patch->>'date_end','')::date, date_end)
  where code = d.code;
  perform jo.log(st.id, 'disiplin_diubah', 'discipline', d.code, p_patch);
  return public.console_categories(null);
end $$;

-- ---------------------------------------------------------------------
-- Sesi & daftar start
-- ---------------------------------------------------------------------
create or replace function public.console_sessions(p_discipline text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri','td','pemantau']);
  perform jo.check_discipline(st, p_discipline);
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.sort, x.day, x.start_time), '[]'::jsonb)
            from jo.sessions x where x.discipline = p_discipline);
end $$;

create or replace function public.console_save_session(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_id integer;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.check_discipline(st, p->>'discipline');
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama sesi.'; end if;
  if nullif(p->>'id','') is null then
    insert into jo.sessions (discipline, name, day, start_time, sort)
    values (p->>'discipline', trim(p->>'name'), nullif(p->>'day','')::date, nullif(p->>'start_time','')::time, coalesce((p->>'sort')::integer, 0))
    returning id into v_id;
  else
    update jo.sessions set name = trim(p->>'name'), day = nullif(p->>'day','')::date,
      start_time = nullif(p->>'start_time','')::time, sort = coalesce((p->>'sort')::integer, sort)
     where id = (p->>'id')::integer and discipline = p->>'discipline' returning id into v_id;
  end if;
  perform jo.log(st.id, 'sesi_disimpan', 'session', v_id::text, p);
  return public.console_sessions(p->>'discipline');
end $$;

create or replace function public.console_delete_session(p_id integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.sessions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into x from jo.sessions where id = p_id;
  if x.id is null then raise exception 'Sesi tidak ditemukan.'; end if;
  perform jo.check_discipline(st, x.discipline);
  delete from jo.sessions where id = x.id;
  perform jo.log(st.id, 'sesi_dihapus', 'session', x.id::text, to_jsonb(x));
  return public.console_sessions(x.discipline);
end $$;

create or replace function public.console_startlist(p_category integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri','td','pemantau']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  return jsonb_build_object(
    'category', to_jsonb(c),
    'sessions', (select coalesce(jsonb_agg(to_jsonb(x) order by x.sort, x.day, x.start_time), '[]'::jsonb) from jo.sessions x where x.discipline = c.discipline),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'athletes', jo.entry_athletes_json(e.id), 'club', jo.entry_club_label(e.id),
        'region', jo.entry_region(e.id), 'session_id', e.session_id, 'group_no', e.group_no,
        'start_order', e.start_order, 'priangan_status', e.priangan_status, 'status', e.status)
        order by e.group_no nulls last, e.start_order nulls last, e.created_at), '[]'::jsonb)
      from jo.entries e join jo.submissions s on s.id = e.submission_id
      where e.category_id = c.id and e.status in ('aktif','dns') and s.status = 'lunas'),
    'unpaid', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id
      where e.category_id = c.id and e.status = 'aktif' and s.status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan'))
  );
end $$;

create or replace function public.console_save_startlist(p_category integer, p_rows jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; r jsonb;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    update jo.entries set
      session_id = nullif(r->>'session_id','')::integer,
      group_no = nullif(r->>'group_no','')::integer,
      start_order = nullif(r->>'start_order','')::integer
     where id = (r->>'entry_id')::uuid and category_id = c.id;
  end loop;
  perform jo.log(st.id, 'start_list_disimpan', 'category', c.id::text, jsonb_build_object('rows', jsonb_array_length(coalesce(p_rows,'[]'::jsonb))));
  return public.console_startlist(c.id);
end $$;

create or replace function public.console_draw_order(p_category integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  if c.startlist_published then raise exception 'Start list sudah dipublikasikan. Batalkan publikasi dulu untuk mengundi ulang.'; end if;
  with x as (
    select e.id, row_number() over (partition by e.group_no order by random()) as rn
      from jo.entries e join jo.submissions s on s.id = e.submission_id
     where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas'
  )
  update jo.entries e set start_order = x.rn from x where e.id = x.id;
  perform jo.log(st.id, 'undian_urutan', 'category', c.id::text);
  return public.console_startlist(c.id);
end $$;

create or replace function public.console_publish_startlist(p_category integer, p_publish boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  update jo.categories set startlist_published = p_publish where id = c.id;
  perform jo.log(st.id, case when p_publish then 'start_list_dipublikasikan' else 'start_list_ditarik' end, 'category', c.id::text);
  return public.console_startlist(c.id);
end $$;

-- ---------------------------------------------------------------------
-- Penilaian
-- ---------------------------------------------------------------------
create or replace function public.console_score_sheet(p_category integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; d jo.disciplines; is_juri boolean; apps jsonb; comps jsonb; res jsonb;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri','td','pemantau']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  select * into d from jo.disciplines where code = c.discipline;
  is_juri := st.role = 'juri';

  select coalesce(jsonb_agg(x order by array_position(c.apparatus, x->>'code')), '[]'::jsonb) into apps
    from jsonb_array_elements(d.apparatus) x
   where (x->>'code') = any(c.apparatus)
     and (not is_juri or st.apparatus is null or (x->>'code') = any(st.apparatus));

  select coalesce(jsonb_agg(x), '[]'::jsonb) into comps
    from jsonb_array_elements(d.components) x
   where not is_juri or st.components is null or (x->>'code') = any(st.components);

  if not is_juri then
    res := jo.category_results(c.id);
  end if;

  return jsonb_build_object(
    'category', to_jsonb(c),
    'window', jo.staff_window(st),
    'apparatus', apps,
    'components', comps,
    'role', st.role,
    'locked', c.scores_locked or c.results_published,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'athletes', jo.entry_athletes_json(e.id), 'club', jo.entry_club_label(e.id),
        'group_no', e.group_no, 'start_order', e.start_order, 'status', e.status,
        'session', (select name from jo.sessions where id = e.session_id),
        'own', (select coalesce(jsonb_object_agg(sc.apparatus || ':' || sc.component, sc.value), '{}'::jsonb)
                  from jo.scores sc where sc.entry_id = e.id and sc.staff_id = st.id),
        'all', case when is_juri then null else (
            select coalesce(jsonb_agg(jsonb_build_object('apparatus', sc.apparatus, 'component', sc.component,
                     'staff_id', sc.staff_id, 'staff', x.name, 'value', sc.value, 'updated_at', sc.updated_at)
                     order by sc.apparatus, sc.component, x.name), '[]'::jsonb)
              from jo.scores sc join jo.staff x on x.id = sc.staff_id where sc.entry_id = e.id) end,
        'result', case when is_juri then null else (
            select r from jsonb_array_elements(res) r where r->>'entry_id' = e.id::text limit 1) end
      ) order by e.group_no nulls last, e.start_order nulls last, e.created_at), '[]'::jsonb)
      from jo.entries e join jo.submissions s on s.id = e.submission_id
      where e.category_id = c.id and e.status in ('aktif','dns') and s.status = 'lunas')
  );
end $$;

create or replace function public.console_save_score(p_entry uuid, p_apparatus text, p_component text, p_value numeric, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; c jo.categories; s jo.submissions; old jo.scores;
  v_app text := upper(trim(p_apparatus)); v_comp text := upper(trim(p_component)); v_locked boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
  select * into e from jo.entries where id = p_entry;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into c from jo.categories where id = e.category_id;
  perform jo.check_discipline(st, c.discipline);
  select * into s from jo.submissions where id = e.submission_id;
  if s.status <> 'lunas' or e.status <> 'aktif' then raise exception 'Atlet ini belum lunas atau tidak aktif.'; end if;
  if not (v_app = any(c.apparatus)) then raise exception 'Alat % tidak ada di kategori ini.', v_app; end if;
  if v_comp not in ('D','E','A','PEN','FINAL') then raise exception 'Komponen nilai tidak dikenal.'; end if;
  v_locked := c.scores_locked or c.results_published;
  if st.role = 'juri' then
    perform jo.require_window(st);
    if v_comp = 'FINAL' then raise exception 'Nilai akhir hanya bisa diisi admin.'; end if;
    if st.apparatus is not null and not (v_app = any(st.apparatus)) then raise exception 'Kode akses Anda tidak untuk alat ini.'; end if;
    if st.components is not null and not (v_comp = any(st.components)) then raise exception 'Kode akses Anda tidak untuk komponen ini.'; end if;
    if v_locked then raise exception 'Nilai kategori ini sudah dikunci. Hubungi admin untuk koreksi.'; end if;
  elsif v_locked and length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Nilai sudah dikunci. Tulis alasan koreksi.';
  end if;
  if p_value is null or p_value < 0 or p_value > 40 then raise exception 'Nilai harus antara 0 dan 40.'; end if;

  select * into old from jo.scores
   where entry_id = e.id and apparatus = v_app and component = v_comp and staff_id = st.id;
  if old.id is null then
    insert into jo.scores (entry_id, apparatus, component, staff_id, value) values (e.id, v_app, v_comp, st.id, p_value);
    if v_comp = 'FINAL' or v_locked then
      insert into jo.score_log (entry_id, apparatus, component, judge_id, old_value, new_value, changed_by, action, reason)
      values (e.id, v_app, v_comp, st.id, null, p_value, st.id, case when v_comp = 'FINAL' then 'nilai_akhir' else 'input_setelah_kunci' end, nullif(trim(coalesce(p_reason,'')),''));
    end if;
  elsif old.value <> p_value then
    update jo.scores set value = p_value, updated_at = now() where id = old.id;
    insert into jo.score_log (entry_id, apparatus, component, judge_id, old_value, new_value, changed_by, action, reason)
    values (e.id, v_app, v_comp, st.id, old.value, p_value, st.id, 'ubah', nullif(trim(coalesce(p_reason,'')),''));
  end if;
  return jsonb_build_object('ok', true, 'value', p_value,
    'apparatus_score', case when st.role = 'juri' then null else jo.apparatus_score(e.id, v_app) end);
end $$;

create or replace function public.console_delete_score(p_entry uuid, p_apparatus text, p_component text, p_staff uuid default null, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; c jo.categories; old jo.scores; v_staff uuid;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
  select * into e from jo.entries where id = p_entry;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into c from jo.categories where id = e.category_id;
  perform jo.check_discipline(st, c.discipline);
  v_staff := coalesce(p_staff, st.id);
  if st.role = 'juri' then perform jo.require_window(st); end if;
  if st.role = 'juri' and (v_staff <> st.id or c.scores_locked or c.results_published) then
    raise exception 'Juri hanya bisa menghapus nilainya sendiri sebelum dikunci.';
  end if;
  if st.role <> 'juri' and (v_staff <> st.id or c.scores_locked or c.results_published)
     and length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Tulis alasan penghapusan nilai.';
  end if;
  select * into old from jo.scores where entry_id = e.id and apparatus = upper(p_apparatus)
     and component = upper(p_component) and staff_id = v_staff;
  if old.id is null then return jsonb_build_object('ok', true); end if;
  delete from jo.scores where id = old.id;
  insert into jo.score_log (entry_id, apparatus, component, judge_id, old_value, new_value, changed_by, action, reason)
  values (e.id, old.apparatus, old.component, v_staff, old.value, null, st.id, 'hapus', nullif(trim(coalesce(p_reason,'')),''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.console_lock_scores(p_category integer, p_lock boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  update jo.categories set scores_locked = p_lock where id = c.id;
  perform jo.log(st.id, case when p_lock then 'nilai_dikunci' else 'nilai_dibuka' end, 'category', c.id::text);
  return public.console_score_sheet(c.id);
end $$;

create or replace function public.console_results(p_category integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','pemantau']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  return jsonb_build_object('category', to_jsonb(c),
    'apparatus', (select coalesce(jsonb_agg(x order by array_position(c.apparatus, x->>'code')), '[]'::jsonb)
                    from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x
                   where d.code = c.discipline and (x->>'code') = any(c.apparatus)),
    'results', jo.category_results(c.id),
    'certificates', (select coalesce(jsonb_agg(jsonb_build_object('entry_id', ea.entry_id, 'athlete_id', ea.athlete_id, 'cert_code', ea.cert_code)), '[]'::jsonb)
                       from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id where e.category_id = c.id),
    'signatories', jo.setting('signatories'));
end $$;

create or replace function public.console_publish_results(p_category integer, p_publish boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  if not p_publish and st.role not in ('owner','superadmin') then
    raise exception 'Menarik hasil yang sudah dipublikasikan hanya bisa dilakukan superadmin.';
  end if;
  update jo.categories set results_published = p_publish,
    results_published_at = case when p_publish then now() else null end,
    scores_locked = case when p_publish then true else scores_locked end
   where id = c.id;
  perform jo.log(st.id, case when p_publish then 'hasil_dipublikasikan' else 'hasil_ditarik' end, 'category', c.id::text);
  return public.console_results(c.id);
end $$;

create or replace function public.console_medal_table(p_priangan boolean, p_published_only boolean default true) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','pemantau']);
  return jo.medal_table(coalesce(p_priangan,false), coalesce(p_published_only,true));
end $$;

create or replace function public.console_score_log(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','td']);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'at', l.at, 'action', l.action, 'apparatus', l.apparatus, 'component', l.component,
      'old_value', l.old_value, 'new_value', l.new_value, 'reason', l.reason,
      'judge', (select name from jo.staff where id = l.judge_id),
      'changed_by', (select name from jo.staff where id = l.changed_by),
      'category', c.name_id, 'discipline', c.discipline,
      'athletes', jo.entry_athletes_json(l.entry_id)) order by l.at desc), '[]'::jsonb)
    from jo.score_log l left join jo.entries e on e.id = l.entry_id left join jo.categories c on c.id = e.category_id
    where (nullif(p_filter->>'category_id','') is null or c.id = (p_filter->>'category_id')::integer)
      and (st.discipline is null or c.discipline = st.discipline)
    limit 2000);
end $$;


-- ---------------------------------------------------------------------
-- Musik Ritmik (admin RG ke atas)
-- ---------------------------------------------------------------------
create or replace function public.console_music(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter,'{}'::jsonb);
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.check_discipline(st, 'RG');
  return (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.category_sort, x.athlete_no), '[]'::jsonb) from (
    select e.id as entry_id, a.full_name, a.athlete_no, c.name_id as category, c.sort as category_sort, c.apparatus,
      coalesce(k.name, 'Perorangan') as club, s.code, s.id as submission_id, s.status as payment_status,
      s.contact_name, s.contact_phone, s.contact_email,
      e.music, e.music_status, e.music_note, e.music_changes, e.music_updated_at,
      (select name from jo.staff where id = e.music_checked_by) as checked_by, e.music_checked_at,
      c.startlist_published
    from jo.entries e join jo.categories c on c.id = e.category_id
    join jo.submissions s on s.id = e.submission_id
    join jo.entry_athletes ea on ea.entry_id = e.id join jo.athletes a on a.id = ea.athlete_id
    left join jo.clubs k on k.id = s.club_id
    where c.discipline = 'RG' and s.status <> 'dibatalkan' and e.status <> 'dibatalkan'
      and (nullif(f->>'status','') is null or e.music_status = f->>'status'
           or (f->>'status' = 'perlu' and e.music_status in ('menunggu','belum','tidak_bisa')))
      and (coalesce(f->>'q','') = '' or lower(a.full_name) like '%' || lower(f->>'q') || '%'
           or lower(coalesce(k.name,'')) like '%' || lower(f->>'q') || '%' or lower(s.code) like '%' || lower(f->>'q') || '%')
  ) x);
end $$;

create or replace function public.console_music_check(p_entry uuid, p_ok boolean, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into e from jo.entries where id = p_entry for update;
  if e.id is null then raise exception 'Entri tidak ditemukan.'; end if;
  select * into c from jo.categories where id = e.category_id;
  perform jo.check_discipline(st, c.discipline);
  if e.music = '{}'::jsonb then raise exception 'Belum ada tautan musik untuk diperiksa.'; end if;
  if not p_ok and length(trim(coalesce(p_note,''))) < 3 then
    raise exception 'Tulis apa masalahnya (mis. folder belum dibagikan, file kosong). Catatan dikirim ke pendaftar.';
  end if;
  update jo.entries set music_status = case when p_ok then 'ok' else 'tidak_bisa' end,
    music_note = case when p_ok then null else trim(p_note) end, music_checked_by = st.id, music_checked_at = now()
   where id = e.id;
  insert into jo.music_log (entry_id, action, new_url, staff_id, note)
  values (e.id, case when p_ok then 'ok' else 'tidak_bisa' end, e.music::text, st.id, nullif(trim(coalesce(p_note,'')),''));
  perform jo.log(st.id, case when p_ok then 'musik_ok' else 'musik_tidak_bisa' end, 'entry', e.id::text, jsonb_build_object('note', p_note));
  if not p_ok then perform jo.queue_music_email(e.id, 'musik_perbaiki'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Beregu: daftar & peringkat per level, publikasi
-- ---------------------------------------------------------------------
create or replace function public.console_teams(p_discipline text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','pemantau']);
  perform jo.check_discipline(st, p_discipline);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'level', lv.level, 'signatories', jo.setting('signatories'),
      'published', coalesce(tl.published, false), 'published_at', tl.published_at,
      'results', jo.team_results(p_discipline, lv.level, true),
      'pending', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name', t.name, 'status', s.status,
                   'club', (select name from jo.clubs where id = s.club_id)) order by t.name), '[]'::jsonb)
                  from jo.teams t join jo.submissions s on s.id = t.submission_id
                 where t.discipline = p_discipline and t.level = lv.level and s.status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan'))
    ) order by lv.sort), '[]'::jsonb)
    from (select c.level, min(c.sort) as sort from jo.categories c where c.discipline = p_discipline and c.active group by c.level) lv
    left join jo.team_levels tl on tl.discipline = p_discipline and tl.level = lv.level
    where exists (select 1 from jo.teams t where t.discipline = p_discipline and t.level = lv.level));
end $$;

create or replace function public.console_team_publish(p_discipline text, p_level text, p_publish boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.check_discipline(st, p_discipline);
  if not p_publish and st.role not in ('owner','superadmin') then
    raise exception 'Menarik hasil beregu yang sudah dipublikasikan hanya bisa dilakukan superadmin.';
  end if;
  insert into jo.team_levels (discipline, level, published, published_at)
  values (p_discipline, p_level, p_publish, case when p_publish then now() end)
  on conflict (discipline, level) do update set published = excluded.published, published_at = excluded.published_at;
  perform jo.log(st.id, case when p_publish then 'hasil_beregu_dipublikasikan' else 'hasil_beregu_ditarik' end, 'team_level', p_discipline || ' ' || p_level);
  return public.console_teams(p_discipline);
end $$;

-- ---------------------------------------------------------------------
-- Ledger & mutasi (superadmin)
-- ---------------------------------------------------------------------
create or replace function public.console_ledger(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter,'{}'::jsonb);
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.created_at), '[]'::jsonb) from (
      select s.id, s.code, s.created_at, s.discipline, coalesce(c.name, 'Perorangan') as club, s.registrant_type,
        (select t.name || ' (' || t.level || ')' from jo.teams t where t.submission_id = s.id) as team_name,
        s.contact_name, s.contact_phone, s.contact_email,
        (select count(*) from jo.athletes a where a.submission_id = s.id) as n_athletes,
        (select count(*) from jo.entries e where e.submission_id = s.id and e.status <> 'dibatalkan') as n_entries,
        s.base_amount, s.priangan_amount, s.unique_code, s.total_amount, s.status, s.payment_method,
        s.paid_amount, s.paid_at, s.proof_path, s.proof_uploaded_at, s.verify_note,
        (select name from jo.staff where id = s.verified_by) as verified_by, s.verified_at,
        (select jsonb_agg(jsonb_build_object('id', m.id, 'amount', m.amount, 'trx_time', m.trx_time, 'reference', m.reference, 'match_status', m.match_status))
           from jo.mutations m where m.submission_id = s.id) as mutations
      from jo.submissions s left join jo.clubs c on c.id = s.club_id
      where (nullif(f->>'discipline','') is null or s.discipline = f->>'discipline')
        and (nullif(f->>'status','') is null or s.status = f->>'status')) x),
    'summary', (select coalesce(jsonb_agg(jsonb_build_object('discipline', d.code, 'name', d.name_id,
        'expected', (select coalesce(sum(total_amount),0) from jo.submissions s where s.discipline = d.code and s.status <> 'dibatalkan'),
        'paid', (select coalesce(sum(coalesce(paid_amount,total_amount)),0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas'),
        'fees_paid', (select coalesce(sum(base_amount),0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas' and s.registrant_type <> 'beregu'),
        'team_paid', (select coalesce(sum(base_amount),0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas' and s.registrant_type = 'beregu'),
        'teams_paid', (select count(*) from jo.submissions s where s.discipline = d.code and s.status = 'lunas' and s.registrant_type = 'beregu'),
        'priangan_paid', (select coalesce(sum(priangan_amount),0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas'),
        'unique_paid', (select coalesce(sum(unique_code),0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas'),
        'count_paid', (select count(*) from jo.submissions s where s.discipline = d.code and s.status = 'lunas'),
        'count_open', (select count(*) from jo.submissions s where s.discipline = d.code and s.status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan'))
      ) order by d.sort), '[]'::jsonb) from jo.disciplines d),
    'mutations', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'imported_at', m.imported_at, 'batch', m.batch,
        'trx_time', m.trx_time, 'amount', m.amount, 'reference', m.reference, 'description', m.description,
        'match_status', m.match_status, 'submission_code', s.code, 'submission_id', s.id,
        'submission_status', s.status) order by m.trx_time desc nulls last, m.id desc), '[]'::jsonb)
      from jo.mutations m left join jo.submissions s on s.id = m.submission_id)
  );
end $$;

create or replace function public.console_import_mutations(p_rows jsonb, p_batch text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; r jsonb; v_ins integer := 0; v_dup integer := 0; v_match integer := 0; m jo.mutations;
  v_batch text := coalesce(nullif(trim(coalesce(p_batch,'')),''), to_char(now() at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI'));
  v_cand uuid[]; v_id bigint;
begin
  st := jo.require_staff(array['owner','superadmin']);
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    if nullif(r->>'amount','') is null or (r->>'amount')::numeric <= 0 then continue; end if;
    v_id := null;
    insert into jo.mutations (imported_by, batch, trx_time, amount, reference, description, raw)
    values (st.id, v_batch, nullif(r->>'trx_time','')::timestamptz, round((r->>'amount')::numeric)::integer,
            nullif(trim(coalesce(r->>'reference','')),''), nullif(trim(coalesce(r->>'description','')),''), r->'raw')
    on conflict do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; else v_ins := v_ins + 1; end if;
  end loop;
  -- pencocokan otomatis: nominal sama persis & hanya satu kandidat
  for m in select * from jo.mutations where match_status = 'belum' and batch = v_batch loop
    select array_agg(s.id) into v_cand from jo.submissions s
     where s.total_amount = m.amount and s.status <> 'dibatalkan'
       and (m.trx_time is null or s.created_at <= m.trx_time + interval '1 day')
       and not exists (select 1 from jo.mutations m2 where m2.submission_id = s.id and m2.match_status in ('otomatis','manual'));
    if array_length(v_cand, 1) = 1 then
      update jo.mutations set submission_id = v_cand[1], match_status = 'otomatis' where id = m.id;
      v_match := v_match + 1;
    end if;
  end loop;
  perform jo.log(st.id, 'impor_mutasi', 'mutation', v_batch,
    jsonb_build_object('inserted', v_ins, 'duplicates', v_dup, 'matched', v_match));
  return jsonb_build_object('batch', v_batch, 'inserted', v_ins, 'duplicates', v_dup, 'matched', v_match,
    'unmatched', (select count(*) from jo.mutations where batch = v_batch and match_status = 'belum'));
end $$;

create or replace function public.console_match_mutation(p_mutation bigint, p_submission uuid, p_status text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; m jo.mutations;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into m from jo.mutations where id = p_mutation;
  if m.id is null then raise exception 'Mutasi tidak ditemukan.'; end if;
  if p_status not in ('manual','abaikan','belum') then raise exception 'Status tidak dikenal.'; end if;
  if p_status = 'manual' and p_submission is null then raise exception 'Pilih pendaftaran yang cocok.'; end if;
  update jo.mutations set submission_id = case when p_status = 'manual' then p_submission else null end,
    match_status = p_status where id = m.id;
  perform jo.log(st.id, 'cocokkan_mutasi', 'mutation', m.id::text,
    jsonb_build_object('submission', p_submission, 'status', p_status, 'amount', m.amount));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Kode akses panitia
-- ---------------------------------------------------------------------
create or replace function jo.new_staff_code() returns text
language sql volatile set search_path = '' as $$
  select 'JO-' || jo.rand_code(4) || '-' || jo.rand_code(4)
$$;

create or replace function public.console_staff_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return (select coalesce(jsonb_agg(jo.staff_json(x) order by
      array_position(array['owner','superadmin','admin','td','juri','pemantau'], x.role), x.discipline nulls first, x.name), '[]'::jsonb)
    from jo.staff x);
end $$;

-- Pembuatan kode inti (tanpa cek peran pemanggil). Dipakai console_staff_create & persetujuan juri.
create or replace function jo.staff_create(st jo.staff, p jsonb) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_code text; v_role text := p->>'role'; x jo.staff;
begin
  if v_role not in ('superadmin','admin','td','juri','pemantau') then raise exception 'Peran tidak dikenal.'; end if;
  if v_role = 'superadmin' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa membuat kode superadmin.'; end if;
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama pemegang kode.'; end if;
  if nullif(p->>'discipline','') is not null and not exists (select 1 from jo.disciplines where code = p->>'discipline') then
    raise exception 'Disiplin tidak dikenal.';
  end if;
  v_code := jo.new_staff_code();
  insert into jo.staff (name, role, discipline, apparatus, components, code_hash, code_hint, note, created_by, phone, access_windows)
  values (trim(p->>'name'), v_role, nullif(p->>'discipline',''),
    case when jsonb_typeof(p->'apparatus') = 'array' and jsonb_array_length(p->'apparatus') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'apparatus') a) end,
    case when jsonb_typeof(p->'components') = 'array' and jsonb_array_length(p->'components') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'components') a) end,
    jo.sha256(jo.norm_code(v_code)), right(v_code, 4), nullif(trim(coalesce(p->>'note','')),''), st.id,
    nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), ''),
    case when v_role = 'juri' then jo.norm_windows(p->'access_windows') end)
  returning * into x;
  perform jo.log(st.id, 'kode_dibuat', 'staff', x.id::text, jsonb_build_object('name', x.name, 'role', x.role, 'discipline', x.discipline));
  return jsonb_build_object('staff', jo.staff_json(x), 'code', v_code);
end $$;

create or replace function public.console_staff_create(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jo.staff_create(st, p);
end $$;

create or replace function public.console_staff_update(p_id uuid, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into x from jo.staff where id = p_id for update;
  if x.id is null then raise exception 'Kode tidak ditemukan.'; end if;
  if x.role = 'owner' and st.role <> 'owner' then raise exception 'Kode owner tidak bisa diubah.'; end if;
  if x.role = 'superadmin' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa mengubah kode superadmin.'; end if;
  if x.role = 'owner' and coalesce((p->>'active')::boolean, true) = false then raise exception 'Kode owner tidak bisa dinonaktifkan.'; end if;
  update jo.staff set
    name = coalesce(nullif(trim(p->>'name'),''), name),
    active = coalesce((p->>'active')::boolean, active),
    discipline = case when p ? 'discipline' then nullif(p->>'discipline','') else discipline end,
    apparatus = case when p ? 'apparatus' then
        case when jsonb_typeof(p->'apparatus') = 'array' and jsonb_array_length(p->'apparatus') > 0
             then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'apparatus') a) end
      else apparatus end,
    components = case when p ? 'components' then
        case when jsonb_typeof(p->'components') = 'array' and jsonb_array_length(p->'components') > 0
             then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'components') a) end
      else components end,
    note = case when p ? 'note' then nullif(trim(p->>'note'),'') else note end,
    phone = case when p ? 'phone' then nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), '') else phone end,
    access_windows = case when x.role <> 'juri' then null when p ? 'access_windows' then jo.norm_windows(p->'access_windows') else access_windows end
  where id = x.id;
  if coalesce((p->>'active')::boolean, true) = false then
    delete from jo.staff_sessions where staff_id = x.id;
  end if;
  perform jo.log(st.id, 'kode_diubah', 'staff', x.id::text, p);
  return public.console_staff_list();
end $$;

create or replace function public.console_staff_new_code(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.staff; v_code text;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into x from jo.staff where id = p_id for update;
  if x.id is null then raise exception 'Kode tidak ditemukan.'; end if;
  if x.role in ('owner','superadmin') and st.role <> 'owner' then raise exception 'Hanya owner yang bisa mengganti kode ini.'; end if;
  v_code := jo.new_staff_code();
  update jo.staff set code_hash = jo.sha256(jo.norm_code(v_code)), code_hint = right(v_code, 4) where id = x.id;
  delete from jo.staff_sessions where staff_id = x.id and uid <> auth.uid();
  perform jo.log(st.id, 'kode_diganti', 'staff', x.id::text, jsonb_build_object('name', x.name));
  return jsonb_build_object('staff', jo.staff_json(x), 'code', v_code);
end $$;

-- Hapus kode akses: hanya kode nonaktif tanpa jejak kerja (nilai, verifikasi, dsb.).
-- Kode yang pernah bekerja cukup dinonaktifkan agar namanya tetap muncul di riwayat.
create or replace function public.console_staff_delete(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.staff; v_work text;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into x from jo.staff where id = p_id for update;
  if x.id is null then raise exception 'Kode tidak ditemukan.'; end if;
  if x.role = 'owner' then raise exception 'Kode owner tidak bisa dihapus.'; end if;
  if x.id = st.id then raise exception 'Anda tidak bisa menghapus kode Anda sendiri.'; end if;
  if x.role = 'superadmin' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa menghapus kode superadmin.'; end if;
  if x.active then raise exception 'Nonaktifkan kode ini dulu, lalu hapus.'; end if;
  v_work := case
    when exists (select 1 from jo.scores where staff_id = x.id)
      or exists (select 1 from jo.score_log where judge_id = x.id or changed_by = x.id) then 'nilai'
    when exists (select 1 from jo.submissions where verified_by = x.id) then 'verifikasi pembayaran'
    when exists (select 1 from jo.athletes where doc_verified_by = x.id) then 'verifikasi dokumen'
    when exists (select 1 from jo.mutations where imported_by = x.id) then 'impor mutasi'
    when exists (select 1 from jo.music_log where staff_id = x.id)
      or exists (select 1 from jo.entries where music_checked_by = x.id) then 'pemeriksaan musik'
  end;
  if v_work is not null then
    raise exception '% sudah tercatat melakukan %. Kode ini cukup dibiarkan nonaktif agar namanya tetap muncul di riwayat.', x.name, v_work
      using hint = 'ERR_STAFF_HAS_WORK';
  end if;
  update jo.audit set detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('staff_name', x.name), staff_id = null
   where staff_id = x.id;
  update jo.staff set created_by = null where created_by = x.id;
  delete from jo.staff_sessions where staff_id = x.id;
  delete from jo.staff where id = x.id;
  perform jo.log(st.id, 'kode_dihapus', 'staff', x.id::text, jsonb_build_object('name', x.name, 'role', x.role, 'discipline', x.discipline));
  return public.console_staff_list();
end $$;

-- Nominative Form Artistik (format lampiran panitia): daftar pesenam & tim per klub
create or replace function public.console_nominative(p_discipline text, p_club uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  if p_discipline not in ('MAG','WAG') then raise exception 'Nominative Form hanya untuk Artistik.'; end if;
  perform jo.check_discipline(st, p_discipline);
  return jsonb_build_object(
    'gymnasts', (select coalesce(jsonb_agg(jsonb_build_object(
        'club', coalesce(k.name, 'Perorangan'), 'name', a.full_name, 'birth_date', a.birth_date,
        'age', 2026 - extract(year from a.birth_date)::integer, 'discipline', c.discipline,
        'level', c.level, 'category', c.age_label, 'athlete_no', a.athlete_no,
        'code', s.code, 'status', s.status, 'priangan', e.priangan_status = 'disetujui')
      order by coalesce(k.name, 'zzz'), c.sort, a.full_name), '[]'::jsonb)
      from jo.entries e join jo.categories c on c.id = e.category_id
      join jo.submissions s on s.id = e.submission_id
      join jo.entry_athletes ea on ea.entry_id = e.id join jo.athletes a on a.id = ea.athlete_id
      left join jo.clubs k on k.id = s.club_id
      where c.discipline = p_discipline and not e.team_only and e.status <> 'dibatalkan' and s.status <> 'dibatalkan'
        and (p_club is null or s.club_id = p_club)),
    'teams', (select coalesce(jsonb_agg(jsonb_build_object(
        'club', coalesce(k.name, 'Perorangan'), 'discipline', t.discipline, 'level', t.level, 'name', t.name,
        'code', s.code, 'status', s.status,
        'members', (select coalesce(jsonb_agg(jsonb_build_object('name', a.full_name, 'team_only', m.team_only) order by m.sort), '[]'::jsonb)
                      from jo.team_members m join jo.athletes a on a.id = m.athlete_id where m.team_id = t.id))
      order by coalesce(k.name, 'zzz'), t.level, t.name), '[]'::jsonb)
      from jo.teams t join jo.submissions s on s.id = t.submission_id left join jo.clubs k on k.id = s.club_id
      where t.discipline = p_discipline and s.status <> 'dibatalkan' and (p_club is null or s.club_id = p_club)),
    'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- Pengaturan, klub, log, email
-- ---------------------------------------------------------------------
create or replace function public.console_settings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'settings', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jo.settings where key not in ('outbox_secret_hash')),
    'email_secret_set', jo.setting_text('outbox_secret_hash') is not null,
    'disciplines', (select coalesce(jsonb_agg(to_jsonb(d) order by d.sort), '[]'::jsonb) from jo.disciplines d));
end $$;

create or replace function public.console_save_setting(p_key text, p_value jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
  allowed text[] := array['event_name','registration_open','registration_deadline','payment_deadline_label',
    'priangan_fee','qris_cap','max_athletes','qris_image_url','qris_merchant','payment_note','contact_email',
    'instagram','signatories','email_guardians','venue','site_url'];
begin
  st := jo.require_staff(array['owner','superadmin']);
  if not (p_key = any(allowed)) then raise exception 'Pengaturan % tidak bisa diubah dari konsol.', p_key; end if;
  if p_key = 'site_url' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa mengubah alamat situs.'; end if;
  insert into jo.settings (key, value, updated_at, updated_by) values (p_key, p_value, now(), st.id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
  perform jo.log(st.id, 'pengaturan_diubah', 'setting', p_key, jsonb_build_object('value', p_value));
  return public.console_settings();
end $$;

create or replace function public.console_new_email_secret() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v text := jo.rand_code(32, '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ');
begin
  st := jo.require_staff(array['owner']);
  insert into jo.settings (key, value) values ('outbox_secret_hash', to_jsonb(jo.sha256(v)))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform jo.log(st.id, 'secret_email_diganti', 'setting', 'outbox_secret_hash');
  return jsonb_build_object('secret', v);
end $$;

create or replace function public.console_clubs() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  return (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
      'submissions', (select count(*) from jo.submissions s where s.club_id = c.id and s.status <> 'dibatalkan'),
      'athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.club_id = c.id and s.status <> 'dibatalkan'),
      'merged_into_name', (select name from jo.clubs m where m.id = c.merged_into)
    ) order by c.merged_into nulls first, c.name), '[]'::jsonb) from jo.clubs c);
end $$;

create or replace function public.console_save_club(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_id uuid;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama klub.'; end if;
  if nullif(p->>'id','') is null then
    insert into jo.clubs (name, kind, kab_kota, province, country, verified, created_via)
    values (trim(p->>'name'), coalesce(nullif(p->>'kind',''),'klub'), nullif(trim(coalesce(p->>'kab_kota','')),''),
      nullif(trim(coalesce(p->>'province','')),''), coalesce(nullif(trim(coalesce(p->>'country','')),''),'Indonesia'),
      coalesce((p->>'verified')::boolean, true), 'konsol')
    returning id into v_id;
  else
    update jo.clubs set name = trim(p->>'name'), kind = coalesce(nullif(p->>'kind',''), kind),
      kab_kota = nullif(trim(coalesce(p->>'kab_kota','')),''), province = nullif(trim(coalesce(p->>'province','')),''),
      country = coalesce(nullif(trim(coalesce(p->>'country','')),''), country),
      verified = coalesce((p->>'verified')::boolean, verified)
     where id = (p->>'id')::uuid returning id into v_id;
  end if;
  perform jo.log(st.id, 'klub_disimpan', 'club', v_id::text, p);
  return public.console_clubs();
end $$;

create or replace function public.console_merge_club(p_from uuid, p_into uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  if p_from = p_into then raise exception 'Pilih dua klub yang berbeda.'; end if;
  if not exists (select 1 from jo.clubs where id = p_into and merged_into is null) then raise exception 'Klub tujuan tidak valid.'; end if;
  update jo.submissions set club_id = p_into where club_id = p_from;
  update jo.clubs set merged_into = p_into where id = p_from;
  update jo.clubs set merged_into = p_into where merged_into = p_from;
  perform jo.log(st.id, 'klub_digabung', 'club', p_from::text, jsonb_build_object('into', p_into));
  return public.console_clubs();
end $$;

create or replace function public.console_audit(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'at', l.at, 'action', l.action,
      'staff', coalesce((select name from jo.staff where id = l.staff_id), l.detail->>'staff_name'), 'target_type', l.target_type,
      'target_id', l.target_id, 'detail', l.detail) order by l.id desc), '[]'::jsonb)
    from (select * from jo.audit
           where (nullif(p_filter->>'action','') is null or action = p_filter->>'action')
           order by id desc limit coalesce((p_filter->>'limit')::integer, 500)) l);
end $$;

create or replace function public.console_outbox() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'last_poll', jo.setting('outbox_last_poll'),
    'secret_set', jo.setting_text('outbox_secret_hash') is not null,
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'created_at', o.created_at, 'kind', o.kind,
        'to', o.to_email, 'cc', o.cc, 'subject', o.subject, 'status', o.status, 'attempts', o.attempts,
        'sent_at', o.sent_at, 'last_error', o.last_error, 'code', s.code) order by o.id desc), '[]'::jsonb)
      from (select * from jo.outbox order by id desc limit 300) o left join jo.submissions s on s.id = o.submission_id));
end $$;

create or replace function public.console_outbox_retry(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  update jo.outbox set status = 'pending', attempts = 0, last_error = null where id = p_id;
  return public.console_outbox();
end $$;
