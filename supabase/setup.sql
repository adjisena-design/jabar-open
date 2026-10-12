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

-- Semua tabel di skema jo: RLS aktif tanpa policy.
-- Akses hanya lewat fungsi (RPC) yang memeriksa hak.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname = 'jo' loop
    execute format('alter table jo.%I enable row level security', t.tablename);
  end loop;
end $$;
-- =====================================================================
--  Fungsi bantu internal (skema jo, tidak bisa dipanggil dari luar)
-- =====================================================================

create or replace function jo.rand_code(n integer, alphabet text default '23456789ABCDEFGHJKMNPQRSTUVWXYZ')
returns text language plpgsql volatile set search_path = '' as $$
declare r text := ''; b bytea := extensions.gen_random_bytes(n); i integer;
begin
  for i in 0..n-1 loop
    r := r || substr(alphabet, (get_byte(b, i) % length(alphabet)) + 1, 1);
  end loop;
  return r;
end $$;

create or replace function jo.sha256(t text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(t, 'sha256'), 'hex')
$$;

create or replace function jo.norm_code(t text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(upper(coalesce(t,'')), '[^A-Z0-9]', '', 'g')
$$;

create or replace function jo.setting(k text) returns jsonb
language sql stable set search_path = '' as $$
  select value from jo.settings where key = k
$$;

create or replace function jo.setting_text(k text) returns text
language sql stable set search_path = '' as $$
  select value #>> '{}' from jo.settings where key = k
$$;

create or replace function jo.setting_int(k text) returns integer
language sql stable set search_path = '' as $$
  select (value #>> '{}')::integer from jo.settings where key = k
$$;

create or replace function jo.setting_bool(k text) returns boolean
language sql stable set search_path = '' as $$
  select (value #>> '{}')::boolean from jo.settings where key = k
$$;

-- Usia kompetisi = tahun kompetisi - tahun lahir (sesuai Undangan: "umur pada tahun kompetisi")
create or replace function jo.comp_age(p_birth date) returns integer
language sql stable set search_path = '' as $$
  select coalesce(jo.setting_int('event_year'), 2026) - extract(year from p_birth)::integer
$$;

create or replace function jo.is_minor(p_birth date) returns boolean
language sql stable set search_path = '' as $$
  select p_birth > (current_date - interval '18 years')::date
$$;

-- Alasan kategori tidak cocok (null = cocok)
create or replace function jo.category_mismatch(c jo.categories, p_gender text, p_birth date) returns text
language plpgsql stable set search_path = '' as $$
declare y integer := extract(year from p_birth)::integer;
begin
  if c.gender in ('M','F') and c.gender <> p_gender then
    return case when c.gender = 'M' then 'Kategori ini khusus putra' else 'Kategori ini khusus putri' end;
  end if;
  if c.birth_year_min is not null and y < c.birth_year_min then
    return format('Kategori ini untuk kelahiran %s ke atas', c.birth_year_min);
  end if;
  if c.birth_year_max is not null and y > c.birth_year_max then
    return format('Kategori ini untuk kelahiran %s ke bawah', c.birth_year_max);
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Panitia: sesi & hak akses
-- ---------------------------------------------------------------------
create or replace function jo.current_staff() returns jo.staff
language sql stable security definer set search_path = '' as $$
  select s.* from jo.staff s
  join jo.staff_sessions ss on ss.staff_id = s.id
  where ss.uid = auth.uid() and ss.expires_at > now() and s.active
  limit 1
$$;

create or replace function jo.require_staff(p_roles text[]) returns jo.staff
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  select * into st from jo.current_staff();
  if st.id is null then
    raise exception 'Sesi panitia berakhir. Masuk lagi dengan kode akses.' using hint = 'ERR_SESSION', errcode = '28000';
  end if;
  if p_roles is not null and not (st.role = any(p_roles)) then
    raise exception 'Kode akses Anda tidak memiliki izin untuk tindakan ini.' using hint = 'ERR_FORBIDDEN', errcode = '42501';
  end if;
  return st;
end $$;

create or replace function jo.check_discipline(st jo.staff, p_disc text) returns void
language plpgsql stable set search_path = '' as $$
begin
  if st.role in ('admin','juri') and st.discipline is not null and st.discipline <> p_disc then
    raise exception 'Kode akses Anda hanya untuk disiplin %.', st.discipline using hint = 'ERR_FORBIDDEN', errcode = '42501';
  end if;
end $$;

create or replace function jo.staff_json(st jo.staff) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', st.id, 'name', st.name, 'role', st.role, 'discipline', st.discipline,
    'apparatus', st.apparatus, 'components', st.components, 'code_hint', st.code_hint,
    'active', st.active, 'note', st.note, 'created_at', st.created_at, 'last_login_at', st.last_login_at)
$$;

create or replace function jo.log(p_staff uuid, p_action text, p_type text, p_id text, p_detail jsonb default '{}'::jsonb)
returns void language sql volatile set search_path = '' as $$
  insert into jo.audit (staff_id, action, target_type, target_id, detail)
  values (p_staff, p_action, p_type, p_id, coalesce(p_detail, '{}'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- Label klub & wilayah untuk sebuah entri
-- ---------------------------------------------------------------------
create or replace function jo.entry_club_label(p_entry uuid) returns text
language sql stable set search_path = '' as $$
  select coalesce(c.name, 'Perorangan')
  from jo.entries e join jo.submissions s on s.id = e.submission_id
  left join jo.clubs c on c.id = s.club_id
  where e.id = p_entry
$$;

create or replace function jo.entry_region(p_entry uuid) returns text
language sql stable set search_path = '' as $$
  select coalesce(c.kab_kota,
    (select a.kab_kota from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id
      where ea.entry_id = e.id order by a.sort limit 1),
    c.country, 'Tidak diketahui')
  from jo.entries e join jo.submissions s on s.id = e.submission_id
  left join jo.clubs c on c.id = s.club_id
  where e.id = p_entry
$$;

create or replace function jo.entry_athletes_json(p_entry uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'name', a.full_name, 'athlete_no', a.athlete_no, 'gender', a.gender)
      order by a.sort, a.full_name), '[]'::jsonb)
  from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id
  where ea.entry_id = p_entry
$$;

-- ---------------------------------------------------------------------
-- Penilaian: rata-rata terpangkas & nilai per alat
-- ---------------------------------------------------------------------
create or replace function jo.trimmed_mean(v numeric[]) returns numeric
language plpgsql immutable set search_path = '' as $$
declare n integer := coalesce(array_length(v, 1), 0); s numeric := 0; mn numeric; mx numeric; x numeric;
begin
  if n = 0 then return null; end if;
  foreach x in array v loop s := s + x; end loop;
  if n >= 4 then
    select min(u), max(u) into mn, mx from unnest(v) u;
    return round((s - mn - mx) / (n - 2), 3);
  end if;
  return round(s / n, 3);
end $$;

create or replace function jo.apparatus_score(p_entry uuid, p_app text) returns numeric
language plpgsql stable set search_path = '' as $$
declare f numeric; d numeric; e numeric; a numeric; pen numeric; has boolean;
begin
  select value into f from jo.scores
   where entry_id = p_entry and apparatus = p_app and component = 'FINAL'
   order by updated_at desc limit 1;
  if f is not null then return f; end if;
  select jo.trimmed_mean(array_agg(value) filter (where component = 'D')),
         jo.trimmed_mean(array_agg(value) filter (where component = 'E')),
         jo.trimmed_mean(array_agg(value) filter (where component = 'A')),
         jo.trimmed_mean(array_agg(value) filter (where component = 'PEN')),
         bool_or(component in ('D','E','A'))
    into d, e, a, pen, has
    from jo.scores where entry_id = p_entry and apparatus = p_app;
  if not coalesce(has, false) then return null; end if;
  return round(coalesce(d,0) + coalesce(e,0) + coalesce(a,0) - coalesce(pen,0), 3);
end $$;

-- Hasil satu kategori: peringkat serba bisa, nilai per alat, medali, peringkat Priangan
create or replace function jo.category_results(p_cat integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare c jo.categories; places integer; res jsonb;
begin
  select * into c from jo.categories where id = p_cat;
  if c.id is null then return '[]'::jsonb; end if;
  places := coalesce((c.medal_rule->>'places')::integer, 3);

  with e as (
    select en.id, (en.priangan_status = 'disetujui' and not en.team_only) as pri, en.team_only as tonly, en.start_order, en.group_no
    from jo.entries en join jo.submissions s on s.id = en.submission_id
    where en.category_id = p_cat and en.status = 'aktif' and s.status = 'lunas'
  ),
  ap as (select unnest(c.apparatus) as app),
  sc as (
    select e.id, ap.app, jo.apparatus_score(e.id, ap.app) as score from e cross join ap
  ),
  apr as (
    select id, app, score,
      case when score is not null then rank() over (partition by app, (score is null) order by score desc) end as arank
    from sc
  ),
  tot as (
    select id, round(sum(score), 3) as total, count(score) as n_scored,
      jsonb_object_agg(app, score) as scores,
      jsonb_object_agg(app, arank) as app_ranks
    from apr group by id
  ),
  rk as (
    -- anggota "khusus beregu" dinilai tetapi tidak ikut peringkat perorangan
    select e.id, e.pri, e.tonly, e.start_order, e.group_no, t.total, t.n_scored, t.scores, t.app_ranks,
      case when t.total is not null and not e.tonly then rank() over (partition by (t.total is null or e.tonly) order by t.total desc) end as rnk,
      case when e.pri and t.total is not null
           then rank() over (partition by (e.pri and t.total is not null) order by t.total desc) end as prnk
    from e join tot t on t.id = e.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', rk.id,
      'athletes', jo.entry_athletes_json(rk.id),
      'club', jo.entry_club_label(rk.id),
      'region', jo.entry_region(rk.id),
      'start_order', rk.start_order,
      'group_no', rk.group_no,
      'total', rk.total,
      'n_scored', rk.n_scored,
      'scores', rk.scores,
      'app_ranks', rk.app_ranks,
      'rank', rk.rnk,
      'medal', case when c.exhibition or rk.rnk is null or rk.rnk > places then null
                    when rk.rnk = 1 then 'emas' when rk.rnk = 2 then 'perak' else 'perunggu' end,
      'team_only', rk.tonly,
      'priangan', rk.pri,
      'priangan_rank', rk.prnk,
      'priangan_medal', case when c.exhibition or rk.prnk is null or rk.prnk > places then null
                    when rk.prnk = 1 then 'emas' when rk.prnk = 2 then 'perak' else 'perunggu' end
    ) order by rk.rnk nulls last, rk.tonly, rk.start_order nulls last), '[]'::jsonb)
  into res
  from rk;
  return res;
end $$;

-- ---------------------------------------------------------------------
-- Beregu: nama dinormalkan (pencocokan anggota), total serba bisa satu entri,
-- dan peringkat tim per level (4 nilai serba bisa terbaik dari maks. 6 pesenam)
-- ---------------------------------------------------------------------
create or replace function jo.norm_name(t text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(lower(coalesce(t,'')), '[^a-z0-9]+', '', 'g')
$$;

create or replace function jo.entry_total(p_entry uuid) returns numeric
language sql stable set search_path = '' as $$
  select round(sum(jo.apparatus_score(e.id, a)), 3)
    from jo.entries e join jo.categories c on c.id = e.category_id
    cross join lateral unnest(c.apparatus) a
   where e.id = p_entry
$$;

create or replace function jo.team_results(p_disc text, p_level text, p_with_codes boolean default false) returns jsonb
language plpgsql stable set search_path = '' as $$
declare res jsonb; v_count integer := coalesce(jo.setting_int('team_counting'), 4);
begin
  with t as (
    select tm.id, tm.name, tm.submission_id, s.code, coalesce(k.name, 'Perorangan') as club,
           coalesce(k.kab_kota, k.country) as region
      from jo.teams tm join jo.submissions s on s.id = tm.submission_id
      left join jo.clubs k on k.id = s.club_id
     where tm.discipline = p_disc and tm.level = p_level and s.status = 'lunas'
  ),
  m as (
    select x.team_id, x.entry_id, x.athlete_id, x.team_only, x.cert_code, x.sort,
           a.full_name, a.athlete_no, c.name_id as category,
           case when e.status = 'aktif' and es.status = 'lunas' then jo.entry_total(e.id) end as total
      from jo.team_members x
      join jo.entries e on e.id = x.entry_id
      join jo.submissions es on es.id = e.submission_id
      join jo.athletes a on a.id = x.athlete_id
      join jo.categories c on c.id = e.category_id
     where x.team_id in (select id from t)
  ),
  mr as (select m.*, row_number() over (partition by team_id order by total desc nulls last, sort) as rn from m),
  tt as (
    select team_id, round(sum(total) filter (where rn <= v_count and total is not null), 3) as team_total,
           count(total) as n_scored, count(*) as n_members
      from mr group by team_id
  ),
  rk as (
    select t.*, tt.team_total, tt.n_scored, tt.n_members,
      case when tt.team_total is not null then rank() over (partition by (tt.team_total is null) order by tt.team_total desc) end as rnk
      from t join tt on tt.team_id = t.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'team_id', rk.id, 'name', rk.name, 'club', rk.club, 'region', rk.region,
      'submission_id', case when p_with_codes then rk.submission_id end,
      'code', case when p_with_codes then rk.code end,
      'total', rk.team_total, 'rank', rk.rnk, 'trophy', rk.rnk is not null and rk.rnk <= 3,
      'n_scored', rk.n_scored, 'n_members', rk.n_members,
      'members', (select coalesce(jsonb_agg(jsonb_build_object(
          'athlete_id', mr.athlete_id, 'entry_id', mr.entry_id, 'name', mr.full_name, 'athlete_no', mr.athlete_no,
          'category', mr.category, 'team_only', mr.team_only, 'total', mr.total,
          'counted', mr.rn <= v_count and mr.total is not null,
          'cert_code', case when p_with_codes then mr.cert_code end) order by mr.rn), '[]'::jsonb)
        from mr where mr.team_id = rk.id)
    ) order by rk.rnk nulls last, rk.name), '[]'::jsonb)
  into res from rk;
  return res;
end $$;

