-- =====================================================================
--  v5: kontak & nomor WA panitia, chat panitia, laporan masalah,
--      pendaftaran juri, hapus klub
-- =====================================================================

-- ---------------------------------------------------------------------
-- Profil sendiri: nomor WhatsApp
-- ---------------------------------------------------------------------
create or replace function public.console_me_update(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_phone text;
begin
  st := jo.require_staff(null);
  if p ? 'phone' then
    v_phone := nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), '');
    if v_phone is not null and length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 9 then
      raise exception 'Nomor WhatsApp tidak valid.';
    end if;
    update jo.staff set phone = v_phone where id = st.id;
  end if;
  return jo.staff_json((select x from jo.staff x where x.id = st.id));
end $$;

-- ---------------------------------------------------------------------
-- Klub: hapus (hanya bila tidak dipakai pendaftaran)
-- ---------------------------------------------------------------------
create or replace function public.console_delete_club(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; k jo.clubs;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into k from jo.clubs where id = p_id;
  if k.id is null then raise exception 'Klub tidak ditemukan.'; end if;
  if exists (select 1 from jo.submissions where club_id = k.id) then
    raise exception 'Klub % dipakai % pendaftaran. Gabungkan ke klub yang benar, jangan dihapus.', k.name,
      (select count(*) from jo.submissions where club_id = k.id);
  end if;
  if exists (select 1 from jo.clubs where merged_into = k.id) then
    raise exception 'Ada klub lain yang sudah digabung ke klub ini. Klub ini tidak bisa dihapus.';
  end if;
  delete from jo.clubs where id = k.id;
  perform jo.log(st.id, 'klub_dihapus', 'club', k.id::text, jsonb_build_object('name', k.name, 'kab_kota', k.kab_kota, 'province', k.province));
  return public.console_clubs();
end $$;

-- ---------------------------------------------------------------------
-- Chat panitia
--   'all'           : semua pemegang kode
--   'disc:<KODE>'   : panitia/juri disiplin itu + pemegang kode semua disiplin
--   'dm:<id>:<id>'  : percakapan pribadi dua orang (id diurutkan)
-- ---------------------------------------------------------------------
create or replace function jo.chat_can(st jo.staff, p_room text) returns boolean
language sql stable set search_path = '' as $$
  select case
    when p_room = 'all' then true
    when p_room like 'disc:%' then exists (select 1 from jo.disciplines d where d.code = substr(p_room, 6))
                                   and (st.discipline is null or st.discipline = substr(p_room, 6))
    when p_room like 'dm:%' then st.id::text in (split_part(p_room, ':', 2), split_part(p_room, ':', 3))
    else false end
$$;

create or replace function jo.chat_room_label(st jo.staff, p_room text) returns text
language sql stable set search_path = '' as $$
  select case
    when p_room = 'all' then 'Semua panitia'
    when p_room like 'disc:%' then 'Tim ' || coalesce((select name_id from jo.disciplines where code = substr(p_room, 6)), substr(p_room, 6))
    else coalesce((select name from jo.staff x where x.id::text = case when split_part(p_room, ':', 2) = st.id::text
                                                                   then split_part(p_room, ':', 3) else split_part(p_room, ':', 2) end), 'Percakapan')
  end
$$;

create or replace function public.console_chat_rooms() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  return jsonb_build_object(
    'me', st.id,
    'rooms', (select coalesce(jsonb_agg(jsonb_build_object(
        'room', r.room, 'label', jo.chat_room_label(st, r.room), 'kind', case when r.room like 'dm:%' then 'dm' else 'group' end,
        'last', (select jsonb_build_object('id', m.id, 'body', left(m.body, 120), 'sender_name', m.sender_name, 'at', m.created_at)
                   from jo.chat_messages m where m.room = r.room order by m.id desc limit 1),
        'unread', (select count(*) from jo.chat_messages m where m.room = r.room and m.id > coalesce(
                     (select last_id from jo.chat_reads cr where cr.staff_id = st.id and cr.room = r.room), 0)
                     and m.sender is distinct from st.id)
      ) order by r.ord, (select max(id) from jo.chat_messages m where m.room = r.room) desc nulls last), '[]'::jsonb)
      from (
        select 'all' as room, 0 as ord
        union all
        select 'disc:' || d.code, 1 from jo.disciplines d where st.discipline is null or st.discipline = d.code
        union all
        select distinct m.room, 2 from jo.chat_messages m
         where m.room like 'dm:%' and st.id::text in (split_part(m.room, ':', 2), split_part(m.room, ':', 3))
      ) r),
    'people', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'role', x.role, 'discipline', x.discipline,
                 'room', 'dm:' || least(x.id::text, st.id::text) || ':' || greatest(x.id::text, st.id::text))
                 order by array_position(array['owner','superadmin','admin','td','juri'], x.role), x.discipline nulls first, x.name), '[]'::jsonb)
               from jo.staff x where x.active and x.id <> st.id));
