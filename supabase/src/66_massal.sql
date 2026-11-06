-- =====================================================================
--  Jabar Open 2026 — Pendaftaran Massal (min. 30 atlet, maks. 250 per kode)
--  Spesifikasi: dokumen proyek "Spesifikasi Pendaftaran Massal" (disetujui 6 Nov 2026)
--
--  Alur: Inda/Owner membuat kode akses untuk satu klub -> klub (pemilik + maks. 2
--  kolaborator) mengisi lembar atlet yang tersimpan di server -> kirim per batch
--  (batch pertama min. 30) -> transfer BCA (boleh dipecah, maks. 5) + unggah bukti
--  -> Inda memverifikasi -> batch lunas -> pendaftaran biasa per disiplin ikut lunas
--  dan email AIC terkirim seperti biasa.
--
--  Saat batch dikirim, sistem memanggil public_register per disiplin dalam "mode
--  massal" (set_config('jo.bulk', ...)): tanpa batas 10 atlet, tanpa QRIS/kode
--  unik (payment_method 'transfer'), tanpa email pendaftaran per disiplin.
-- =====================================================================

alter table jo.submissions drop constraint if exists submissions_payment_method_check;
alter table jo.submissions add constraint submissions_payment_method_check
  check (payment_method in ('qris','manual','transfer'));

create sequence if not exists jo.bulk_seq;

create table if not exists jo.bulk_accounts (
  id             uuid primary key default gen_random_uuid(),
  seq            integer not null unique,
  code_hash      text not null unique,
  code_hint      text,
  status         text not null default 'aktif' check (status in ('aktif','dicabut')),
  label          text not null,                 -- nama klub sesuai catatan panitia
  req_name       text,                          -- peminta kode
  req_phone      text,
  note           text,
  created_by     uuid references jo.staff(id),
  created_at     timestamptz not null default now(),
  opened_at      timestamptz,                   -- pertama kali kode dibuka klub
  expires_at     timestamptz,                   -- 7 hari sejak dibuka (maks. batas pendaftaran)
  extended_days  integer,
  extended_by    uuid references jo.staff(id),
  extended_at    timestamptz,
  owner_name     text,
  owner_phone    text,
  owner_email    text,
  owner_role     text,
  club_id        uuid references jo.clubs(id),
  club_new       jsonb,                         -- klub baru (dibuat saat batch pertama)
  collaborators  jsonb not null default '[]'::jsonb,  -- [{id:'k1',name,phone}]
  reminded_at    timestamptz,
  updated_at     timestamptz not null default now()
);

create table if not exists jo.bulk_batches (
  id           uuid primary key default gen_random_uuid(),
  bulk_id      uuid not null references jo.bulk_accounts(id) on delete cascade,
  no           integer not null,
  code         text not null unique,
  person       text,
  athletes     integer not null default 0,
  total        integer not null default 0,
  split        jsonb not null default '{}'::jsonb,   -- {mode:'penuh'|'rata'|'bebas', amounts:[...]}
  due_at       timestamptz not null,
  status       text not null default 'menunggu' check (status in ('menunggu','lunas','dibatalkan')),
  paid_at      timestamptz,
  verified_by  uuid references jo.staff(id),
  created_at   timestamptz not null default now(),
  unique (bulk_id, no)
);

create table if not exists jo.bulk_rows (
  id          uuid primary key default gen_random_uuid(),
  bulk_id     uuid not null references jo.bulk_accounts(id) on delete cascade,
  row_no      integer not null check (row_no between 1 and 250),
  data        jsonb not null default '{}'::jsonb,
  photo_thumb text,
  batch_id    uuid references jo.bulk_batches(id),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  unique (bulk_id, row_no)
);
create index if not exists bulk_rows_bulk_idx on jo.bulk_rows(bulk_id, updated_at);

create table if not exists jo.bulk_payments (
  id            bigserial primary key,
  batch_id      uuid not null references jo.bulk_batches(id) on delete cascade,
  amount        integer not null check (amount > 0),
  transfer_date date,
  proof_path    text not null,
  person        text,
  uploaded_at   timestamptz not null default now(),
  status        text not null default 'menunggu' check (status in ('menunggu','cocok','tidak_cocok')),
  note          text,
  verified_by   uuid references jo.staff(id),
  verified_at   timestamptz
);

create table if not exists jo.bulk_log (
  id      bigserial primary key,
  bulk_id uuid not null references jo.bulk_accounts(id) on delete cascade,
  at      timestamptz not null default now(),
  person  text,
  action  text not null,
  detail  jsonb not null default '{}'::jsonb
);
create index if not exists bulk_log_bulk_idx on jo.bulk_log(bulk_id, at desc);

alter table jo.submissions add column if not exists bulk_batch_id uuid references jo.bulk_batches(id);

