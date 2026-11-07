-- =====================================================================
--  Patch 7 Nov 2026: berkas atlet oleh panitia + AIC diterbitkan ulang
--  Isi sama dengan src/67_berkas.sql dan perubahan fungsi di src/30, 40, 50, 56, 66.
-- =====================================================================

-- =====================================================================
--  Berkas atlet oleh panitia (7 Nov 2026)
--  Owner, superadmin, dan admin (disiplinnya) bisa mengganti, menambah,
--  atau menghapus dokumen dan pas foto atlet, dengan alasan wajib.
--  Berkas lama tidak dihapus: tersimpan di riwayat (jo.athlete_file_log).
--  Status dokumen tidak berubah.
--  Bila pas foto (atau ada/tidaknya BPJS) atlet yang sudah lunas berubah,
--  AIC ditandai "Diterbitkan ulang" dan menunggu dikirim ulang. Kode QR
--  (ticket_code) tidak pernah berubah, jadi AIC lama tetap terbaca.
--  Pengiriman ulang manual: per pendaftaran (console_resend_email 'lunas')
--  atau per batch massal (console_bulk_resend_aic, satu email gabungan).
-- =====================================================================

alter table jo.athletes add column if not exists aic_reissued_at timestamptz;
alter table jo.athletes add column if not exists aic_update_pending boolean not null default false;

create table if not exists jo.athlete_file_log (
  id          bigserial primary key,
  athlete_id  uuid not null references jo.athletes(id) on delete cascade,
  slot        text not null check (slot in ('akte','ktp','ijazah','passport','bpjs','photo')),
  action      text not null check (action in ('ganti','tambah','hapus')),
  old_path    text,
  new_path    text,
  reason      text not null,
  staff_id    uuid references jo.staff(id) on delete set null,
  at          timestamptz not null default now()
);
create index if not exists athlete_file_log_athlete on jo.athlete_file_log (athlete_id, at desc);
alter table jo.athlete_file_log enable row level security;

create or replace function jo.file_slot_label(p_slot text) returns text
language sql immutable set search_path = '' as $$
  select case p_slot when 'akte' then 'Akte Kelahiran' when 'ktp' then 'KTP' when 'ijazah' then 'Ijazah'
    when 'passport' then 'Paspor' when 'bpjs' then 'BPJS Ketenagakerjaan' when 'photo' then 'Pas foto' else p_slot end
$$;

-- berkas dan riwayat satu atlet (untuk panel Berkas di konsol)
create or replace function public.console_athlete_files(p_athlete uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into a from jo.athletes where id = p_athlete;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id;
  perform jo.check_discipline(st, s.discipline);
  return jsonb_build_object(
    'id', a.id, 'athlete_no', a.athlete_no, 'full_name', a.full_name, 'nationality', a.nationality,
    'submission_id', s.id, 'submission_code', s.code, 'submission_status', s.status, 'bulk_batch_id', s.bulk_batch_id,
    'has_aic', s.status = 'lunas' and a.ticket_code is not null,
    'aic_reissued_at', a.aic_reissued_at, 'aic_update_pending', a.aic_update_pending,
    'photo_thumb', a.photo_thumb, 'id_doc_path', a.id_doc_path,
    'files', jsonb_build_object('akte', a.akte_path, 'ktp', a.ktp_path, 'ijazah', a.ijazah_path,
                                'passport', a.passport_path, 'bpjs', a.bpjs_path, 'photo', a.photo_path),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'slot', l.slot, 'label', jo.file_slot_label(l.slot),
          'action', l.action, 'old_path', l.old_path, 'new_path', l.new_path, 'reason', l.reason,
          'staff', (select x.name from jo.staff x where x.id = l.staff_id), 'at', l.at) order by l.at desc), '[]'::jsonb)
        from jo.athlete_file_log l where l.athlete_id = a.id));
end $$;