end $$;

create or replace function public.console_chat_messages(p_room text, p_after bigint default 0) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_max bigint; res jsonb;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  if not jo.chat_can(st, p_room) then raise exception 'Anda tidak termasuk dalam percakapan ini.' using hint = 'ERR_FORBIDDEN'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'sender', x.sender, 'sender_name', x.sender_name,
           'role', (select role from jo.staff where id = x.sender), 'body', x.body, 'at', x.created_at) order by x.id), '[]'::jsonb),
         max(x.id)
    into res, v_max
    from (select * from jo.chat_messages m where m.room = p_room and m.id > coalesce(p_after, 0)
           order by m.id desc limit 200) x;
  if v_max is not null then
    insert into jo.chat_reads (staff_id, room, last_id) values (st.id, p_room, v_max)
    on conflict (staff_id, room) do update set last_id = greatest(jo.chat_reads.last_id, excluded.last_id);
  end if;
  return jsonb_build_object('room', p_room, 'label', jo.chat_room_label(st, p_room), 'messages', res);
end $$;

create or replace function public.console_chat_send(p_room text, p_body text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_body text := trim(coalesce(p_body, '')); m jo.chat_messages;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  if v_body = '' then raise exception 'Pesan kosong.'; end if;
  if length(v_body) > 4000 then raise exception 'Pesan terlalu panjang (maks. 4000 karakter).'; end if;
  if p_room like 'dm:%' then
    if split_part(p_room, ':', 2) >= split_part(p_room, ':', 3)
       or not exists (select 1 from jo.staff where id::text = split_part(p_room, ':', 2))
       or not exists (select 1 from jo.staff where id::text = split_part(p_room, ':', 3)) then
      raise exception 'Percakapan tidak valid.';
    end if;
  end if;
  if not jo.chat_can(st, p_room) then raise exception 'Anda tidak termasuk dalam percakapan ini.' using hint = 'ERR_FORBIDDEN'; end if;
  if (select count(*) from jo.chat_messages where sender = st.id and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Terlalu banyak pesan dalam satu menit.';
  end if;
  insert into jo.chat_messages (room, sender, sender_name, body) values (p_room, st.id, st.name, v_body) returning * into m;
  insert into jo.chat_reads (staff_id, room, last_id) values (st.id, p_room, m.id)
  on conflict (staff_id, room) do update set last_id = greatest(jo.chat_reads.last_id, excluded.last_id);
  return jsonb_build_object('id', m.id, 'sender', m.sender, 'sender_name', m.sender_name, 'role', st.role, 'body', m.body, 'at', m.created_at);
end $$;

-- ---------------------------------------------------------------------
-- Laporan masalah
-- ---------------------------------------------------------------------
create or replace function jo.issue_visible(st jo.staff, i jo.issues) returns boolean
language sql stable set search_path = '' as $$
  select st.role in ('owner','superadmin')
      or i.reporter = st.id
      or (st.role in ('admin','td') and (st.discipline is null or i.discipline is null or i.discipline = st.discipline))
$$;

create or replace function jo.issue_json(st jo.staff, i jo.issues) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', i.id, 'created_at', i.created_at, 'updated_at', i.updated_at,
    'reporter', i.reporter, 'reporter_name', i.reporter_name,
    'reporter_role', (select role from jo.staff where id = i.reporter),
    'discipline', i.discipline, 'title', i.title, 'body', i.body, 'shot_path', i.shot_path,
    'status', i.status, 'handled_by', (select name from jo.staff where id = i.handled_by), 'resolved_at', i.resolved_at,
    'comments', (select count(*) from jo.issue_comments c where c.issue_id = i.id),
    'unread', i.updated_at > coalesce((select seen_at from jo.issue_reads r where r.staff_id = st.id and r.issue_id = i.id), 'epoch'::timestamptz),
    'can_manage', st.role in ('owner','superadmin') or (st.role = 'admin' and (st.discipline is null or i.discipline is null or i.discipline = st.discipline)))
$$;

create or replace function public.console_issues(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  return (select coalesce(jsonb_agg(jo.issue_json(st, i) order by (i.status = 'selesai'), i.updated_at desc), '[]'::jsonb)
    from jo.issues i
    where jo.issue_visible(st, i)
      and (nullif(f->>'status','') is null or i.status = f->>'status' or (f->>'status' = 'terbuka' and i.status <> 'selesai'))
      and (coalesce((f->>'mine')::boolean, false) = false or i.reporter = st.id));
end $$;

create or replace function public.console_issue(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; i jo.issues;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  select * into i from jo.issues where id = p_id;
  if i.id is null or not jo.issue_visible(st, i) then raise exception 'Laporan tidak ditemukan.'; end if;
  insert into jo.issue_reads (staff_id, issue_id, seen_at) values (st.id, i.id, now())
  on conflict (staff_id, issue_id) do update set seen_at = now();
  return jo.issue_json(st, i) || jsonb_build_object('thread', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'staff_name', c.staff_name, 'role', (select role from jo.staff where id = c.staff_id), 'body', c.body, 'at', c.created_at) order by c.id), '[]'::jsonb)
    from jo.issue_comments c where c.issue_id = i.id));