insert into jo.settings (key, value) values
  ('bulk_min', '30'::jsonb),
  ('bulk_max', '250'::jsonb),
  ('bulk_days', '7'::jsonb),
  ('bulk_wa', '"6282115596852"'::jsonb),
  ('bulk_bank', '{"bank":"BCA","number":"1300030431533","name":"Inda Sopia","title":"Finance Manager Jabar Open 2026"}'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------
create or replace function jo.in_bulk() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(current_setting('jo.bulk', true), '') <> ''
$$;

create or replace function jo.bulk_deadline() returns timestamptz
language sql stable set search_path = '' as $$
  select coalesce((jo.setting_text('registration_deadline'))::timestamptz, now() + interval '30 days')
$$;

create or replace function jo.bulk_code_label(b jo.bulk_accounts) returns text
language sql immutable set search_path = '' as $$
  select 'JO26-MS-' || lpad(b.seq::text, 3, '0')
$$;

-- pengelola: owner, atau superadmin yang namanya ada di pengaturan bulk_manager_ids
create or replace function jo.bulk_manager() returns jo.staff
language plpgsql stable set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  if st.role <> 'owner' and not coalesce(jo.setting('bulk_manager_ids') ? st.id::text, false) then
    raise exception 'Hanya Inda (Finance Manager) dan owner yang bisa mengubah pendaftaran massal.';
  end if;
  return st;
end $$;

create or replace function jo.bulk_is_manager(st jo.staff) returns boolean
language sql stable set search_path = '' as $$
  select st.role = 'owner' or coalesce(jo.setting('bulk_manager_ids') ? st.id::text, false)
$$;

create or replace function jo.bulk_add_log(p_bulk uuid, p_person text, p_action text, p_detail jsonb default '{}'::jsonb)
returns void language sql volatile set search_path = '' as $$
  insert into jo.bulk_log (bulk_id, person, action, detail) values (p_bulk, p_person, p_action, coalesce(p_detail, '{}'::jsonb));
$$;

-- nama orang yang sedang mengisi (pemilik / kolaborator)
create or replace function jo.bulk_person_name(b jo.bulk_accounts, p_person text) returns text
language plpgsql stable set search_path = '' as $$
declare v text;
begin
  if p_person = 'pemilik' then return b.owner_name; end if;
  select x->>'name' into v from jsonb_array_elements(b.collaborators) x where x->>'id' = p_person;
  return v;
end $$;

-- Autentikasi kode akses. p_write: perlu masa berlaku masih aktif.
create or replace function jo.bulk_auth(p_code text, p_person text, p_write boolean) returns jo.bulk_accounts
language plpgsql volatile set search_path = '' as $$
declare b jo.bulk_accounts; v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  select * into b from jo.bulk_accounts where code_hash = jo.sha256(jo.norm_code(p_code));
  if b.id is null or b.status <> 'aktif' then
    raise exception 'Kode akses tidak dikenal atau sudah tidak berlaku. Hubungi Inda untuk kode baru.' using hint = 'ERR_BULK_CODE';
  end if;
  if p_person is not null then
    if b.owner_name is null then
      raise exception 'Data pemilik belum diisi.' using hint = 'ERR_BULK_SETUP';
    end if;
    if jo.bulk_person_name(b, p_person) is null then
      raise exception 'Pilih nama Anda dari daftar.' using hint = 'ERR_BULK_PERSON';
    end if;
  end if;
  if p_write then
    if b.expires_at is not null and now() > b.expires_at then
      raise exception 'Masa pengisian sudah berakhir (%). Hubungi Inda bila perlu.', to_char(b.expires_at at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB' using hint = 'ERR_BULK_EXPIRED';
    end if;
    if now() > jo.bulk_deadline() then
      raise exception 'Pendaftaran sudah ditutup.' using hint = 'ERR_CLOSED';
    end if;
  end if;
  return b;
end $$;

-- ---------------------------------------------------------------------
-- Email
-- ---------------------------------------------------------------------
create or replace function jo.bulk_portal_link() returns text
language sql stable set search_path = '' as $$ select jo.site_url() || 'massal.html' $$;

create or replace function jo.bulk_bank_html() returns text
language sql stable set search_path = '' as $$
  select '<table role="presentation" cellpadding="0" cellspacing="0" style="margin:10px 0 14px;font-size:14px;background:#f4f6fa;border-radius:8px"><tr><td style="padding:12px 16px">'
    || 'Bank <b>' || jo.h(jo.setting('bulk_bank')->>'bank') || '</b><br>'
    || 'No. rekening <b style="font-size:17px;letter-spacing:.5px">' || jo.h(jo.setting('bulk_bank')->>'number') || '</b><br>'
    || 'a.n. <b>' || jo.h(jo.setting('bulk_bank')->>'name') || '</b> (' || jo.h(jo.setting('bulk_bank')->>'title') || ')'
    || '</td></tr></table>'
$$;

create or replace function jo.queue_bulk_email(p_bulk uuid, p_kind text, p_extra jsonb default '{}'::jsonb) returns void
language plpgsql volatile set search_path = '' as $$
declare b jo.bulk_accounts; bt jo.bulk_batches; body text; subj text; title text; v_exp text;
begin
  select * into b from jo.bulk_accounts where id = p_bulk;
  if b.owner_email is null then return; end if;
  v_exp := to_char(b.expires_at at time zone 'Asia/Jakarta', 'DD-MM-YYYY, HH24.MI') || ' WIB';
  body := '<p>Halo ' || jo.h(b.owner_name) || ',</p>';
  if p_kind = 'massal_aktif' then
    title := 'Pendaftaran massal aktif';
    subj := 'Pendaftaran massal aktif — ' || jo.bulk_code_label(b);
    body := body || '<p>Lembar pendaftaran massal untuk <b>' || jo.h(b.label) || '</b> (' || jo.h(jo.bulk_code_label(b)) || ') sudah aktif. '
      || 'Isi data atlet dan unggah dokumen di portal. Semua tersimpan otomatis dan bisa dilanjutkan dari perangkat mana pun dengan kode akses yang sama.</p>'
      || '<p><b>Batas pengisian: ' || jo.h(v_exp) || '</b>. Batch pertama minimal ' || coalesce(jo.setting_int('bulk_min'),30) || ' atlet.</p>'
      || jo.email_button(jo.bulk_portal_link(), 'Buka portal pendaftaran massal')
      || '<p style="font-size:13px;color:#5b6b88">Jangan bagikan kode akses selain kepada kolaborator yang Anda daftarkan.</p>';
  elsif p_kind = 'massal_pengingat' then
    title := 'Masa pengisian segera berakhir';
    subj := 'Pengingat: pendaftaran massal berakhir ' || to_char(b.expires_at at time zone 'Asia/Jakarta', 'DD-MM-YYYY');
    body := body || '<p>Masa pengisian pendaftaran massal <b>' || jo.h(b.label) || '</b> berakhir <b>' || jo.h(v_exp) || '</b>. '
      || 'Atlet yang belum dikirim dalam batch setelah waktu itu tidak bisa diubah atau dikirim lagi.</p>'
      || '<p>Saat ini ' || (select count(*) from jo.bulk_rows r where r.bulk_id = b.id) || ' atlet di lembar, '
      || (select count(*) from jo.bulk_rows r where r.bulk_id = b.id and r.batch_id is not null) || ' sudah dikirim.</p>'
      || jo.email_button(jo.bulk_portal_link(), 'Lanjutkan pengisian');
  elsif p_kind = 'massal_batch' then
    select * into bt from jo.bulk_batches where id = (p_extra->>'batch_id')::uuid;
    title := 'Batch diterima';
    subj := 'Batch diterima — ' || bt.code;
    body := body || '<p>Batch <b>' || jo.h(bt.code) || '</b> berisi <b>' || bt.athletes || ' atlet</b> sudah kami terima.</p>'
      || '<p style="font-size:14px;margin:0">Total yang harus ditransfer</p>'
      || '<p style="font-size:24px;font-weight:bold;color:#13284a;margin:2px 0 6px">' || jo.fmt_rp(bt.total) || '</p>'
      || jo.bulk_bank_html()
      || '<p>Tulis <b>' || jo.h(bt.code) || '</b> di berita transfer. Transfer boleh dipecah (maks. 5 kali). '
      || '<b>Selesaikan transfer dan unggah setiap bukti transfer di portal paling lambat '
      || jo.h(to_char(bt.due_at at time zone 'Asia/Jakarta', 'DD-MM-YYYY, HH24.MI')) || ' WIB</b>.</p>'
      || jo.email_button(jo.bulk_portal_link(), 'Unggah bukti transfer')
      || '<p style="font-size:13px;color:#5b6b88">Setelah semua transfer diverifikasi panitia, Athlete Identification Card (AIC) dikirim ke email ini.</p>';
  elsif p_kind = 'massal_perbaikan' then
    title := 'Bukti transfer perlu diperbaiki';
    subj := 'Bukti transfer perlu diperbaiki — ' || coalesce(p_extra->>'batch_code', '');
    body := body || '<p>Bukti transfer ' || jo.fmt_rp(coalesce((p_extra->>'amount')::integer, 0)) || ' untuk <b>' || jo.h(coalesce(p_extra->>'batch_code','')) || '</b> belum bisa kami verifikasi. Catatan panitia:</p>'
      || '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(coalesce(p_extra->>'note','-')) || '</p>'
      || '<p>Unggah bukti yang benar di portal, atau hubungi Inda lewat WhatsApp.</p>'
      || jo.email_button(jo.bulk_portal_link(), 'Buka portal');
  else
    return;
  end if;
  perform jo.queue_email(null, p_kind, b.owner_email, null, subj, jo.email_layout(title, body, 'id'));
end $$;

-- pengingat hari ke-5 dan pembersihan; dipanggil oleh outbox_claim (setiap menit)
create or replace function jo.bulk_tick() returns void
language plpgsql volatile set search_path = '' as $$
declare r record;
begin
  for r in select id from jo.bulk_accounts
            where status = 'aktif' and owner_email is not null and reminded_at is null
              and expires_at is not null and now() < expires_at and expires_at - now() <= interval '2 days'
            for update skip locked loop
    perform jo.queue_bulk_email(r.id, 'massal_pengingat');
    update jo.bulk_accounts set reminded_at = now() where id = r.id;
  end loop;
  if now() > jo.bulk_deadline() + interval '1 day' then
    delete from jo.bulk_rows where batch_id is null;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Portal publik
-- ---------------------------------------------------------------------
create or replace function public.public_bulk_info() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'min', coalesce(jo.setting_int('bulk_min'), 30), 'max', coalesce(jo.setting_int('bulk_max'), 250),
    'days', coalesce(jo.setting_int('bulk_days'), 7), 'wa', jo.setting_text('bulk_wa'), 'bank', jo.setting('bulk_bank'),
    'deadline', jo.bulk_deadline(), 'open', coalesce(jo.setting_bool('registration_open'), false) and now() <= jo.bulk_deadline())
$$;

create or replace function jo.bulk_public_json(b jo.bulk_accounts) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code_label', jo.bulk_code_label(b), 'label', b.label, 'status', b.status,
    'opened_at', b.opened_at, 'expires_at', b.expires_at, 'extended_days', b.extended_days,
    'setup', b.owner_name is not null,
    'owner', case when b.owner_name is not null then jsonb_build_object('name', b.owner_name, 'phone', b.owner_phone, 'email', b.owner_email, 'role', b.owner_role) end,
    'collaborators', b.collaborators,
    'people', case when b.owner_name is not null then
        jsonb_build_array(jsonb_build_object('id', 'pemilik', 'name', b.owner_name, 'role', 'Pemilik')) ||
        coalesce((select jsonb_agg(jsonb_build_object('id', x->>'id', 'name', x->>'name', 'role', 'Kolaborator')) from jsonb_array_elements(b.collaborators) x), '[]'::jsonb)
      else '[]'::jsonb end,
    'club', case when b.club_id is not null then (select jsonb_build_object('id', c.id, 'name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) from jo.clubs c where c.id = b.club_id)
                 else b.club_new end,
    'locked', (b.expires_at is not null and now() > b.expires_at) or now() > jo.bulk_deadline())
$$;

-- membuka kode: hari pertama dibuka memulai masa berlaku 7 hari
create or replace function public.public_bulk_open(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  -- kode salah dicatat tanpa exception agar catatannya tidak ikut dibatalkan
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'bulk_fail' and at > now() - interval '15 minutes') >= 10 then
    return jsonb_build_object('ok', false, 'message', 'Terlalu banyak percobaan kode yang salah. Tunggu 15 menit lalu coba lagi.');
  end if;
  select * into b from jo.bulk_accounts where code_hash = jo.sha256(jo.norm_code(p_code));
  if b.id is null or b.status <> 'aktif' then
    insert into jo.rate_events (uid, action) values (v_uid, 'bulk_fail');
    return jsonb_build_object('ok', false, 'message', 'Kode akses tidak dikenal atau sudah tidak berlaku. Hubungi Inda untuk kode baru.');
  end if;
  if b.opened_at is null then
    update jo.bulk_accounts
       set opened_at = now(),
           expires_at = least(now() + make_interval(days => coalesce(jo.setting_int('bulk_days'), 7)), jo.bulk_deadline()),
           updated_at = now()
     where id = b.id returning * into b;
    perform jo.bulk_add_log(b.id, null, 'kode_dibuka', jsonb_build_object('expires_at', b.expires_at));
  end if;
  return jo.bulk_public_json(b) || jsonb_build_object('ok', true);
end $$;

-- data pemilik, klub, dan kolaborator (pertama kali, atau diubah oleh pemilik)
create or replace function public.public_bulk_setup(p_code text, p_person text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_first boolean; v_col jsonb := '[]'::jsonb; x jsonb; i integer := 0; v_club jo.clubs; v_role text;
begin
  b := jo.bulk_auth(p_code, null, true);
  v_first := b.owner_name is null;
  if not v_first and coalesce(p_person,'') <> 'pemilik' then
    raise exception 'Hanya pemilik yang bisa mengubah data klub dan kolaborator.' using hint = 'ERR_BULK_PERSON';
  end if;
  if length(trim(coalesce(p->>'name',''))) < 3 then raise exception 'Isi nama Anda.' using hint = 'ERR_BULK_SETUP'; end if;
  if length(regexp_replace(coalesce(p->>'phone',''), '[^0-9]', '', 'g')) < 9 then raise exception 'Isi nomor WhatsApp Anda.' using hint = 'ERR_BULK_SETUP'; end if;
  if lower(trim(coalesce(p->>'email',''))) !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Alamat email belum valid.' using hint = 'ERR_BULK_SETUP'; end if;
  v_role := lower(trim(coalesce(p->>'role','')));
  if v_role not in ('pemilik','admin','pelatih','manajer','lainnya') then raise exception 'Pilih peran Anda di klub.' using hint = 'ERR_BULK_SETUP'; end if;
  for x in select * from jsonb_array_elements(coalesce(p->'collaborators','[]'::jsonb)) loop
    if length(trim(coalesce(x->>'name',''))) = 0 then continue; end if;
    i := i + 1;
    if i > 2 then raise exception 'Maksimal 2 kolaborator.' using hint = 'ERR_BULK_SETUP'; end if;
    if length(trim(x->>'name')) < 3 then raise exception 'Kolaborator %: isi nama lengkap.', i using hint = 'ERR_BULK_SETUP'; end if;
    if length(regexp_replace(coalesce(x->>'phone',''), '[^0-9]', '', 'g')) < 9 then raise exception 'Kolaborator %: isi nomor WhatsApp.', i using hint = 'ERR_BULK_SETUP'; end if;
    v_col := v_col || jsonb_build_object('id', coalesce(nullif(x->>'id',''), 'k' || i), 'name', jo.name_case(x->>'name'), 'phone', trim(x->>'phone'));
  end loop;
  if not exists (select 1 from jo.bulk_batches bt where bt.bulk_id = b.id) then
    if nullif(p->'club'->>'id','') is not null then
      select * into v_club from jo.clubs where id = (p->'club'->>'id')::uuid and merged_into is null;
      if v_club.id is null then raise exception 'Klub tidak ditemukan.' using hint = 'ERR_BULK_SETUP'; end if;
      update jo.bulk_accounts set club_id = v_club.id, club_new = null where id = b.id;
    elsif p->'club'->'new' is not null then
      if length(trim(coalesce(p->'club'->'new'->>'name',''))) < 3 then raise exception 'Isi nama klub.' using hint = 'ERR_BULK_SETUP'; end if;
      if coalesce(p->'club'->'new'->>'country','Indonesia') = 'Indonesia'
         and (coalesce(p->'club'->'new'->>'province','') = '' or coalesce(p->'club'->'new'->>'kab_kota','') = '') then
        raise exception 'Isi provinsi dan kabupaten/kota klub.' using hint = 'ERR_BULK_SETUP';
      end if;
      update jo.bulk_accounts set club_id = null,
        club_new = jsonb_build_object('name', jo.org_case(p->'club'->'new'->>'name'), 'kind', coalesce(nullif(p->'club'->'new'->>'kind',''),'klub'),
          'province', nullif(trim(coalesce(p->'club'->'new'->>'province','')),''), 'kab_kota', nullif(trim(coalesce(p->'club'->'new'->>'kab_kota','')),''),
          'country', coalesce(nullif(trim(coalesce(p->'club'->'new'->>'country','')),''), 'Indonesia'))
       where id = b.id;
    else
      raise exception 'Pilih klub atau tambahkan klub baru.' using hint = 'ERR_BULK_SETUP';
    end if;
  end if;
  update jo.bulk_accounts set owner_name = jo.name_case(p->>'name'), owner_phone = trim(p->>'phone'),
    owner_email = lower(trim(p->>'email')), owner_role = v_role, collaborators = v_col, updated_at = now()
   where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, b.owner_name, case when v_first then 'data_pemilik' else 'data_pemilik_diubah' end,
    jsonb_build_object('collaborators', (select coalesce(jsonb_agg(c->>'name'), '[]'::jsonb) from jsonb_array_elements(v_col) c)));
  if v_first then perform jo.queue_bulk_email(b.id, 'massal_aktif'); end if;
  return jo.bulk_public_json(b);
end $$;

create or replace function jo.bulk_batches_json(p_bulk uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', bt.id, 'no', bt.no, 'code', bt.code, 'person', bt.person, 'athletes', bt.athletes, 'total', bt.total,
      'split', bt.split, 'due_at', bt.due_at, 'status', bt.status, 'paid_at', bt.paid_at, 'created_at', bt.created_at,
      'overdue', bt.status = 'menunggu' and now() > bt.due_at,
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

-- lembar lengkap (p_since null) atau hanya baris yang berubah sejak p_since
create or replace function public.public_bulk_sheet(p_code text, p_person text, p_since timestamptz default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts;
begin
  b := jo.bulk_auth(p_code, p_person, false);
  return jsonb_build_object(
    'account', jo.bulk_public_json(b),
    'now', now(),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', r.data, 'has_photo', r.photo_thumb is not null,
              'batch_id', r.batch_id, 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)
             from jo.bulk_rows r where r.bulk_id = b.id and (p_since is null or r.updated_at > p_since)),
    'deleted', case when p_since is not null then (select coalesce(jsonb_agg((l.detail->>'row_no')::integer), '[]'::jsonb)
             from jo.bulk_log l where l.bulk_id = b.id and l.action = 'baris_dihapus' and l.at > p_since) end,
    'batches', jo.bulk_batches_json(b.id),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'person', l.person, 'action', l.action, 'detail', l.detail) order by l.at desc), '[]'::jsonb)
             from (select * from jo.bulk_log l where l.bulk_id = b.id order by l.at desc limit 30) l));
