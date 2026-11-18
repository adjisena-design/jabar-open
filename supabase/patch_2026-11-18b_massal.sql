-- 18 Nov 2026 (b): revisi pendaftaran massal — berkas menyusul, kuota klub boleh dilampaui, kendali penuh di konsol; cek kelayakan khusus panitia. Sudah diterapkan.
-- =====================================================================
--  PENDAFTARAN MASSAL — REVISI 18 NOVEMBER 2026
--  1. Batch boleh dikirim dan dibayar walau berkas atlet belum lengkap;
--     atletnya ditandai "berkas belum lengkap" dan klub mengunggah susulan
--     lewat portal selama kode berlaku atau selama perpanjangan berkas dari panitia
--     (paling lambat sebelum kejuaraan dimulai).
--  2. Batas peserta per klub per kategori (arahan TD) tidak menghalangi
--     pendaftaran massal; kelebihannya ditandai di konsol.
--  3. Kendali penuh pendaftaran massal di konsol (owner & superadmin).
-- =====================================================================

alter table jo.bulk_accounts add column if not exists files_until timestamptz;      -- perpanjangan unggah berkas (terpisah dari masa pengisian)
alter table jo.bulk_accounts add column if not exists files_by uuid references jo.staff(id);
alter table jo.bulk_accounts add column if not exists settings jsonb not null default '{}'::jsonb;  -- {min, max, pay_hours} khusus kode ini

-- Pengelola pendaftaran massal untuk kendali konsol: owner & superadmin (termasuk Inda)
create or replace function jo.bulk_admin() returns jo.staff
language plpgsql stable set search_path = '' as $$
begin
  return jo.require_staff(array['owner','superadmin']);
end $$;

-- Hari pertama kejuaraan, pukul 00.00 WIB: batas akhir unggah berkas susulan
create or replace function jo.bulk_event_start() returns timestamptz
language sql stable set search_path = '' as $$
  select coalesce((select (min(date_start)::timestamp) at time zone 'Asia/Jakarta' from jo.disciplines),
                  timestamptz '2026-12-12 00:00+07')
$$;

-- Pengaturan per kode (min. atlet batch pertama, maks. baris, batas bayar dalam jam)
create or replace function jo.bulk_cfg_int(b jo.bulk_accounts, k text) returns integer
language sql stable set search_path = '' as $$
  select coalesce(nullif(b.settings->>k, '')::integer,
    case k when 'min' then coalesce(jo.setting_int('bulk_min'), 30)
           when 'max' then coalesce(jo.setting_int('bulk_max'), 250)
           when 'pay_hours' then 48 end)
$$;

-- Unggah berkas untuk baris yang sudah dikirim: selama kode berlaku, atau selama perpanjangan berkas
create or replace function jo.bulk_files_open(b jo.bulk_accounts) returns boolean
language sql stable set search_path = '' as $$
  select b.status = 'aktif' and now() < jo.bulk_event_start()
     and ((b.expires_at is not null and now() <= b.expires_at and now() <= jo.bulk_deadline())
          or (b.files_until is not null and now() <= b.files_until))
$$;

create or replace function jo.bulk_files_until(b jo.bulk_accounts) returns timestamptz
language sql stable set search_path = '' as $$
  select case when jo.bulk_files_open(b) then
    least(jo.bulk_event_start(), greatest(case when now() <= jo.bulk_deadline() then least(b.expires_at, jo.bulk_deadline()) end, b.files_until)) end
$$;

-- Berkas wajib yang belum ada (mengikuti Konsol → Aturan pendaftaran)
create or replace function jo.athlete_docs_missing(a jo.athletes) returns text[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(v.lbl order by v.ord), '{}') from (values
      (1, 'akte', 'Akte Kelahiran', a.akte_path), (2, 'passport', 'Paspor', a.passport_path), (3, 'ktp', 'KTP', a.ktp_path),
      (4, 'ijazah', 'Ijazah', a.ijazah_path), (5, 'bpjs', 'BPJS Ketenagakerjaan', a.bpjs_path), (6, 'photo', 'Pas foto', a.photo_path)) v(ord, k, lbl, p)
   where jo.rules()->'docs'->(case when a.nationality = 'WNA' then 'WNA' else 'WNI' end)->>v.k = 'wajib'
     and coalesce(v.p, '') = ''
$$;

-- Kategori yang pesertanya dari satu klub melebihi batas per klub (arahan TD)
create or replace function jo.club_over_quota(p_club uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('category_id', x.id, 'category', x.name_id, 'n', x.n, 'max', x.max_per_club) order by x.sort), '[]'::jsonb)
  from (select c.id, c.name_id, c.sort, c.max_per_club, count(*) n
          from jo.entries e join jo.submissions s on s.id = e.submission_id join jo.categories c on c.id = e.category_id
         where s.club_id = p_club and p_club is not null and e.status = 'aktif' and s.status <> 'dibatalkan' and c.max_per_club is not null
         group by c.id having count(*) > c.max_per_club) x
$$;

-- Data baris untuk ditampilkan: baris terkirim memakai berkas terbaru dari data atlet
-- (berkas bisa diganti panitia di halaman pendaftaran).
create or replace function jo.bulk_row_data(r jo.bulk_rows) returns jsonb
language plpgsql stable set search_path = '' as $$
declare a jo.athletes; v jsonb := '{}'::jsonb; k text; p text;
begin
  if r.batch_id is null then return r.data; end if;
  select * into a from jo.athletes where bulk_row_id = r.id limit 1;
  if a.id is null then return r.data; end if;
  foreach k in array array['akte','ktp','ijazah','passport','bpjs','photo'] loop
    p := case k when 'akte' then a.akte_path when 'ktp' then a.ktp_path when 'ijazah' then a.ijazah_path
                when 'passport' then a.passport_path when 'bpjs' then a.bpjs_path else a.photo_path end;
    if coalesce(p, '') <> '' then
      v := v || jsonb_build_object(k, jsonb_build_object('path', p,
        'name', coalesce(case when r.data->'docs'->k->>'path' = p then r.data->'docs'->k->>'name' end, 'Terunggah')));
    end if;
  end loop;
  return r.data || jsonb_build_object('docs', v, 'athlete_id', a.id, 'athlete_no', a.athlete_no,
    'docs_missing', to_jsonb(jo.athlete_docs_missing(a)));