end $$;

create or replace function public.console_issue_create(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; i jo.issues; v_disc text := nullif(p->>'discipline','');
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  if length(trim(coalesce(p->>'title',''))) < 4 then raise exception 'Tulis judul masalah (min. 4 karakter).'; end if;
  if v_disc is not null and not exists (select 1 from jo.disciplines where code = v_disc) then raise exception 'Disiplin tidak dikenal.'; end if;
  if v_disc is null and st.discipline is not null then v_disc := st.discipline; end if;
  if nullif(p->>'shot_path','') is not null and split_part(p->>'shot_path', '/', 1) <> auth.uid()::text then
    raise exception 'Berkas tangkapan layar tidak valid. Unggah ulang.';
  end if;
  if (select count(*) from jo.issues where reporter = st.id and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Terlalu banyak laporan dalam satu jam.';
  end if;
  insert into jo.issues (reporter, reporter_name, discipline, title, body, shot_path)
  values (st.id, st.name, v_disc, trim(p->>'title'), nullif(trim(coalesce(p->>'body','')),''), nullif(p->>'shot_path',''))
  returning * into i;
  insert into jo.issue_reads (staff_id, issue_id, seen_at) values (st.id, i.id, now()) on conflict do nothing;
  perform jo.log(st.id, 'laporan_dibuat', 'issue', i.id::text, jsonb_build_object('title', i.title, 'discipline', i.discipline));
  return public.console_issue(i.id);
end $$;

create or replace function public.console_issue_comment(p_id bigint, p_body text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; i jo.issues;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  select * into i from jo.issues where id = p_id for update;
  if i.id is null or not jo.issue_visible(st, i) then raise exception 'Laporan tidak ditemukan.'; end if;
  if length(trim(coalesce(p_body,''))) < 1 then raise exception 'Tulis tanggapan.'; end if;
  insert into jo.issue_comments (issue_id, staff_id, staff_name, body) values (i.id, st.id, st.name, trim(p_body));
  update jo.issues set updated_at = now() where id = i.id;
  return public.console_issue(i.id);
end $$;

create or replace function public.console_issue_status(p_id bigint, p_status text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; i jo.issues;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into i from jo.issues where id = p_id for update;
  if i.id is null or not jo.issue_visible(st, i) then raise exception 'Laporan tidak ditemukan.'; end if;
  if not ((jo.issue_json(st, i)->>'can_manage')::boolean) then raise exception 'Laporan ini ditangani admin disiplin lain.'; end if;
  if p_status not in ('baru','diproses','selesai') then raise exception 'Status tidak dikenal.'; end if;
  update jo.issues set status = p_status, updated_at = now(), handled_by = st.id,
    resolved_at = case when p_status = 'selesai' then now() end where id = i.id;
  insert into jo.issue_comments (issue_id, staff_id, staff_name, body)
  values (i.id, st.id, st.name, 'Status diubah menjadi ' || case p_status when 'baru' then 'Baru' when 'diproses' then 'Diproses' else 'Selesai' end || '.');
  perform jo.log(st.id, 'laporan_status', 'issue', i.id::text, jsonb_build_object('status', p_status));
  return public.console_issue(i.id);
end $$;

-- Lencana menu: pesan & laporan yang belum dibaca
create or replace function public.console_unread() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  return jsonb_build_object(
    'chat', (select count(*) from jo.chat_messages m
              where m.sender is distinct from st.id and jo.chat_can(st, m.room)
                and m.id > coalesce((select last_id from jo.chat_reads r where r.staff_id = st.id and r.room = m.room), 0)
                and (m.room like 'dm:%' or m.created_at > now() - interval '14 days')),
    'issues', (select count(*) from jo.issues i where jo.issue_visible(st, i) and i.status <> 'selesai'
                and i.updated_at > coalesce((select seen_at from jo.issue_reads r where r.staff_id = st.id and r.issue_id = i.id), 'epoch'::timestamptz)),
    'jury', case when st.role in ('owner','superadmin','admin') then
              (select count(*) from jo.jury_applications j where j.status = 'baru' and (st.discipline is null or st.discipline = any(j.disciplines))) else 0 end,
    'phone_missing', st.phone is null);
end $$;

-- ---------------------------------------------------------------------
-- Kontak: panitia & juri (semua), pendaftar (admin ke atas & TD)
-- ---------------------------------------------------------------------
create or replace function public.console_contacts() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; v_reg boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin','td','juri']);
  v_reg := st.role in ('owner','superadmin','admin','td');
  return jsonb_build_object(
    'me', st.id,
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'role', x.role, 'discipline', x.discipline,
               'phone', x.phone, 'note', x.note,
               'room', 'dm:' || least(x.id::text, st.id::text) || ':' || greatest(x.id::text, st.id::text))
               order by array_position(array['owner','superadmin','admin','td','juri'], x.role), x.discipline nulls first, x.name), '[]'::jsonb)
              from jo.staff x where x.active),
    'coordinators', (select coalesce(jsonb_agg(jsonb_build_object('discipline', d.code, 'name', d.contact_name, 'phone', d.contact_phone) order by d.sort), '[]'::jsonb)
              from jo.disciplines d where d.contact_name is not null),
    'can_registrants', v_reg,
    'registrants', case when v_reg then (select coalesce(jsonb_agg(jsonb_build_object(
               'submission_id', s.id, 'code', s.code, 'status', s.status, 'discipline', s.discipline,
               'name', s.contact_name, 'role', s.contact_role, 'phone', s.contact_phone, 'email', s.contact_email,
               'club', coalesce(k.name, 'Perorangan'), 'type', s.registrant_type,
               'athletes', (select count(*) from jo.athletes a where a.submission_id = s.id)) order by coalesce(k.name, s.contact_name)), '[]'::jsonb)
              from jo.submissions s left join jo.clubs k on k.id = s.club_id
              where s.status <> 'dibatalkan' and (st.discipline is null or s.discipline = st.discipline)) else '[]'::jsonb end);