end $$;

create or replace function public.public_bulk_thumb(p_code text, p_person text, p_row integer) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts;
begin
  b := jo.bulk_auth(p_code, p_person, false);
  return (select photo_thumb from jo.bulk_rows where bulk_id = b.id and row_no = p_row);
end $$;

-- simpan beberapa baris: [{row_no, data, photo_thumb?, delete?}]
create or replace function public.public_bulk_save(p_code text, p_person text, p_rows jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_uid uuid := auth.uid(); x jsonb; v_no integer; v_old jo.bulk_rows; v_name text; k text; v_path text;
        v_max integer := coalesce(jo.setting_int('bulk_max'), 250); v_saved jsonb := '[]'::jsonb; v_thumb text; v_n integer := 0; v_del integer := 0;
begin
  b := jo.bulk_auth(p_code, p_person, true);
  v_name := jo.bulk_person_name(b, p_person);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 260 then
    raise exception 'Data tidak valid.' using hint = 'ERR_BULK_DATA';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_no := (x->>'row_no')::integer;
    if v_no is null or v_no < 1 or v_no > v_max then
      raise exception 'Nomor baris harus 1 sampai %.', v_max using hint = 'ERR_BULK_ROWS';
    end if;
    select * into v_old from jo.bulk_rows where bulk_id = b.id and row_no = v_no for update;
    if v_old.batch_id is not null then
      raise exception 'Baris % sudah dikirim dalam batch dan terkunci. Koreksi lewat Inda.', v_no using hint = 'ERR_BULK_LOCKED';
    end if;
    if coalesce((x->>'delete')::boolean, false) then
      if v_old.id is not null then
        delete from jo.bulk_rows where id = v_old.id;
        perform jo.bulk_add_log(b.id, v_name, 'baris_dihapus', jsonb_build_object('row_no', v_no, 'name', v_old.data->>'full_name'));
        v_del := v_del + 1;
      end if;
      continue;
    end if;
    if jsonb_typeof(x->'data') <> 'object' or length((x->'data')::text) > 12000 then
      raise exception 'Baris %: data tidak valid.', v_no using hint = 'ERR_BULK_DATA';
    end if;
    for k in select * from jsonb_object_keys(coalesce(x->'data'->'docs','{}'::jsonb)) loop
      v_path := x->'data'->'docs'->k->>'path';
      if k not in ('akte','ktp','ijazah','passport','bpjs','photo') then
        raise exception 'Baris %: jenis dokumen tidak dikenal.', v_no using hint = 'ERR_BULK_DATA';
      end if;
      if coalesce(v_path,'') <> '' and v_path is distinct from (v_old.data->'docs'->k->>'path')
         and split_part(v_path, '/', 1) <> v_uid::text then
        raise exception 'Baris %: berkas unggahan tidak valid. Unggah ulang.', v_no using hint = 'ERR_UPLOAD';
      end if;
    end loop;
    v_thumb := case when x ? 'photo_thumb' then nullif(x->>'photo_thumb','') else v_old.photo_thumb end;
    if v_thumb is not null and (v_thumb !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(v_thumb) > 150000) then
      raise exception 'Baris %: pas foto tidak terbaca. Unggah ulang.', v_no using hint = 'ERR_ATHLETE_PHOTO';
    end if;
    if v_old.id is null then
      if (select count(*) from jo.bulk_rows where bulk_id = b.id) >= v_max then
        raise exception 'Maksimal % atlet per kode akses.', v_max using hint = 'ERR_BULK_ROWS';
      end if;
      insert into jo.bulk_rows (bulk_id, row_no, data, photo_thumb, updated_by) values (b.id, v_no, x->'data', v_thumb, v_name);
    else
      update jo.bulk_rows set data = x->'data', photo_thumb = v_thumb, updated_at = now(), updated_by = v_name where id = v_old.id;
    end if;
    v_n := v_n + 1;
    v_saved := v_saved || to_jsonb(v_no);
  end loop;
  if v_n > 0 then
    if not exists (select 1 from jo.bulk_log where bulk_id = b.id and person = v_name and action = 'lembar_diubah' and at > now() - interval '10 minutes') then
      perform jo.bulk_add_log(b.id, v_name, 'lembar_diubah', jsonb_build_object('rows', v_n));
    end if;
  end if;
  update jo.bulk_accounts set updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true, 'saved', v_saved, 'deleted', v_del, 'at', now(), 'by', v_name);