-- ganti / tambah (p_path diisi) atau hapus (p_path null) satu berkas atlet
create or replace function public.console_athlete_file(p_athlete uuid, p_slot text, p_path text, p_thumb text, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.athletes; s jo.submissions; v_col text; v_old text; v_new text := nullif(trim(coalesce(p_path,'')),'');
        v_action text; v_aic boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into a from jo.athletes where id = p_athlete for update;
  if a.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into s from jo.submissions where id = a.submission_id;
  perform jo.check_discipline(st, s.discipline);
  if p_slot not in ('akte','ktp','ijazah','passport','bpjs','photo') then raise exception 'Jenis berkas tidak dikenal.'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan perubahan berkas.'; end if;
  v_col := case p_slot when 'passport' then 'passport_path' else p_slot || '_path' end;
  execute format('select %I from jo.athletes where id = $1', v_col) into v_old using a.id;

  if v_new is null then
    if v_old is null then raise exception 'Berkas ini memang belum ada.'; end if;
    v_action := 'hapus';
  else
    if split_part(v_new, '/', 1) <> auth.uid()::text
       or not exists (select 1 from storage.objects o where o.bucket_id = 'dokumen' and o.name = v_new) then
      raise exception 'Berkas unggahan tidak ditemukan. Unggah ulang.';
    end if;
    if p_slot = 'photo' and (coalesce(p_thumb,'') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(p_thumb) > 150000) then
      raise exception 'Pas foto tidak terbaca. Gunakan berkas JPG atau PNG.';
    end if;
    v_action := case when v_old is null then 'tambah' else 'ganti' end;
  end if;

  execute format('update jo.athletes set %I = $1 where id = $2', v_col) using v_new, a.id;
  if p_slot = 'photo' then
    update jo.athletes set photo_thumb = case when v_new is null then null else p_thumb end where id = a.id;
  end if;

  -- AIC berubah bila pas foto berubah, atau tanda "BPJS belum diunggah" berubah
  v_aic := s.status = 'lunas' and a.ticket_code is not null
           and (p_slot = 'photo' or (p_slot = 'bpjs' and v_action <> 'ganti'));
  if v_aic then
    update jo.athletes set aic_reissued_at = now(), aic_update_pending = true where id = a.id;
  end if;

  insert into jo.athlete_file_log (athlete_id, slot, action, old_path, new_path, reason, staff_id)
  values (a.id, p_slot, v_action, v_old, v_new, trim(p_reason), st.id);
  perform jo.log(st.id, 'berkas_atlet_diubah', 'submission', s.id::text,
    jsonb_build_object('code', s.code, 'athlete', a.full_name, 'athlete_no', a.athlete_no,
                       'file', jo.file_slot_label(p_slot), 'action', v_action, 'reason', trim(p_reason), 'aic', v_aic));
  return public.console_athlete_files(a.id);
end $$;

-- email gabungan untuk satu batch pendaftaran massal: semua tautan AIC batch itu
create or replace function jo.queue_bulk_aic_email(p_batch uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare bt jo.bulk_batches; b jo.bulk_accounts; s jo.submissions; body text; v_upd text; cc text; v_secs text := ''; v_to text;
begin
  select * into bt from jo.bulk_batches where id = p_batch;
  select * into b from jo.bulk_accounts where id = bt.bulk_id;
  v_to := coalesce(b.owner_email, (select contact_email from jo.submissions where bulk_batch_id = bt.id order by code limit 1));
  if v_to is null then raise exception 'Email pemilik pendaftaran massal belum ada.'; end if;
  select string_agg(jo.h(a.full_name) || coalesce(' (' || jo.h(a.athlete_no) || ')', ''), ', ' order by s2.code, a.sort)
    into v_upd from jo.athletes a join jo.submissions s2 on s2.id = a.submission_id
   where s2.bulk_batch_id = bt.id and s2.status = 'lunas' and a.aic_update_pending;
  -- tembusan hanya untuk orang tua/wali atlet yang AIC-nya diperbarui (AIC atlet lain tidak berubah)
  if coalesce(jo.setting_bool('email_guardians'), true) then
    select string_agg(distinct lower(a.guardian_email), ',') into cc
      from jo.athletes a join jo.submissions s2 on s2.id = a.submission_id
     where s2.bulk_batch_id = bt.id and s2.status = 'lunas' and a.aic_update_pending
       and a.guardian_email is not null and lower(a.guardian_email) <> lower(v_to);
  end if;
  for s in select * from jo.submissions where bulk_batch_id = bt.id and status = 'lunas' order by code loop
    v_secs := v_secs || '<h3 style="margin:18px 0 4px;font-size:15px;color:#13284a">' || jo.h(coalesce((select name_id from jo.disciplines where code = s.discipline), s.discipline))
      || ' · ' || jo.h(s.code) || '</h3>' || jo.email_aic_links(s.id, 'id')
      || case when (select count(*) from jo.athletes a where a.submission_id = s.id and a.ticket_code is not null) > 1
           then jo.email_button(jo.aic_link(s.code, s.token, 'all'), 'Unduh semua AIC ' || s.code || ' (1 PDF)') else '' end;
  end loop;
  body := '<p>Halo ' || jo.h(coalesce(b.owner_name, 'Bapak/Ibu')) || ',</p>'
    || case when v_upd is not null then
         '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px"><b>AIC diperbarui</b> untuk: ' || v_upd
         || '.<br>Gunakan AIC terbaru dari tautan di bawah dan hapus versi lama. Kode QR tidak berubah.</p>' else '' end
    || '<p>Berikut Athlete Identification Card (AIC) Jabar Open 2026 untuk batch <b>' || jo.h(bt.code) || '</b> (' || bt.athletes || ' atlet). '
    || 'Tekan tautan di bawah; AIC terunduh otomatis sebagai PDF. AIC ditunjukkan secara digital (dari ponsel, tanpa dicetak) di venue.</p>'
    || v_secs
    || '<p style="font-size:13px;color:#5b6b88">Tautan ini bisa dibuka lagi kapan saja, juga dari portal pendaftaran massal.</p>';
  perform jo.queue_email(null, 'lunas', v_to, cc,
    case when v_upd is not null then 'AIC diperbarui — ' else 'Athlete Identification Card (AIC) — ' end || bt.code,
    jo.email_layout(case when v_upd is not null then 'AIC diperbarui' else 'Athlete Identification Card (AIC)' end, body, 'id'));
  update jo.athletes a set aic_update_pending = false from jo.submissions s2
   where s2.id = a.submission_id and s2.bulk_batch_id = bt.id and a.aic_update_pending;
end $$;

create or replace function public.console_bulk_resend_aic(p_batch uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into bt from jo.bulk_batches where id = p_batch;
  if bt.id is null then raise exception 'Batch tidak ditemukan.'; end if;
  if bt.status <> 'lunas' then raise exception 'AIC hanya bisa dikirim untuk batch yang sudah lunas.'; end if;
  perform jo.queue_bulk_aic_email(bt.id);
  perform jo.log(st.id, 'kirim_ulang_email', 'bulk_batch', bt.id::text, jsonb_build_object('kind', 'aic_batch', 'code', bt.code));
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'aic_dikirim_ulang', jsonb_build_object('code', bt.code));
  return public.console_bulk(bt.bulk_id);
end $$;


create or replace function jo.queue_paid_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text; cc text; v_upd text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  -- 7 Nov 2026: atlet yang berkas AIC-nya diganti panitia sejak email AIC terakhir
  select string_agg(jo.h(a.full_name) || coalesce(' (' || jo.h(a.athlete_no) || ')', ''), ', ' order by a.sort) into v_upd
    from jo.athletes a where a.submission_id = s.id and a.aic_update_pending;
  if coalesce(jo.setting_bool('email_guardians'), true) then
    select string_agg(distinct lower(a.guardian_email), ',') into cc
      from jo.athletes a where a.submission_id = s.id and a.guardian_email is not null
       and lower(a.guardian_email) <> lower(s.contact_email);
  end if;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || case when v_upd is not null then
         '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px"><b>' || jo.tr(l,'AIC diperbarui','AIC updated') || '</b> '
         || jo.tr(l,'untuk: ','for: ') || v_upd || '.<br>'
         || jo.tr(l,'Gunakan AIC terbaru dari tautan di bawah dan hapus versi lama. Kode QR tidak berubah.',
                    'Use the latest AIC from the links below and delete the old version. The QR code is unchanged.') || '</p>' else '' end
    || '<p>' || jo.tr(l,'Pembayaran untuk pendaftaran ','Payment for registration ') || '<b>' || jo.h(s.code) || '</b> '
    || jo.tr(l,'sudah kami verifikasi. Status: <b style="color:#1b8a4b">LUNAS</b>.','has been verified. Status: <b style="color:#1b8a4b">PAID</b>.') || '</p>'
    || jo.email_roster(s.id, l) || coalesce(jo.email_team(s.id, l), '')
    || '<p>' || jo.tr(l,'Athlete Identification Card (AIC) Jabar Open 2026 sudah bisa diunduh. Tekan tautan di bawah; AIC terunduh otomatis sebagai PDF. AIC wajib ditunjukkan secara digital (dari ponsel, tanpa dicetak) di venue. Tidak ada registrasi ulang: cukup datang sesuai jadwal yang diumumkan di Instagram dan situs Jabar Open 2026.',
                      'The Athlete Identification Cards (AIC) Jabar Open 2026 are ready. Tap a link below and the AIC downloads as a PDF. Show it digitally (on a phone, no printing) at the venue. There is no on-site check-in: just come at the schedule announced on Instagram and the Jabar Open 2026 website.') || '</p>'
    || jo.email_aic_links(s.id, l)
    || case when (select count(*) from jo.athletes a where a.submission_id = s.id and a.ticket_code is not null) > 1
         then jo.email_button(jo.aic_link(s.code, s.token, 'all'), jo.tr(l,'Unduh semua AIC (1 PDF)','Download all AICs (1 PDF)'))
         else '' end
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Tautan ini juga bisa dibuka lagi kapan saja. Halaman status: ','You can open these links again at any time. Status page: ')
    || '<a href="' || jo.h(jo.status_link(s.code, s.token)) || '" style="color:#2c4c7b">' || jo.tr(l,'buka','open') || '</a>.</p>';
  perform jo.queue_email(s.id, 'lunas', s.contact_email, cc,
    case when v_upd is not null then jo.tr(l,'AIC diperbarui — ','AIC updated — ')
         else jo.tr(l,'Pembayaran lunas — Athlete Identification Card (AIC) ','Payment confirmed — Athlete Identification Cards (AIC) ') end || s.code,
    jo.email_layout(case when v_upd is not null then jo.tr(l,'AIC diperbarui','AIC updated') else jo.tr(l,'Pembayaran lunas','Payment confirmed') end, body, l));
  update jo.athletes set aic_update_pending = false where submission_id = s.id and aic_update_pending;
end $$;

create or replace function jo.submission_public_json(s jo.submissions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code', s.code, 'status', s.status, 'discipline', s.discipline,
    'discipline_name_id', d.name_id, 'discipline_name_en', d.name_en,
    'registrant_type', s.registrant_type,
    'contact', jsonb_build_object('name', s.contact_name, 'email', s.contact_email, 'phone', s.contact_phone, 'role', s.contact_role),
    'club', case when c.id is null then null else jsonb_build_object('name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) end,
    'payment_method', s.payment_method,
    'base_amount', s.base_amount, 'priangan_amount', s.priangan_amount,
    'unique_code', s.unique_code, 'total_amount', s.total_amount,
    'proof_uploaded_at', s.proof_uploaded_at, 'paid_at', s.paid_at,
    'verify_note', case when s.status = 'perlu_perbaikan' then s.verify_note end,
    'created_at', s.created_at,
    'expires_at', case when s.payment_method = 'qris' and s.status = 'menunggu_pembayaran' and s.proof_path is null
                       then s.created_at + interval '15 minutes' end,
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note'),
      'deadline_label', jo.setting_text('payment_deadline_label')),
    'signatories', jo.setting('signatories'),
    'apparatus_names', (select jsonb_object_agg(x->>'code', jsonb_build_object('id', x->>'id', 'en', x->>'en')) from jsonb_array_elements(d.apparatus) x),
    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'athlete_no', a.athlete_no, 'full_name', a.full_name, 'gender', a.gender,
        'birth_date', a.birth_date, 'nationality', a.nationality, 'province', a.province, 'kab_kota', a.kab_kota,
        'doc_status', a.doc_status, 'has_bpjs', a.bpjs_path is not null, 'photo_thumb', a.photo_thumb,
        'aic_reissued_at', a.aic_reissued_at,
        'docs', jsonb_build_object('akte', a.akte_path is not null, 'ktp', a.ktp_path is not null, 'ijazah', a.ijazah_path is not null,
                                   'passport', a.passport_path is not null, 'bpjs', a.bpjs_path is not null),
        'ticket_code', case when s.status = 'lunas' then a.ticket_code end
      ) order by a.sort), '[]'::jsonb) from jo.athletes a where a.submission_id = s.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', en.id, 'category_id', cat.id, 'category_name_id', cat.name_id, 'category_name_en', cat.name_en,
        'level', cat.level, 'age_label', cat.age_label, 'apparatus', cat.apparatus,
        'fee', en.fee, 'priangan_requested', en.priangan_requested, 'priangan_status', en.priangan_status,
        'status', en.status, 'team_only', en.team_only,
        'music', en.music, 'music_status', en.music_status, 'music_note', en.music_note,
        'music_changes', en.music_changes, 'startlist_published', cat.startlist_published, 'jabar_only', cat.jabar_only,
        'athlete_ids', (select jsonb_agg(ea.athlete_id) from jo.entry_athletes ea where ea.entry_id = en.id),
        'start', case when cat.startlist_published and s.status = 'lunas' then jsonb_build_object(
            'session', ses.name, 'day', ses.day, 'start_time', ses.start_time,
            'group_no', en.group_no, 'start_order', en.start_order) end,
        'result', case when cat.results_published and s.status = 'lunas' then (
            select r from jsonb_array_elements(jo.category_results(cat.id)) r
             where r->>'entry_id' = en.id::text limit 1) end,
        'certificates', case when cat.results_published and s.status = 'lunas' then (
            select jsonb_agg(jsonb_build_object('athlete_id', ea.athlete_id, 'cert_code', ea.cert_code))
              from jo.entry_athletes ea where ea.entry_id = en.id) end
      ) order by cat.sort), '[]'::jsonb)
      from jo.entries en join jo.categories cat on cat.id = en.category_id
      left join jo.sessions ses on ses.id = en.session_id
      where en.submission_id = s.id and en.status <> 'dibatalkan'),
    'team_amount', s.team_amount,
    'teams', (select coalesce(jsonb_agg(jsonb_build_object(
        'name', t.name, 'level', t.level,
        'published', coalesce(tl.published, false) and s.status = 'lunas',
        'members', (select coalesce(jsonb_agg(jsonb_build_object(
            'athlete_id', m.athlete_id, 'name', a.full_name, 'athlete_no', a.athlete_no, 'team_only', m.team_only,
            'category_name_id', c2.name_id, 'category_name_en', c2.name_en,
            'cert_code', case when coalesce(tl.published, false) and s.status = 'lunas' then m.cert_code end) order by m.sort), '[]'::jsonb)
          from jo.team_members m join jo.athletes a on a.id = m.athlete_id
          join jo.entries e2 on e2.id = m.entry_id join jo.categories c2 on c2.id = e2.category_id
          where m.team_id = t.id),
        'result', case when coalesce(tl.published, false) and s.status = 'lunas' then (
            select r from jsonb_array_elements(jo.team_results(t.discipline, t.level, false)) r
             where r->>'team_id' = t.id::text limit 1) end) order by t.level, t.name), '[]'::jsonb)
      from jo.teams t left join jo.team_levels tl on tl.discipline = t.discipline and tl.level = t.level
      where t.submission_id = s.id)
  )
  from jo.disciplines d left join jo.clubs c on c.id = s.club_id
  where d.code = s.discipline