end $$;

create or replace function jo.bulk_row_has_photo(r jo.bulk_rows) returns boolean
language sql stable set search_path = '' as $$
  select r.photo_thumb is not null or exists (select 1 from jo.athletes a where a.bulk_row_id = r.id and a.photo_thumb is not null)
$$;

-- Terapkan berkas ke baris terkirim dan ke data atletnya. p_docs: {jenis: {path, name}}
create or replace function jo.bulk_apply_files(b jo.bulk_accounts, r jo.bulk_rows, p_docs jsonb, p_thumb text, p_who text, p_staff uuid, p_uid uuid)
returns integer language plpgsql volatile set search_path = '' as $$
declare k text; v_path text; a jo.athletes; s jo.submissions; v_col text; v_old text; v_n integer := 0; v_data jsonb := r.data;
begin
  perform jo.bulk_link_rows(r.batch_id);
  select * into a from jo.athletes where bulk_row_id = r.id for update;
  for k in select jsonb_object_keys(coalesce(p_docs, '{}'::jsonb)) loop
    if k not in ('akte','ktp','ijazah','passport','bpjs','photo') then
      raise exception 'Baris %: jenis dokumen tidak dikenal.', r.row_no using hint = 'ERR_BULK_DATA';
    end if;
    v_path := nullif(trim(coalesce(p_docs->k->>'path', '')), '');
    if v_path is null then continue; end if;   -- berkas susulan hanya menambah atau mengganti
    if p_uid is not null and split_part(v_path, '/', 1) <> p_uid::text then
      raise exception 'Baris %: berkas unggahan tidak valid. Unggah ulang.', r.row_no using hint = 'ERR_UPLOAD';
    end if;
    if k = 'photo' and (coalesce(p_thumb, '') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(p_thumb) > 150000) then
      raise exception 'Baris %: pas foto tidak terbaca. Unggah ulang (JPG atau PNG).', r.row_no using hint = 'ERR_ATHLETE_PHOTO';
    end if;
    v_data := jsonb_set(v_data, '{docs}', coalesce(v_data->'docs', '{}'::jsonb) || jsonb_build_object(k, jsonb_build_object('path', v_path, 'name', coalesce(p_docs->k->>'name', 'Berkas'))));
    if a.id is not null then
      v_col := k || '_path';
      execute format('select %I from jo.athletes where id = $1', v_col) into v_old using a.id;
      if v_old is distinct from v_path then
        execute format('update jo.athletes set %I = $1 where id = $2', v_col) using v_path, a.id;
        if k = 'photo' then update jo.athletes set photo_thumb = p_thumb where id = a.id; end if;
        insert into jo.athlete_file_log (athlete_id, slot, action, old_path, new_path, reason, staff_id)
        values (a.id, k, case when v_old is null then 'tambah' else 'ganti' end, v_old, v_path,
                'Berkas susulan pendaftaran massal (' || coalesce(p_who, 'klub') || ')', p_staff);
        v_n := v_n + 1;
      end if;
    else
      v_n := v_n + 1;
    end if;
  end loop;
  if v_n = 0 then return 0; end if;
  update jo.bulk_rows set data = v_data, photo_thumb = case when p_docs ? 'photo' and nullif(p_docs->'photo'->>'path', '') is not null then p_thumb else photo_thumb end,
         updated_at = now(), updated_by = p_who where id = r.id;
  if a.id is not null then
    select * into s from jo.submissions where id = a.submission_id;
    update jo.athletes set id_doc_path = coalesce(akte_path, passport_path),
           doc_status = case when doc_status = 'valid' then 'menunggu' else doc_status end,
           aic_update_pending = aic_update_pending or (s.status = 'lunas' and ticket_code is not null),
           aic_reissued_at = case when s.status = 'lunas' and ticket_code is not null then now() else aic_reissued_at end
     where id = a.id;
  end if;
  return v_n;
end $$;