end $$;

-- ---------------------------------------------------------------------
-- Kirim batch: rakit payload per disiplin lalu daftarkan lewat public_register
-- ---------------------------------------------------------------------
create or replace function jo.bulk_payload(b jo.bulk_accounts, p_batch uuid, p_disc text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare r jo.bulk_rows; d jsonb; v_cat jo.categories; v_pcat jo.categories; v_ath jsonb := '[]'::jsonb; v_ent jsonb := '[]'::jsonb;
        v_teams jsonb := '{}'::jsonb; v_key text; v_mus jsonb; i integer; v_member jsonb; v_tkey text; v_level text; v_partner jo.bulk_rows;
        v_docs jsonb;
begin
  for r in select * from jo.bulk_rows where bulk_id = b.id and batch_id = p_batch and data->>'discipline' = p_disc order by row_no loop
    d := r.data;
    v_cat := null; v_pcat := null;
    v_key := 'r' || r.row_no;
    v_docs := jsonb_build_object(
      'akte_path', d->'docs'->'akte'->>'path', 'ktp_path', d->'docs'->'ktp'->>'path', 'ijazah_path', d->'docs'->'ijazah'->>'path',
      'passport_path', d->'docs'->'passport'->>'path', 'bpjs_path', d->'docs'->'bpjs'->>'path', 'photo_path', d->'docs'->'photo'->>'path',
      'photo_thumb', r.photo_thumb);
    if coalesce((d->>'team_only')::boolean, false) then
      v_level := d->>'team_level';
      v_tkey := coalesce(v_level,'') || '|' || lower(trim(coalesce(d->>'team_name','')));
      v_member := v_docs || jsonb_build_object('kind', 'tim', 'full_name', d->>'full_name', 'birth_date', d->>'birth_date',
        'nationality', coalesce(d->>'nationality','WNI'), 'country', d->>'country',
        'guardian', jsonb_build_object('name', d->>'g_name', 'relation', d->>'g_relation', 'phone', d->>'g_phone', 'email', d->>'g_email'));
      v_teams := jsonb_set(v_teams, array[v_tkey], coalesce(v_teams->v_tkey, jsonb_build_object('level', v_level, 'name', d->>'team_name', 'members', '[]'::jsonb)));
      v_teams := jsonb_set(v_teams, array[v_tkey, 'members'], (v_teams->v_tkey->'members') || v_member);
      continue;
    end if;
    v_ath := v_ath || (v_docs || jsonb_build_object('key', v_key, 'full_name', d->>'full_name', 'gender', d->>'gender', 'birth_date', d->>'birth_date',
      'nationality', coalesce(d->>'nationality','WNI'), 'country', d->>'country', 'province', d->>'province', 'kab_kota', d->>'kab_kota',
      'guardian', jsonb_build_object('name', d->>'g_name', 'relation', d->>'g_relation', 'phone', d->>'g_phone', 'email', d->>'g_email')));
    if nullif(d->>'category_id','') is not null then
      select * into v_cat from jo.categories where id = (d->>'category_id')::integer;
      v_mus := '{}'::jsonb;
      if p_disc = 'RG' and v_cat.id is not null then
        for i in 1 .. coalesce(array_length(v_cat.apparatus, 1), 0) loop
          v_mus := v_mus || jsonb_build_object(v_cat.apparatus[i], coalesce(d->'music'->>(i - 1), ''));
        end loop;
      end if;
      if v_cat.entry_type = 'pair' then
        if nullif(d->>'pair_row','') is null then
          raise exception 'Baris %: isi nomor baris pasangan untuk %.', r.row_no, v_cat.name_id using hint = 'ERR_PAIR';
        end if;
        if r.row_no < (d->>'pair_row')::integer then
          v_ent := v_ent || jsonb_build_object('category_id', v_cat.id, 'athletes', jsonb_build_array(v_key, 'r' || (d->>'pair_row')), 'music', v_mus);
        end if;
      else
        v_ent := v_ent || jsonb_build_object('category_id', v_cat.id, 'athletes', jsonb_build_array(v_key), 'music', v_mus);
      end if;
    end if;
    if nullif(d->>'pair_category_id','') is not null then
      select * into v_pcat from jo.categories where id = (d->>'pair_category_id')::integer;
      if nullif(d->>'pair_row','') is null then
        raise exception 'Baris %: isi nomor baris pasangan untuk %.', r.row_no, coalesce(v_pcat.name_id, 'kategori pasangan') using hint = 'ERR_PAIR';
      end if;
      select * into v_partner from jo.bulk_rows where bulk_id = b.id and row_no = (d->>'pair_row')::integer;
      if v_partner.id is null or v_partner.batch_id is distinct from p_batch
         or v_partner.data->>'pair_row' is distinct from r.row_no::text
         or v_partner.data->>'pair_category_id' is distinct from d->>'pair_category_id' then
        raise exception 'Baris %: pasangan di baris % harus memilih kategori pasangan yang sama, menunjuk balik ke baris %, dan dikirim di batch yang sama.',
          r.row_no, d->>'pair_row', r.row_no using hint = 'ERR_PAIR';
      end if;
      if r.row_no < (d->>'pair_row')::integer then
        v_ent := v_ent || jsonb_build_object('category_id', v_pcat.id, 'athletes', jsonb_build_array(v_key, 'r' || (d->>'pair_row')), 'music', '{}'::jsonb);
      end if;
    end if;
    if length(trim(coalesce(d->>'team_name',''))) > 0 and v_cat.id is not null then
      v_level := v_cat.level;
      v_tkey := coalesce(v_level,'') || '|' || lower(trim(d->>'team_name'));
      v_teams := jsonb_set(v_teams, array[v_tkey], coalesce(v_teams->v_tkey, jsonb_build_object('level', v_level, 'name', d->>'team_name', 'members', '[]'::jsonb)));
      v_teams := jsonb_set(v_teams, array[v_tkey, 'members'], (v_teams->v_tkey->'members') || jsonb_build_object('kind', 'form', 'key', v_key));
    end if;
  end loop;

  return jsonb_build_object(
    'discipline', p_disc, 'registrant_type', 'klub', 'lang', 'id',
    'contact', jsonb_build_object('name', b.owner_name, 'email', b.owner_email, 'phone', b.owner_phone, 'role', b.owner_role),
    'club', case when b.club_id is not null then jsonb_build_object('id', b.club_id) else jsonb_build_object('new', b.club_new) end,
    'consents', jsonb_build_object('waiver', true, 'insurance', true, 'data', true, 'rules', true, 'guardian', true, 'bulk', true),
    'athletes', v_ath, 'entries', v_ent,
    'teams', (select coalesce(jsonb_agg(value), '[]'::jsonb) from jsonb_each(v_teams)));
end $$;

create or replace function public.public_bulk_submit(p_code text, p_person text, p_rows integer[], p_split jsonb, p_confirm text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_name text; v_no integer; v_batch jo.bulk_batches; v_disc text; v_res jsonb; v_sub jo.submissions;
        v_total integer := 0; v_n integer; v_min integer := coalesce(jo.setting_int('bulk_min'), 30); v_amounts jsonb; v_sum integer;
        v_msg text; v_hint text; v_codes jsonb := '[]'::jsonb; v_m text[]; v_row text;
begin
  b := jo.bulk_auth(p_code, p_person, true);
  v_name := jo.bulk_person_name(b, p_person);
  if coalesce(p_confirm,'') <> 'SAYA SETUJU' then
    raise exception 'Centang pernyataan transfer sebelum mengirim.' using hint = 'ERR_CONSENT';
  end if;
  if not coalesce(jo.setting_bool('registration_open'), false) then
    raise exception 'Pendaftaran sedang ditutup.' using hint = 'ERR_CLOSED';
  end if;
  p_rows := (select array_agg(distinct x order by x) from unnest(coalesce(p_rows, '{}')) x);
  v_n := coalesce(array_length(p_rows, 1), 0);
  if v_n = 0 then raise exception 'Pilih atlet yang akan dikirim.' using hint = 'ERR_BULK_ROWS'; end if;
  if not exists (select 1 from jo.bulk_batches where bulk_id = b.id and status <> 'dibatalkan') and v_n < v_min then
    raise exception 'Batch pertama minimal % atlet (dipilih %).', v_min, v_n using hint = 'ERR_BULK_MIN';
  end if;
  if (select count(*) from jo.bulk_rows where bulk_id = b.id and row_no = any(p_rows) and batch_id is null) <> v_n then
    raise exception 'Sebagian baris yang dipilih tidak ada atau sudah dikirim. Muat ulang lembar.' using hint = 'ERR_BULK_ROWS';
  end if;
  if exists (select 1 from jo.bulk_rows where bulk_id = b.id and row_no = any(p_rows) and coalesce(data->>'discipline','') = '') then
    raise exception 'Setiap atlet harus memilih disiplin.' using hint = 'ERR_BULK_ROWS';
  end if;

  perform pg_advisory_xact_lock(4242031);
  insert into jo.bulk_batches (bulk_id, no, code, person, due_at)
  values (b.id, coalesce((select max(no) from jo.bulk_batches where bulk_id = b.id), 0) + 1,
          jo.bulk_code_label(b) || '-B' || (coalesce((select max(no) from jo.bulk_batches where bulk_id = b.id), 0) + 1),
          v_name, now() + interval '48 hours')
  returning * into v_batch;
  update jo.bulk_rows set batch_id = v_batch.id where bulk_id = b.id and row_no = any(p_rows);

  perform set_config('jo.bulk', v_batch.id::text, true);
  for v_disc in select distinct data->>'discipline' from jo.bulk_rows where batch_id = v_batch.id order by 1 loop
    begin
      v_res := public.public_register(jo.bulk_payload(b, v_batch.id, v_disc));
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
      v_m := regexp_match(v_msg, 'Atlet (\d+)');
      if v_m is not null then
        select lpad(r.row_no::text, 3, '0') into v_row from jo.bulk_rows r
         where r.batch_id = v_batch.id and r.data->>'discipline' = v_disc and not coalesce((r.data->>'team_only')::boolean, false)
         order by r.row_no offset (v_m[1]::integer - 1) limit 1;
        if v_row is not null then v_msg := regexp_replace(v_msg, 'Atlet \d+', 'Baris ' || v_row); end if;
      end if;
      raise exception '% %', (select name_id from jo.disciplines where code = v_disc) || ':', v_msg using hint = coalesce(v_hint, 'ERR_BULK_SUBMIT');
    end;
    select * into v_sub from jo.submissions where code = v_res->>'code';
    update jo.submissions set bulk_batch_id = v_batch.id where id = v_sub.id;
    if b.club_id is null and v_sub.club_id is not null then
      update jo.bulk_accounts set club_id = v_sub.club_id, club_new = null where id = b.id returning * into b;
    end if;
    v_total := v_total + v_sub.total_amount;
    v_codes := v_codes || to_jsonb(v_sub.code);
  end loop;
  perform set_config('jo.bulk', '', true);

  v_amounts := coalesce(p_split->'amounts', jsonb_build_array(v_total));
  if jsonb_typeof(v_amounts) <> 'array' or jsonb_array_length(v_amounts) < 1 or jsonb_array_length(v_amounts) > 5 then
    raise exception 'Transfer boleh dipecah menjadi 1 sampai 5 kali.' using hint = 'ERR_BULK_SPLIT';
  end if;
  select sum((x)::text::integer) into v_sum from jsonb_array_elements(v_amounts) x;
  if exists (select 1 from jsonb_array_elements(v_amounts) x where (x)::text::integer <= 0) or v_sum <> v_total then
    raise exception 'Jumlah rencana transfer (%) harus sama dengan total tagihan (%).', jo.fmt_rp(coalesce(v_sum,0)), jo.fmt_rp(v_total) using hint = 'ERR_BULK_SPLIT';
  end if;
  update jo.bulk_batches set athletes = v_n, total = v_total,
    split = jsonb_build_object('mode', coalesce(p_split->>'mode', 'penuh'), 'amounts', v_amounts)
   where id = v_batch.id returning * into v_batch;

  perform jo.bulk_add_log(b.id, v_name, 'batch_dikirim', jsonb_build_object('code', v_batch.code, 'athletes', v_n, 'total', v_total, 'submissions', v_codes));
  perform jo.log(null, 'massal_batch_dikirim', 'bulk', b.id::text, jsonb_build_object('code', v_batch.code, 'club', b.label, 'athletes', v_n, 'total', v_total, 'person', v_name));
  perform jo.queue_bulk_email(b.id, 'massal_batch', jsonb_build_object('batch_id', v_batch.id));
  return jsonb_build_object('batch', (select x from jsonb_array_elements(jo.bulk_batches_json(b.id)) x where x->>'id' = v_batch.id::text));
end $$;

create or replace function public.public_bulk_pay(p_code text, p_person text, p_batch uuid, p_amount integer, p_date date, p_path text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare b jo.bulk_accounts; v_name text; bt jo.bulk_batches; v_uid uuid := auth.uid();
begin
  b := jo.bulk_auth(p_code, p_person, false);
  v_name := jo.bulk_person_name(b, p_person);
  select * into bt from jo.bulk_batches where id = p_batch and bulk_id = b.id;
  if bt.id is null then raise exception 'Batch tidak ditemukan.' using hint = 'ERR_BULK_BATCH'; end if;
  if bt.status <> 'menunggu' then raise exception 'Batch ini sudah %.', case when bt.status = 'lunas' then 'lunas' else 'dibatalkan' end using hint = 'ERR_BULK_BATCH'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Isi nominal transfer.' using hint = 'ERR_BULK_PAY'; end if;
  if p_date is null or p_date > (now() at time zone 'Asia/Jakarta')::date or p_date < (bt.created_at at time zone 'Asia/Jakarta')::date - 1 then
    raise exception 'Tanggal transfer tidak valid.' using hint = 'ERR_BULK_PAY';
  end if;
  if coalesce(p_path,'') = '' or split_part(p_path, '/', 1) <> v_uid::text then
    raise exception 'Unggah bukti transfer.' using hint = 'ERR_UPLOAD';
  end if;
  if (select count(*) from jo.bulk_payments where batch_id = bt.id and status <> 'tidak_cocok') >= 5 then
    raise exception 'Maksimal 5 transfer per batch. Hubungi Inda.' using hint = 'ERR_BULK_PAY';
  end if;
  insert into jo.bulk_payments (batch_id, amount, transfer_date, proof_path, person) values (bt.id, p_amount, p_date, p_path, v_name);
  perform jo.bulk_add_log(b.id, v_name, 'bukti_transfer', jsonb_build_object('code', bt.code, 'amount', p_amount, 'date', p_date));
  perform jo.log(null, 'massal_bukti_transfer', 'bulk', b.id::text, jsonb_build_object('code', bt.code, 'club', b.label, 'amount', p_amount, 'person', v_name));
  return jsonb_build_object('batches', jo.bulk_batches_json(b.id));
end $$;

-- ---------------------------------------------------------------------
-- Konsol
-- ---------------------------------------------------------------------
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
    'last_activity', (select max(at) from jo.bulk_log l where l.bulk_id = b.id))
$$;

create or replace function public.console_bulk_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object('manager', jo.bulk_is_manager(st), 'wa', jo.setting_text('bulk_wa'),
    'items', (select coalesce(jsonb_agg(jo.bulk_console_row(b) order by b.created_at desc), '[]'::jsonb) from jo.bulk_accounts b));
end $$;

create or replace function public.console_bulk_summary() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'active', (select count(*) from jo.bulk_accounts where status = 'aktif' and (expires_at is null or now() <= expires_at)),
    'to_verify', (select count(*) from jo.bulk_payments where status = 'menunggu'),
    'overdue', (select count(*) from jo.bulk_batches where status = 'menunggu' and now() > due_at));
end $$;

create or replace function public.console_bulk(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into b from jo.bulk_accounts where id = p_id;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  return jo.bulk_console_row(b) || jsonb_build_object(
    'manager', jo.bulk_is_manager(st),
    'sheet', (select coalesce(jsonb_agg(jsonb_build_object('row_no', r.row_no, 'data', r.data, 'has_photo', r.photo_thumb is not null,
              'batch', (select code from jo.bulk_batches bt where bt.id = r.batch_id), 'updated_at', r.updated_at, 'updated_by', r.updated_by) order by r.row_no), '[]'::jsonb)
              from jo.bulk_rows r where r.bulk_id = b.id),
    'batch_list', jo.bulk_batches_json(b.id),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'person', l.person, 'action', l.action, 'detail', l.detail) order by l.at desc), '[]'::jsonb)
             from (select * from jo.bulk_log l where l.bulk_id = b.id order by l.at desc limit 200) l));
