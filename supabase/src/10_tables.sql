-- =====================================================================
--  JABAR OPEN 2026 — sistem pendaftaran & operasional panitia
--  File setup Supabase. Jalankan SELURUH isi file ini di SQL Editor.
--  Aman dijalankan ulang (tabel "if not exists", fungsi "or replace").
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists jo;
revoke all on schema jo from public;
do $$ begin
  execute 'revoke all on schema jo from anon, authenticated';
exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- Pengaturan umum (key/value)
-- ---------------------------------------------------------------------
create table if not exists jo.settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- ---------------------------------------------------------------------
-- Disiplin & kategori
-- ---------------------------------------------------------------------
create table if not exists jo.disciplines (
  code              text primary key,          -- MAG, WAG, RG, AER
  name_id           text not null,
  name_en           text not null,
  date_start        date,
  date_end          date,
  apparatus         jsonb not null default '[]'::jsonb,   -- [{code,id,en}]
  components        jsonb not null default '[]'::jsonb,   -- [{code,id,en}]
  contact_name      text,
  contact_phone     text,
  registration_open boolean not null default true,
  sort              integer not null default 0
);

create table if not exists jo.categories (
  id                   serial primary key,
  discipline           text not null references jo.disciplines(code),
  code                 text not null unique,
  level                text not null,
  age_label            text,
  division             text,
  name_id              text not null,
  name_en              text not null,
  gender               text not null check (gender in ('M','F','X')),
  birth_year_min       integer,
  birth_year_max       integer,
  entry_type           text not null default 'individual' check (entry_type in ('individual','pair')),
  fee                  integer not null,
  apparatus            text[] not null default '{}',
  max_per_club         integer,
  allow_priangan       boolean not null default true,
  medal_rule           jsonb not null default '{"type":"rank","places":3}'::jsonb,
  exhibition           boolean not null default false,
  active               boolean not null default true,
  sort                 integer not null default 0,
  scores_locked        boolean not null default false,
  results_published    boolean not null default false,
  results_published_at timestamptz,
  startlist_published  boolean not null default false,
  note                 text
);

-- ---------------------------------------------------------------------
-- Klub / sekolah / pengkab
-- ---------------------------------------------------------------------
create table if not exists jo.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        text not null default 'klub' check (kind in ('klub','sekolah','pengkab','lainnya')),
  kab_kota    text,
  province    text,
  country     text not null default 'Indonesia',
  verified    boolean not null default false,
  merged_into uuid references jo.clubs(id),
  created_at  timestamptz not null default now(),
  created_via text
);
create unique index if not exists clubs_name_place_uq
  on jo.clubs (lower(name), lower(coalesce(kab_kota,'')), lower(country)) where merged_into is null;

-- ---------------------------------------------------------------------
-- Panitia (kode akses), sesi login, percobaan login
-- ---------------------------------------------------------------------
create table if not exists jo.staff (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  role          text not null check (role in ('owner','superadmin','admin','juri')),
  discipline    text references jo.disciplines(code),     -- null = semua disiplin
  apparatus     text[],                                   -- juri: null = semua alat
  components    text[],                                   -- juri: null = semua komponen (D/E/A/PEN)
  code_hash     text not null unique,
  code_hint     text,
  active        boolean not null default true,
  note          text,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  last_login_at timestamptz
);