-- Tabel perolehan medali dari kategori yang sudah dipublikasikan
create or replace function jo.medal_table(p_priangan boolean, p_published_only boolean default true) returns jsonb
language plpgsql stable set search_path = '' as $$
declare r jsonb;
begin
  with rows as (
    select c.discipline, x
    from jo.categories c
    cross join lateral jsonb_array_elements(jo.category_results(c.id)) x
    where c.active and not c.exhibition and (c.results_published or not p_published_only)
  ),
  m as (
    select discipline, x->>'club' as club, x->>'region' as region,
      case when p_priangan then x->>'priangan_medal' else x->>'medal' end as medal
    from rows
  ),
  m2 as (select * from m where medal is not null),
  by_club as (
    select club as label, min(region) as region,
      count(*) filter (where medal = 'emas') as emas,
      count(*) filter (where medal = 'perak') as perak,
      count(*) filter (where medal = 'perunggu') as perunggu,
      count(*) as total
    from m2 group by club
  ),
  by_region as (
    select region as label,
      count(*) filter (where medal = 'emas') as emas,
      count(*) filter (where medal = 'perak') as perak,
      count(*) filter (where medal = 'perunggu') as perunggu,
      count(*) as total
    from m2 group by region
  )
  select jsonb_build_object(
    'by_club', coalesce((select jsonb_agg(to_jsonb(b) order by b.emas desc, b.perak desc, b.perunggu desc, b.label) from by_club b), '[]'::jsonb),
    'by_region', coalesce((select jsonb_agg(to_jsonb(b) order by b.emas desc, b.perak desc, b.perunggu desc, b.label) from by_region b), '[]'::jsonb)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Kode unik pembayaran: total harus unik di antara tagihan yang belum lunas
-- (dan sebisa mungkin juga unik terhadap yang sudah lunas)
-- ---------------------------------------------------------------------
create or replace function jo.pick_unique_code(p_base integer) returns integer
language plpgsql volatile set search_path = '' as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(4242026);
  select g into n from generate_series(1, 999) g
   where not exists (select 1 from jo.submissions s
                      where s.status <> 'dibatalkan' and s.total_amount = p_base + g)
   order by random() limit 1;
  if n is null then
    select g into n from generate_series(1, 999) g
     where not exists (select 1 from jo.submissions s
                        where s.status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan')
                          and s.total_amount = p_base + g)
     order by random() limit 1;
  end if;
  if n is null then
    raise exception 'Kode unik pembayaran habis untuk nominal ini. Hubungi panitia.' using hint = 'ERR_UNIQUE_CODE';
  end if;
  return n;
end $$;

create or replace function jo.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists submissions_touch on jo.submissions;
create trigger submissions_touch before update on jo.submissions
  for each row execute function jo.touch_updated_at();
-- =====================================================================
--  Email: dibuat di database, dikirim oleh Google Apps Script (Gmail)
--  yang mengambil antrean (jo.outbox) secara berkala.
-- =====================================================================

create or replace function jo.h(t text) returns text
language sql immutable set search_path = '' as $$
  select replace(replace(replace(replace(replace(coalesce(t,''),
    '&','&amp;'), '<','&lt;'), '>','&gt;'), '"','&quot;'), '''','&#39;')
$$;

create or replace function jo.tr(l text, id text, en text) returns text
language sql immutable set search_path = '' as $$
  select case when l = 'en' then en else id end
$$;

create or replace function jo.fmt_rp(n integer) returns text
language sql immutable set search_path = '' as $$
  select 'Rp' || replace(to_char(coalesce(n,0), 'FM999,999,999,999'), ',', '.')
$$;

create or replace function jo.site_url() returns text
language sql stable set search_path = '' as $$
  select rtrim(coalesce(jo.setting_text('site_url'), 'https://adjisena-design.github.io/jabar-open/'), '/') || '/'
$$;

create or replace function jo.status_link(p_code text, p_token text) returns text
language sql stable set search_path = '' as $$
  select jo.site_url() || 'status.html?k=' || p_code || '&t=' || p_token
$$;

create or replace function jo.email_layout(p_title text, p_body text, p_lang text) returns text
language sql stable set search_path = '' as $$
  select
  '<!doctype html><html><body style="margin:0;padding:0;background:#f4f6fa;font-family:Arial,Helvetica,sans-serif;color:#34476a">'
  || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6fa;padding:24px 0"><tr><td align="center">'
  || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:10px;overflow:hidden">'
  || '<tr><td style="background:#13284a;padding:22px 28px;color:#ffffff">'
  || '<div style="font-size:13px;color:#e4c87d">' || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || '</div>'
  || '<div style="font-size:21px;font-weight:bold;margin-top:4px">' || jo.h(p_title) || '</div></td></tr>'
  || '<tr><td style="height:4px;background:#e4c87d"></td></tr>'
  || '<tr><td style="padding:26px 28px;font-size:15px;line-height:1.6">' || p_body || '</td></tr>'
  || '<tr><td style="padding:18px 28px;background:#f4f6fa;font-size:12px;color:#5b6b88;line-height:1.5">'
  || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || ' &middot; Gimnastik Indonesia (GI) Jawa Barat<br>'
  || jo.tr(p_lang, 'Pertanyaan: ', 'Questions: ') || jo.h(coalesce(jo.setting_text('contact_email'),'')) || '<br>'
  || case when coalesce(jo.setting_text('pm_email'),'') <> '' then
       jo.tr(p_lang, 'Permintaan khusus atau belum ada balasan: Project Manager, ', 'Special requests or no reply yet: Project Manager, ')
       || jo.h(jo.setting_text('pm_email')) || '<br>' else '' end
  || jo.tr(p_lang, 'Email ini dikirim otomatis. Simpan email ini sebagai bukti pendaftaran.',
                   'This email was sent automatically. Keep it as your registration record.')
  || '</td></tr></table></td></tr></table></body></html>'
$$;

create or replace function jo.email_button(p_url text, p_label text) returns text
language sql immutable set search_path = '' as $$
  select '<p style="margin:22px 0"><a href="' || jo.h(p_url) || '" style="display:inline-block;background:#2c4c7b;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 22px;border-radius:999px">'
    || jo.h(p_label) || '</a></p>'
$$;

-- Ringkasan atlet & kategori untuk email
create or replace function jo.email_roster(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:8px 0 4px">'
    || coalesce(string_agg(
      '<tr><td style="padding:8px 0;border-bottom:1px solid #e2e8f1;vertical-align:top"><b>' || jo.h(a.full_name) || '</b>'
      || '<div style="font-size:13px;color:#5b6b88">' || jo.h(coalesce(a.athlete_no,'')) || '</div></td>'
      || '<td style="padding:8px 0;border-bottom:1px solid #e2e8f1;text-align:right;font-size:13px;vertical-align:top">'
      || coalesce((select string_agg(jo.h(case when p_lang = 'en' then c.name_en else c.name_id end)
                     || case when e.priangan_requested then ' + Priangan' else '' end, '<br>')
                   from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id
                   join jo.categories c on c.id = e.category_id
                   where ea.athlete_id = a.id and e.status <> 'dibatalkan'), '')
      || '</td></tr>', '' order by a.sort), '')
    || '</table>'
  from jo.athletes a where a.submission_id = p_sub
$$;

-- Ringkasan tim beregu untuk email
create or replace function jo.email_team(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<p style="margin:10px 0 2px"><b>' || jo.h(t.name) || '</b> &middot; '
    || jo.h(case when p_lang = 'en' then d.name_en else d.name_id end) || ' ' || jo.h(t.level) || '</p>'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:4px 0">'
    || coalesce((select string_agg(
         '<tr><td style="padding:7px 0;border-bottom:1px solid #e2e8f1"><b>' || jo.h(a.full_name) || '</b>'
         || '<div style="font-size:13px;color:#5b6b88">' || jo.h(coalesce(a.athlete_no,'')) || '</div></td>'
         || '<td style="padding:7px 0;border-bottom:1px solid #e2e8f1;text-align:right;font-size:13px">'
         || case when m.team_only then jo.tr(p_lang,'Khusus beregu','Team only') else jo.tr(p_lang,'Juga perorangan','Also individual') end
         || '<br><span style="color:#5b6b88">' || jo.h(case when p_lang = 'en' then c.name_en else c.name_id end) || '</span></td></tr>', '' order by m.sort)
       from jo.team_members m join jo.athletes a on a.id = m.athlete_id
       join jo.entries e on e.id = m.entry_id join jo.categories c on c.id = e.category_id
       where m.team_id = t.id), '')
    || '</table>'
  from jo.teams t join jo.disciplines d on d.code = t.discipline
  where t.submission_id = p_sub
$$;

create or replace function jo.queue_email(p_sub uuid, p_kind text, p_to text, p_cc text, p_subject text, p_html text)
returns void language sql volatile set search_path = '' as $$
  insert into jo.outbox (kind, submission_id, to_email, cc, subject, html)
  values (p_kind, p_sub, p_to, nullif(p_cc,''), p_subject, p_html);
$$;

create or replace function jo.queue_registration_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; d jo.disciplines; l text; body text; link text;
begin
  select * into s from jo.submissions where id = p_sub;
  select * into d from jo.disciplines where code = s.discipline;
  l := s.lang;
  link := jo.status_link(s.code, s.token);
  body := '<p>' || jo.tr(l, 'Halo ', 'Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l, 'Pendaftaran ', 'Your ')
    || jo.h(case when l = 'en' then d.name_en else d.name_id end)
    || jo.tr(l, ' sudah kami terima. Kode pendaftaran Anda:', ' registration has been received. Your registration code:')
    || '</p><p style="font-size:22px;font-weight:bold;letter-spacing:1px;margin:6px 0 14px">' || jo.h(s.code) || '</p>'
    || case when s.registrant_type = 'beregu' then coalesce(jo.email_team(s.id, l), '') else jo.email_roster(s.id, l) end
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:14px 0;font-size:14px">'
    || '<tr><td style="padding:3px 0">' || case when s.registrant_type = 'beregu' then jo.tr(l,'Biaya beregu (per tim)','Team fee (per team)') else jo.tr(l,'Biaya pendaftaran','Entry fees') end || '</td><td align="right">' || jo.fmt_rp(s.base_amount) || '</td></tr>'
    || case when s.priangan_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kategori Priangan','Priangan category') || '</td><td align="right">' || jo.fmt_rp(s.priangan_amount) || '</td></tr>' else '' end
    || case when s.unique_code > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kode unik','Unique code') || '</td><td align="right">' || jo.fmt_rp(s.unique_code) || '</td></tr>' else '' end
    || '<tr><td style="padding:10px 0 0;font-weight:bold;font-size:16px">' || jo.tr(l,'Total yang harus dibayar','Total to pay') || '</td>'
    || '<td align="right" style="padding:10px 0 0;font-weight:bold;font-size:20px;color:#13284a">' || jo.fmt_rp(s.total_amount) || '</td></tr></table>';
  if s.payment_method = 'qris' then
    body := body || '<p>' || jo.tr(l,
      'Bayar lewat QRIS Jabar Open 2026 yang tampil di halaman status, lalu ketik nominal <b>tepat ',
      'Pay with the Jabar Open 2026 QRIS shown on the status page and type the <b>exact amount ')
      || jo.fmt_rp(s.total_amount) || '</b>. '
      || jo.tr(l,'Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Setelah membayar, unggah bukti pembayaran di halaman status.',
                 'The last three digits are a unique code that matches your payment to this registration. After paying, upload the payment proof on the status page.')
      || '</p>';
  else
    body := body || '<p>' || jo.tr(l,
      'Pendaftaran atlet internasional dibayar terpisah. Panitia akan menghubungi Anda melalui email ini untuk cara pembayaran.',
      'International registrations are paid separately. The committee will contact you at this email with payment instructions.')
      || '</p>';
  end if;
  body := body || jo.email_button(link, jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Batas pembayaran: ','Payment deadline: ')
    || jo.h(coalesce(jo.setting_text('payment_deadline_label'), '12 November 2026')) || '<br>'
    || jo.tr(l,'Simpan tautan di atas. Siapa pun yang memegang tautan ini dapat melihat data pendaftaran Anda.',
               'Keep the link above private. Anyone with it can see your registration details.')
    || '</p>';
  perform jo.queue_email(s.id, 'pendaftaran', s.contact_email, null,
    jo.tr(l,'Pendaftaran diterima — ','Registration received — ') || s.code,
    jo.email_layout(jo.tr(l,'Pendaftaran diterima','Registration received'), body, l));
end $$;

create or replace function jo.queue_paid_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text; cc text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  if coalesce(jo.setting_bool('email_guardians'), true) then
    select string_agg(distinct lower(a.guardian_email), ',') into cc
      from jo.athletes a where a.submission_id = s.id and a.guardian_email is not null
       and lower(a.guardian_email) <> lower(s.contact_email);
  end if;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Pembayaran untuk pendaftaran ','Payment for registration ') || '<b>' || jo.h(s.code) || '</b> '
    || jo.tr(l,'sudah kami verifikasi. Status: <b style="color:#1b8a4b">LUNAS</b>.','has been verified. Status: <b style="color:#1b8a4b">PAID</b>.') || '</p>'
    || case when s.registrant_type = 'beregu' then coalesce(jo.email_team(s.id, l), '') else jo.email_roster(s.id, l) end
    || '<p>' || jo.tr(l,'E-ticket (PDF) untuk setiap atlet dapat diunduh di halaman status. Tidak ada registrasi ulang: cukup datang sesuai jadwal yang diumumkan di Instagram dan situs Jabar Open 2026.',
                      'Each athlete''s e-ticket (PDF) can be downloaded from the status page. There is no on-site check-in: just come at the schedule announced on Instagram and the Jabar Open 2026 website.') || '</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Unduh e-ticket','Download e-tickets'));
  perform jo.queue_email(s.id, 'lunas', s.contact_email, cc,
    jo.tr(l,'Pembayaran lunas — e-ticket ','Payment confirmed — e-tickets ') || s.code,
    jo.email_layout(jo.tr(l,'Pembayaran lunas','Payment confirmed'), body, l));
end $$;

create or replace function jo.queue_fix_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Bukti pembayaran untuk ','The payment proof for ') || '<b>' || jo.h(s.code) || '</b> '
    || jo.tr(l,'belum bisa kami verifikasi. Catatan panitia:','could not be verified yet. Committee note:') || '</p>'
    || '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(coalesce(s.verify_note,'-')) || '</p>'
    || '<p>' || jo.tr(l,'Nominal yang harus dibayar: ','Amount due: ') || '<b>' || jo.fmt_rp(s.total_amount) || '</b>. '
    || jo.tr(l,'Silakan unggah ulang bukti yang benar di halaman status.','Please upload the correct proof on the status page.') || '</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Unggah ulang bukti','Upload proof again'));
  perform jo.queue_email(s.id, 'perbaikan', s.contact_email, null,
    jo.tr(l,'Bukti pembayaran perlu diperbaiki — ','Payment proof needs attention — ') || s.code,
    jo.email_layout(jo.tr(l,'Bukti pembayaran perlu diperbaiki','Payment proof needs attention'), body, l));
end $$;

create or replace function jo.queue_link_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Berikut tautan halaman status untuk pendaftaran ','Here is the status page link for registration ')
    || '<b>' || jo.h(s.code) || '</b>.</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Jika Anda tidak meminta email ini, abaikan saja.','If you did not request this email, you can ignore it.') || '</p>';
  perform jo.queue_email(s.id, 'tautan', s.contact_email, null,
    jo.tr(l,'Tautan status pendaftaran — ','Registration status link — ') || s.code,
    jo.email_layout(jo.tr(l,'Tautan halaman status','Status page link'), body, l));
end $$;

-- ---------------------------------------------------------------------
-- Musik Ritmik: konfirmasi perubahan tautan & permintaan perbaikan berbagi
-- ---------------------------------------------------------------------
create or replace function jo.music_link() returns text
language sql stable set search_path = '' as $$
  select jo.site_url() || 'musik.html'
$$;

create or replace function jo.queue_music_email(p_entry uuid, p_kind text) returns void
language plpgsql volatile set search_path = '' as $$
declare e jo.entries; s jo.submissions; a jo.athletes; c jo.categories; l text; body text; subj text; title text;
begin
  select * into e from jo.entries where id = p_entry;
  select * into s from jo.submissions where id = e.submission_id;
  select a2.* into a from jo.entry_athletes ea join jo.athletes a2 on a2.id = ea.athlete_id where ea.entry_id = e.id limit 1;
  select * into c from jo.categories where id = e.category_id;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>';
  if p_kind = 'musik_perbaiki' then
    title := jo.tr(l,'Tautan musik perlu diperbaiki','Music link needs fixing');
    subj := title || ' — ' || a.full_name;
    body := body || '<p>' || jo.tr(l,'Tautan musik untuk ','The music link for ') || '<b>' || jo.h(a.full_name) || '</b> ('
      || jo.h(case when l = 'en' then c.name_en else c.name_id end) || ') '
      || jo.tr(l,'tidak bisa dibuka panitia. Catatan:','could not be opened by the committee. Note:') || '</p>'
      || '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(coalesce(e.music_note,'-')) || '</p>'
      || '<p>' || jo.tr(l,'Pastikan folder Google Drive dibagikan sebagai <b>"Siapa saja yang memiliki link"</b>, lalu kirim ulang tautannya. Perbaikan ini <b>tidak</b> memakai kesempatan ganti musik.',
                       'Make sure the Google Drive folder is shared as <b>"Anyone with the link"</b>, then submit the link again. Fixing this does <b>not</b> use up the music change.') || '</p>';
  else
    title := jo.tr(l,'Tautan musik diterima','Music link received');
    subj := title || ' — ' || a.full_name;
    body := body || '<p>' || jo.tr(l,'Tautan musik untuk ','The music link for ') || '<b>' || jo.h(a.full_name) || '</b> ('
      || jo.h(case when l = 'en' then c.name_en else c.name_id end) || ') '
      || jo.tr(l,'sudah tersimpan:','has been saved:') || '</p>'
      || '<p style="word-break:break-all"><a href="' || jo.h(e.music_url) || '">' || jo.h(e.music_url) || '</a></p>'
      || '<p>' || case when e.music_changes >= 1
           then jo.tr(l,'Kesempatan ganti musik untuk atlet ini sudah dipakai.','The music change for this athlete has now been used.')
           else jo.tr(l,'Musik dapat diganti satu kali sampai start list kategori ini terbit.','The music can be changed once until this category''s start list is published.') end
      || ' ' || jo.tr(l,'Panitia akan memeriksa bahwa tautan bisa dibuka.','The committee will check that the link opens.') || '</p>';
  end if;
  body := body || jo.email_button(jo.music_link(), jo.tr(l,'Buka halaman musik Ritmik','Open the Rhythmic music page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Kode pendaftaran: ','Registration code: ') || jo.h(s.code) || '</p>';
  perform jo.queue_email(s.id, p_kind, s.contact_email, null, subj, jo.email_layout(title, body, l));
end $$;
-- =====================================================================
--  Fungsi PUBLIK (dipanggil dari situs: pendaftaran, status, hasil)
--  Nama diawali public_ -> boleh dipanggil pengunjung (anon & authenticated)
-- =====================================================================

create or replace function public.public_config() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'event', jsonb_build_object(
      'name', jo.setting_text('event_name'),
      'year', jo.setting_int('event_year'),
      'venue', jo.setting('venue'),
      'contact_email', jo.setting_text('contact_email'),
      'pm_email', jo.setting_text('pm_email'),
      'instagram', jo.setting_text('instagram')),
    'registration', jsonb_build_object(
      'open', coalesce(jo.setting_bool('registration_open'), false)
              and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
      'deadline', jo.setting_text('registration_deadline'),
      'deadline_label', jo.setting_text('payment_deadline_label'),
      'max_athletes', coalesce(jo.setting_int('max_athletes'), 5),
      'priangan_fee', coalesce(jo.setting_int('priangan_fee'), 150000),
      'team_fee', coalesce(jo.setting_int('team_fee'), 650000),
      'team_max', coalesce(jo.setting_int('team_max'), 6),
      'team_counting', coalesce(jo.setting_int('team_counting'), 4),
      'qris_cap', coalesce(jo.setting_int('qris_cap'), 10000000)),
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note')),
    'disciplines', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', d.code, 'name_id', d.name_id, 'name_en', d.name_en,
        'date_start', d.date_start, 'date_end', d.date_end,
        'apparatus', d.apparatus, 'contact_name', d.contact_name, 'contact_phone', d.contact_phone,
        'registration_open', d.registration_open) order by d.sort), '[]'::jsonb) from jo.disciplines d),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'discipline', c.discipline, 'code', c.code, 'level', c.level,
        'age_label', c.age_label, 'division', c.division,
        'name_id', c.name_id, 'name_en', c.name_en, 'gender', c.gender,
        'birth_year_min', c.birth_year_min, 'birth_year_max', c.birth_year_max,
        'entry_type', c.entry_type, 'fee', c.fee, 'apparatus', c.apparatus,
        'max_per_club', c.max_per_club, 'allow_priangan', c.allow_priangan) order by c.sort, c.id), '[]'::jsonb)
        from jo.categories c where c.active),
    'clubs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'kind', k.kind, 'kab_kota', k.kab_kota,
        'province', k.province, 'country', k.country) order by k.name), '[]'::jsonb)
        from jo.clubs k where k.merged_into is null)
  )
$$;

-- ---------------------------------------------------------------------
-- Pendaftaran
-- ---------------------------------------------------------------------
create or replace function jo.valid_drive_url(u text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(trim(u), '') ~* '^https://(drive|docs)\.google\.com/[^\s]+$'
$$;

create or replace function public.public_register(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid       uuid := auth.uid();
  v_disc      jo.disciplines;
  v_type      text := p->>'registrant_type';
  v_contact   jsonb := coalesce(p->'contact', '{}'::jsonb);
  v_max       integer := coalesce(jo.setting_int('max_athletes'), 5);
  v_pri_fee   integer := coalesce(jo.setting_int('priangan_fee'), 150000);
  v_team_fee  integer := coalesce(jo.setting_int('team_fee'), 650000);
  v_team_max  integer := coalesce(jo.setting_int('team_max'), 6);
  v_cap       integer := coalesce(jo.setting_int('qris_cap'), 10000000);
  v_lang      text := case when p->>'lang' = 'en' then 'en' else 'id' end;
  v_club      jo.clubs;
  v_club_id   uuid;
  v_pm        text := 'qris';
  v_sub_id    uuid := gen_random_uuid();
  v_code      text;
  v_token     text := lower(jo.rand_code(28, '23456789abcdefghjkmnpqrstuvwxyz'));
  v_n_ath     integer;
  a           jsonb;
  e           jsonb;
  k           text;
  v_keys      text[] := '{}';
  v_ath_id    uuid;
  v_ath       jo.athletes;
  v_cat       jo.categories;
  v_entry_id  uuid;
  v_eath      text[];
  v_genders   text[];
  v_reason    text;
  v_base      integer := 0;
  v_pri       integer := 0;
  v_uc        integer := 0;
  v_total     integer;
  v_any_minor boolean := false;
  v_cnt       integer;
  v_next      integer;
  v_pri_ok    boolean;
  v_consents  jsonb := coalesce(p->'consents', '{}'::jsonb);
  i           integer := 0;
  -- beregu
  v_team      jsonb := coalesce(p->'team', '{}'::jsonb);
  v_level     text;
  v_tname     text;
  v_team_id   uuid;
  v_seen      uuid[] := '{}';
  v_mname     text;
  v_mbirth    date;
  v_mgender   text;
  v_music     text;
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman lalu coba lagi.' using hint = 'ERR_SESSION';
  end if;

  if (select count(*) from jo.rate_events where uid = v_uid and action = 'register' and at > now() - interval '1 hour') >= 12 then
    raise exception 'Terlalu banyak pendaftaran dari perangkat ini dalam satu jam. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;

  -- Status pendaftaran
  if not coalesce(jo.setting_bool('registration_open'), false)
     or now() > coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()) then
    raise exception 'Pendaftaran sedang ditutup.' using hint = 'ERR_CLOSED';
  end if;

  select * into v_disc from jo.disciplines where code = p->>'discipline';
  if v_disc.code is null then
    raise exception 'Pilih disiplin terlebih dahulu.' using hint = 'ERR_DISCIPLINE';
  end if;
  if not v_disc.registration_open then
    raise exception 'Pendaftaran disiplin % sedang ditutup.', v_disc.name_id using hint = 'ERR_CLOSED';
  end if;

  if v_type not in ('individu','klub','beregu') then
    raise exception 'Pilih jenis pendaftar: perorangan, klub/sekolah, atau beregu.' using hint = 'ERR_TYPE';
  end if;
  if v_type = 'beregu' and v_disc.code not in ('MAG','WAG') then
    raise exception 'Beregu hanya untuk Artistik Putra dan Artistik Putri.' using hint = 'ERR_TEAM';
  end if;

  -- Kontak
  if length(trim(coalesce(v_contact->>'name',''))) < 3 then
    raise exception 'Isi nama penanggung jawab pendaftaran.' using hint = 'ERR_CONTACT_NAME';
  end if;
  if coalesce(v_contact->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Alamat email penanggung jawab tidak valid.' using hint = 'ERR_CONTACT_EMAIL';
  end if;
  if length(regexp_replace(coalesce(v_contact->>'phone',''), '[^0-9]', '', 'g')) < 9 then
    raise exception 'Nomor WhatsApp penanggung jawab tidak valid.' using hint = 'ERR_CONTACT_PHONE';
  end if;

  -- Atlet (perorangan / klub)
  v_n_ath := coalesce(jsonb_array_length(p->'athletes'), 0);
  if v_type <> 'beregu' then
    if v_n_ath < 1 then
      raise exception 'Tambahkan minimal satu atlet.' using hint = 'ERR_NO_ATHLETE';
    end if;
    if v_type = 'individu' and v_n_ath > 1 then
      raise exception 'Pendaftaran perorangan hanya untuk satu atlet. Pilih klub/sekolah untuk mendaftarkan beberapa atlet.' using hint = 'ERR_INDIVIDU_MULTI';
    end if;
    if v_n_ath > v_max then
      raise exception 'Satu pendaftaran maksimal % atlet. Kirim sisanya sebagai pendaftaran terpisah.', v_max using hint = 'ERR_MAX_ATHLETES';
    end if;
  end if;

  -- Klub
  if p->'club'->>'id' is not null then
    select * into v_club from jo.clubs where id = (p->'club'->>'id')::uuid;
    if v_club.id is null then
      raise exception 'Klub yang dipilih tidak ditemukan. Muat ulang halaman.' using hint = 'ERR_CLUB';
    end if;
    if v_club.merged_into is not null then
      select * into v_club from jo.clubs where id = v_club.merged_into;
    end if;
    v_club_id := v_club.id;
  elsif p->'club'->'new' is not null then
    if length(trim(coalesce(p->'club'->'new'->>'name',''))) < 3 then
      raise exception 'Isi nama klub/sekolah.' using hint = 'ERR_CLUB';
    end if;
    if coalesce(p->'club'->'new'->>'country','Indonesia') = 'Indonesia'
       and (coalesce(p->'club'->'new'->>'province','') = '' or coalesce(p->'club'->'new'->>'kab_kota','') = '') then
      raise exception 'Isi provinsi dan kabupaten/kota klub.' using hint = 'ERR_CLUB';
    end if;
    select * into v_club from jo.clubs
     where merged_into is null
       and lower(name) = lower(trim(p->'club'->'new'->>'name'))
       and lower(coalesce(kab_kota,'')) = lower(coalesce(trim(p->'club'->'new'->>'kab_kota'),''))
       and lower(country) = lower(coalesce(p->'club'->'new'->>'country','Indonesia'))
     limit 1;
    if v_club.id is null then
      insert into jo.clubs (name, kind, kab_kota, province, country, created_via)
      values (trim(p->'club'->'new'->>'name'),
              coalesce(nullif(p->'club'->'new'->>'kind',''), 'klub'),
              nullif(trim(coalesce(p->'club'->'new'->>'kab_kota','')),''),
              nullif(trim(coalesce(p->'club'->'new'->>'province','')),''),
              coalesce(nullif(trim(coalesce(p->'club'->'new'->>'country','')),''), 'Indonesia'),
              'pendaftaran')
      returning * into v_club;
    end if;
    v_club_id := v_club.id;
  else
    if v_type in ('klub','beregu') then
      raise exception 'Pilih atau tambahkan klub/sekolah.' using hint = 'ERR_CLUB';
    end if;
    v_club_id := null;
  end if;

  -- Persetujuan
  if not (coalesce((v_consents->>'waiver')::boolean, false)
      and coalesce((v_consents->>'insurance')::boolean, false)
      and coalesce((v_consents->>'data')::boolean, false)
      and coalesce((v_consents->>'rules')::boolean, false)) then
    raise exception 'Centang semua pernyataan persetujuan sebelum mengirim.' using hint = 'ERR_CONSENT';
  end if;

  v_code := 'TMP-' || v_sub_id::text;   -- kode final diberikan setelah semua validasi lolos

  insert into jo.submissions (id, code, token, discipline, registrant_type, contact_name, contact_email,
     contact_phone, contact_role, club_id, payment_method, consents, lang, auth_uid)
  values (v_sub_id, v_code, v_token, v_disc.code, v_type, trim(v_contact->>'name'), lower(trim(v_contact->>'email')),
     trim(v_contact->>'phone'), nullif(trim(coalesce(v_contact->>'role','')),''), v_club_id, 'qris',
     v_consents || jsonb_build_object('at', now()), v_lang, v_uid);

  if v_type = 'beregu' then
    -- =================================================================
    --  BEREGU (Artistik): satu tim, 1–6 pesenam, satu level
    -- =================================================================
    v_level := trim(coalesce(v_team->>'level',''));
    if not exists (select 1 from jo.categories where discipline = v_disc.code and level = v_level and active) then
      raise exception 'Pilih level beregu.' using hint = 'ERR_TEAM_LEVEL';
    end if;
    v_tname := regexp_replace(trim(coalesce(v_team->>'name','')), '\s+', ' ', 'g');
    if length(v_tname) < 2 then
      raise exception 'Isi nama tim.' using hint = 'ERR_TEAM_NAME';
    end if;
    if exists (select 1 from jo.teams t join jo.submissions s on s.id = t.submission_id
                where t.discipline = v_disc.code and t.level = v_level and s.club_id = v_club_id
                  and s.status <> 'dibatalkan' and lower(t.name) = lower(v_tname)) then
      raise exception 'Nama tim "%" sudah dipakai klub ini di % %. Beri nama berbeda, mis. "% B".', v_tname, v_disc.name_id, v_level, v_tname using hint = 'ERR_TEAM_NAME';
    end if;
    v_n_ath := coalesce(jsonb_array_length(v_team->'members'), 0);
    if v_n_ath < 1 or v_n_ath > v_team_max then
      raise exception 'Satu tim berisi 1 sampai % pesenam.', v_team_max using hint = 'ERR_TEAM_SIZE';
    end if;
    v_mgender := case when v_disc.code = 'MAG' then 'M' else 'F' end;

    v_team_id := gen_random_uuid();
    insert into jo.teams (id, submission_id, discipline, level, name) values (v_team_id, v_sub_id, v_disc.code, v_level, v_tname);

    for a in select * from jsonb_array_elements(v_team->'members') loop
      i := i + 1;
      v_mname := trim(coalesce(a->>'full_name',''));
      if length(v_mname) < 3 then
        raise exception 'Anggota %: isi nama lengkap sesuai identitas.', i using hint = 'ERR_ATHLETE_NAME';
      end if;
      if coalesce(a->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$'
         or (a->>'birth_date')::date < date '1950-01-01' or (a->>'birth_date')::date > current_date then
        raise exception 'Anggota %: tanggal lahir tidak valid.', i using hint = 'ERR_ATHLETE_BIRTH';
      end if;
      v_mbirth := (a->>'birth_date')::date;

      -- cari atlet perorangan klub ini di level yang sama
      v_entry_id := null; v_ath_id := null;
      select en.id, at2.id into v_entry_id, v_ath_id
        from jo.athletes at2
        join jo.entry_athletes ea on ea.athlete_id = at2.id
        join jo.entries en on en.id = ea.entry_id
        join jo.categories c on c.id = en.category_id
        join jo.submissions s on s.id = en.submission_id
       where c.discipline = v_disc.code and c.level = v_level and not en.team_only
         and en.status <> 'dibatalkan' and s.status <> 'dibatalkan' and s.club_id = v_club_id
         and at2.birth_date = v_mbirth and jo.norm_name(at2.full_name) = jo.norm_name(v_mname)
       order by en.created_at limit 1;

      if coalesce(a->>'kind','') = 'individu' then
        if v_entry_id is null then
          raise exception 'Anggota %: % (lahir %) belum terdaftar sebagai atlet perorangan % % di klub ini. Daftarkan perorangan dulu, periksa ejaan nama dan tanggal lahir, atau pilih "Khusus beregu".',
            i, v_mname, to_char(v_mbirth, 'DD-MM-YYYY'), v_disc.name_id, v_level using hint = 'ERR_TEAM_MEMBER';
        end if;
        if v_entry_id = any(v_seen) then
          raise exception 'Anggota %: % tercantum dua kali.', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        if exists (select 1 from jo.team_members tm join jo.teams t2 on t2.id = tm.team_id
                    join jo.submissions s2 on s2.id = t2.submission_id
                    where tm.entry_id = v_entry_id and s2.status <> 'dibatalkan') then
          raise exception 'Anggota %: % sudah masuk tim lain di level ini.', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        v_seen := v_seen || v_entry_id;
        insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
        values (v_team_id, v_entry_id, v_ath_id, false, 'B' || jo.rand_code(9), i);

      elsif coalesce(a->>'kind','') = 'tim' then
        if v_entry_id is not null then
          raise exception 'Anggota %: % sudah terdaftar sebagai atlet perorangan di level ini. Pilih "Juga perorangan" untuknya.', i, v_mname using hint = 'ERR_TEAM_MEMBER';
        end if;
        if coalesce(a->>'nationality','WNI') not in ('WNI','WNA') then
          raise exception 'Anggota %: pilih kewarganegaraan.', i using hint = 'ERR_ATHLETE';
        end if;
        if coalesce(a->>'nationality','WNI') = 'WNA' then
          v_pm := 'manual';
          if length(trim(coalesce(a->>'country',''))) < 2 then
            raise exception 'Anggota %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
          end if;
        end if;
        if coalesce(a->>'id_doc_path','') = '' then
          raise exception 'Anggota %: unggah dokumen identitas (KTP / Akte Kelahiran / Ijazah / Paspor).', i using hint = 'ERR_ATHLETE_DOC';
        end if;
        if split_part(a->>'id_doc_path', '/', 1) <> v_uid::text
           or (coalesce(a->>'photo_path','') <> '' and split_part(a->>'photo_path', '/', 1) <> v_uid::text) then
          raise exception 'Berkas unggahan tidak valid. Unggah ulang dokumen.' using hint = 'ERR_UPLOAD';
        end if;
        if jo.is_minor(v_mbirth) then
          v_any_minor := true;
          if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
             or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
             or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
            raise exception 'Anggota %: pesenam di bawah 18 tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i using hint = 'ERR_GUARDIAN';
          end if;
        end if;
        -- kategori usia di level ini (ditentukan dari tanggal lahir)
        v_cat := null;
        select c.* into v_cat from jo.categories c
         where c.discipline = v_disc.code and c.level = v_level and c.active and c.entry_type = 'individual'
           and jo.category_mismatch(c, v_mgender, v_mbirth) is null
         order by (c.id = nullif(a->>'category_id','')::integer) desc, c.sort limit 1;
        if v_cat.id is null then
          raise exception 'Anggota %: tidak ada kelompok usia % % yang sesuai dengan tanggal lahir %.', i, v_disc.name_id, v_level, to_char(v_mbirth, 'DD-MM-YYYY') using hint = 'ERR_ELIGIBILITY';
        end if;
        if v_cat.max_per_club is not null then
          select count(*) into v_cnt
            from jo.entries en join jo.submissions s on s.id = en.submission_id
           where en.category_id = v_cat.id and en.status = 'aktif'
             and s.club_id = v_club_id and s.status <> 'dibatalkan';
          if v_cnt + 1 > v_cat.max_per_club then
            raise exception 'Klub ini sudah mencapai batas % peserta untuk kategori %.', v_cat.max_per_club, v_cat.name_id using hint = 'ERR_CLUB_LIMIT';
          end if;
        end if;
        insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
           id_doc_path, photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
        values (v_sub_id, v_mname, v_mgender, v_mbirth, coalesce(a->>'nationality','WNI'),
           case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
           null, null, a->>'id_doc_path', nullif(a->>'photo_path',''),
           nullif(trim(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
           nullif(lower(trim(coalesce(a->'guardian'->>'email',''))),''), nullif(trim(coalesce(a->'guardian'->>'relation','')),''),
           'T' || jo.rand_code(9), i)
        returning id into v_ath_id;
        insert into jo.entries (submission_id, category_id, fee, team_only)
        values (v_sub_id, v_cat.id, 0, true) returning id into v_entry_id;
        insert into jo.entry_athletes (entry_id, athlete_id, cert_code) values (v_entry_id, v_ath_id, 'C' || jo.rand_code(9));
        insert into jo.team_members (team_id, entry_id, athlete_id, team_only, cert_code, sort)
        values (v_team_id, v_entry_id, v_ath_id, true, 'B' || jo.rand_code(9), i);
      else
        raise exception 'Anggota %: pilih "Juga perorangan" atau "Khusus beregu".', i using hint = 'ERR_TEAM_MEMBER';
      end if;
    end loop;

    if v_any_minor and not coalesce((v_consents->>'guardian')::boolean, false) then
      raise exception 'Persetujuan orang tua/wali wajib dicentang untuk pesenam di bawah 18 tahun.' using hint = 'ERR_CONSENT';
    end if;
    v_base := v_team_fee;

  else
    -- =================================================================
    --  PERORANGAN / KLUB
    -- =================================================================
    for a in select * from jsonb_array_elements(p->'athletes') loop
      i := i + 1;
      k := coalesce(a->>'key', 'a' || i);
      if k = any(v_keys) then
        raise exception 'Data atlet ganda.' using hint = 'ERR_ATHLETE';
      end if;
      v_keys := v_keys || k;

      if length(trim(coalesce(a->>'full_name',''))) < 3 then
        raise exception 'Atlet %: isi nama lengkap sesuai identitas.', i using hint = 'ERR_ATHLETE_NAME';
      end if;
      if coalesce(a->>'gender','') not in ('M','F') then
        raise exception 'Atlet %: pilih jenis kelamin.', i using hint = 'ERR_ATHLETE_GENDER';
      end if;
      if coalesce(a->>'birth_date','') !~ '^\d{4}-\d{2}-\d{2}$'
         or (a->>'birth_date')::date < date '1950-01-01' or (a->>'birth_date')::date > current_date then
        raise exception 'Atlet %: tanggal lahir tidak valid.', i using hint = 'ERR_ATHLETE_BIRTH';
      end if;
      if coalesce(a->>'nationality','WNI') not in ('WNI','WNA') then
        raise exception 'Atlet %: pilih kewarganegaraan.', i using hint = 'ERR_ATHLETE';
      end if;
      if coalesce(a->>'nationality','WNI') = 'WNI' then
        if coalesce(a->>'province','') = '' or coalesce(a->>'kab_kota','') = '' then
          raise exception 'Atlet %: isi provinsi dan kabupaten/kota sesuai alamat di identitas.', i using hint = 'ERR_ATHLETE_ADDRESS';
        end if;
      else
        v_pm := 'manual';
        if length(trim(coalesce(a->>'country',''))) < 2 then
          raise exception 'Atlet %: isi negara asal.', i using hint = 'ERR_ATHLETE_ADDRESS';
        end if;
      end if;
      if coalesce(a->>'id_doc_path','') = '' then
        raise exception 'Atlet %: unggah dokumen identitas (KTP / Akte Kelahiran / Ijazah / Paspor).', i using hint = 'ERR_ATHLETE_DOC';
      end if;
      if split_part(a->>'id_doc_path', '/', 1) <> v_uid::text
         or (coalesce(a->>'photo_path','') <> '' and split_part(a->>'photo_path', '/', 1) <> v_uid::text) then
        raise exception 'Berkas unggahan tidak valid. Unggah ulang dokumen.' using hint = 'ERR_UPLOAD';
      end if;
      if jo.is_minor((a->>'birth_date')::date) then
        v_any_minor := true;
        if length(trim(coalesce(a->'guardian'->>'name',''))) < 3
           or length(regexp_replace(coalesce(a->'guardian'->>'phone',''), '[^0-9]', '', 'g')) < 9
           or coalesce(a->'guardian'->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
          raise exception 'Atlet %: atlet di bawah 18 tahun wajib mencantumkan nama, nomor WhatsApp, dan email orang tua/wali.', i using hint = 'ERR_GUARDIAN';
        end if;
      end if;

      insert into jo.athletes (submission_id, full_name, gender, birth_date, nationality, country, province, kab_kota,
         id_doc_path, photo_path, guardian_name, guardian_phone, guardian_email, guardian_relation, ticket_code, sort)
      values (v_sub_id, trim(a->>'full_name'), a->>'gender', (a->>'birth_date')::date,
         coalesce(a->>'nationality','WNI'),
         case when coalesce(a->>'nationality','WNI') = 'WNI' then 'Indonesia' else trim(a->>'country') end,
         nullif(trim(coalesce(a->>'province','')),''), nullif(trim(coalesce(a->>'kab_kota','')),''),
         a->>'id_doc_path', nullif(a->>'photo_path',''),
         nullif(trim(coalesce(a->'guardian'->>'name','')),''), nullif(trim(coalesce(a->'guardian'->>'phone','')),''),
         nullif(lower(trim(coalesce(a->'guardian'->>'email',''))),''), nullif(trim(coalesce(a->'guardian'->>'relation','')),''),
         'T' || jo.rand_code(9), i)
      returning id into v_ath_id;
      -- simpan pemetaan kunci -> id di tabel sementara (jsonb)
      p := jsonb_set(p, '{_map}', coalesce(p->'_map','{}'::jsonb) || jsonb_build_object(k, v_ath_id));
    end loop;

    if v_any_minor and not coalesce((v_consents->>'guardian')::boolean, false) then
      raise exception 'Persetujuan orang tua/wali wajib dicentang untuk atlet di bawah 18 tahun.' using hint = 'ERR_CONSENT';
    end if;

    -- Entri (nomor lomba)
    if coalesce(jsonb_array_length(p->'entries'), 0) < 1 then
      raise exception 'Pilih kategori lomba untuk setiap atlet.' using hint = 'ERR_NO_ENTRY';
    end if;

    for e in select * from jsonb_array_elements(p->'entries') loop
      select * into v_cat from jo.categories
       where id = nullif(e->>'category_id','')::integer and discipline = v_disc.code and active;
      if v_cat.id is null then
        raise exception 'Kategori yang dipilih tidak tersedia untuk disiplin ini.' using hint = 'ERR_CATEGORY';
      end if;

      select array_agg(x) into v_eath from jsonb_array_elements_text(e->'athletes') x;
      v_eath := coalesce(v_eath, '{}');
      if v_cat.entry_type = 'individual' and array_length(v_eath, 1) is distinct from 1 then
        raise exception 'Kategori % hanya untuk satu atlet.', v_cat.name_id using hint = 'ERR_CATEGORY';
      end if;
      if v_cat.entry_type = 'pair' and (array_length(v_eath, 1) is distinct from 2 or v_eath[1] = v_eath[2]) then
        raise exception 'Kategori % membutuhkan dua atlet (pasangan).', v_cat.name_id using hint = 'ERR_PAIR';
      end if;

      v_genders := '{}';
      v_pri_ok := true;
      foreach k in array v_eath loop
        if (p->'_map'->>k) is null then
          raise exception 'Atlet pada kategori % tidak ditemukan dalam formulir.', v_cat.name_id using hint = 'ERR_ENTRY';
        end if;
        select * into v_ath from jo.athletes where id = (p->'_map'->>k)::uuid;
        v_genders := v_genders || v_ath.gender;
        v_reason := jo.category_mismatch(v_cat, v_ath.gender, v_ath.birth_date);
        if v_reason is not null then
          raise exception '% tidak bisa ikut % (%).', v_ath.full_name, v_cat.name_id, v_reason using hint = 'ERR_ELIGIBILITY';
        end if;
        -- satu atlet tidak boleh dua kali di kategori yang sama
        if exists (select 1 from jo.entry_athletes ea join jo.entries en on en.id = ea.entry_id
                    where ea.athlete_id = v_ath.id and en.category_id = v_cat.id) then
          raise exception '% terdaftar dua kali di kategori %.', v_ath.full_name, v_cat.name_id using hint = 'ERR_DUPLICATE';
        end if;
        -- aturan jumlah nomor per atlet
        if v_disc.code in ('MAG','WAG','RG') then
          if exists (select 1 from jo.entry_athletes ea where ea.athlete_id = v_ath.id) then
            raise exception '% hanya boleh mengikuti satu kategori di disiplin ini.', v_ath.full_name using hint = 'ERR_ONE_CATEGORY';
          end if;
        else
          if exists (select 1 from jo.entry_athletes ea join jo.entries en on en.id = ea.entry_id
                      join jo.categories cc on cc.id = en.category_id
                      where ea.athlete_id = v_ath.id and cc.entry_type = v_cat.entry_type) then
            raise exception '% hanya boleh mengikuti satu nomor perorangan dan satu nomor pasangan.', v_ath.full_name using hint = 'ERR_ONE_CATEGORY';
          end if;
        end if;
        -- kelayakan Priangan: WNI, alamat identitas di Jawa Barat, dan klub di Jawa Barat
        if v_ath.nationality <> 'WNI' or coalesce(v_ath.province,'') <> 'Jawa Barat'
           or (v_club_id is not null and coalesce(v_club.province,'') <> 'Jawa Barat') then
          v_pri_ok := false;
        end if;
      end loop;

      if v_cat.entry_type = 'pair' and v_cat.gender = 'X'
         and not (('M' = any(v_genders)) and ('F' = any(v_genders))) then
        raise exception 'Kategori % adalah pasangan campuran: satu putra dan satu putri.', v_cat.name_id using hint = 'ERR_PAIR';
      end if;

      -- batas peserta per klub per kategori
      if v_club_id is not null and v_cat.max_per_club is not null then
        select count(*) into v_cnt
          from jo.entries en join jo.submissions s on s.id = en.submission_id
         where en.category_id = v_cat.id and en.status = 'aktif'
           and s.club_id = v_club_id and s.status <> 'dibatalkan';
        if v_cnt + 1 > v_cat.max_per_club then
          raise exception 'Klub ini sudah mencapai batas % peserta untuk kategori %.', v_cat.max_per_club, v_cat.name_id using hint = 'ERR_CLUB_LIMIT';
        end if;
      end if;

      if coalesce((e->>'priangan')::boolean, false) then
        if not v_cat.allow_priangan then
          raise exception 'Kategori % tidak membuka penilaian Priangan.', v_cat.name_id using hint = 'ERR_PRIANGAN';
        end if;
        if not v_pri_ok then
          raise exception 'Kategori Priangan hanya untuk atlet WNI dengan alamat identitas di Jawa Barat dan klub di Jawa Barat (%).', v_cat.name_id using hint = 'ERR_PRIANGAN';
        end if;
      end if;

      -- musik Ritmik: tautan Google Drive wajib
      v_music := null;
      if v_disc.code = 'RG' then
        v_music := trim(coalesce(e->>'music_url',''));
        if not jo.valid_drive_url(v_music) then
          raise exception 'Isi tautan Google Drive musik untuk % (diawali https://drive.google.com/).', v_ath.full_name using hint = 'ERR_MUSIC';
        end if;
      end if;

      insert into jo.entries (submission_id, category_id, fee, priangan_requested, priangan_fee, priangan_status,
                              music_url, music_status, music_updated_at)
      values (v_sub_id, v_cat.id, v_cat.fee,
              coalesce((e->>'priangan')::boolean, false),
              case when coalesce((e->>'priangan')::boolean, false) then v_pri_fee else 0 end,
              case when coalesce((e->>'priangan')::boolean, false) then 'menunggu' else 'tidak' end,
              v_music, case when v_music is not null then 'menunggu' else 'tidak_perlu' end,
              case when v_music is not null then now() end)
      returning id into v_entry_id;
      if v_music is not null then
        insert into jo.music_log (entry_id, action, new_url) values (v_entry_id, 'daftar', v_music);
      end if;

      foreach k in array v_eath loop
        insert into jo.entry_athletes (entry_id, athlete_id, cert_code)
        values (v_entry_id, (p->'_map'->>k)::uuid, 'C' || jo.rand_code(9));
      end loop;

      v_base := v_base + v_cat.fee;
      if coalesce((e->>'priangan')::boolean, false) then v_pri := v_pri + v_pri_fee; end if;
    end loop;

    -- setiap atlet harus punya minimal satu nomor
    if exists (select 1 from jo.athletes a where a.submission_id = v_sub_id
                and not exists (select 1 from jo.entry_athletes ea where ea.athlete_id = a.id)) then
      raise exception 'Setiap atlet harus memilih minimal satu kategori.' using hint = 'ERR_NO_ENTRY';
    end if;
  end if;

  -- nomor atlet per disiplin (MAG-001, ...)
  perform pg_advisory_xact_lock(4242027);
  select coalesce(max(nullif(regexp_replace(a.athlete_no, '^.*-', ''), '')::integer), 0)
    into v_next from jo.athletes a where a.athlete_no like v_disc.code || '-%';
  for v_ath in select * from jo.athletes where submission_id = v_sub_id order by sort loop
    v_next := v_next + 1;
    update jo.athletes set athlete_no = v_disc.code || '-' || lpad(v_next::text, 3, '0') where id = v_ath.id;
  end loop;

  -- nominal & kode unik
  if v_pm = 'qris' then
    v_uc := jo.pick_unique_code(v_base + v_pri);
  end if;
  v_total := v_base + v_pri + v_uc;
  if v_pm = 'qris' and v_total > v_cap then
    raise exception 'Total % melebihi batas satu transaksi QRIS (%). Bagi atlet ke dalam dua pendaftaran.',
      jo.fmt_rp(v_total), jo.fmt_rp(v_cap) using hint = 'ERR_QRIS_CAP';
  end if;

  v_code := 'JO26-' || v_disc.code || '-' || lpad(nextval('jo.submission_seq')::text, 4, '0');
  update jo.submissions
     set code = v_code, base_amount = v_base, priangan_amount = v_pri, unique_code = v_uc, total_amount = v_total,
         payment_method = v_pm
   where id = v_sub_id;

  insert into jo.rate_events (uid, action) values (v_uid, 'register');
  perform jo.log(null, 'pendaftaran_baru', 'submission', v_sub_id::text,
    jsonb_build_object('code', v_code, 'athletes', v_n_ath, 'total', v_total, 'type', v_type));
  perform jo.queue_registration_email(v_sub_id);

  return jsonb_build_object(
    'code', v_code, 'token', v_token, 'status', 'menunggu_pembayaran', 'payment_method', v_pm,
    'base_amount', v_base, 'priangan_amount', v_pri, 'unique_code', v_uc, 'total_amount', v_total);
end $$;

-- ---------------------------------------------------------------------
-- Beregu: periksa anggota "juga perorangan" sebelum mengirim
-- ---------------------------------------------------------------------
create or replace function public.public_team_check(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_club uuid; m jsonb; i integer := 0; out jsonb := '[]'::jsonb; v_found boolean; v_in_team boolean; v_e uuid;
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'team_check' and at > now() - interval '1 hour') >= 60 then
    raise exception 'Terlalu banyak pemeriksaan. Coba lagi nanti.' using hint = 'ERR_RATE';
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'team_check');
  v_club := nullif(p->>'club_id','')::uuid;
  if v_club is not null then
    select coalesce(merged_into, id) into v_club from jo.clubs where id = v_club;
  end if;
  for m in select * from jsonb_array_elements(coalesce(p->'members','[]'::jsonb)) loop
    i := i + 1;
    v_e := null;
    if v_club is not null and coalesce(m->>'birth_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
      select en.id into v_e
        from jo.athletes at2
        join jo.entry_athletes ea on ea.athlete_id = at2.id
        join jo.entries en on en.id = ea.entry_id
        join jo.categories c on c.id = en.category_id
        join jo.submissions s on s.id = en.submission_id
       where c.discipline = p->>'discipline' and c.level = p->>'level' and not en.team_only
         and en.status <> 'dibatalkan' and s.status <> 'dibatalkan' and s.club_id = v_club
         and at2.birth_date = (m->>'birth_date')::date and jo.norm_name(at2.full_name) = jo.norm_name(m->>'full_name')
       order by en.created_at limit 1;
    end if;
    v_found := v_e is not null;
    v_in_team := v_found and exists (select 1 from jo.team_members tm join jo.teams t2 on t2.id = tm.team_id
                   join jo.submissions s2 on s2.id = t2.submission_id where tm.entry_id = v_e and s2.status <> 'dibatalkan');
    out := out || jsonb_build_object('i', i, 'found', v_found, 'in_team', v_in_team);
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- Halaman status (akses dengan kode + token dari email)
-- ---------------------------------------------------------------------
create or replace function jo.submission_public_json(s jo.submissions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code', s.code, 'status', s.status, 'discipline', s.discipline,
    'discipline_name_id', d.name_id, 'discipline_name_en', d.name_en,
    'registrant_type', s.registrant_type,
    'contact', jsonb_build_object('name', s.contact_name, 'email', s.contact_email, 'phone', s.contact_phone),
    'club', case when c.id is null then null else jsonb_build_object('name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) end,
    'payment_method', s.payment_method,
    'base_amount', s.base_amount, 'priangan_amount', s.priangan_amount,
    'unique_code', s.unique_code, 'total_amount', s.total_amount,
    'proof_uploaded_at', s.proof_uploaded_at, 'paid_at', s.paid_at,
    'verify_note', case when s.status = 'perlu_perbaikan' then s.verify_note end,
    'created_at', s.created_at,
    'payment', jsonb_build_object(
      'qris_image_url', jo.setting_text('qris_image_url'),
      'qris_merchant', jo.setting_text('qris_merchant'),
      'note', jo.setting_text('payment_note'),
      'deadline_label', jo.setting_text('payment_deadline_label')),
    'signatories', jo.setting('signatories'),
    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'athlete_no', a.athlete_no, 'full_name', a.full_name, 'gender', a.gender,
        'birth_date', a.birth_date, 'nationality', a.nationality, 'province', a.province, 'kab_kota', a.kab_kota,
        'doc_status', a.doc_status,
        'ticket_code', case when s.status = 'lunas' then a.ticket_code end
      ) order by a.sort), '[]'::jsonb) from jo.athletes a where a.submission_id = s.id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', en.id, 'category_id', cat.id, 'category_name_id', cat.name_id, 'category_name_en', cat.name_en,
        'level', cat.level, 'age_label', cat.age_label, 'apparatus', cat.apparatus,
        'fee', en.fee, 'priangan_requested', en.priangan_requested, 'priangan_status', en.priangan_status,
        'status', en.status, 'team_only', en.team_only,
        'music_url', en.music_url, 'music_status', en.music_status, 'music_note', en.music_note,
        'music_changes', en.music_changes, 'startlist_published', cat.startlist_published,
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
    'team', (select jsonb_build_object(
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
             where r->>'team_id' = t.id::text limit 1) end)
      from jo.teams t left join jo.team_levels tl on tl.discipline = t.discipline and tl.level = t.level
      where t.submission_id = s.id)
  )
  from jo.disciplines d left join jo.clubs c on c.id = s.club_id
  where d.code = s.discipline
$$;

create or replace function public.public_get_submission(p_code text, p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare s jo.submissions;
begin
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan. Periksa kembali tautan dari email Anda.' using hint = 'ERR_NOT_FOUND';
  end if;
  return jo.submission_public_json(s);
end $$;

create or replace function public.public_attach_proof(p_code text, p_token text, p_path text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  select * into s from jo.submissions where code = upper(trim(p_code)) and token = trim(p_token);
  if s.id is null then
    raise exception 'Pendaftaran tidak ditemukan.' using hint = 'ERR_NOT_FOUND';
  end if;
  if s.status not in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan') then
    raise exception 'Pendaftaran ini sudah tidak menunggu pembayaran.' using hint = 'ERR_STATUS';
  end if;
  if split_part(coalesce(p_path,''), '/', 1) <> v_uid::text then
    raise exception 'Berkas unggahan tidak valid. Unggah ulang.' using hint = 'ERR_UPLOAD';
  end if;
  update jo.submissions
     set proof_path = p_path, proof_uploaded_at = now(), status = 'menunggu_verifikasi'
   where id = s.id;
  perform jo.log(null, 'bukti_bayar_diunggah', 'submission', s.id::text, jsonb_build_object('code', s.code));
  select * into s from jo.submissions where id = s.id;
  return jo.submission_public_json(s);
end $$;

create or replace function public.public_resend_link(p_code text, p_email text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; v_uid uuid := auth.uid();
begin
  if (select count(*) from jo.rate_events where action = 'resend' and (uid = v_uid or v_uid is null)
        and at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('ok', true);
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'resend');
  select * into s from jo.submissions
   where code = upper(trim(p_code)) and lower(contact_email) = lower(trim(p_email));
  if s.id is not null
     and not exists (select 1 from jo.outbox o where o.submission_id = s.id and o.kind = 'tautan'
                      and o.created_at > now() - interval '10 minutes') then
    perform jo.queue_link_email(s.id);
  end if;
  -- jawaban selalu sama agar tidak bisa dipakai menebak data
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Statistik, daftar start, hasil, medali, verifikasi QR
-- ---------------------------------------------------------------------
create or replace function public.public_stats() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status <> 'dibatalkan'),
    'athletes_paid', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.status = 'lunas'),
    'clubs', (select count(distinct s.club_id) from jo.submissions s where s.status <> 'dibatalkan' and s.club_id is not null),
    'regions', (select count(distinct coalesce(c.kab_kota, a.kab_kota, a.country))
                  from jo.athletes a join jo.submissions s on s.id = a.submission_id
                  left join jo.clubs c on c.id = s.club_id where s.status <> 'dibatalkan'),
    'by_discipline', (select coalesce(jsonb_object_agg(d.code, (
        select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
         where s.status <> 'dibatalkan' and s.discipline = d.code)), '{}'::jsonb) from jo.disciplines d)
  )
$$;

create or replace function public.public_startlist(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category_id', c.id, 'discipline', c.discipline, 'name_id', c.name_id, 'name_en', c.name_en, 'level', c.level,
    'age_label', c.age_label, 'apparatus', c.apparatus, 'exhibition', c.exhibition,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'start_order', en.start_order, 'group_no', en.group_no,
        'session', ses.name, 'day', ses.day, 'start_time', ses.start_time,
        'athletes', jo.entry_athletes_json(en.id), 'team_only', en.team_only,
        'club', jo.entry_club_label(en.id), 'region', jo.entry_region(en.id))
        order by ses.sort nulls last, ses.day nulls last, ses.start_time nulls last, en.group_no nulls last, en.start_order nulls last), '[]'::jsonb)
      from jo.entries en join jo.submissions s on s.id = en.submission_id
      left join jo.sessions ses on ses.id = en.session_id
      where en.category_id = c.id and en.status = 'aktif' and s.status = 'lunas')
  ) order by c.sort, c.id), '[]'::jsonb)
  from jo.categories c
  where c.startlist_published and c.active and (p_discipline is null or c.discipline = p_discipline)
$$;

create or replace function public.public_results(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category_id', c.id, 'discipline', c.discipline, 'name_id', c.name_id, 'name_en', c.name_en,
    'level', c.level, 'age_label', c.age_label, 'apparatus', c.apparatus,
    'exhibition', c.exhibition, 'published_at', c.results_published_at,
    'results', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(jo.category_results(c.id)) x
                 where not coalesce((x->>'team_only')::boolean, false))
  ) order by c.sort, c.id), '[]'::jsonb)
  from jo.categories c
  where c.results_published and c.active and (p_discipline is null or c.discipline = p_discipline)
$$;

create or replace function public.public_medal_table(p_priangan boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jo.medal_table(coalesce(p_priangan, false), true)
$$;

create or replace function public.public_verify(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v text := upper(trim(coalesce(p_code,''))); a jo.athletes; s jo.submissions; ea jo.entry_athletes;
        en jo.entries; c jo.categories; r jsonb; club text;
begin
  select * into a from jo.athletes where ticket_code = v;
  if a.id is not null then
    select * into s from jo.submissions where id = a.submission_id;
    select coalesce(k.name, 'Perorangan') into club from jo.submissions x left join jo.clubs k on k.id = x.club_id where x.id = s.id;
    return jsonb_build_object('type', 'ticket', 'valid', s.status = 'lunas', 'status', s.status,
      'athlete_no', a.athlete_no, 'name', a.full_name, 'club', club, 'discipline', s.discipline,
      'categories', (select jsonb_agg(cc.name_id) from jo.entry_athletes x join jo.entries e on e.id = x.entry_id
                     join jo.categories cc on cc.id = e.category_id where x.athlete_id = a.id and e.status <> 'dibatalkan'));
  end if;
  -- sertifikat juara beregu
  declare tm jo.team_members; tt jo.teams; ts jo.submissions; tr jsonb; tpub boolean;
  begin
    select * into tm from jo.team_members where cert_code = v;
    if tm.team_id is not null then
      select * into tt from jo.teams where id = tm.team_id;
      select * into ts from jo.submissions where id = tt.submission_id;
      select coalesce(published, false) into tpub from jo.team_levels where discipline = tt.discipline and level = tt.level;
      if not coalesce(tpub, false) or ts.status <> 'lunas' then
        return jsonb_build_object('type', 'team_certificate', 'valid', false);
      end if;
      select x into tr from jsonb_array_elements(jo.team_results(tt.discipline, tt.level, false)) x where x->>'team_id' = tt.id::text;
      select * into a from jo.athletes where id = tm.athlete_id;
      return jsonb_build_object('type', 'team_certificate', 'valid', coalesce((tr->>'trophy')::boolean, false),
        'name', a.full_name, 'athlete_no', a.athlete_no, 'team', tt.name, 'club', tr->>'club',
        'discipline', tt.discipline, 'level', tt.level, 'rank', tr->'rank', 'total', tr->'total');
    end if;
  end;
  select * into ea from jo.entry_athletes where cert_code = v;
  if ea.entry_id is not null then
    select * into en from jo.entries where id = ea.entry_id;
    select * into c from jo.categories where id = en.category_id;
    select * into a from jo.athletes where id = ea.athlete_id;
    select * into s from jo.submissions where id = en.submission_id;
    if not c.results_published or s.status <> 'lunas' then
      return jsonb_build_object('type', 'certificate', 'valid', false);
    end if;
    select x into r from jsonb_array_elements(jo.category_results(c.id)) x where x->>'entry_id' = en.id::text;
    return jsonb_build_object('type', 'certificate', 'valid', true,
      'name', a.full_name, 'athlete_no', a.athlete_no, 'club', r->>'club', 'region', r->>'region',
      'category_id', c.id, 'category_name_id', c.name_id, 'category_name_en', c.name_en, 'discipline', c.discipline,
      'rank', r->'rank', 'medal', r->'medal', 'total', r->'total',
      'priangan', r->'priangan', 'priangan_rank', r->'priangan_rank', 'priangan_medal', r->'priangan_medal');
  end if;
  return jsonb_build_object('type', null, 'valid', false);
end $$;


-- ---------------------------------------------------------------------
-- Musik Ritmik: lihat & ganti tautan (kode pendaftaran + email)
-- ---------------------------------------------------------------------
create or replace function jo.music_json(s jo.submissions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'code', s.code, 'contact_name', s.contact_name, 'status', s.status,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'athlete_name', a.full_name, 'athlete_no', a.athlete_no,
        'category_name_id', c.name_id, 'category_name_en', c.name_en, 'apparatus', c.apparatus,
        'music_url', e.music_url, 'music_status', e.music_status, 'music_note', e.music_note,
        'music_changes', e.music_changes, 'music_updated_at', e.music_updated_at,
        'startlist_published', c.startlist_published,
        'can_fill', e.music_url is null and not c.scores_locked,
        'can_fix', e.music_url is not null and e.music_status = 'tidak_bisa' and not c.scores_locked,
        'can_change', e.music_url is not null and e.music_status <> 'tidak_bisa' and e.music_changes < 1 and not c.startlist_published
      ) order by a.sort), '[]'::jsonb)
      from jo.entries e join jo.categories c on c.id = e.category_id
      join jo.entry_athletes ea on ea.entry_id = e.id join jo.athletes a on a.id = ea.athlete_id
      where e.submission_id = s.id and e.status <> 'dibatalkan' and c.discipline = 'RG')
  )
$$;

create or replace function jo.music_auth(p_code text, p_email text) returns jo.submissions
language plpgsql volatile set search_path = '' as $$
declare v_uid uuid := auth.uid(); s jo.submissions;
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'music' and at > now() - interval '1 hour') >= 30 then
    raise exception 'Terlalu banyak percobaan. Coba lagi dalam satu jam.' using hint = 'ERR_RATE';
  end if;
  insert into jo.rate_events (uid, action) values (v_uid, 'music');
  select * into s from jo.submissions
   where code = upper(trim(coalesce(p_code,''))) and lower(contact_email) = lower(trim(coalesce(p_email,'')))
     and discipline = 'RG' and status <> 'dibatalkan';
  if s.id is null then
    raise exception 'Kode pendaftaran Ritmik dan email penanggung jawab tidak cocok.' using hint = 'ERR_NOT_FOUND';
  end if;
  return s;
end $$;

create or replace function public.public_music_lookup(p_code text, p_email text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions;
begin
  s := jo.music_auth(p_code, p_email);
  return jo.music_json(s);
end $$;

create or replace function public.public_music_set(p_code text, p_email text, p_entry uuid, p_url text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare s jo.submissions; e jo.entries; c jo.categories; v_url text := trim(coalesce(p_url,'')); v_action text;
begin
  s := jo.music_auth(p_code, p_email);
  select * into e from jo.entries where id = p_entry and submission_id = s.id and status <> 'dibatalkan' for update;
  if e.id is null then raise exception 'Atlet tidak ditemukan di pendaftaran ini.' using hint = 'ERR_NOT_FOUND'; end if;
  select * into c from jo.categories where id = e.category_id;
  if c.discipline <> 'RG' then raise exception 'Tautan musik hanya untuk Ritmik.'; end if;
  if not jo.valid_drive_url(v_url) then
    raise exception 'Tautan harus dari Google Drive (diawali https://drive.google.com/).' using hint = 'ERR_MUSIC';
  end if;
  if e.music_url is null then
    v_action := 'isi';
  elsif e.music_status = 'tidak_bisa' then
    v_action := 'perbaiki';
  else
    v_action := 'ganti';
    if c.startlist_published then
      raise exception 'Batas ganti musik sudah lewat: start list kategori ini sudah terbit. Hubungi narahubung Ritmik.' using hint = 'ERR_MUSIC_CLOSED';
    end if;
    if e.music_changes >= 1 then
      raise exception 'Musik atlet ini sudah pernah diganti. Kesempatan ganti hanya satu kali.' using hint = 'ERR_MUSIC_USED';
    end if;
    if v_url = e.music_url then
      raise exception 'Tautan baru sama dengan tautan sekarang.' using hint = 'ERR_MUSIC';
    end if;
  end if;
  if v_action <> 'ganti' and c.scores_locked then
    raise exception 'Nilai kategori ini sudah dikunci; musik tidak bisa diubah lagi.' using hint = 'ERR_MUSIC_CLOSED';
  end if;
  update jo.entries set music_url = v_url, music_status = 'menunggu', music_note = null, music_updated_at = now(),
    music_changes = music_changes + case when v_action = 'ganti' then 1 else 0 end,
    music_checked_by = null, music_checked_at = null
   where id = e.id;
  insert into jo.music_log (entry_id, action, old_url, new_url) values (e.id, v_action, e.music_url, v_url);
  perform jo.log(null, 'musik_' || v_action, 'entry', e.id::text, jsonb_build_object('code', s.code, 'old', e.music_url, 'new', v_url));
  perform jo.queue_music_email(e.id, 'musik_diterima');
  return jo.music_json(s);
end $$;

-- ---------------------------------------------------------------------
-- Hasil beregu yang sudah dipublikasikan
-- ---------------------------------------------------------------------
create or replace function public.public_team_results(p_discipline text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'discipline', tl.discipline, 'level', tl.level, 'published_at', tl.published_at,
    'results', jo.team_results(tl.discipline, tl.level, false)
  ) order by tl.discipline, (select min(c.sort) from jo.categories c where c.discipline = tl.discipline and c.level = tl.level)), '[]'::jsonb)
  from jo.team_levels tl
  where tl.published and (p_discipline is null or tl.discipline = p_discipline)
$$;

-- ---------------------------------------------------------------------
-- Antrean email untuk Google Apps Script (diamankan dengan secret)
-- ---------------------------------------------------------------------
create or replace function public.outbox_claim(p_secret text, p_limit integer default 20) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r jsonb;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  insert into jo.settings (key, value) values ('outbox_last_poll', to_jsonb(now()))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  with picked as (
    select id from jo.outbox
     where (status = 'pending')
        or (status = 'sending' and claimed_at < now() - interval '10 minutes')
        or (status = 'error' and attempts < 5 and claimed_at < now() - interval '15 minutes')
     order by id limit greatest(1, least(coalesce(p_limit, 20), 50))
     for update skip locked
  ), upd as (
    update jo.outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
      from picked where o.id = picked.id
    returning o.id, o.to_email, o.cc, o.subject, o.html
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'to', to_email, 'cc', cc, 'subject', subject, 'html', html) order by id), '[]'::jsonb)
    into r from upd;
  return r;
end $$;

create or replace function public.outbox_report(p_secret text, p_results jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; n integer := 0;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if coalesce((x->>'ok')::boolean, false) then
      update jo.outbox set status = 'sent', sent_at = now(), last_error = null where id = (x->>'id')::bigint;
    elsif coalesce((x->>'release')::boolean, false) then
      -- belum dicoba (mis. kuota harian Gmail habis): kembalikan ke antrean tanpa menambah percobaan
      update jo.outbox set status = 'pending', attempts = greatest(attempts - 1, 0), last_error = left(coalesce(x->>'error',''), 500)
       where id = (x->>'id')::bigint;
    else
      update jo.outbox set status = 'error', last_error = left(coalesce(x->>'error','tidak diketahui'), 500)
       where id = (x->>'id')::bigint;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('updated', n);
end $$;
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
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; d text; is_super boolean;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
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
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter, '{}'::jsonb); q text; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
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
        'music_url', e.music_url, 'music_status', e.music_status, 'music_note', e.music_note,
        'music_changes', e.music_changes, 'music_updated_at', e.music_updated_at,
        'music_checked_by', (select name from jo.staff where id = e.music_checked_by), 'music_checked_at', e.music_checked_at,
        'music_log', (select coalesce(jsonb_agg(jsonb_build_object('at', ml.at, 'action', ml.action, 'old_url', ml.old_url, 'new_url', ml.new_url,
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
  update jo.entries set category_id = c_new.id, session_id = null, group_no = null, start_order = null where id = e.id;
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
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; f jsonb := coalesce(p_filter,'{}'::jsonb); d text; q text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
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
                         || case when e.priangan_requested then ' [Priangan: ' || e.priangan_status || ']' else '' end, '; ' order by cat.sort)
         from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id join jo.categories cat on cat.id = e.category_id
        where ea.athlete_id = a.id and e.status <> 'dibatalkan') as categories,
      a.id_doc_path, a.photo_path
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
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
  d := coalesce(st.discipline, nullif(p_discipline,''));
  return jsonb_build_object(
    'disciplines', (select coalesce(jsonb_agg(to_jsonb(x) order by x.sort), '[]'::jsonb) from jo.disciplines x where d is null or x.code = d),
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
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
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
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
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
  st := jo.require_staff(array['owner','superadmin','admin','juri']);
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
  st := jo.require_staff(array['owner','superadmin','admin']);
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
  st := jo.require_staff(array['owner','superadmin','admin']);
  return jo.medal_table(coalesce(p_priangan,false), coalesce(p_published_only,true));
end $$;

create or replace function public.console_score_log(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'at', l.at, 'action', l.action, 'apparatus', l.apparatus, 'component', l.component,
      'old_value', l.old_value, 'new_value', l.new_value, 'reason', l.reason,
      'judge', (select name from jo.staff where id = l.judge_id),
      'changed_by', (select name from jo.staff where id = l.changed_by),
      'category', c.name_id, 'discipline', c.discipline,
      'athletes', jo.entry_athletes_json(l.entry_id)) order by l.at desc), '[]'::jsonb)
    from jo.score_log l left join jo.entries e on e.id = l.entry_id left join jo.categories c on c.id = e.category_id
    where (nullif(p_filter->>'category_id','') is null or c.id = (p_filter->>'category_id')::integer)
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
      e.music_url, e.music_status, e.music_note, e.music_changes, e.music_updated_at,
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
  if e.music_url is null then raise exception 'Belum ada tautan musik untuk diperiksa.'; end if;
  if not p_ok and length(trim(coalesce(p_note,''))) < 3 then
    raise exception 'Tulis apa masalahnya (mis. folder belum dibagikan, file kosong). Catatan dikirim ke pendaftar.';
  end if;
  update jo.entries set music_status = case when p_ok then 'ok' else 'tidak_bisa' end,
    music_note = case when p_ok then null else trim(p_note) end, music_checked_by = st.id, music_checked_at = now()
   where id = e.id;
  insert into jo.music_log (entry_id, action, new_url, staff_id, note)
  values (e.id, case when p_ok then 'ok' else 'tidak_bisa' end, e.music_url, st.id, nullif(trim(coalesce(p_note,'')),''));
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
  st := jo.require_staff(array['owner','superadmin','admin']);
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
      array_position(array['owner','superadmin','admin','juri'], x.role), x.discipline nulls first, x.name), '[]'::jsonb)
    from jo.staff x);
end $$;

create or replace function public.console_staff_create(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_code text; v_role text := p->>'role'; x jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  if v_role not in ('superadmin','admin','juri') then raise exception 'Peran tidak dikenal.'; end if;
  if v_role = 'superadmin' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa membuat kode superadmin.'; end if;
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama pemegang kode.'; end if;
  if nullif(p->>'discipline','') is not null and not exists (select 1 from jo.disciplines where code = p->>'discipline') then
    raise exception 'Disiplin tidak dikenal.';
  end if;
  v_code := jo.new_staff_code();
  insert into jo.staff (name, role, discipline, apparatus, components, code_hash, code_hint, note, created_by)
  values (trim(p->>'name'), v_role, nullif(p->>'discipline',''),
    case when jsonb_typeof(p->'apparatus') = 'array' and jsonb_array_length(p->'apparatus') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'apparatus') a) end,
    case when jsonb_typeof(p->'components') = 'array' and jsonb_array_length(p->'components') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'components') a) end,
    jo.sha256(jo.norm_code(v_code)), right(v_code, 4), nullif(trim(coalesce(p->>'note','')),''), st.id)
  returning * into x;
  perform jo.log(st.id, 'kode_dibuat', 'staff', x.id::text, jsonb_build_object('name', x.name, 'role', x.role, 'discipline', x.discipline));
  return jsonb_build_object('staff', jo.staff_json(x), 'code', v_code);
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
    note = case when p ? 'note' then nullif(trim(p->>'note'),'') else note end
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
  st := jo.require_staff(array['owner','superadmin']);
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
      'staff', (select name from jo.staff where id = l.staff_id), 'target_type', l.target_type,
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
-- =====================================================================
--  Data awal: disiplin, kategori (Undangan 06/10/2026), pengaturan
--  'on conflict do nothing' -> perubahan dari konsol tidak tertimpa
-- =====================================================================

insert into jo.disciplines (code, name_id, name_en, date_start, date_end, apparatus, components, contact_name, contact_phone, sort) values
  ('MAG', 'Artistik Putra', 'Men''s Artistic', '2026-12-12', '2026-12-15', '[{"code": "FX", "id": "Lantai", "en": "Floor"}, {"code": "PH", "id": "Kuda Pelana", "en": "Pommel Horse"}, {"code": "SR", "id": "Gelang-gelang", "en": "Rings"}, {"code": "VT", "id": "Meja Lompat", "en": "Vault"}, {"code": "PB", "id": "Palang Sejajar", "en": "Parallel Bars"}, {"code": "HB", "id": "Palang Tunggal", "en": "High Bar"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Pengurangan netral", "en": "Neutral deductions"}]'::jsonb, 'Fegie Rizkia Mulyana', '0811-2348-753', 1),
  ('WAG', 'Artistik Putri', 'Women''s Artistic', '2026-12-12', '2026-12-15', '[{"code": "VT", "id": "Meja Lompat", "en": "Vault"}, {"code": "UB", "id": "Palang Bertingkat", "en": "Uneven Bars"}, {"code": "BB", "id": "Balok Keseimbangan", "en": "Balance Beam"}, {"code": "FX", "id": "Lantai", "en": "Floor"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Pengurangan netral", "en": "Neutral deductions"}]'::jsonb, 'Vicy Ayu', '0856-2383-455', 2),
  ('RG', 'Ritmik', 'Rhythmic', '2026-12-16', '2026-12-18', '[{"code": "FH", "id": "Tanpa Alat (Floor)", "en": "Freehand"}, {"code": "ROPE", "id": "Tali", "en": "Rope"}, {"code": "HOOP", "id": "Simpai", "en": "Hoop"}, {"code": "BALL", "id": "Bola", "en": "Ball"}, {"code": "CLUBS", "id": "Gada", "en": "Clubs"}, {"code": "RIBBON", "id": "Pita", "en": "Ribbon"}]'::jsonb, '[{"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "A", "id": "Nilai A (artistik)", "en": "A score (artistry)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "PEN", "id": "Penalti", "en": "Penalties"}]'::jsonb, 'Yuanita Vidya M', '0815-6361-1403', 3),
  ('AER', 'Aerobik', 'Aerobic', '2026-12-19', '2026-12-20', '[{"code": "RTN", "id": "Rangkaian", "en": "Routine"}]'::jsonb, '[{"code": "A", "id": "Nilai A (artistik)", "en": "A score (artistry)"}, {"code": "E", "id": "Nilai E (eksekusi)", "en": "E score (execution)"}, {"code": "D", "id": "Nilai D (kesulitan)", "en": "D score (difficulty)"}, {"code": "PEN", "id": "Penalti", "en": "Penalties"}]'::jsonb, 'Mustika Fitri', '0816-605-281', 4)
on conflict (code) do nothing;

insert into jo.categories (discipline, code, level, age_label, division, name_id, name_en, gender, birth_year_min, birth_year_max, entry_type, fee, apparatus, max_per_club, sort, note) values
  ('MAG', 'MAG-L1-A', 'Level 1', '6 tahun ke bawah', null, 'Artistik Putra Level 1 (6 tahun ke bawah)', 'Men''s Artistic Level 1 (6 & under)', 'M', 2020, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 10, null),
  ('MAG', 'MAG-L1-B', 'Level 1', '7–8 tahun', null, 'Artistik Putra Level 1 (7–8 tahun)', 'Men''s Artistic Level 1 (7–8)', 'M', 2018, 2019, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 20, null),
  ('MAG', 'MAG-L1-C', 'Level 1', '9 tahun ke atas', null, 'Artistik Putra Level 1 (9 tahun ke atas)', 'Men''s Artistic Level 1 (9 & over)', 'M', null, 2017, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 30, null),
  ('MAG', 'MAG-L2-A', 'Level 2', '7 tahun ke bawah', null, 'Artistik Putra Level 2 (7 tahun ke bawah)', 'Men''s Artistic Level 2 (7 & under)', 'M', 2019, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 40, null),
  ('MAG', 'MAG-L2-B', 'Level 2', '8–9 tahun', null, 'Artistik Putra Level 2 (8–9 tahun)', 'Men''s Artistic Level 2 (8–9)', 'M', 2017, 2018, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 50, null),
  ('MAG', 'MAG-L2-C', 'Level 2', '10 tahun ke atas', null, 'Artistik Putra Level 2 (10 tahun ke atas)', 'Men''s Artistic Level 2 (10 & over)', 'M', null, 2016, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 60, null),
  ('MAG', 'MAG-L3', 'Level 3', 'Usia terbuka', null, 'Artistik Putra Level 3 (usia terbuka)', 'Men''s Artistic Level 3 (open age)', 'M', null, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 70, null),
  ('MAG', 'MAG-L4', 'Level 4', 'Usia terbuka', null, 'Artistik Putra Level 4 (usia terbuka)', 'Men''s Artistic Level 4 (open age)', 'M', null, null, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 80, null),
  ('MAG', 'MAG-JR', 'Junior', '12–16 tahun', null, 'Artistik Putra Junior (12–16 tahun)', 'Men''s Artistic Junior (12–16)', 'M', 2010, 2014, 'individual', 750000, array['FX','PH','SR','VT','PB','HB']::text[], 10, 90, null),
  ('WAG', 'WAG-L1-A', 'Level 1', '6 tahun ke bawah', null, 'Artistik Putri Level 1 (6 tahun ke bawah)', 'Women''s Artistic Level 1 (6 & under)', 'F', 2020, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 100, null),
  ('WAG', 'WAG-L1-B', 'Level 1', '7–8 tahun', null, 'Artistik Putri Level 1 (7–8 tahun)', 'Women''s Artistic Level 1 (7–8)', 'F', 2018, 2019, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 110, null),
  ('WAG', 'WAG-L1-C', 'Level 1', '9 tahun ke atas', null, 'Artistik Putri Level 1 (9 tahun ke atas)', 'Women''s Artistic Level 1 (9 & over)', 'F', null, 2017, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 120, null),
  ('WAG', 'WAG-L2-A', 'Level 2', '6 tahun ke bawah', null, 'Artistik Putri Level 2 (6 tahun ke bawah)', 'Women''s Artistic Level 2 (6 & under)', 'F', 2020, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 130, null),
  ('WAG', 'WAG-L2-B', 'Level 2', '7–8 tahun', null, 'Artistik Putri Level 2 (7–8 tahun)', 'Women''s Artistic Level 2 (7–8)', 'F', 2018, 2019, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 140, null),
  ('WAG', 'WAG-L2-C', 'Level 2', '9 tahun ke atas', null, 'Artistik Putri Level 2 (9 tahun ke atas)', 'Women''s Artistic Level 2 (9 & over)', 'F', null, 2017, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 150, null),
  ('WAG', 'WAG-L3-A', 'Level 3', '9 tahun ke bawah', null, 'Artistik Putri Level 3 (9 tahun ke bawah)', 'Women''s Artistic Level 3 (9 & under)', 'F', 2017, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 160, null),
  ('WAG', 'WAG-L3-B', 'Level 3', '10 tahun ke atas', null, 'Artistik Putri Level 3 (10 tahun ke atas)', 'Women''s Artistic Level 3 (10 & over)', 'F', null, 2016, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 170, null),
  ('WAG', 'WAG-L4-A', 'Level 4', '11 tahun ke bawah', null, 'Artistik Putri Level 4 (11 tahun ke bawah)', 'Women''s Artistic Level 4 (11 & under)', 'F', 2015, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 180, null),
  ('WAG', 'WAG-L4-B', 'Level 4', '12 tahun ke atas', null, 'Artistik Putri Level 4 (12 tahun ke atas)', 'Women''s Artistic Level 4 (12 & over)', 'F', null, 2014, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 190, null),
  ('WAG', 'WAG-L5-A', 'Level 5', '12 tahun ke bawah', null, 'Artistik Putri Level 5 (12 tahun ke bawah)', 'Women''s Artistic Level 5 (12 & under)', 'F', 2014, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 200, null),
  ('WAG', 'WAG-L5-B', 'Level 5', '13 tahun ke atas', null, 'Artistik Putri Level 5 (13 tahun ke atas)', 'Women''s Artistic Level 5 (13 & over)', 'F', null, 2013, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 210, null),
  ('WAG', 'WAG-L6-A', 'Level 6', '12 tahun ke bawah', null, 'Artistik Putri Level 6 (12 tahun ke bawah)', 'Women''s Artistic Level 6 (12 & under)', 'F', 2014, null, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 220, null),
  ('WAG', 'WAG-L6-B', 'Level 6', '13 tahun ke atas', null, 'Artistik Putri Level 6 (13 tahun ke atas)', 'Women''s Artistic Level 6 (13 & over)', 'F', null, 2013, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 230, null),
  ('WAG', 'WAG-PJ', 'Pre Junior', '11–13 tahun', null, 'Artistik Putri Pre Junior (11–13 tahun)', 'Women''s Artistic Pre Junior (11–13)', 'F', 2013, 2015, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 240, null),
  ('WAG', 'WAG-JR', 'Junior', '14–15 tahun', null, 'Artistik Putri Junior (14–15 tahun)', 'Women''s Artistic Junior (14–15)', 'F', 2011, 2012, 'individual', 750000, array['VT','UB','BB','FX']::text[], 10, 250, null),
  ('RG', 'RG-A-KU56', 'KU 5–6', 'Kelahiran 2020–2021', 'Profesional', 'Ritmik Profesional KU 5–6', 'Rhythmic Professional KU 5–6', 'F', 2020, 2021, 'individual', 750000, array['FH','BALL']::text[], null, 260, null),
  ('RG', 'RG-A-KU78', 'KU 7–8', 'Kelahiran 2018–2019', 'Profesional', 'Ritmik Profesional KU 7–8', 'Rhythmic Professional KU 7–8', 'F', 2018, 2019, 'individual', 750000, array['FH','HOOP']::text[], null, 270, null),
  ('RG', 'RG-A-KU910', 'KU 9–10', 'Kelahiran 2016–2017', 'Profesional', 'Ritmik Profesional KU 9–10', 'Rhythmic Professional KU 9–10', 'F', 2016, 2017, 'individual', 750000, array['FH','HOOP','BALL']::text[], null, 280, null),
  ('RG', 'RG-A-KU1112', 'KU 11–12', 'Kelahiran 2014–2015', 'Profesional', 'Ritmik Profesional KU 11–12', 'Rhythmic Professional KU 11–12', 'F', 2014, 2015, 'individual', 750000, array['FH','BALL','CLUBS']::text[], null, 290, null),
  ('RG', 'RG-A-JR', 'Junior', 'Kelahiran 2012–2013', 'Profesional', 'Ritmik Profesional Junior', 'Rhythmic Professional Junior', 'F', 2012, 2013, 'individual', 750000, array['HOOP','BALL','CLUBS','RIBBON']::text[], null, 300, null),
  ('RG', 'RG-B-KU56', 'KU 5–6', 'Kelahiran 2020–2021', 'Amatir', 'Ritmik Amatir KU 5–6', 'Rhythmic Amateur KU 5–6', 'F', 2020, 2021, 'individual', 750000, array['FH','BALL']::text[], null, 310, null),
  ('RG', 'RG-B-KU78', 'KU 7–8', 'Kelahiran 2018–2019', 'Amatir', 'Ritmik Amatir KU 7–8', 'Rhythmic Amateur KU 7–8', 'F', 2018, 2019, 'individual', 750000, array['FH','HOOP']::text[], null, 320, null),
  ('RG', 'RG-B-KU910', 'KU 9–10', 'Kelahiran 2016–2017', 'Amatir', 'Ritmik Amatir KU 9–10', 'Rhythmic Amateur KU 9–10', 'F', 2016, 2017, 'individual', 750000, array['FH','HOOP','BALL']::text[], null, 330, null),
  ('RG', 'RG-B-KU1112', 'KU 11–12', 'Kelahiran 2014–2015', 'Amatir', 'Ritmik Amatir KU 11–12', 'Rhythmic Amateur KU 11–12', 'F', 2014, 2015, 'individual', 750000, array['FH','BALL','CLUBS']::text[], null, 340, null),
  ('RG', 'RG-B-JR', 'Junior', 'Kelahiran 2012–2013', 'Amatir', 'Ritmik Amatir Junior', 'Rhythmic Amateur Junior', 'F', 2012, 2013, 'individual', 750000, array['HOOP','BALL','CLUBS','RIBBON']::text[], null, 350, null),
  ('AER', 'AER-JR-IM', 'Junior', '15–17 tahun', null, 'Aerobik Junior Perorangan Putra (IM)', 'Aerobic Junior Individual Men (IM)', 'M', 2009, 2011, 'individual', 300000, array['RTN']::text[], 4, 360, null),
  ('AER', 'AER-JR-IW', 'Junior', '15–17 tahun', null, 'Aerobik Junior Perorangan Putri (IW)', 'Aerobic Junior Individual Women (IW)', 'F', 2009, 2011, 'individual', 300000, array['RTN']::text[], 4, 370, null),
  ('AER', 'AER-JR-MP', 'Junior', '15–17 tahun', null, 'Aerobik Junior Pasangan Campuran (MP)', 'Aerobic Junior Mixed Pair (MP)', 'X', 2009, 2011, 'pair', 400000, array['RTN']::text[], 4, 380, null),
  ('AER', 'AER-YT-IM', 'Youth', '12–14 tahun', null, 'Aerobik Youth Perorangan Putra (IM)', 'Aerobic Youth Individual Men (IM)', 'M', 2012, 2014, 'individual', 300000, array['RTN']::text[], 4, 390, null),
  ('AER', 'AER-YT-IW', 'Youth', '12–14 tahun', null, 'Aerobik Youth Perorangan Putri (IW)', 'Aerobic Youth Individual Women (IW)', 'F', 2012, 2014, 'individual', 300000, array['RTN']::text[], 4, 400, null),
  ('AER', 'AER-YT-MP', 'Youth', '12–14 tahun', null, 'Aerobik Youth Pasangan Campuran (MP)', 'Aerobic Youth Mixed Pair (MP)', 'X', 2012, 2014, 'pair', 400000, array['RTN']::text[], 4, 410, null),
  ('AER', 'AER-ND-IM', 'National Development', '9–11 tahun', null, 'Aerobik National Development Perorangan Putra (IM)', 'Aerobic National Development Individual Men (IM)', 'M', 2015, 2017, 'individual', 300000, array['RTN']::text[], 4, 420, null),
  ('AER', 'AER-ND-IW', 'National Development', '9–11 tahun', null, 'Aerobik National Development Perorangan Putri (IW)', 'Aerobic National Development Individual Women (IW)', 'F', 2015, 2017, 'individual', 300000, array['RTN']::text[], 4, 430, null),
  ('AER', 'AER-PND-IM', 'Pre National Development', '6–8 tahun', null, 'Aerobik Pre National Development Perorangan Putra (IM)', 'Aerobic Pre National Development Individual Men (IM)', 'M', 2018, 2020, 'individual', 300000, array['RTN']::text[], 4, 440, null),
  ('AER', 'AER-PND-IW', 'Pre National Development', '6–8 tahun', null, 'Aerobik Pre National Development Perorangan Putri (IW)', 'Aerobic Pre National Development Individual Women (IW)', 'F', 2018, 2020, 'individual', 300000, array['RTN']::text[], 4, 450, null)
on conflict (code) do nothing;

insert into jo.settings (key, value) values
  ('event_name', '"Jabar Open 2026"'::jsonb),
  ('event_year', '2026'::jsonb),
  ('site_url', '"https://adjisena-design.github.io/jabar-open/"'::jsonb),
  ('registration_open', 'true'::jsonb),
  ('registration_deadline', '"2026-11-12T23:59:59+07:00"'::jsonb),
  ('payment_deadline_label', '"12 November 2026"'::jsonb),
  ('priangan_fee', '150000'::jsonb),
  ('qris_cap', '10000000'::jsonb),
  ('max_athletes', '5'::jsonb),
  ('qris_image_url', 'null'::jsonb),
  ('qris_merchant', '"Jabar Open 2026"'::jsonb),
  ('payment_note', '"Scan QRIS dengan aplikasi bank atau dompet digital apa pun, lalu ketik nominal persis seperti tertera (termasuk tiga digit kode unik)."'::jsonb),
  ('contact_email', '"jabaropen2026@gmail.com"'::jsonb),
  ('pm_email', '"adjisena.daffa@gmail.com"'::jsonb),
  ('team_fee', '650000'::jsonb),
  ('team_max', '6'::jsonb),
  ('team_counting', '4'::jsonb),
  ('instagram', '"gimnastikjabar"'::jsonb),
  ('email_guardians', 'true'::jsonb),
  ('venue', '{"name": "Gymnasium Arcamanik", "address": "Jl. Pacuan Kuda No. 15b, Sukamiskin, Arcamanik, Kota Bandung, Jawa Barat 40231"}'::jsonb),
  ('signatories', '[{"name": "Andi Juliandi", "title": "Ketua Pelaksana Jabar Open 2026"}, {"name": "Dika Chrisna Irzandi, S.A.B., M.B.A", "title": "Ketua Gimnastik Indonesia (GI) Jawa Barat"}]'::jsonb)
on conflict (key) do nothing;
-- =====================================================================
--  Penyesuaian data untuk instalasi yang sudah berjalan (aman diulang)
-- =====================================================================
-- v3: email kontak resmi pindah ke jabaropen2026@gmail.com, PM tetap tercantum
update jo.settings set value = '"jabaropen2026@gmail.com"'::jsonb, updated_at = now()
 where key = 'contact_email' and value = '"adjisena.daffa@gmail.com"'::jsonb;
-- =====================================================================
--  Penyimpanan berkas (Supabase Storage)
--   dokumen : identitas & foto atlet (privat)
--   bukti   : bukti pembayaran (privat)
--   publik  : gambar QRIS & aset yang boleh dilihat siapa saja
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('dokumen', 'dokumen', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('bukti',   'bukti',   false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('publik',  'publik',  true,  5242880, array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Dipakai oleh aturan storage: apakah pengguna sesi ini panitia dengan peran tertentu?
create or replace function public.jo_is_staff(p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from jo.staff s join jo.staff_sessions ss on ss.staff_id = s.id
     where ss.uid = auth.uid() and ss.expires_at > now() and s.active and s.role = any(p_roles))
$$;

drop policy if exists "jo: unggah ke folder sendiri" on storage.objects;
create policy "jo: unggah ke folder sendiri" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('dokumen','bukti') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "jo: baca unggahan sendiri" on storage.objects;
create policy "jo: baca unggahan sendiri" on storage.objects
  for select to authenticated
  using (bucket_id in ('dokumen','bukti') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "jo: panitia baca dokumen" on storage.objects;
create policy "jo: panitia baca dokumen" on storage.objects
  for select to authenticated
  using (bucket_id in ('dokumen','bukti') and public.jo_is_staff(array['owner','superadmin','admin']));

drop policy if exists "jo: superadmin unggah publik" on storage.objects;
create policy "jo: superadmin unggah publik" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'publik' and public.jo_is_staff(array['owner','superadmin']));

drop policy if exists "jo: superadmin baca publik" on storage.objects;
create policy "jo: superadmin baca publik" on storage.objects
  for select to authenticated
  using (bucket_id = 'publik' and public.jo_is_staff(array['owner','superadmin']));

-- =====================================================================
--  Hak eksekusi fungsi
--   public_*  & outbox_* : pengunjung (anon) dan pengguna sesi (authenticated)
--   console_* & jo_*     : hanya pengguna sesi (authenticated); hak dicek di dalam fungsi
--   skema jo             : tertutup sepenuhnya
-- =====================================================================
revoke all on all tables in schema jo from public;
revoke all on all sequences in schema jo from public;
revoke all on all functions in schema jo from public;
do $$ begin
  execute 'revoke all on all tables in schema jo from anon, authenticated';
  execute 'revoke all on all sequences in schema jo from anon, authenticated';
  execute 'revoke all on all functions in schema jo from anon, authenticated';
exception when others then null; end $$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname like 'public\_%' or p.proname like 'console\_%'
            or p.proname like 'outbox\_%' or p.proname like 'jo\_%')
  loop
    execute format('revoke all on function %s from public', f.sig);
    begin
      execute format('revoke all on function %s from anon, authenticated', f.sig);
    exception when others then null; end;
    if f.proname like 'public\_%' or f.proname like 'outbox\_%' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    else
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- =====================================================================
--  Setup pertama: membuat kode OWNER dan secret email (sekali saja)
-- =====================================================================
create or replace function jo.bootstrap(p_owner_name text) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_code text; v_secret text; r jsonb := '{}'::jsonb;
begin
  if not exists (select 1 from jo.staff where role = 'owner') then
    v_code := jo.new_staff_code();
    insert into jo.staff (name, role, code_hash, code_hint, note)
    values (p_owner_name, 'owner', jo.sha256(jo.norm_code(v_code)), right(v_code, 4), 'Dibuat saat setup');
    r := r || jsonb_build_object('kode_owner', v_code);
  else
    r := r || jsonb_build_object('kode_owner', 'sudah dibuat sebelumnya (tidak ditampilkan lagi)');
  end if;
  if jo.setting_text('outbox_secret_hash') is null then
    v_secret := jo.rand_code(32, '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ');
    insert into jo.settings (key, value) values ('outbox_secret_hash', to_jsonb(jo.sha256(v_secret)))
    on conflict (key) do update set value = excluded.value;
    r := r || jsonb_build_object('secret_email', v_secret);
  else
    r := r || jsonb_build_object('secret_email', 'sudah dibuat sebelumnya (ganti lewat konsol bila perlu)');
  end if;
  return r;
end $$;
revoke all on function jo.bootstrap(text) from public;

notify pgrst, 'reload schema';

-- Baris terakhir: tampilkan kode owner & secret email. SIMPAN keduanya.
select jo.bootstrap('Daffa Adjisena') as hasil_setup;