-- Portal: unggah berkas susulan untuk baris yang sudah dikirim. p_rows: [{row_no, docs:{jenis:{path,name}}, photo_thumb?}]
create or replace function public.public_bulk_files(p_code text, p_person text, p_rows jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_name text; x jsonb; r jo.bulk_rows; v_n integer := 0; v_rows jsonb := '[]'::jsonb;
begin
  b := jo.bulk_auth(p_code, p_person, false);
  v_name := jo.bulk_person_name(b, p_person);
  if not jo.bulk_files_open(b) then
    raise exception 'Masa unggah berkas sudah berakhir. Hubungi Inda untuk perpanjangan berkas.' using hint = 'ERR_BULK_FILES_CLOSED';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 260 then
    raise exception 'Data tidak valid.' using hint = 'ERR_BULK_DATA';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    select * into r from jo.bulk_rows where bulk_id = b.id and row_no = (x->>'row_no')::integer for update;
    if r.id is null or r.batch_id is null then
      raise exception 'Baris % belum dikirim; simpan lewat lembar biasa.', x->>'row_no' using hint = 'ERR_BULK_ROWS';
    end if;
    if jo.bulk_apply_files(b, r, x->'docs', x->>'photo_thumb', v_name, null, auth.uid()) > 0 then
      v_n := v_n + 1; v_rows := v_rows || to_jsonb(r.row_no);
    end if;
  end loop;
  if v_n > 0 then
    perform jo.bulk_add_log(b.id, v_name, 'berkas_susulan', jsonb_build_object('rows', v_rows));
    update jo.bulk_accounts set updated_at = now() where id = b.id;
  end if;
  return jsonb_build_object('ok', true, 'saved', v_rows, 'at', now(), 'by', v_name);
end $$;

-- =====================================================================
--  Konsol: kendali penuh
-- =====================================================================

-- (a, e) Ubah / tambah baris draf, atau ganti berkas baris terkirim, atas nama klub.
-- p: {row_no, data, photo_thumb?}. Baris terkirim: hanya berkas (data atletnya diubah di halaman Pendaftaran).
create or replace function public.console_bulk_row_save(p_id uuid, p jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; r jo.bulk_rows; v_no integer := (p->>'row_no')::integer; v_thumb text; k text; v_who text;
begin
  st := jo.bulk_admin();
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Tulis alasan (masuk riwayat).'; end if;
  if v_no is null or v_no < 1 or v_no > 250 then raise exception 'Nomor baris harus 1 sampai 250.'; end if;
  v_who := st.name || ' (panitia)';
  select * into r from jo.bulk_rows where bulk_id = b.id and row_no = v_no for update;
  if r.batch_id is not null then
    if jo.bulk_apply_files(b, r, p->'data'->'docs', p->>'photo_thumb', v_who, st.id, null) = 0 then
      raise exception 'Tidak ada berkas baru. Data atlet yang sudah dikirim diubah di halaman Pendaftaran.';
    end if;
  else
    if jsonb_typeof(p->'data') <> 'object' or length((p->'data')::text) > 12000 then raise exception 'Data baris tidak valid.'; end if;
    for k in select jsonb_object_keys(coalesce(p->'data'->'docs', '{}'::jsonb)) loop
      if k not in ('akte','ktp','ijazah','passport','bpjs','photo') then raise exception 'Jenis dokumen tidak dikenal.'; end if;
    end loop;
    v_thumb := case when p ? 'photo_thumb' then nullif(p->>'photo_thumb', '') else r.photo_thumb end;
    if v_thumb is not null and (v_thumb !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(v_thumb) > 150000) then
      raise exception 'Pas foto tidak terbaca. Unggah ulang (JPG atau PNG).';
    end if;
    if r.id is null then
      if (select count(*) from jo.bulk_rows where bulk_id = b.id) >= jo.bulk_cfg_int(b, 'max') then
        raise exception 'Lembar sudah mencapai batas % baris. Naikkan batas di pengaturan kode ini.', jo.bulk_cfg_int(b, 'max');
      end if;
      insert into jo.bulk_rows (bulk_id, row_no, data, photo_thumb, updated_by) values (b.id, v_no, p->'data', v_thumb, v_who);
    else
      update jo.bulk_rows set data = p->'data', photo_thumb = v_thumb, updated_at = now(), updated_by = v_who where id = r.id;
    end if;
  end if;
  perform jo.bulk_add_log(b.id, st.name, case when r.batch_id is not null then 'berkas_diubah_panitia' when r.id is null then 'baris_ditambah_panitia' else 'baris_diubah_panitia' end,
    jsonb_build_object('row_no', v_no, 'name', p->'data'->>'full_name', 'note', trim(p_reason)));
  perform jo.log(st.id, 'massal_baris_diubah', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label, 'row_no', v_no, 'reason', trim(p_reason)));
  update jo.bulk_accounts set updated_at = now() where id = b.id;
  return public.console_bulk(b.id);
end $$;

-- (b) Buka kembali baris terkirim: atlet dikeluarkan dari pendaftaran batch (seperti Tarik),
-- barisnya kembali ke lembar sebagai draf agar klub bisa memperbaiki lalu mengirim ulang.
create or replace function public.console_bulk_unlock_row(p_id uuid, p_row integer, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v_res jsonb; v_snap jsonb; v_no integer;
begin
  st := jo.bulk_admin();
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Tulis alasan (masuk riwayat).'; end if;
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if not exists (select 1 from jo.bulk_rows where bulk_id = b.id and row_no = p_row and batch_id is not null) then
    raise exception 'Baris % bukan baris terkirim.', p_row;
  end if;
  v_res := jo.bulk_withdraw(b, p_row, st.name, st.id, 'Dibuka kembali untuk diperbaiki: ' || trim(p_reason));
  select snap->'row' into v_snap from jo.bulk_actions where id = (v_res->>'action')::bigint;
  v_no := jo.bulk_put_row(v_snap, null);
  update jo.bulk_rows set updated_by = st.name || ' (panitia, dibuka kembali)' where bulk_id = b.id and row_no = v_no;
  update jo.bulk_actions set reason = 'Dibuka kembali sebagai draf: ' || trim(p_reason) where id = (v_res->>'action')::bigint;
  perform jo.bulk_add_log(b.id, st.name, 'baris_dibuka_kembali', jsonb_build_object('row_no', v_no, 'name', v_snap->'data'->>'full_name',
    'amount', v_res->'amount', 'refund', v_res->'refund', 'note', trim(p_reason)));
  perform jo.log(st.id, 'massal_baris_dibuka', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'row_no', v_no, 'reason', trim(p_reason)));
  return public.console_bulk(b.id) || jsonb_build_object('unlocked_row', v_no, 'refund', v_res->'refund');
end $$;

-- (c) Masa pengisian: atur tanggal berakhir bebas (berulang kali), maksimal batas pendaftaran
create or replace function public.console_bulk_set_expiry(p_id uuid, p_until timestamptz) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.bulk_admin();
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if p_until is null or p_until <= now() then raise exception 'Pilih waktu setelah sekarang.'; end if;
  if p_until > jo.bulk_deadline() then
    raise exception 'Masa pengisian tidak boleh melewati batas pendaftaran (%). Untuk berkas susulan, pakai Perpanjangan berkas.',
      to_char(jo.bulk_deadline() at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB';
  end if;
  update jo.bulk_accounts set expires_at = p_until, opened_at = coalesce(opened_at, now()),
         extended_days = coalesce(extended_days, 0) + 1, extended_by = st.id, extended_at = now(), reminded_at = null, updated_at = now()
   where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, st.name, 'masa_pengisian_diatur', jsonb_build_object('expires_at', p_until));
  perform jo.log(st.id, 'massal_diperpanjang', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label, 'until', p_until));
  return jo.bulk_console_row(b);