end $$;

-- ---------------------------------------------------------------------
-- Pendaftaran juri
-- ---------------------------------------------------------------------
create or replace function jo.queue_jury_email(p_id uuid, p_kind text) returns void
language plpgsql volatile set search_path = '' as $$
declare j jo.jury_applications; title text; body text;
begin
  select * into j from jo.jury_applications where id = p_id;
  if j.id is null or coalesce(j.email, '') = '' then return; end if;
  body := '<p>Halo ' || jo.h(j.full_name) || ',</p>';
  if p_kind = 'juri_diterima' then
    title := 'Pendaftaran juri diterima';
    body := body || '<p>Terima kasih telah mendaftar sebagai juri Jabar Open 2026. Data Anda sudah kami terima dan akan diperiksa panitia. '
      || 'Kami akan menghubungi Anda lewat WhatsApp atau email.</p>'
      || '<p style="font-size:13px;color:#5b6b88">Disiplin: ' || jo.h(array_to_string(j.disciplines, ', ')) || '</p>';
  elsif p_kind = 'juri_disetujui' then
    title := 'Anda terpilih sebagai juri Jabar Open 2026';
    body := body || '<p>Selamat, pendaftaran juri Anda <b>disetujui</b>. Kode akses konsol penilaian akan dikirim panitia secara pribadi lewat WhatsApp. '
      || 'Jangan bagikan kode tersebut kepada siapa pun.</p>'
      || coalesce('<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(j.review_note) || '</p>', '');
  else
    title := 'Pendaftaran juri Jabar Open 2026';
    body := body || '<p>Terima kasih atas minat Anda. Untuk Jabar Open 2026, panitia belum dapat menempatkan Anda sebagai juri.</p>'
      || coalesce('<p style="background:#f4f6fa;border-left:4px solid #cdd6e4;padding:10px 14px">' || jo.h(j.review_note) || '</p>', '');
  end if;
  perform jo.queue_email(null, p_kind, j.email, null, title, jo.email_layout(title, body, 'id'));
end $$;

create or replace function jo.jury_validate(p jsonb, p_require_docs boolean) returns void
language plpgsql stable set search_path = '' as $$
declare d text; v_uid text := auth.uid()::text; dt text;
begin
  if length(trim(coalesce(p->>'full_name',''))) < 3 then raise exception 'Isi nama lengkap.' using hint = 'ERR_JURY'; end if;
  if length(regexp_replace(coalesce(p->>'phone',''), '[^0-9]', '', 'g')) < 9 then raise exception 'Isi nomor WhatsApp yang valid.' using hint = 'ERR_JURY'; end if;
  if p_require_docs and coalesce(p->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Isi email yang valid.' using hint = 'ERR_JURY'; end if;
  -- v6: satu disiplin saja; Aerobik tidak membuka pendaftaran juri
  if jsonb_typeof(p->'disciplines') <> 'array' or jsonb_array_length(p->'disciplines') <> 1 then
    raise exception 'Pilih satu disiplin.' using hint = 'ERR_JURY';
  end if;
  for d in select jsonb_array_elements_text(p->'disciplines') loop
    if d not in ('MAG','WAG','RG') then raise exception 'Pendaftaran juri hanya untuk Artistik Putra, Artistik Putri, dan Ritmik.' using hint = 'ERR_JURY'; end if;
    if coalesce(p->'brevet'->d->>'level', '') = '' then raise exception 'Pilih tingkat brevet untuk %.', d using hint = 'ERR_JURY'; end if;
  end loop;
  if jsonb_typeof(p->'availability') = 'array' then
    for dt in select jsonb_array_elements_text(p->'availability') loop
      if dt !~ '^2026-12-(1[2-9]|20)$' then raise exception 'Tanggal ketersediaan harus 12–20 Desember 2026.' using hint = 'ERR_JURY'; end if;
    end loop;
  end if;
  if p_require_docs then
    if coalesce(p->>'bpjs_path','') = '' then raise exception 'Unggah kartu BPJS Ketenagakerjaan.' using hint = 'ERR_JURY'; end if;
    if coalesce(p->>'ktp_path','') = '' then raise exception 'Unggah KTP atau identitas.' using hint = 'ERR_JURY'; end if;
    if coalesce(p->>'photo_path','') = '' then raise exception 'Unggah pas foto.' using hint = 'ERR_JURY'; end if;
  end if;
  if (nullif(p->>'ktp_path','') is not null and split_part(p->>'ktp_path','/',1) <> v_uid)
     or (nullif(p->>'photo_path','') is not null and split_part(p->>'photo_path','/',1) <> v_uid)
     or (nullif(p->>'cert_path','') is not null and split_part(p->>'cert_path','/',1) <> v_uid)
     or (nullif(p->>'bpjs_path','') is not null and split_part(p->>'bpjs_path','/',1) <> v_uid) then
    raise exception 'Berkas unggahan tidak valid. Unggah ulang.' using hint = 'ERR_UPLOAD';
  end if;
end $$;

create or replace function jo.jury_insert(p jsonb, p_source text) returns uuid
language plpgsql volatile set search_path = '' as $$
declare v_id uuid;
begin
  insert into jo.jury_applications (source, auth_uid, full_name, phone, email, city, province, disciplines, brevet,
     cert_path, availability, ktp_path, photo_path, bpjs_path, note)
  values (p_source, auth.uid(), trim(p->>'full_name'), regexp_replace(p->>'phone', '[^0-9+]', '', 'g'),
     nullif(lower(trim(coalesce(p->>'email',''))),''), nullif(trim(coalesce(p->>'city','')),''), nullif(trim(coalesce(p->>'province','')),''),
     (select array_agg(x) from jsonb_array_elements_text(p->'disciplines') x),
     coalesce(p->'brevet', '{}'::jsonb), nullif(p->>'cert_path',''),
     coalesce((select array_agg(x::date order by x) from jsonb_array_elements_text(case when jsonb_typeof(p->'availability') = 'array' then p->'availability' else '[]'::jsonb end) x), '{}'),
     nullif(p->>'ktp_path',''), nullif(p->>'photo_path',''), nullif(p->>'bpjs_path',''), nullif(trim(coalesce(p->>'note','')),''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.public_jury_apply(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'jury' and at > now() - interval '1 hour') >= 5 then
    raise exception 'Terlalu banyak pendaftaran dari perangkat ini. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'jury');
  perform jo.jury_validate(p, true);
  if exists (select 1 from jo.jury_applications where status <> 'ditolak'
              and regexp_replace(phone, '[^0-9]', '', 'g') = regexp_replace(p->>'phone', '[^0-9]', '', 'g')) then
    raise exception 'Nomor WhatsApp ini sudah terdaftar sebagai pendaftar juri. Hubungi panitia bila ada perubahan data.' using hint = 'ERR_JURY_DUP';
  end if;
  if not coalesce((p->>'consent')::boolean, false) then
    raise exception 'Centang persetujuan pengolahan data.' using hint = 'ERR_CONSENT';
  end if;
  v_id := jo.jury_insert(p, 'publik');
  perform jo.log(null, 'juri_mendaftar', 'jury', v_id::text, jsonb_build_object('name', p->>'full_name', 'disciplines', p->'disciplines'));
  perform jo.queue_jury_email(v_id, 'juri_diterima');
  return jsonb_build_object('ok', true);
end $$;

create or replace function jo.jury_json(j jo.jury_applications) returns jsonb
language sql stable set search_path = '' as $$
  select to_jsonb(j) - 'auth_uid' || jsonb_build_object(
    'staff_name', (select name from jo.staff where id = j.staff_id),
    'staff_active', (select active from jo.staff where id = j.staff_id),
    'reviewed_by_name', (select name from jo.staff where id = j.reviewed_by))
$$;

create or replace function public.console_jury_list(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  return (select coalesce(jsonb_agg(jo.jury_json(j) order by (j.status <> 'baru'), j.created_at desc), '[]'::jsonb)
    from jo.jury_applications j
    where (st.discipline is null or st.discipline = any(j.disciplines))
      and (nullif(f->>'status','') is null or j.status = f->>'status')
      and (nullif(f->>'discipline','') is null or (f->>'discipline') = any(j.disciplines)));
end $$;

create or replace function public.console_jury_add(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_id uuid; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  perform jo.jury_validate(p, false);
  if st.discipline is not null then
    for d in select jsonb_array_elements_text(p->'disciplines') loop
      if d <> st.discipline then raise exception 'Kode akses Anda hanya untuk disiplin %.', st.discipline; end if;
    end loop;
  end if;
  v_id := jo.jury_insert(p, 'konsol');
  perform jo.log(st.id, 'juri_ditambah', 'jury', v_id::text, jsonb_build_object('name', p->>'full_name'));
  return jo.jury_json((select j from jo.jury_applications j where j.id = v_id));
end $$;

create or replace function public.console_jury_approve(p_id uuid, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; j jo.jury_applications; v_disc text := nullif(p->>'discipline',''); r jsonb;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into j from jo.jury_applications where id = p_id for update;
  if j.id is null then raise exception 'Pendaftar tidak ditemukan.'; end if;
  if j.status = 'disetujui' and j.staff_id is not null then raise exception 'Pendaftar ini sudah disetujui. Buat kode baru dari Kode akses bila perlu.'; end if;
  if st.discipline is not null and coalesce(v_disc, '') <> st.discipline then
    raise exception 'Kode akses Anda hanya untuk disiplin %. Pilih disiplin itu.', st.discipline;
  end if;
  if v_disc is not null and not (v_disc = any(j.disciplines)) then raise exception 'Pendaftar tidak mendaftar untuk disiplin ini.'; end if;
  r := jo.staff_create(st, jsonb_build_object('name', j.full_name, 'role', 'juri', 'discipline', v_disc,
         'apparatus', coalesce(p->'apparatus', '[]'::jsonb), 'components', coalesce(p->'components', '[]'::jsonb),
         'phone', j.phone, 'note', coalesce(nullif(trim(coalesce(p->>'note','')),''), 'Juri dari pendaftaran'),
         'access_windows', p->'access_windows'));
  update jo.jury_applications set status = 'disetujui', staff_id = (r->'staff'->>'id')::uuid, reviewed_by = st.id, reviewed_at = now(),
    review_note = nullif(trim(coalesce(p->>'message','')),'') where id = j.id;
  perform jo.log(st.id, 'juri_disetujui', 'jury', j.id::text, jsonb_build_object('name', j.full_name, 'discipline', v_disc));
  perform jo.queue_jury_email(j.id, 'juri_disetujui');
  return jsonb_build_object('code', r->>'code', 'staff', r->'staff', 'phone', j.phone, 'name', j.full_name);
end $$;

create or replace function public.console_jury_reject(p_id uuid, p_note text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; j jo.jury_applications;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into j from jo.jury_applications where id = p_id for update;
  if j.id is null then raise exception 'Pendaftar tidak ditemukan.'; end if;
  if st.discipline is not null and not (st.discipline = any(j.disciplines)) then raise exception 'Pendaftar ini bukan untuk disiplin Anda.'; end if;
  if j.status = 'disetujui' then raise exception 'Pendaftar sudah disetujui. Nonaktifkan kodenya di Kode akses bila perlu.'; end if;
  update jo.jury_applications set status = 'ditolak', reviewed_by = st.id, reviewed_at = now(), review_note = nullif(trim(coalesce(p_note,'')),'') where id = j.id;
  perform jo.log(st.id, 'juri_ditolak', 'jury', j.id::text, jsonb_build_object('name', j.full_name));
  perform jo.queue_jury_email(j.id, 'juri_ditolak');
  return public.console_jury_list('{}'::jsonb);
end $$;