end $$;

create or replace function jo.bulk_new_code() returns text
language sql volatile set search_path = '' as $$
  select 'MS-' || jo.rand_code(4) || '-' || jo.rand_code(4) || '-' || jo.rand_code(4)
$$;

create or replace function public.console_bulk_create(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_code text := jo.bulk_new_code(); b jo.bulk_accounts;
begin
  st := jo.bulk_manager();
  if length(trim(coalesce(p->>'label',''))) < 3 then raise exception 'Isi nama klub.'; end if;
  insert into jo.bulk_accounts (seq, code_hash, code_hint, label, req_name, req_phone, note, created_by)
  values (nextval('jo.bulk_seq'), jo.sha256(jo.norm_code(v_code)), right(v_code, 4), jo.org_case(p->>'label'),
          nullif(jo.name_case(coalesce(p->>'req_name','')),''), nullif(trim(coalesce(p->>'req_phone','')),''), nullif(trim(coalesce(p->>'note','')),''), st.id)
  returning * into b;
  perform jo.bulk_add_log(b.id, st.name, 'kode_dibuat', '{}'::jsonb);
  perform jo.log(st.id, 'massal_kode_dibuat', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label));
  return jsonb_build_object('item', jo.bulk_console_row(b), 'code', v_code);
end $$;