$$;

create or replace function jo.purge_submission(p_id uuid) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_files jsonb;
begin
  select coalesce(jsonb_agg(distinct f), '[]'::jsonb) into v_files from (
    select jsonb_build_object('bucket', 'bukti', 'path', s.proof_path) f from jo.submissions s where s.id = p_id and s.proof_path is not null
    union all
    select jsonb_build_object('bucket', 'dokumen', 'path', x) from jo.athletes a
      cross join lateral unnest(array[a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path]) x
     where a.submission_id = p_id and x is not null
    union all
    select jsonb_build_object('bucket', 'dokumen', 'path', x) from jo.athlete_file_log l join jo.athletes a on a.id = l.athlete_id
      cross join lateral unnest(array[l.old_path, l.new_path]) x
     where a.submission_id = p_id and x is not null
  ) z;
  delete from jo.score_log where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.scores where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.music_log where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.team_members where team_id in (select id from jo.teams where submission_id = p_id)
     or entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.teams where submission_id = p_id;
  delete from jo.entry_athletes where entry_id in (select id from jo.entries where submission_id = p_id);
  delete from jo.entries where submission_id = p_id;
  delete from jo.athletes where submission_id = p_id;
  update jo.mutations set submission_id = null, match_status = 'belum' where submission_id = p_id;
  delete from jo.submissions where id = p_id;
  return v_files;
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
    from (select unnest(array[a.id_doc_path, a.akte_path, a.ktp_path, a.ijazah_path, a.passport_path, a.bpjs_path, a.photo_path]) x
          union all select unnest(array[l.old_path, l.new_path]) from jo.athlete_file_log l where l.athlete_id = a.id) y where x is not null;
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
      and not exists (select 1 from jo.athlete_file_log l where o.name in (l.old_path, l.new_path))
      and not exists (select 1 from jo.issues i where i.shot_path = o.name)
      and not exists (select 1 from jo.bulk_rows r cross join lateral jsonb_each(coalesce(r.data->'docs','{}'::jsonb)) dd where dd.value->>'path' = o.name)
      and not exists (select 1 from jo.bulk_payments bp where bp.proof_path = o.name));