end $$;

-- Perpanjangan berkas: unggah berkas susulan untuk baris terkirim sampai p_until (null = tutup). Maks. sebelum kejuaraan dimulai.
create or replace function public.console_bulk_files(p_id uuid, p_until timestamptz) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.bulk_admin();
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if p_until is not null and p_until <= now() then raise exception 'Pilih waktu setelah sekarang.'; end if;
  if p_until is not null and p_until > jo.bulk_event_start() then
    raise exception 'Perpanjangan berkas paling lambat sebelum kejuaraan dimulai (%).',
      to_char(jo.bulk_event_start() at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB';
  end if;
  update jo.bulk_accounts set files_until = p_until, files_by = st.id, updated_at = now() where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, st.name, case when p_until is null then 'perpanjangan_berkas_ditutup' else 'perpanjangan_berkas' end,
    jsonb_build_object('until', p_until));
  perform jo.log(st.id, 'massal_perpanjangan_berkas', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label, 'until', p_until));
  return jo.bulk_console_row(b);
end $$;

-- (d) Pemilik dan kolaborator
create or replace function public.console_bulk_people(p_id uuid, p jsonb, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v_col jsonb := '[]'::jsonb; x jsonb; i integer := 0; v_role text;
begin
  st := jo.bulk_admin();
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Tulis alasan (masuk riwayat).'; end if;
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if length(trim(coalesce(p->>'name',''))) < 3 then raise exception 'Isi nama pemilik.'; end if;
  if length(regexp_replace(coalesce(p->>'phone',''), '[^0-9]', '', 'g')) < 9 then raise exception 'Isi nomor WhatsApp pemilik.'; end if;
  if lower(trim(coalesce(p->>'email',''))) !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Email pemilik belum valid.'; end if;
  v_role := lower(trim(coalesce(p->>'role', b.owner_role, 'lainnya')));
  if v_role not in ('pemilik','admin','pelatih','manajer','lainnya') then v_role := 'lainnya'; end if;
  for x in select * from jsonb_array_elements(coalesce(p->'collaborators','[]'::jsonb)) loop
    if length(trim(coalesce(x->>'name',''))) = 0 then continue; end if;
    i := i + 1;
    if i > 2 then raise exception 'Maksimal 2 kolaborator.'; end if;
    if length(trim(x->>'name')) < 3 then raise exception 'Kolaborator %: isi nama lengkap.', i; end if;
    if length(regexp_replace(coalesce(x->>'phone',''), '[^0-9]', '', 'g')) < 9 then raise exception 'Kolaborator %: isi nomor WhatsApp.', i; end if;
    v_col := v_col || jsonb_build_object('id', coalesce(nullif(x->>'id',''), 'k' || i), 'name', jo.name_case(x->>'name'), 'phone', trim(x->>'phone'));
  end loop;
  update jo.bulk_accounts set owner_name = jo.name_case(p->>'name'), owner_phone = trim(p->>'phone'), owner_email = lower(trim(p->>'email')),
         owner_role = v_role, collaborators = v_col, updated_at = now()
   where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, st.name, 'pengisi_diubah_panitia', jsonb_build_object('owner', b.owner_name,
    'collaborators', (select coalesce(jsonb_agg(c->>'name'), '[]'::jsonb) from jsonb_array_elements(v_col) c), 'note', trim(p_reason)));
  perform jo.log(st.id, 'massal_pengisi_diubah', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'owner', b.owner_name, 'reason', trim(p_reason)));
  return jo.bulk_console_row(b);
end $$;

-- (f) Batas bayar batch: tanggal bebas
create or replace function public.console_bulk_due_at(p_batch uuid, p_until timestamptz) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches;
begin
  st := jo.bulk_admin();
  if p_until is null or p_until <= now() then raise exception 'Pilih waktu setelah sekarang.'; end if;
  update jo.bulk_batches set due_at = p_until where id = p_batch and status = 'menunggu' returning * into bt;
  if bt.id is null then raise exception 'Batch tidak ditemukan atau sudah selesai.'; end if;
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'batas_bayar_diatur', jsonb_build_object('code', bt.code, 'due_at', bt.due_at));
  perform jo.log(st.id, 'massal_batas_bayar', 'bulk', bt.bulk_id::text, jsonb_build_object('code', bt.code, 'due_at', bt.due_at));
  return public.console_bulk(bt.bulk_id);
end $$;

-- (g) Pengaturan khusus kode: {min, max, pay_hours}; nilai kosong = ikut pengaturan umum
create or replace function public.console_bulk_settings(p_id uuid, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v jsonb := '{}'::jsonb; n integer;
begin
  st := jo.bulk_admin();
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  n := nullif(p->>'min', '')::integer;
  if n is not null then if n < 1 or n > 250 then raise exception 'Minimal atlet batch pertama 1 sampai 250.'; end if; v := v || jsonb_build_object('min', n); end if;
  n := nullif(p->>'max', '')::integer;
  if n is not null then
    if n < 1 or n > 250 then raise exception 'Maksimal baris 1 sampai 250.'; end if;
    if n < (select coalesce(max(row_no), 0) from jo.bulk_rows where bulk_id = b.id) then
      raise exception 'Lembar sudah memakai baris sampai %. Batas tidak boleh lebih kecil.', (select max(row_no) from jo.bulk_rows where bulk_id = b.id);
    end if;
    v := v || jsonb_build_object('max', n);
  end if;
  n := nullif(p->>'pay_hours', '')::integer;
  if n is not null then if n < 1 or n > 336 then raise exception 'Batas bayar 1 sampai 336 jam.'; end if; v := v || jsonb_build_object('pay_hours', n); end if;
  if coalesce((v->>'min')::integer, 0) > coalesce((v->>'max')::integer, 250) then raise exception 'Minimal tidak boleh lebih besar dari maksimal.'; end if;
  update jo.bulk_accounts set settings = v, updated_at = now() where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, st.name, 'pengaturan_kode', v);
  perform jo.log(st.id, 'massal_pengaturan', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'settings', v));
  return jo.bulk_console_row(b);