create or replace function public.console_bulk_new_code(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_code text := jo.bulk_new_code(); b jo.bulk_accounts;
begin
  st := jo.bulk_manager();
  update jo.bulk_accounts set code_hash = jo.sha256(jo.norm_code(v_code)), code_hint = right(v_code, 4), status = 'aktif', updated_at = now()
   where id = p_id returning * into b;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  perform jo.bulk_add_log(b.id, st.name, 'kode_diganti', '{}'::jsonb);
  perform jo.log(st.id, 'massal_kode_diganti', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label));
  return jsonb_build_object('item', jo.bulk_console_row(b), 'code', v_code);
end $$;

create or replace function public.console_bulk_revoke(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.bulk_manager();
  update jo.bulk_accounts set status = 'dicabut', updated_at = now() where id = p_id returning * into b;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  perform jo.bulk_add_log(b.id, st.name, 'kode_dicabut', '{}'::jsonb);
  perform jo.log(st.id, 'massal_kode_dicabut', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label));
  return jo.bulk_console_row(b);
end $$;

-- hapus kode massal beserta lembar, batch, transfer, dan riwayatnya (mis. data uji).
-- Ditolak bila sudah ada pendaftaran dari batch kode ini: hapus dulu pendaftarannya di menu Pendaftaran.
create or replace function public.console_bulk_delete(p_id uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts; v_files jsonb; v_subs text;
begin
  st := jo.bulk_manager();
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Tulis alasan penghapusan (masuk Log).'; end if;
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  select string_agg(s.code, ', ' order by s.code) into v_subs
    from jo.submissions s join jo.bulk_batches bt on bt.id = s.bulk_batch_id where bt.bulk_id = b.id;
  if v_subs is not null then
    raise exception 'Kode ini sudah punya pendaftaran (%). Hapus dulu pendaftaran tersebut di menu Pendaftaran, lalu hapus kode ini.', v_subs;
  end if;
  select coalesce(jsonb_agg(f), '[]'::jsonb) into v_files from (
    select jsonb_build_object('bucket', 'dokumen', 'path', d.value->>'path') f
      from jo.bulk_rows r, jsonb_each(coalesce(r.data->'docs', '{}'::jsonb)) d
     where r.bulk_id = b.id and coalesce(d.value->>'path', '') <> ''
    union all
    select jsonb_build_object('bucket', 'bukti', 'path', p.proof_path)
      from jo.bulk_payments p join jo.bulk_batches bt on bt.id = p.batch_id where bt.bulk_id = b.id
  ) x;
  delete from jo.bulk_accounts where id = b.id;
  perform jo.log(st.id, 'massal_dihapus', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label,
    'owner', b.owner_name, 'files', jsonb_array_length(v_files), 'reason', trim(p_reason)));
  return jsonb_build_object('ok', true, 'files', v_files);