create table if not exists jo.staff_sessions (
  uid        uuid primary key,
  staff_id   uuid not null references jo.staff(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists jo.login_attempts (
  id  bigserial primary key,
  uid uuid,
  at  timestamptz not null default now(),
  ok  boolean not null
);

-- ---------------------------------------------------------------------
-- Pendaftaran (satu pengiriman = satu disiplin, maks 5 atlet)
-- ---------------------------------------------------------------------
create sequence if not exists jo.submission_seq;

create table if not exists jo.submissions (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  token             text not null,
  discipline        text not null references jo.disciplines(code),
  registrant_type   text not null check (registrant_type in ('individu','klub')),
  contact_name      text not null,
  contact_email     text not null,
  contact_phone     text not null,
  contact_role      text,
  club_id           uuid references jo.clubs(id),
  payment_method    text not null default 'qris' check (payment_method in ('qris','manual')),
  base_amount       integer not null default 0,
  priangan_amount   integer not null default 0,
  unique_code       integer not null default 0,
  total_amount      integer not null default 0,
  status            text not null default 'menunggu_pembayaran'
                    check (status in ('menunggu_pembayaran','menunggu_verifikasi','lunas','perlu_perbaikan','dibatalkan')),
  proof_path        text,
  proof_uploaded_at timestamptz,
  paid_amount       integer,
  paid_at           timestamptz,
  verified_by       uuid references jo.staff(id),
  verified_at       timestamptz,
  verify_note       text,
  cancel_reason     text,
  consents          jsonb not null default '{}'::jsonb,
  lang              text not null default 'id',
  auth_uid          uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists submissions_status_idx on jo.submissions(status);
create index if not exists submissions_total_idx on jo.submissions(total_amount);

create table if not exists jo.athletes (
  id                uuid primary key default gen_random_uuid(),
  submission_id     uuid not null references jo.submissions(id) on delete cascade,
  athlete_no        text unique,
  full_name         text not null,
  gender            text not null check (gender in ('M','F')),
  birth_date        date not null,
  nationality       text not null default 'WNI' check (nationality in ('WNI','WNA')),
  country           text not null default 'Indonesia',
  province          text,
  kab_kota          text,
  id_doc_path       text,
  photo_path        text,
  guardian_name     text,
  guardian_phone    text,
  guardian_email    text,
  guardian_relation text,
  doc_status        text not null default 'menunggu' check (doc_status in ('menunggu','valid','tidak_valid')),
  doc_note          text,
  doc_verified_by   uuid references jo.staff(id),
  doc_verified_at   timestamptz,
  ticket_code       text not null unique,
  sort              integer not null default 0,
  created_at        timestamptz not null default now()
);
create index if not exists athletes_sub_idx on jo.athletes(submission_id);

create table if not exists jo.sessions (
  id         serial primary key,
  discipline text not null references jo.disciplines(code),
  name       text not null,
  day        date,
  start_time time,
  sort       integer not null default 0
);

create table if not exists jo.entries (
  id                 uuid primary key default gen_random_uuid(),
  submission_id      uuid not null references jo.submissions(id) on delete cascade,
  category_id        integer not null references jo.categories(id),
  fee                integer not null,
  priangan_requested boolean not null default false,
  priangan_fee       integer not null default 0,
  priangan_status    text not null default 'tidak' check (priangan_status in ('tidak','menunggu','disetujui','ditolak')),
  priangan_note      text,
  session_id         integer references jo.sessions(id) on delete set null,
  group_no           integer,
  start_order        integer,
  status             text not null default 'aktif' check (status in ('aktif','dns','dibatalkan')),
  created_at         timestamptz not null default now()
);
create index if not exists entries_cat_idx on jo.entries(category_id);
create index if not exists entries_sub_idx on jo.entries(submission_id);

create table if not exists jo.entry_athletes (
  entry_id   uuid not null references jo.entries(id) on delete cascade,
  athlete_id uuid not null references jo.athletes(id) on delete cascade,
  cert_code  text not null unique,
  primary key (entry_id, athlete_id)
);
create index if not exists entry_athletes_ath_idx on jo.entry_athletes(athlete_id);

-- ---------------------------------------------------------------------
-- Penilaian
-- ---------------------------------------------------------------------
create table if not exists jo.scores (
  id         bigserial primary key,
  entry_id   uuid not null references jo.entries(id) on delete cascade,
  apparatus  text not null,
  component  text not null check (component in ('D','E','A','PEN','FINAL')),
  staff_id   uuid not null references jo.staff(id),
  value      numeric(7,3) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entry_id, apparatus, component, staff_id)
);

create table if not exists jo.score_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  entry_id   uuid,
  apparatus  text,
  component  text,
  judge_id   uuid,
  old_value  numeric(7,3),
  new_value  numeric(7,3),
  changed_by uuid,
  action     text not null,
  reason     text
);

-- ---------------------------------------------------------------------
-- Keuangan: mutasi masuk (impor dari laporan GoBiz / bank)
-- ---------------------------------------------------------------------
create table if not exists jo.mutations (
  id            bigserial primary key,
  imported_at   timestamptz not null default now(),
  imported_by   uuid references jo.staff(id),
  batch         text,
  trx_time      timestamptz,
  amount        integer not null,
  reference     text,
  description   text,
  raw           jsonb,
  submission_id uuid references jo.submissions(id),
  match_status  text not null default 'belum' check (match_status in ('belum','otomatis','manual','abaikan'))
);
create unique index if not exists mutations_dedupe_uq
  on jo.mutations (coalesce(reference,''), amount, coalesce(trx_time, 'epoch'::timestamptz));

-- ---------------------------------------------------------------------
-- Log & email
-- ---------------------------------------------------------------------
create table if not exists jo.audit (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  staff_id    uuid references jo.staff(id),
  action      text not null,
  target_type text,
  target_id   text,
  detail      jsonb not null default '{}'::jsonb
);
create index if not exists audit_target_idx on jo.audit(target_type, target_id);

create table if not exists jo.outbox (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  kind          text not null,
  submission_id uuid references jo.submissions(id) on delete set null,
  to_email      text not null,
  cc            text,
  subject       text not null,
  html          text not null,
  status        text not null default 'pending' check (status in ('pending','sending','sent','error')),
  attempts      integer not null default 0,
  claimed_at    timestamptz,
  sent_at       timestamptz,
  last_error    text
);
create index if not exists outbox_status_idx on jo.outbox(status);

create table if not exists jo.rate_events (
  id     bigserial primary key,
  uid    uuid,
  action text not null,
  at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- v3 (12 Okt 2026): beregu Artistik & musik Ritmik
--   * Beregu: pendaftaran terpisah (registrant_type 'beregu'), satu tim per
--     pendaftaran, 1–6 pesenam. Anggota bisa atlet perorangan (ditautkan ke
--     entrinya) atau "khusus beregu" (entri team_only: dinilai, tidak diperingkat).
--   * Musik Ritmik: tautan Google Drive per entri, boleh diganti satu kali
--     sampai start list kategorinya terbit; panitia memeriksa tautan.
-- ---------------------------------------------------------------------
alter table jo.submissions drop constraint if exists submissions_registrant_type_check;
alter table jo.submissions add constraint submissions_registrant_type_check
  check (registrant_type in ('individu','klub','beregu'));

alter table jo.entries add column if not exists team_only        boolean not null default false;
alter table jo.entries add column if not exists music_url        text;
alter table jo.entries add column if not exists music_status     text not null default 'tidak_perlu';
alter table jo.entries add column if not exists music_note       text;
alter table jo.entries add column if not exists music_changes    integer not null default 0;
alter table jo.entries add column if not exists music_updated_at timestamptz;
alter table jo.entries add column if not exists music_checked_by uuid references jo.staff(id);
alter table jo.entries add column if not exists music_checked_at timestamptz;
alter table jo.entries drop constraint if exists entries_music_status_check;
alter table jo.entries add constraint entries_music_status_check
  check (music_status in ('tidak_perlu','belum','menunggu','ok','tidak_bisa'));
-- entri Ritmik lama tanpa tautan musik: tandai "belum"
update jo.entries e set music_status = 'belum'
  from jo.categories c
 where c.id = e.category_id and c.discipline = 'RG' and e.music_url is null and e.music_status = 'tidak_perlu';

create table if not exists jo.music_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  entry_id  uuid not null references jo.entries(id) on delete cascade,
  action    text not null,          -- daftar, isi, ganti, perbaiki, ok, tidak_bisa
  old_url   text,
  new_url   text,
  staff_id  uuid references jo.staff(id),
  note      text
);
create index if not exists music_log_entry_idx on jo.music_log(entry_id);

create table if not exists jo.teams (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references jo.submissions(id) on delete cascade,
  discipline    text not null references jo.disciplines(code),
  level         text not null,
  name          text not null,
  created_at    timestamptz not null default now()
);
create index if not exists teams_level_idx on jo.teams(discipline, level);

create table if not exists jo.team_members (
  team_id    uuid not null references jo.teams(id) on delete cascade,
  entry_id   uuid not null references jo.entries(id) on delete cascade,
  athlete_id uuid not null references jo.athletes(id) on delete cascade,
  team_only  boolean not null default false,
  cert_code  text not null unique,
  sort       integer not null default 0,
  primary key (team_id, entry_id)
);
create index if not exists team_members_entry_idx on jo.team_members(entry_id);

create table if not exists jo.team_levels (
  discipline   text not null references jo.disciplines(code),
  level        text not null,
  published    boolean not null default false,
  published_at timestamptz,
  primary key (discipline, level)
);

-- ---------------------------------------------------------------------
-- v5 (14 Okt 2026): peran TD, nomor WA panitia, chat, laporan masalah, pendaftaran juri
-- ---------------------------------------------------------------------
alter table jo.staff drop constraint if exists staff_role_check;
alter table jo.staff add constraint staff_role_check check (role in ('owner','superadmin','admin','td','juri','pemantau'));
alter table jo.staff add column if not exists phone text;
alter table jo.clubs add column if not exists note text;

create table if not exists jo.chat_messages (
  id         bigserial primary key,
  room       text not null,              -- 'all' | 'disc:MAG' | 'dm:<uuid>:<uuid>' (urut)
  sender     uuid references jo.staff(id) on delete set null,
  sender_name text not null,
  body       text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_idx on jo.chat_messages(room, id);

create table if not exists jo.chat_reads (
  staff_id uuid not null references jo.staff(id) on delete cascade,
  room     text not null,
  last_id  bigint not null default 0,
  primary key (staff_id, room)
);

create table if not exists jo.issues (
  id           bigserial primary key,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  reporter     uuid references jo.staff(id) on delete set null,
  reporter_name text not null,
  discipline   text references jo.disciplines(code),
  title        text not null,
  body         text,
  shot_path    text,
  status       text not null default 'baru' check (status in ('baru','diproses','selesai')),
  handled_by   uuid references jo.staff(id) on delete set null,
  resolved_at  timestamptz
);
create table if not exists jo.issue_comments (
  id         bigserial primary key,
  issue_id   bigint not null references jo.issues(id) on delete cascade,
  staff_id   uuid references jo.staff(id) on delete set null,
  staff_name text not null,
  body       text not null,
  created_at timestamptz not null default now()
);
create table if not exists jo.issue_reads (
  staff_id uuid not null references jo.staff(id) on delete cascade,
  issue_id bigint not null references jo.issues(id) on delete cascade,
  seen_at  timestamptz not null default now(),
  primary key (staff_id, issue_id)
);

create table if not exists jo.jury_applications (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  source      text not null default 'publik' check (source in ('publik','konsol')),
  auth_uid    uuid,
  full_name   text not null,
  phone       text not null,
  email       text,
  city        text,
  province    text,
  disciplines text[] not null,
  brevet      jsonb not null default '{}'::jsonb,   -- {"WAG":{"level":"Nasional","other":null}}
  cert_path   text,
  availability date[] not null default '{}',
  ktp_path    text,
  photo_path  text,
  note        text,
  status      text not null default 'baru' check (status in ('baru','disetujui','ditolak')),
  staff_id    uuid references jo.staff(id) on delete set null,
  reviewed_by uuid references jo.staff(id) on delete set null,
  reviewed_at timestamptz,
  review_note text
);

-- ---------------------------------------------------------------------
-- v6 (14 Okt 2026, revisi PDF): Priangan khusus Ritmik, musik per nomor,
--     dokumen atlet terpisah + BPJS TK, juri satu disiplin + BPJS TK
-- ---------------------------------------------------------------------
alter table jo.categories add column if not exists jabar_only boolean not null default false;
alter table jo.categories alter column allow_priangan set default false;
alter table jo.entries add column if not exists music jsonb not null default '{}'::jsonb;   -- {"FH":"https://drive…","BALL":"…"}
alter table jo.music_log add column if not exists apparatus text;
alter table jo.athletes add column if not exists akte_path text;
alter table jo.athletes add column if not exists ktp_path text;
alter table jo.athletes add column if not exists ijazah_path text;
alter table jo.athletes add column if not exists passport_path text;
alter table jo.athletes add column if not exists bpjs_path text;
alter table jo.athletes add column if not exists photo_thumb text;   -- pas foto kecil (data URL JPEG) untuk kartu atlet
alter table jo.jury_applications add column if not exists bpjs_path text;

-- 15 Okt 2026: jam tugas juri (di luar jam = hanya lihat). [{"date":"2026-12-13","from":"07:00","to":"12:00"}]; null = tanpa batas
alter table jo.staff add column if not exists access_windows jsonb;

-- ---------------------------------------------------------------------
-- FAQ (15 Okt 2026): dikelola panitia di konsol; publik hanya melihat status 'terbit'.
--   Tidak ada hapus permanen: butir lama diarsipkan, kategori dinonaktifkan.
-- ---------------------------------------------------------------------
create table if not exists jo.faq_categories (
  key      text primary key check (key ~ '^[a-z0-9-]{2,40}$'),
  name_id  text not null,
  name_en  text,
  sort     integer not null default 0,
  active   boolean not null default true
);
create table if not exists jo.faq_items (
  id         uuid primary key default gen_random_uuid(),
  category   text not null references jo.faq_categories(key),
  slug       text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  q_id       text not null,
  a_id       text not null,
  q_en       text,
  a_en       text,
  sort       integer not null default 0,
  status     text not null default 'draf' check (status in ('draf','terbit','arsip')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text
);
create index if not exists faq_items_cat on jo.faq_items (category, sort);

-- v8 (15/10/2026): semua pendaftaran lewat klub (maks. 10 atlet), beregu menjadi bagian
-- pendaftaran klub. Bagian biaya beregu disimpan terpisah untuk buku besar.
alter table jo.submissions add column if not exists team_amount integer not null default 0;
-- satu pendaftaran klub boleh berisi lebih dari satu tim (level berbeda atau nama berbeda)
alter table jo.teams drop constraint if exists teams_submission_id_key;
create index if not exists teams_submission_idx on jo.teams(submission_id);

-- v9 (19/10/2026): notifikasi WhatsApp ke admin pendaftaran (lewat gateway, dikirim Apps Script)
create table if not exists jo.wa_recipients (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text not null,
  discipline  text references jo.disciplines(code),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create table if not exists jo.wa_outbox (
  id           bigserial primary key,
  created_at   timestamptz not null default now(),
  kind         text not null default 'digest',
  recipient_id uuid references jo.wa_recipients(id) on delete set null,
  to_phone     text not null,
  message      text not null,
  status       text not null default 'pending' check (status in ('pending','sending','sent','error')),
  attempts     integer not null default 0,
  claimed_at   timestamptz,
  sent_at      timestamptz,
  last_error   text
);
create index if not exists wa_outbox_status on jo.wa_outbox (status, id);

-- Semua tabel di skema jo: RLS aktif tanpa policy.
-- Akses hanya lewat fungsi (RPC) yang memeriksa hak.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname = 'jo' loop
    execute format('alter table jo.%I enable row level security', t.tablename);
  end loop;
end $$;