end $$;

-- (h) Tandai batch lunas tanpa bukti transfer (mis. dibayar tunai / transfer dicek langsung)
create or replace function public.console_bulk_mark_paid(p_batch uuid, p_note text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches; s jo.submissions; v_note text := trim(coalesce(p_note, ''));
begin
  st := jo.bulk_admin();
  if length(v_note) < 5 then raise exception 'Tulis keterangan pembayaran (mis. tunai ke Inda 20 Nov, dicek di mutasi BCA).'; end if;
  select * into bt from jo.bulk_batches where id = p_batch for update;
  if bt.id is null then raise exception 'Batch tidak ditemukan.'; end if;
  if bt.status <> 'menunggu' then raise exception 'Batch ini sudah %.', bt.status; end if;
  update jo.bulk_batches set status = 'lunas', paid_at = now(), verified_by = st.id where id = bt.id;
  for s in select * from jo.submissions where bulk_batch_id = bt.id and status <> 'dibatalkan' loop
    update jo.submissions set status = 'lunas', paid_amount = s.total_amount, paid_at = now(), verified_by = st.id, verified_at = now(),
      verify_note = 'Pendaftaran massal ' || bt.code || ' (ditandai lunas manual: ' || v_note || ')'
     where id = s.id;
    perform jo.log(st.id, 'pembayaran_lunas', 'submission', s.id::text,
      jsonb_build_object('code', s.code, 'amount', s.total_amount, 'note', 'Pendaftaran massal ' || bt.code || ', manual: ' || v_note, 'mutation_match', false));
    perform jo.queue_paid_email(s.id);
  end loop;
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'batch_lunas_manual', jsonb_build_object('code', bt.code, 'total', bt.total, 'note', v_note));
  perform jo.log(st.id, 'massal_lunas_manual', 'bulk', bt.bulk_id::text, jsonb_build_object('code', bt.code, 'total', bt.total, 'note', v_note));
  return public.console_bulk(bt.bulk_id);
end $$;

-- Atlet di baris pendaftaran massal ikut menyegarkan lembar klub bila berkasnya diubah panitia
create or replace function jo.athlete_touch_bulk_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.bulk_row_id is not null and (new.akte_path, new.ktp_path, new.ijazah_path, new.passport_path, new.bpjs_path, new.photo_path)
       is distinct from (old.akte_path, old.ktp_path, old.ijazah_path, old.passport_path, old.bpjs_path, old.photo_path) then
    update jo.bulk_rows set updated_at = now() where id = new.bulk_row_id;
  end if;
  return new;
end $$;
drop trigger if exists athlete_touch_bulk_row on jo.athletes;
create trigger athlete_touch_bulk_row after update on jo.athletes for each row execute function jo.athlete_touch_bulk_row();

revoke all on function public.public_bulk_files(text, text, jsonb) from public;
grant execute on function public.public_bulk_files(text, text, jsonb) to anon, authenticated;
revoke all on function public.console_bulk_row_save(uuid, jsonb, text) from public, anon;
grant execute on function public.console_bulk_row_save(uuid, jsonb, text) to authenticated;
revoke all on function public.console_bulk_unlock_row(uuid, integer, text) from public, anon;
grant execute on function public.console_bulk_unlock_row(uuid, integer, text) to authenticated;
revoke all on function public.console_bulk_set_expiry(uuid, timestamptz) from public, anon;
grant execute on function public.console_bulk_set_expiry(uuid, timestamptz) to authenticated;
revoke all on function public.console_bulk_files(uuid, timestamptz) from public, anon;
grant execute on function public.console_bulk_files(uuid, timestamptz) to authenticated;
revoke all on function public.console_bulk_people(uuid, jsonb, text) from public, anon;
grant execute on function public.console_bulk_people(uuid, jsonb, text) to authenticated;
revoke all on function public.console_bulk_due_at(uuid, timestamptz) from public, anon;
grant execute on function public.console_bulk_due_at(uuid, timestamptz) to authenticated;
revoke all on function public.console_bulk_settings(uuid, jsonb) from public, anon;
grant execute on function public.console_bulk_settings(uuid, jsonb) to authenticated;
revoke all on function public.console_bulk_mark_paid(uuid, text) from public, anon;
grant execute on function public.console_bulk_mark_paid(uuid, text) to authenticated;