end $$;

-- perpanjangan masa pengisian: satu kali, 1–3 hari, tidak melewati batas pendaftaran
create or replace function public.console_bulk_extend(p_id uuid, p_days integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; b jo.bulk_accounts;
begin
  st := jo.bulk_manager();
  select * into b from jo.bulk_accounts where id = p_id for update;
  if b.id is null then raise exception 'Data tidak ditemukan.'; end if;
  if b.opened_at is null then raise exception 'Kode belum pernah dibuka klub; masa berlaku belum dimulai.'; end if;
  if b.extended_days is not null then raise exception 'Kode ini sudah pernah diperpanjang. Perpanjangan hanya satu kali.'; end if;
  if p_days not between 1 and 3 then raise exception 'Perpanjangan 1, 2, atau 3 hari.'; end if;
  if b.expires_at >= jo.bulk_deadline() then raise exception 'Masa berlaku sudah sampai batas akhir pendaftaran.'; end if;
  update jo.bulk_accounts
     set expires_at = least(greatest(expires_at, now()) + make_interval(days => p_days), jo.bulk_deadline()),
         extended_days = p_days, extended_by = st.id, extended_at = now(), reminded_at = null, updated_at = now()
   where id = b.id returning * into b;
  perform jo.bulk_add_log(b.id, st.name, 'diperpanjang', jsonb_build_object('days', p_days, 'expires_at', b.expires_at));
  perform jo.log(st.id, 'massal_diperpanjang', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'club', b.label, 'days', p_days));
  return jo.bulk_console_row(b);