end $$;

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
      a.bpjs_path is not null as has_bpjs, a.aic_update_pending, a.aic_reissued_at
    from jo.athletes a join jo.submissions s on s.id = a.submission_id
    left join jo.clubs c on c.id = s.club_id
    where (d is null or s.discipline = d)
      and (coalesce(f->>'include_cancelled','false') = 'true' or s.status <> 'dibatalkan')
      and (nullif(f->>'status','') is null or s.status = f->>'status')
      and (coalesce(f->>'q','') = '' or lower(a.full_name) like q or lower(coalesce(a.athlete_no,'')) like q
           or lower(coalesce(c.name,'')) like q or lower(coalesce(a.kab_kota,'')) like q)
  ) x);
end $$;

create or replace function jo.bulk_batches_json(p_bulk uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', bt.id, 'no', bt.no, 'code', bt.code, 'person', bt.person, 'athletes', bt.athletes, 'total', bt.total,
      'split', bt.split, 'due_at', bt.due_at, 'status', bt.status, 'paid_at', bt.paid_at, 'created_at', bt.created_at,
      'overdue', bt.status = 'menunggu' and now() > bt.due_at,
      'aic_pending', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.bulk_batch_id = bt.id and a.aic_update_pending),
      'paid_verified', (select coalesce(sum(amount),0) from jo.bulk_payments p where p.batch_id = bt.id and p.status = 'cocok'),
      'paid_pending', (select coalesce(sum(amount),0) from jo.bulk_payments p where p.batch_id = bt.id and p.status = 'menunggu'),
      'payments', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'amount', p.amount, 'transfer_date', p.transfer_date,
            'person', p.person, 'uploaded_at', p.uploaded_at, 'status', p.status, 'note', p.note, 'proof_path', p.proof_path) order by p.id), '[]'::jsonb)
          from jo.bulk_payments p where p.batch_id = bt.id),
      'submissions', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'token', s.token, 'discipline', s.discipline,
            'status', s.status, 'total', s.total_amount,
            'athletes', (select count(*) from jo.athletes a where a.submission_id = s.id)) order by s.code), '[]'::jsonb)
          from jo.submissions s where s.bulk_batch_id = bt.id)
    ) order by bt.no), '[]'::jsonb)
  from jo.bulk_batches bt where bt.bulk_id = p_bulk
$$;

do $$ declare f text; begin
  foreach f in array array['public.console_athlete_files(uuid)','public.console_athlete_file(uuid,text,text,text,text)','public.console_bulk_resend_aic(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  execute 'revoke all on function jo.queue_bulk_aic_email(uuid) from public';
  execute 'revoke all on function jo.file_slot_label(text) from public';
  execute 'revoke all on table jo.athlete_file_log from anon, authenticated';
  execute 'revoke all on sequence jo.athlete_file_log_id_seq from anon, authenticated';
end $$;
notify pgrst, 'reload schema';