do $r$
declare d text; o text; n integer;
begin
  d := pg_get_functiondef('jo.check_athlete_docs(jsonb,text,uuid)'::regprocedure);
  o := $o1$begin
  foreach k in array array['akte','passport','ktp','ijazah','bpjs'] loop$o1$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 1 (jo.check_athlete_docs) ditemukan % kali', n; end if;
  d := replace(d, o, $n1$begin
  -- pendaftaran massal (18 Nov 2026): boleh dikirim tanpa berkas; atlet ditandai berkas belum lengkap
  if not jo.in_bulk() then
  foreach k in array array['akte','passport','ktp','ijazah','bpjs'] loop$n1$);
  o := $o2$  end loop;
  if v_req->>'photo' = 'wajib' and coalesce(a->>'photo_path','') = '' then
    raise exception '%: unggah pas foto (wajib untuk Athlete Identification Card).', p_label using hint = 'ERR_ATHLETE_PHOTO';$o2$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 2 (jo.check_athlete_docs) ditemukan % kali', n; end if;
  d := replace(d, o, $n2$  end loop;
  end if;
  if not jo.in_bulk() and v_req->>'photo' = 'wajib' and coalesce(a->>'photo_path','') = '' then
    raise exception '%: unggah pas foto (wajib untuk Athlete Identification Card).', p_label using hint = 'ERR_ATHLETE_PHOTO';$n2$);
  execute d;
  d := pg_get_functiondef('public.public_register(jsonb)'::regprocedure);
  o := $o3$
    -- batas peserta per klub per kategori
    if v_club_id is not null and v_cat.max_per_club is not null then
      select count(*) into v_cnt$o3$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 3 (public.public_register) ditemukan % kali', n; end if;
  d := replace(d, o, $n3$
    -- batas peserta per klub per kategori (arahan TD); pendaftaran massal boleh melebihi, ditandai di konsol
    if v_club_id is not null and v_cat.max_per_club is not null and not jo.in_bulk() then
      select count(*) into v_cnt$n3$);
  o := $o4$        end if;
        if v_cat.max_per_club is not null then
          select count(*) into v_cnt$o4$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 4 (public.public_register) ditemukan % kali', n; end if;
  d := replace(d, o, $n4$        end if;
        if v_cat.max_per_club is not null and not jo.in_bulk() then
          select count(*) into v_cnt$n4$);
  execute d;
  d := pg_get_functiondef('jo.submission_public_json(jo.submissions)'::regprocedure);
  o := $o5$        'doc_status', a.doc_status, 'has_bpjs', a.bpjs_path is not null, 'photo_thumb', a.photo_thumb,
        'aic_reissued_at', a.aic_reissued_at,
        'docs', jsonb_build_object('akte', a.akte_path is not null, 'ktp', a.ktp_path is not null, 'ijazah', a.ijazah_path is not null,$o5$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 5 (jo.submission_public_json) ditemukan % kali', n; end if;
  d := replace(d, o, $n5$        'doc_status', a.doc_status, 'has_bpjs', a.bpjs_path is not null, 'photo_thumb', a.photo_thumb,
        'aic_reissued_at', a.aic_reissued_at, 'docs_missing', to_jsonb(jo.athlete_docs_missing(a)),
        'docs', jsonb_build_object('akte', a.akte_path is not null, 'ktp', a.ktp_path is not null, 'ijazah', a.ijazah_path is not null,$n5$);
  execute d;
  d := pg_get_functiondef('public.public_verify(text)'::regprocedure);
  o := $o6$      'photo', case when s.status = 'lunas' then a.photo_thumb end,
      'registered_by', case when s.status = 'lunas' then s.contact_name || coalesce(' (' || case s.contact_role$o6$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 6 (public.public_verify) ditemukan % kali', n; end if;
  d := replace(d, o, $n6$      'photo', case when s.status = 'lunas' then a.photo_thumb end,
      'docs_missing', case when s.status = 'lunas' then to_jsonb(jo.athlete_docs_missing(a)) end,
      'registered_by', case when s.status = 'lunas' then s.contact_name || coalesce(' (' || case s.contact_role$n6$);
  execute d;
  d := pg_get_functiondef('public.public_check_eligibility(jsonb)'::regprocedure);
  o := $o7$  v_staff := st.id is not null;
  v_pri := jo.priangan_reason(nat, case when nat = 'WNI' then prov end, cprov);$o7$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 7 (public.public_check_eligibility) ditemukan % kali', n; end if;
  d := replace(d, o, $n7$  v_staff := st.id is not null;
  if not v_staff then raise exception 'Cek kelayakan hanya untuk panitia.' using hint = 'ERR_SESSION'; end if;
  v_pri := jo.priangan_reason(nat, case when nat = 'WNI' then prov end, cprov);$n7$);
  execute d;
  d := pg_get_functiondef('public.console_athletes(jsonb)'::regprocedure);
  o := $o8$        where ea.athlete_id = a.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issue
    from jo.athletes a join jo.submissions s on s.id = a.submission_id$o8$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 8 (public.console_athletes) ditemukan % kali', n; end if;
  d := replace(d, o, $n8$        where ea.athlete_id = a.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issue,
      array_to_string(jo.athlete_docs_missing(a), ', ') as docs_missing, s.bulk_batch_id is not null as is_bulk
    from jo.athletes a join jo.submissions s on s.id = a.submission_id$n8$);
  o := $o9$             where ea.athlete_id = a.id and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
  ) x where coalesce(f->>'flag','') <> 'aturan' or x.rule_issue is not null);
end $o9$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 9 (public.console_athletes) ditemukan % kali', n; end if;
  d := replace(d, o, $n9$             where ea.athlete_id = a.id and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
  ) x where (coalesce(f->>'flag','') <> 'aturan' or x.rule_issue is not null)
          and (coalesce(f->>'flag','') <> 'berkas' or coalesce(x.docs_missing, '') <> ''));
end $n9$);
  execute d;
  d := pg_get_functiondef('public.console_submissions(jsonb)'::regprocedure);
  o := $o10$        where e.submission_id = s.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issues
    from jo.submissions s left join jo.clubs c on c.id = s.club_id$o10$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 10 (public.console_submissions) ditemukan % kali', n; end if;
  d := replace(d, o, $n10$        where e.submission_id = s.id and e.status <> 'dibatalkan'
          and (not cat.active or jo.category_mismatch(cat, a.gender, a.birth_date) is not null)) as rule_issues,
      (select count(*) from jo.athletes a where a.submission_id = s.id and cardinality(jo.athlete_docs_missing(a)) > 0) as docs_missing
    from jo.submissions s left join jo.clubs c on c.id = s.club_id$n10$);
  o := $o11$             and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
    order by s.created_at desc$o11$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 11 (public.console_submissions) ditemukan % kali', n; end if;
  d := replace(d, o, $n11$             and e.status <> 'dibatalkan' and e.category_id = (f->>'category')::integer))
      and (coalesce(f->>'flag','') <> 'berkas' or (s.status <> 'dibatalkan'
             and exists (select 1 from jo.athletes a where a.submission_id = s.id and cardinality(jo.athlete_docs_missing(a)) > 0)))
    order by s.created_at desc$n11$);
  execute d;
  d := pg_get_functiondef('jo.bulk_public_json(jo.bulk_accounts)'::regprocedure);
  o := $o12$                 else b.club_new end,
    'locked', (b.expires_at is not null and now() > b.expires_at) or now() > jo.bulk_deadline())
