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