end $$;

-- tambahan waktu bayar untuk satu batch (bila transfer terhambat limit rekening)
create or replace function public.console_bulk_due(p_batch uuid, p_hours integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; bt jo.bulk_batches;
begin
  st := jo.bulk_manager();
  if p_hours not in (24, 48) then raise exception 'Tambahan waktu 24 atau 48 jam.'; end if;
  update jo.bulk_batches set due_at = greatest(due_at, now()) + make_interval(hours => p_hours)
   where id = p_batch and status = 'menunggu' returning * into bt;
  if bt.id is null then raise exception 'Batch tidak ditemukan atau sudah selesai.'; end if;
  perform jo.bulk_add_log(bt.bulk_id, st.name, 'batas_bayar_diperpanjang', jsonb_build_object('code', bt.code, 'hours', p_hours, 'due_at', bt.due_at));
  perform jo.log(st.id, 'massal_batas_bayar', 'bulk', bt.bulk_id::text, jsonb_build_object('code', bt.code, 'hours', p_hours));
  return public.console_bulk(bt.bulk_id);
end $$;

-- verifikasi satu bukti transfer; batch lunas otomatis bila total terverifikasi >= tagihan
create or replace function public.console_bulk_verify(p_payment bigint, p_ok boolean, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; p jo.bulk_payments; bt jo.bulk_batches; v_paid integer; s jo.submissions;
begin
  st := jo.bulk_manager();
  select * into p from jo.bulk_payments where id = p_payment for update;
  if p.id is null then raise exception 'Bukti transfer tidak ditemukan.'; end if;
  select * into bt from jo.bulk_batches where id = p.batch_id for update;
  if bt.status = 'lunas' then raise exception 'Batch ini sudah lunas.'; end if;
  if not p_ok and length(trim(coalesce(p_note,''))) < 5 then
    raise exception 'Tulis alasan yang jelas (dikirim ke klub).';
  end if;
  update jo.bulk_payments set status = case when p_ok then 'cocok' else 'tidak_cocok' end, note = nullif(trim(coalesce(p_note,'')),''),
    verified_by = st.id, verified_at = now() where id = p.id;
  perform jo.bulk_add_log(bt.bulk_id, st.name, case when p_ok then 'transfer_cocok' else 'transfer_tidak_cocok' end,
    jsonb_build_object('code', bt.code, 'amount', p.amount, 'note', p_note));
  perform jo.log(st.id, case when p_ok then 'massal_transfer_cocok' else 'massal_transfer_tidak_cocok' end, 'bulk', bt.bulk_id::text,
    jsonb_build_object('code', bt.code, 'amount', p.amount, 'note', p_note));
  if not p_ok then
    perform jo.queue_bulk_email(bt.bulk_id, 'massal_perbaikan', jsonb_build_object('batch_code', bt.code, 'amount', p.amount, 'note', p_note));
  end if;
  select coalesce(sum(amount),0) into v_paid from jo.bulk_payments where batch_id = bt.id and status = 'cocok';
  if v_paid >= bt.total then
    update jo.bulk_batches set status = 'lunas', paid_at = now(), verified_by = st.id where id = bt.id;
    for s in select * from jo.submissions where bulk_batch_id = bt.id and status <> 'dibatalkan' loop
      update jo.submissions set status = 'lunas', paid_amount = s.total_amount, paid_at = now(), verified_by = st.id, verified_at = now(),
        verify_note = 'Pendaftaran massal ' || bt.code
       where id = s.id;
      perform jo.log(st.id, 'pembayaran_lunas', 'submission', s.id::text,
        jsonb_build_object('code', s.code, 'amount', s.total_amount, 'note', 'Pendaftaran massal ' || bt.code, 'mutation_match', false));
      perform jo.queue_paid_email(s.id);
    end loop;
    perform jo.bulk_add_log(bt.bulk_id, st.name, 'batch_lunas', jsonb_build_object('code', bt.code, 'paid', v_paid, 'total', bt.total));
  end if;
  return public.console_bulk(bt.bulk_id);
end $$;