$o12$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 12 (jo.bulk_public_json) ditemukan % kali', n; end if;
  d := replace(d, o, $n12$                 else b.club_new end,
    'locked', (b.expires_at is not null and now() > b.expires_at) or now() > jo.bulk_deadline(),
    'files_open', jo.bulk_files_open(b), 'files_until', jo.bulk_files_until(b),
    'min', jo.bulk_cfg_int(b, 'min'), 'max', jo.bulk_cfg_int(b, 'max'), 'pay_hours', jo.bulk_cfg_int(b, 'pay_hours'))
$n12$);
  execute d;
  d := pg_get_functiondef('public.public_bulk_sheet(text,text,timestamptz)'::regprocedure);
  o := $o13$    'now', now(),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', r.data, 'has_photo', r.photo_thumb is not null,
              'batch_id', r.batch_id, 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)$o13$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 13 (public.public_bulk_sheet) ditemukan % kali', n; end if;
  d := replace(d, o, $n13$    'now', now(),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', jo.bulk_row_data(r), 'has_photo', jo.bulk_row_has_photo(r),
              'batch_id', r.batch_id, 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)$n13$);
  execute d;
  d := pg_get_functiondef('public.public_bulk_thumb(text,text,integer)'::regprocedure);
  o := $o14$  b := jo.bulk_auth(p_code, p_person, false);
  return (select photo_thumb from jo.bulk_rows where bulk_id = b.id and row_no = p_row);
end $o14$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 14 (public.public_bulk_thumb) ditemukan % kali', n; end if;
  d := replace(d, o, $n14$  b := jo.bulk_auth(p_code, p_person, false);
  return (select coalesce((select a.photo_thumb from jo.athletes a where a.bulk_row_id = r.id and a.photo_thumb is not null limit 1), r.photo_thumb)
            from jo.bulk_rows r where r.bulk_id = b.id and r.row_no = p_row);
end $n14$);
  execute d;
  d := pg_get_functiondef('public.public_bulk_save(text,text,jsonb)'::regprocedure);
  o := $o15$declare b jo.bulk_accounts; v_uid uuid := auth.uid(); x jsonb; v_no integer; v_old jo.bulk_rows; v_name text; k text; v_path text;
        v_max integer := coalesce(jo.setting_int('bulk_max'), 250); v_saved jsonb := '[]'::jsonb; v_thumb text; v_n integer := 0; v_del integer := 0;
begin$o15$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 15 (public.public_bulk_save) ditemukan % kali', n; end if;
  d := replace(d, o, $n15$declare b jo.bulk_accounts; v_uid uuid := auth.uid(); x jsonb; v_no integer; v_old jo.bulk_rows; v_name text; k text; v_path text;
        v_max integer; v_saved jsonb := '[]'::jsonb; v_thumb text; v_n integer := 0; v_del integer := 0;
begin$n15$);
  o := $o16$  b := jo.bulk_auth(p_code, p_person, true);
  v_name := jo.bulk_person_name(b, p_person);$o16$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 16 (public.public_bulk_save) ditemukan % kali', n; end if;
  d := replace(d, o, $n16$  b := jo.bulk_auth(p_code, p_person, true);
  v_max := jo.bulk_cfg_int(b, 'max');
  v_name := jo.bulk_person_name(b, p_person);$n16$);
  o := $o17$    if v_old.batch_id is not null then
      raise exception 'Baris % sudah dikirim dalam batch dan terkunci. Koreksi lewat Inda.', v_no using hint = 'ERR_BULK_LOCKED';
    end if;$o17$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 17 (public.public_bulk_save) ditemukan % kali', n; end if;
  d := replace(d, o, $n17$    if v_old.batch_id is not null then
      raise exception 'Baris % sudah dikirim dalam batch dan terkunci. Berkas susulan diunggah lewat tombol dokumen; koreksi data lewat Inda.', v_no using hint = 'ERR_BULK_LOCKED';
    end if;$n17$);
  execute d;
  d := pg_get_functiondef('public.public_bulk_submit(text,text,integer[],jsonb,text)'::regprocedure);
  o := $o18$declare b jo.bulk_accounts; v_name text; v_no integer; v_batch jo.bulk_batches; v_disc text; v_res jsonb; v_sub jo.submissions;
        v_total integer := 0; v_n integer; v_min integer := coalesce(jo.setting_int('bulk_min'), 30); v_amounts jsonb; v_sum integer;
        v_msg text; v_hint text; v_codes jsonb := '[]'::jsonb; v_m text[]; v_row text;$o18$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 18 (public.public_bulk_submit) ditemukan % kali', n; end if;
  d := replace(d, o, $n18$declare b jo.bulk_accounts; v_name text; v_no integer; v_batch jo.bulk_batches; v_disc text; v_res jsonb; v_sub jo.submissions;
        v_total integer := 0; v_n integer; v_min integer; v_amounts jsonb; v_sum integer;
        v_msg text; v_hint text; v_codes jsonb := '[]'::jsonb; v_m text[]; v_row text;$n18$);
  o := $o19$  b := jo.bulk_auth(p_code, p_person, true);
  v_name := jo.bulk_person_name(b, p_person);$o19$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 19 (public.public_bulk_submit) ditemukan % kali', n; end if;
  d := replace(d, o, $n19$  b := jo.bulk_auth(p_code, p_person, true);
  v_min := jo.bulk_cfg_int(b, 'min');
  v_name := jo.bulk_person_name(b, p_person);$n19$);
  o := $o20$          jo.bulk_code_label(b) || '-B' || (coalesce((select max(no) from jo.bulk_batches where bulk_id = b.id), 0) + 1),
          v_name, now() + interval '48 hours')
  returning * into v_batch;$o20$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 20 (public.public_bulk_submit) ditemukan % kali', n; end if;
  d := replace(d, o, $n20$          jo.bulk_code_label(b) || '-B' || (coalesce((select max(no) from jo.bulk_batches where bulk_id = b.id), 0) + 1),
          v_name, now() + make_interval(hours => jo.bulk_cfg_int(b, 'pay_hours')))
  returning * into v_batch;$n20$);
  execute d;
  d := pg_get_functiondef('jo.bulk_console_row(jo.bulk_accounts)'::regprocedure);
  o := $o21$                      join jo.bulk_batches bt on bt.id = s.bulk_batch_id
                     where bt.bulk_id = b.id and s.status <> 'dibatalkan' and a.doc_status = 'menunggu'))
$o21$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 21 (jo.bulk_console_row) ditemukan % kali', n; end if;
  d := replace(d, o, $n21$                      join jo.bulk_batches bt on bt.id = s.bulk_batch_id
                     where bt.bulk_id = b.id and s.status <> 'dibatalkan' and a.doc_status = 'menunggu'),
    'docs_incomplete', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
                      join jo.bulk_batches bt on bt.id = s.bulk_batch_id
                     where bt.bulk_id = b.id and s.status <> 'dibatalkan' and cardinality(jo.athlete_docs_missing(a)) > 0),
    'over_quota', jo.club_over_quota(b.club_id),
    'files_until', b.files_until, 'files_open', jo.bulk_files_open(b), 'files_open_until', jo.bulk_files_until(b),
    'event_start', jo.bulk_event_start(), 'deadline', jo.bulk_deadline(),
    'settings', b.settings, 'cfg', jsonb_build_object('min', jo.bulk_cfg_int(b, 'min'), 'max', jo.bulk_cfg_int(b, 'max'), 'pay_hours', jo.bulk_cfg_int(b, 'pay_hours')),
    'owner_role', b.owner_role)
$n21$);
  execute d;
  d := pg_get_functiondef('public.console_bulk(uuid)'::regprocedure);
  o := $o22$    'manager', jo.bulk_is_manager(st),
    'sheet', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', r.data, 'has_photo', r.photo_thumb is not null,
              'batch', (select code from jo.bulk_batches bt where bt.id = r.batch_id), 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)$o22$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 22 (public.console_bulk) ditemukan % kali', n; end if;
  d := replace(d, o, $n22$    'manager', jo.bulk_is_manager(st),
    'admin', st.role in ('owner','superadmin'),
    'sheet', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', jo.bulk_row_data(r), 'has_photo', jo.bulk_row_has_photo(r),
              'batch', (select code from jo.bulk_batches bt where bt.id = r.batch_id), 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)$n22$);
  execute d;
  d := pg_get_functiondef('public.console_bulk_extend(uuid,integer)'::regprocedure);
  o := $o23$begin
  st := jo.bulk_manager();
  select * into b from jo.bulk_accounts where id = p_id for update;$o23$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 23 (public.console_bulk_extend) ditemukan % kali', n; end if;
  d := replace(d, o, $n23$begin
  st := jo.bulk_admin();
  select * into b from jo.bulk_accounts where id = p_id for update;$n23$);
  o := $o24$  if b.opened_at is null then raise exception 'Kode belum pernah dibuka klub; masa berlaku belum dimulai.'; end if;
  if b.extended_days is not null then raise exception 'Kode ini sudah pernah diperpanjang. Perpanjangan hanya satu kali.'; end if;
  if p_days not between 1 and 3 then raise exception 'Perpanjangan 1, 2, atau 3 hari.'; end if;
  if b.expires_at >= jo.bulk_deadline() then raise exception 'Masa berlaku sudah sampai batas akhir pendaftaran.'; end if;$o24$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 24 (public.console_bulk_extend) ditemukan % kali', n; end if;
  d := replace(d, o, $n24$  if b.opened_at is null then raise exception 'Kode belum pernah dibuka klub; masa berlaku belum dimulai.'; end if;
  if p_days not between 1 and 30 then raise exception 'Perpanjangan 1 sampai 30 hari.'; end if;
  if b.expires_at >= jo.bulk_deadline() then raise exception 'Masa berlaku sudah sampai batas akhir pendaftaran.'; end if;$n24$);
  o := $o25$     set expires_at = least(greatest(expires_at, now()) + make_interval(days => p_days), jo.bulk_deadline()),
         extended_days = p_days, extended_by = st.id, extended_at = now(), reminded_at = null, updated_at = now()
   where id = b.id returning * into b;$o25$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 25 (public.console_bulk_extend) ditemukan % kali', n; end if;
  d := replace(d, o, $n25$     set expires_at = least(greatest(expires_at, now()) + make_interval(days => p_days), jo.bulk_deadline()),
         extended_days = coalesce(extended_days, 0) + p_days, extended_by = st.id, extended_at = now(), reminded_at = null, updated_at = now()
   where id = b.id returning * into b;$n25$);
  execute d;
  d := pg_get_functiondef('public.console_bulk_due(uuid,integer)'::regprocedure);
  o := $o26$begin
  st := jo.bulk_manager();
  if p_hours not in (24, 48) then raise exception 'Tambahan waktu 24 atau 48 jam.'; end if;
  update jo.bulk_batches set due_at = greatest(due_at, now()) + make_interval(hours => p_hours)$o26$;
  n := (length(d) - length(replace(d, o, ''))) / length(o); if n <> 1 then raise exception 'Pola 26 (public.console_bulk_due) ditemukan % kali', n; end if;
  d := replace(d, o, $n26$begin
  st := jo.bulk_admin();
  if p_hours not between 1 and 336 then raise exception 'Tambahan waktu 1 sampai 336 jam.'; end if;
  update jo.bulk_batches set due_at = greatest(due_at, now()) + make_interval(hours => p_hours)$n26$);
  execute d;
end $r$;
