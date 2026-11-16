-- =====================================================================
--  KONSOL JURI (/juri/) — penilaian dari lembar kertas, verifikasi,
--  PUBLIC LIVE VIEW, dan simulasi DUMMY.  (16 November 2026)
--
--  Alur nilai:
--    juri menulis di lembar kertas
--    -> Asisten Juri (asjur) mengetik per juri (D, E1..En, A.., PEN) dan "Kirim"
--    -> Verifikator Nilai memeriksa: Verifikasi / Kembalikan / Ubah
--    -> nilai terverifikasi langsung tayang di live.html (tidak resmi)
--    -> TD mengonfirmasi hasil resmi: PDF hasil + publikasi medali (hasil.html)
--
--  Mode:
--    real  : data sungguhan; nilai terverifikasi juga ditulis ke jo.scores (FINAL)
--            sehingga hasil resmi (jo.category_results) memakai nilai yang sama.
--    dummy : simulasi; tidak pernah menyentuh jo.scores / start list asli.
--            Dihapus lewat tombol saat keluar, atau otomatis setelah 2 jam tanpa aktivitas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Peran & kode akses
-- ---------------------------------------------------------------------
alter table jo.staff drop constraint if exists staff_role_check;
alter table jo.staff add constraint staff_role_check check (role in
  ('owner','superadmin','admin','td','juri','pemantau','bendahara','asjur','verifikator'));
alter table jo.staff add column if not exists disc_group text;          -- ART | RG | AER ; null = semua
alter table jo.staff add column if not exists is_dummy boolean not null default false;
alter table jo.staff drop constraint if exists staff_disc_group_check;
alter table jo.staff add constraint staff_disc_group_check check (disc_group is null or disc_group in ('ART','RG','AER'));
alter table jo.staff_sessions add column if not exists disc_group text;  -- kotak yang dipilih saat masuk /juri/
alter table jo.staff_sessions add column if not exists console text;     -- 'juri' bila masuk dari /juri/

alter table jo.categories add column if not exists td_confirmed_at timestamptz;
alter table jo.categories add column if not exists td_confirmed_by uuid;
alter table jo.categories add column if not exists td_pdf_at timestamptz;

-- ---------------------------------------------------------------------
-- Panel juri: slot isian per disiplin / kategori / alat (bisa tambah-kurang E, dst.)
--   slots: [{key:'E1', comp:'E', label:'E1'}, ...]   comp: D | E | A | PEN
--   e_mode: 'score' (isi nilai E) | 'deduction' (isi pengurangan; E = e_base - rata-rata)
-- ---------------------------------------------------------------------
create table if not exists jo.judge_panels (
  id          serial primary key,
  discipline  text not null references jo.disciplines(code),
  category_id integer references jo.categories(id) on delete cascade,
  apparatus   text,
  slots       jsonb not null,
  e_mode      text not null default 'score' check (e_mode in ('score','deduction')),
  e_base      numeric(6,3) not null default 10,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table jo.judge_panels add column if not exists runs integer not null default 1;
alter table jo.judge_panels add column if not exists sheet text not null default 'standar';
alter table jo.judge_panels drop constraint if exists judge_panels_runs_check;
alter table jo.judge_panels add constraint judge_panels_runs_check check (runs between 1 and 3);
alter table jo.judge_panels drop constraint if exists judge_panels_sheet_check;
alter table jo.judge_panels add constraint judge_panels_sheet_check check (sheet in ('standar','artistik'));
create unique index if not exists judge_panels_uq on jo.judge_panels (discipline, coalesce(category_id, 0), coalesce(apparatus, ''));

insert into jo.judge_panels (discipline, slots)
select d, s::jsonb from (values
  ('MAG', '[{"key":"D","comp":"D","label":"D"},{"key":"E1","comp":"E","label":"E1"},{"key":"E2","comp":"E","label":"E2"},{"key":"E3","comp":"E","label":"E3"},{"key":"PEN","comp":"PEN","label":"Pen"}]'),
  ('WAG', '[{"key":"D","comp":"D","label":"D"},{"key":"E1","comp":"E","label":"E1"},{"key":"E2","comp":"E","label":"E2"},{"key":"E3","comp":"E","label":"E3"},{"key":"PEN","comp":"PEN","label":"Pen"}]'),
  ('RG',  '[{"key":"D","comp":"D","label":"D"},{"key":"A1","comp":"A","label":"A1"},{"key":"A2","comp":"A","label":"A2"},{"key":"E1","comp":"E","label":"E1"},{"key":"E2","comp":"E","label":"E2"},{"key":"PEN","comp":"PEN","label":"Pen"}]'),
  ('AER', '[{"key":"A1","comp":"A","label":"A1"},{"key":"A2","comp":"A","label":"A2"},{"key":"E1","comp":"E","label":"E1"},{"key":"E2","comp":"E","label":"E2"},{"key":"D","comp":"D","label":"D"},{"key":"PEN","comp":"PEN","label":"Pen"}]')
) v(d, s)
where not exists (select 1 from jo.judge_panels p where p.discipline = v.d and p.category_id is null and p.apparatus is null);

-- ---------------------------------------------------------------------
-- Lembar nilai digital (satu baris = satu atlet x satu alat x satu mode)
-- ---------------------------------------------------------------------
create table if not exists jo.jscores (
  id           bigserial primary key,
  mode         text not null default 'real' check (mode in ('real','dummy')),
  entry_id     uuid not null references jo.entries(id) on delete cascade,
  apparatus    text not null,
  slots        jsonb not null default '{}'::jsonb,
  d            numeric(7,3),
  e            numeric(7,3),
  a            numeric(7,3),
  pen          numeric(7,3),
  total        numeric(7,3),
  status       text not null default 'draft' check (status in ('draft','submitted','returned','verified')),
  note         text,
  entered_by   uuid,
  entered_at   timestamptz,
  submitted_at timestamptz,
  verified_by  uuid,
  verified_at  timestamptz,
  updated_at   timestamptz not null default now(),
  unique (mode, entry_id, apparatus)
);
create index if not exists jscores_status_idx on jo.jscores (mode, status);
alter table jo.jscores add column if not exists flags jsonb not null default '[]'::jsonb;

-- Lembar Artistik (form kertas): D1/D2, E1–E3, Rerata (otomatis), Pinalti, Nilai Akhir (otomatis);
-- Meja Lompat: 2 lompatan, nilai alat = rata-rata Nilai Akhir kedua lompatan
update jo.judge_panels set sheet = 'artistik' where discipline in ('MAG','WAG') and sheet = 'standar' and category_id is null and apparatus is null;
insert into jo.judge_panels (discipline, apparatus, slots, runs, sheet)
select p.discipline, 'VT', p.slots, 2, 'artistik' from jo.judge_panels p
 where p.discipline in ('MAG','WAG') and p.category_id is null and p.apparatus is null
   and not exists (select 1 from jo.judge_panels x where x.discipline = p.discipline and x.category_id is null and x.apparatus = 'VT');

create table if not exists jo.jscore_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  mode      text not null,
  jscore_id bigint,
  entry_id  uuid,
  apparatus text,
  action    text not null,
  old_val   jsonb,
  new_val   jsonb,
  by_staff  uuid,
  reason    text
);
create index if not exists jscore_log_entry_idx on jo.jscore_log (entry_id);

-- Start list simulasi (dummy): urutan sendiri tanpa menyentuh start list asli
create table if not exists jo.sim_order (
  category_id integer not null references jo.categories(id) on delete cascade,
  entry_id    uuid not null references jo.entries(id) on delete cascade,
  group_no    integer,
  start_order integer,
  primary key (category_id, entry_id)
);

-- Layar (TV di venue & tampilan publik)
create table if not exists jo.live_screens (
  id          serial primary key,
  mode        text not null default 'real' check (mode in ('real','dummy')),
  name        text not null,
  category_id integer references jo.categories(id) on delete set null,
  view        text not null default 'aa' check (view in ('aa','app','rotate')),
  apparatus   text,
  layout      integer not null default 1 check (layout between 1 and 3),
  cam1        text,
  cam2        text,
  first_n     integer not null default 6 check (first_n between 3 and 14),
  next_n      integer not null default 10 check (next_n between 3 and 14),
  page_secs   integer not null default 8 check (page_secs between 4 and 60),
  active      boolean not null default false,
  sort        integer not null default 0,
  vkey        text not null default jo.rand_code(10),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

-- ---------------------------------------------------------------------
-- Pembantu
-- ---------------------------------------------------------------------
create or replace function jo.disc_group_of(p_disc text) returns text
language sql immutable set search_path = '' as $$
  select case when p_disc in ('MAG','WAG') then 'ART' else p_disc end
$$;

create or replace function jo.group_discs(p_group text) returns text[]
language sql immutable set search_path = '' as $$
  select case p_group when 'ART' then array['MAG','WAG'] when 'RG' then array['RG'] when 'AER' then array['AER']
              else array['MAG','WAG','RG','AER'] end
$$;

-- Batas disiplin: kolom discipline (lama) dan disc_group (konsol juri)
create or replace function jo.check_discipline(st jo.staff, p_disc text) returns void
language plpgsql stable set search_path = '' as $$
begin
  if st.role in ('admin','td','juri','pemantau','asjur','verifikator') and st.discipline is not null and st.discipline <> p_disc then
    raise exception 'Kode akses Anda hanya untuk disiplin %.', st.discipline using hint = 'ERR_FORBIDDEN', errcode = '42501';
  end if;
  if st.disc_group is not null and jo.disc_group_of(p_disc) <> st.disc_group then
    raise exception 'Kode akses Anda hanya untuk disiplin %.',
      case st.disc_group when 'ART' then 'Artistik' when 'RG' then 'Ritmik' else 'Aerobik' end using hint = 'ERR_FORBIDDEN', errcode = '42501';
  end if;
end $$;

create or replace function jo.staff_json(st jo.staff) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', st.id, 'name', st.name, 'role', st.role, 'discipline', st.discipline,
    'apparatus', st.apparatus, 'components', st.components, 'code_hint', st.code_hint,
    'active', st.active, 'note', st.note, 'created_at', st.created_at, 'last_login_at', st.last_login_at, 'phone', st.phone,
    'access_windows', st.access_windows, 'window', jo.staff_window(st),
    'disc_group', st.disc_group, 'is_dummy', st.is_dummy)
$$;

-- Kirim sinyal ke semua layar live (Supabase Realtime, kanal publik "jo-live")
create or replace function jo.live_ping(p_mode text default 'real') returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform realtime.send(jsonb_build_object('mode', p_mode, 't', extract(epoch from now())), 'tick', 'jo-live', false);
exception when others then null;   -- sinyal gagal tidak boleh menggagalkan penyimpanan nilai
end $$;

-- Panel yang berlaku untuk satu kategori + alat
create or replace function jo.panel_for(p_cat integer, p_app text) returns jo.judge_panels
language sql stable set search_path = '' as $$
  select p.* from jo.judge_panels p join jo.categories c on c.id = p_cat
   where p.discipline = c.discipline
     and (p.category_id is null or p.category_id = c.id)
     and (p.apparatus is null or p.apparatus = p_app)
   order by (p.category_id is not null) desc, (p.apparatus is not null) desc
   limit 1
$$;

-- Hitung D/E/A/PEN/total dari slot. D, E, A = rata-rata (>=4 juri: buang tertinggi & terendah);
-- PEN = jumlah. Mode 'deduction': E = e_base - rata-rata pengurangan.
create or replace function jo.calc_slots(p jo.judge_panels, s jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
-- D, E, A = rata-rata isian komponennya (>=4 isian: tertinggi & terendah dibuang); PEN = jumlah.
-- Mode 'deduction': E = e_base - rata-rata pengurangan.
-- Lembar 'artistik': E disebut Rerata dan Nilai Akhir = D + Rerata - Pinalti; keduanya otomatis tetapi boleh
-- diisi manual (kunci RERATA / AKHIR) dan setiap isian manual dicatat sebagai flag.
-- runs > 1 (Meja Lompat): kunci lompatan ke-2 diberi akhiran @2; nilai alat = rata-rata Nilai Akhir semua lompatan.
declare r integer; nruns integer := greatest(coalesce(p.runs, 1), 1); sfx text; sl jsonb; v numeric; ov numeric;
  dv numeric[]; ev numeric[]; av numeric[]; pv numeric[]; have_r integer;
  d numeric; e_auto numeric; e numeric; a numeric; pen numeric; ak_auto numeric; ak numeric;
  runs jsonb := '[]'::jsonb; flags jsonb := '[]'::jsonb; n_have integer := 0; n_need integer := 0;
  sd numeric := 0; se numeric := 0; sa numeric := 0; sp numeric := 0; st numeric := 0; nr integer := 0;
  any_a boolean := false; any_d boolean := false; any_e boolean := false;
begin
  for r in 1..nruns loop
    sfx := case when r = 1 then '' else '@' || r end;
    dv := null; ev := null; av := null; pv := null; have_r := 0;
    for sl in select * from jsonb_array_elements(coalesce(p.slots, '[]'::jsonb)) loop
      if sl->>'comp' <> 'PEN' then n_need := n_need + 1; end if;
      v := nullif(s->>((sl->>'key') || sfx), '')::numeric;
      if v is null then continue; end if;
      n_have := n_have + 1; have_r := have_r + 1;
      case sl->>'comp'
        when 'D' then dv := dv || v; when 'E' then ev := ev || v;
        when 'A' then av := av || v; when 'PEN' then pv := pv || v; else null;
      end case;
    end loop;
    d := jo.trimmed_mean(dv); a := jo.trimmed_mean(av); e_auto := jo.trimmed_mean(ev);
    if e_auto is not null and p.e_mode = 'deduction' then e_auto := round(p.e_base - e_auto, 3); end if;
    pen := coalesce((select round(sum(x), 3) from unnest(pv) x), 0);
    e := e_auto;
    if p.sheet = 'artistik' then
      ov := nullif(s->>('RERATA' || sfx), '')::numeric;
      if ov is not null then
        e := ov; have_r := have_r + 1;
        flags := flags || jsonb_build_object('field', 'RERATA', 'run', r, 'auto', e_auto, 'manual', ov);
      end if;
    end if;
    ak_auto := case when have_r = 0 then null else round(coalesce(d,0) + coalesce(e,0) + coalesce(a,0) - pen, 3) end;
    ak := ak_auto;
    if p.sheet = 'artistik' then
      ov := nullif(s->>('AKHIR' || sfx), '')::numeric;
      if ov is not null then
        ak := ov;
        flags := flags || jsonb_build_object('field', 'AKHIR', 'run', r, 'auto', ak_auto, 'manual', ov);
      end if;
    end if;
    runs := runs || jsonb_build_object('run', r, 'd', d, 'e_auto', e_auto, 'e', e, 'a', a, 'pen', pen, 'akhir_auto', ak_auto, 'akhir', ak);
    if ak is not null then
      nr := nr + 1; st := st + ak; sp := sp + pen;
      if d is not null then any_d := true; sd := sd + d; end if;
      if e is not null then any_e := true; se := se + e; end if;
      if a is not null then any_a := true; sa := sa + a; end if;
    end if;
  end loop;
  return jsonb_build_object(
    'd', case when any_d then round(sd / nr, 3) end,
    'e', case when any_e then round(se / nr, 3) end,
    'a', case when any_a then round(sa / nr, 3) end,
    'pen', case when nr > 0 then round(sp / nr, 3) else 0 end,
    'total', case when nr = nruns then round(st / nr, 3) end,
    'partial', case when nr > 0 then round(st / nr, 3) end,
    'runs', runs, 'flags', flags, 'filled', n_have, 'slots_total', n_need * nruns);
end $$;

-- Kunci isian yang sah untuk satu panel (termasuk lompatan ke-2 dan isian manual Rerata / Nilai Akhir)
create or replace function jo.panel_keys(p jo.judge_panels) returns text[]
language sql stable set search_path = '' as $$
  select array_agg(k) from (
    select (sl->>'key') || case when r = 1 then '' else '@' || r end as k
      from generate_series(1, greatest(coalesce(p.runs,1),1)) r cross join jsonb_array_elements(coalesce(p.slots,'[]'::jsonb)) sl
    union all
    select f || case when r = 1 then '' else '@' || r end
      from generate_series(1, greatest(coalesce(p.runs,1),1)) r cross join unnest(array['RERATA','AKHIR']) f where p.sheet = 'artistik'
  ) q
$$;

-- ---------------------------------------------------------------------
-- Simulasi: aktivitas & penghapusan otomatis
-- ---------------------------------------------------------------------
create or replace function jo.sim_touch() returns void
language sql volatile set search_path = '' as $$
  insert into jo.settings (key, value, updated_at) values ('sim_last_activity', to_jsonb(now()), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
$$;

create or replace function jo.sim_wipe(p_by uuid, p_reason text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare n integer;
begin
  select count(*) into n from jo.jscores where mode = 'dummy';
  delete from jo.jscores where mode = 'dummy';
  delete from jo.jscore_log where mode = 'dummy';
  delete from jo.sim_order;
  update jo.live_screens set active = false where mode = 'dummy';
  insert into jo.settings (key, value, updated_at) values ('live_dummy_on', 'false'::jsonb, now())
  on conflict (key) do update set value = 'false'::jsonb, updated_at = now();
  delete from jo.staff_sessions ss using jo.staff s where s.id = ss.staff_id and s.is_dummy and ss.uid <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
  perform jo.log(p_by, 'simulasi_dihapus', 'sim', null, jsonb_build_object('nilai', n, 'alasan', p_reason));
  perform jo.live_ping('dummy');
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

-- dipanggil di awal fungsi konsol juri & live: hapus simulasi yang menganggur > 2 jam
create or replace function jo.sim_autowipe() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare last timestamptz;
begin
  select (value #>> '{}')::timestamptz into last from jo.settings where key = 'sim_last_activity';
  if last is not null and last < now() - interval '2 hours'
     and (exists (select 1 from jo.jscores where mode = 'dummy') or exists (select 1 from jo.sim_order)
          or coalesce(jo.setting_bool('live_dummy_on'), false)) then
    perform jo.sim_wipe(null, 'otomatis: 2 jam tanpa aktivitas');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Akses konsol juri
-- ---------------------------------------------------------------------
create or replace function jo.require_judging(p_roles text[] default null) returns jo.staff
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(coalesce(p_roles, array['owner','superadmin','td','asjur','verifikator','pemantau']));
  if st.is_dummy then
    perform jo.sim_touch();
    update jo.staff_sessions set expires_at = now() + interval '2 hours' where uid = auth.uid();
  end if;
  return st;
end $$;

-- Mode dari kode akses: dummy -> 'dummy', selain itu 'real'
create or replace function jo.mode_of(st jo.staff) returns text
language sql immutable set search_path = '' as $$
  select case when st.is_dummy then 'dummy' else 'real' end
$$;

create or replace function public.console_juri_login(p_code text, p_group text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); st jo.staff; v_fail integer; v_group text := upper(coalesce(p_group,''));
begin
  if v_uid is null then raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION'; end if;
  if v_group not in ('ART','RG','AER') then raise exception 'Pilih disiplin: Artistik, Ritmik, atau Aerobik.'; end if;
  perform jo.sim_autowipe();
  select count(*) into v_fail from jo.login_attempts where uid = v_uid and not ok and at > now() - interval '15 minutes';
  if v_fail >= 8 then
    return jsonb_build_object('ok', false, 'message', 'Terlalu banyak percobaan gagal. Tunggu 15 menit lalu coba lagi.');
  end if;
  select * into st from jo.staff where code_hash = jo.sha256(jo.norm_code(p_code)) and active;
  if st.id is null then
    insert into jo.login_attempts (uid, ok) values (v_uid, false);
    return jsonb_build_object('ok', false, 'message', 'Kode akses tidak dikenal atau sudah dinonaktifkan.');
  end if;
  if st.role not in ('owner','superadmin','td','asjur','verifikator','pemantau') then
    insert into jo.login_attempts (uid, ok) values (v_uid, false);
    return jsonb_build_object('ok', false, 'message', 'Kode ini untuk konsol panitia, bukan konsol juri. Konsol juri memakai kode Asisten Juri, Verifikator Nilai, atau TD.');
  end if;
  if (st.disc_group is not null and st.disc_group <> v_group)
     or (st.discipline is not null and jo.disc_group_of(st.discipline) <> v_group) then
    insert into jo.login_attempts (uid, ok) values (v_uid, false);
    return jsonb_build_object('ok', false, 'message', 'Kode ini untuk disiplin ' ||
      case coalesce(st.disc_group, jo.disc_group_of(st.discipline)) when 'ART' then 'Artistik' when 'RG' then 'Ritmik' else 'Aerobik' end
      || '. Pilih kotak disiplin yang sesuai.');
  end if;
  insert into jo.login_attempts (uid, ok) values (v_uid, true);
  insert into jo.staff_sessions (uid, staff_id, expires_at, disc_group, console)
  values (v_uid, st.id, now() + case when st.is_dummy then interval '2 hours' else interval '14 hours' end, v_group, 'juri')
  on conflict (uid) do update set staff_id = excluded.staff_id, created_at = now(), expires_at = excluded.expires_at,
    disc_group = excluded.disc_group, console = 'juri';
  update jo.staff set last_login_at = now() where id = st.id;
  if st.is_dummy then perform jo.sim_touch(); end if;
  perform jo.log(st.id, 'masuk_konsol_juri', 'staff', st.id::text, jsonb_build_object('disiplin', v_group));
  return jsonb_build_object('ok', true, 'staff', jo.staff_json(st) || jsonb_build_object('group', v_group));
end $$;

create or replace function public.console_juri_me() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text;
begin
  perform jo.sim_autowipe();
  select * into st from jo.current_staff();
  if st.id is null then return null; end if;
  select disc_group into g from jo.staff_sessions where uid = auth.uid() and console = 'juri';
  if g is null or st.role not in ('owner','superadmin','td','asjur','verifikator','pemantau') then return null; end if;
  return jo.staff_json(st) || jsonb_build_object('group', g,
    'live_dummy_on', coalesce(jo.setting_bool('live_dummy_on'), false),
    'live_public_on', coalesce(jo.setting_bool('live_public_on'), true));
end $$;

-- Keluar. Kode dummy bisa sekaligus menghapus SEMUA data simulasi.
create or replace function public.console_juri_logout(p_wipe boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  select * into st from jo.current_staff();
  if st.id is not null and coalesce(p_wipe, false) and (st.is_dummy or st.role in ('owner','superadmin')) then
    perform jo.sim_wipe(st.id, 'keluar dan hapus simulasi');
  end if;
  delete from jo.staff_sessions where uid = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.console_sim_wipe() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_judging();
  if not (st.is_dummy or st.role in ('owner','superadmin')) then
    raise exception 'Hanya kode dummy, owner, atau superadmin yang bisa menghapus simulasi.' using hint = 'ERR_FORBIDDEN';
  end if;
  return jo.sim_wipe(st.id, 'tombol hapus simulasi');
end $$;

-- ---------------------------------------------------------------------
-- Kategori & atlet untuk penilaian (mode real: start list asli; dummy: start list simulasi)
-- ---------------------------------------------------------------------
create or replace function public.console_j_categories() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text; v_mode text;
begin
  st := jo.require_judging();
  select disc_group into g from jo.staff_sessions where uid = auth.uid();
  v_mode := jo.mode_of(st);
  return jsonb_build_object(
    'mode', v_mode,
    'disciplines', (select coalesce(jsonb_agg(jsonb_build_object('code', d.code, 'name', d.name_id, 'apparatus', d.apparatus) order by d.sort), '[]'::jsonb)
                      from jo.disciplines d where d.code = any(jo.group_discs(g))),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'code', c.code, 'discipline', c.discipline, 'name', c.name_id, 'level', c.level,
        'apparatus', c.apparatus, 'startlist_published', c.startlist_published,
        'results_published', c.results_published, 'td_confirmed_at', c.td_confirmed_at, 'exhibition', c.exhibition,
        'paid', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id
                  where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas'),
        'pending', (select count(*) from jo.jscores j join jo.entries e on e.id = j.entry_id
                     where e.category_id = c.id and j.mode = v_mode and j.status = 'submitted'),
        'verified', (select count(*) from jo.jscores j join jo.entries e on e.id = j.entry_id
                     where e.category_id = c.id and j.mode = v_mode and j.status = 'verified')
      ) order by c.sort, c.id), '[]'::jsonb)
      from jo.categories c where c.active and c.discipline = any(jo.group_discs(g))));
end $$;

create or replace function jo.entry_name_mode(p_entry uuid, p_mode text) returns text
language sql stable set search_path = '' as $$
  select string_agg(a.full_name || case when p_mode = 'dummy' then ' – DUMMY TEST' else '' end, ' & ' order by a.sort, a.full_name)
    from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id where ea.entry_id = p_entry
$$;

-- Lembar penilaian satu kategori (semua alat) untuk asjur / verifikator / TD
create or replace function public.console_j_sheet(p_category integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; v_mode text;
begin
  st := jo.require_judging();
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  v_mode := jo.mode_of(st);
  return jsonb_build_object(
    'mode', v_mode, 'role', st.role,
    'category', jsonb_build_object('id', c.id, 'name', c.name_id, 'discipline', c.discipline, 'apparatus', c.apparatus,
       'startlist_published', c.startlist_published, 'results_published', c.results_published,
       'td_confirmed_at', c.td_confirmed_at, 'exhibition', c.exhibition),
    'apparatus', (select coalesce(jsonb_agg(x order by array_position(c.apparatus, x->>'code')), '[]'::jsonb)
                    from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x
                   where d.code = c.discipline and (x->>'code') = any(c.apparatus)),
    'panels', (select coalesce(jsonb_object_agg(a, to_jsonb(jo.panel_for(c.id, a))), '{}'::jsonb) from unnest(c.apparatus) a),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'name', jo.entry_name_mode(e.id, v_mode), 'club', jo.entry_club_label(e.id),
        'group_no', case when v_mode = 'dummy' then so.group_no else e.group_no end,
        'start_order', case when v_mode = 'dummy' then so.start_order else e.start_order end,
        'status', e.status,
        'scores', (select coalesce(jsonb_object_agg(j.apparatus, jsonb_build_object(
              'id', j.id, 'slots', j.slots, 'flags', j.flags, 'd', j.d, 'e', j.e, 'a', j.a, 'pen', j.pen, 'total', j.total,
              'status', j.status, 'note', j.note, 'updated_at', j.updated_at,
              'entered_by', (select name from jo.staff where id = j.entered_by),
              'verified_by', (select name from jo.staff where id = j.verified_by), 'verified_at', j.verified_at)), '{}'::jsonb)
            from jo.jscores j where j.entry_id = e.id and j.mode = v_mode)
      ) order by case when v_mode = 'dummy' then so.group_no else e.group_no end nulls last,
                 case when v_mode = 'dummy' then so.start_order else e.start_order end nulls last, e.created_at), '[]'::jsonb)
      from jo.entries e join jo.submissions s on s.id = e.submission_id
      left join jo.sim_order so on so.entry_id = e.id and so.category_id = c.id
      where e.category_id = c.id and e.status in ('aktif','dns') and s.status = 'lunas'));
end $$;

-- ---------------------------------------------------------------------
-- Simpan / kirim / verifikasi / kembalikan / batalkan
-- p_action: 'draft' | 'submit' | 'unsubmit' | 'verify' | 'return' | 'correct' | 'unverify' | 'clear'
-- ---------------------------------------------------------------------
create or replace function public.console_j_save(p_entry uuid, p_apparatus text, p_slots jsonb, p_action text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; e jo.entries; c jo.categories; s jo.submissions; j jo.jscores; pnl jo.judge_panels;
  v_mode text; v_app text := upper(trim(p_apparatus)); v_act text := lower(coalesce(p_action,'draft'));
  v_slots jsonb; calc jsonb; old jsonb; k text; vv text; n numeric; is_ver boolean; is_asj boolean; v_status text;
begin
  st := jo.require_judging(array['owner','superadmin','asjur','verifikator']);
  v_mode := jo.mode_of(st);
  is_ver := st.role in ('owner','superadmin','verifikator');
  is_asj := st.role in ('owner','superadmin','asjur');
  select * into e from jo.entries where id = p_entry;
  if e.id is null then raise exception 'Atlet tidak ditemukan.'; end if;
  select * into c from jo.categories where id = e.category_id;
  perform jo.check_discipline(st, c.discipline);
  select * into s from jo.submissions where id = e.submission_id;
  if s.status <> 'lunas' or e.status <> 'aktif' then raise exception 'Atlet ini belum lunas atau tidak aktif (DNS).'; end if;
  if not (v_app = any(c.apparatus)) then raise exception 'Alat % tidak ada di kategori ini.', v_app; end if;
  if v_mode = 'real' and c.results_published and v_act <> 'draft' and st.role not in ('owner','superadmin') then
    raise exception 'Hasil kategori ini sudah dikonfirmasi TD dan dipublikasikan. Minta superadmin menarik publikasi untuk koreksi.';
  end if;
  pnl := jo.panel_for(c.id, v_app);

  select * into j from jo.jscores where mode = v_mode and entry_id = e.id and apparatus = v_app for update;
  old := case when j.id is null then null else jsonb_build_object('slots', j.slots, 'total', j.total, 'status', j.status, 'flags', j.flags) end;

  -- bersihkan slot: hanya kunci di panel, angka 0..40
  v_slots := coalesce(j.slots, '{}'::jsonb);
  if p_slots is not null and jsonb_typeof(p_slots) = 'object' then
    v_slots := '{}'::jsonb;
    for k, vv in select key, value #>> '{}' from jsonb_each(p_slots) loop
      if not (k = any(jo.panel_keys(pnl))) then continue; end if;
      vv := replace(trim(coalesce(vv,'')), ',', '.');
      if vv = '' then continue; end if;
      begin n := vv::numeric; exception when others then raise exception 'Nilai % tidak valid: %', k, vv; end;
      if n < 0 or n > 40 then raise exception 'Nilai % harus antara 0 dan 40.', k; end if;
      v_slots := v_slots || jsonb_build_object(k, round(n, 3));
    end loop;
  end if;
  calc := jo.calc_slots(pnl, v_slots);
  v_status := coalesce(j.status, 'draft');

  if v_act in ('draft','submit') then
    if not is_asj and not (is_ver and v_status <> 'verified') then raise exception 'Hanya asisten juri yang mengisi nilai.' using hint = 'ERR_FORBIDDEN'; end if;
    if v_status in ('submitted','verified') and not is_ver then
      raise exception 'Nilai ini sudah % ke verifikator. Tarik kembali dulu untuk mengubah.', case v_status when 'verified' then 'diverifikasi' else 'dikirim' end;
    end if;
    if v_status = 'verified' then raise exception 'Nilai sudah diverifikasi. Gunakan Koreksi.'; end if;
    if v_act = 'submit' and (calc->>'total') is null then
      raise exception '%', case when (calc->>'partial') is not null then 'Isi semua lompatan sebelum mengirim.' else 'Isi nilai dulu sebelum mengirim.' end;
    end if;
    v_status := case when v_act = 'submit' then 'submitted' else case when v_status = 'returned' then 'returned' else 'draft' end end;
  elsif v_act = 'unsubmit' then
    if v_status <> 'submitted' then raise exception 'Nilai tidak sedang menunggu verifikasi.'; end if;
    v_status := 'draft'; v_slots := j.slots; calc := jo.calc_slots(pnl, v_slots);
  elsif v_act in ('verify','correct') then
    if not is_ver then raise exception 'Hanya verifikator nilai yang bisa memverifikasi.' using hint = 'ERR_FORBIDDEN'; end if;
    if (calc->>'total') is null then raise exception '%', case when (calc->>'partial') is not null then 'Isi semua lompatan sebelum verifikasi.' else 'Nilai masih kosong.' end; end if;
    if v_act = 'correct' and v_status = 'verified' and length(trim(coalesce(p_note,''))) < 3 then
      raise exception 'Tulis alasan koreksi.';
    end if;
    v_status := 'verified';
  elsif v_act = 'return' then
    if not is_ver then raise exception 'Hanya verifikator nilai yang bisa mengembalikan.' using hint = 'ERR_FORBIDDEN'; end if;
    if length(trim(coalesce(p_note,''))) < 2 then raise exception 'Tulis catatan untuk asisten juri.'; end if;
    v_status := 'returned'; v_slots := coalesce(j.slots, v_slots); calc := jo.calc_slots(pnl, v_slots);
  elsif v_act = 'unverify' then
    if not is_ver then raise exception 'Hanya verifikator nilai.' using hint = 'ERR_FORBIDDEN'; end if;
    if length(trim(coalesce(p_note,''))) < 3 then raise exception 'Tulis alasan membatalkan verifikasi.'; end if;
    v_status := 'submitted'; v_slots := j.slots; calc := jo.calc_slots(pnl, v_slots);
  elsif v_act = 'clear' then
    if j.id is null then return jsonb_build_object('ok', true); end if;
    if j.status = 'verified' and length(trim(coalesce(p_note,''))) < 3 then raise exception 'Tulis alasan menghapus nilai terverifikasi.'; end if;
    if not is_ver and j.status in ('submitted','verified') then raise exception 'Nilai yang sudah dikirim hanya bisa dihapus verifikator.'; end if;
    delete from jo.jscores where id = j.id;
    if v_mode = 'real' then delete from jo.scores where entry_id = e.id and apparatus = v_app and component = 'FINAL'; end if;
    insert into jo.jscore_log (mode, jscore_id, entry_id, apparatus, action, old_val, new_val, by_staff, reason)
    values (v_mode, j.id, e.id, v_app, 'hapus', old, null, st.id, nullif(trim(coalesce(p_note,'')),''));
    if j.status = 'verified' then perform jo.live_ping(v_mode); end if;
    return jsonb_build_object('ok', true, 'score', null);
  else
    raise exception 'Tindakan tidak dikenal.';
  end if;

  if j.id is null then
    insert into jo.jscores (mode, entry_id, apparatus) values (v_mode, e.id, v_app) returning * into j;
  end if;
  update jo.jscores set
    slots = v_slots, d = (calc->>'d')::numeric, e = (calc->>'e')::numeric, a = (calc->>'a')::numeric,
    pen = (calc->>'pen')::numeric, total = (calc->>'total')::numeric, status = v_status, flags = coalesce(calc->'flags', '[]'::jsonb),
    note = case when v_act = 'return' then trim(p_note) when v_act in ('submit','verify','correct') then null else note end,
    entered_by = case when v_act in ('draft','submit') then st.id else entered_by end,
    entered_at = case when v_act in ('draft','submit') then now() else entered_at end,
    submitted_at = case when v_act = 'submit' then now() else submitted_at end,
    verified_by = case when v_status = 'verified' then st.id when v_act in ('unverify','return') then null else verified_by end,
    verified_at = case when v_status = 'verified' then now() when v_act in ('unverify','return') then null else verified_at end,
    updated_at = now()
  where id = j.id returning * into j;

  insert into jo.jscore_log (mode, jscore_id, entry_id, apparatus, action, old_val, new_val, by_staff, reason)
  values (v_mode, j.id, e.id, v_app,
    case v_act when 'draft' then 'simpan' when 'submit' then 'kirim' when 'unsubmit' then 'tarik' when 'verify' then 'verifikasi'
               when 'correct' then 'koreksi' when 'return' then 'kembalikan' when 'unverify' then 'batal_verifikasi' end,
    old, jsonb_build_object('slots', j.slots, 'total', j.total, 'status', j.status, 'flags', j.flags), st.id, nullif(trim(coalesce(p_note,'')),''));

  -- mode real: nilai terverifikasi menjadi nilai akhir alat (dipakai hasil resmi)
  if v_mode = 'real' then
    if j.status = 'verified' then
      delete from jo.scores where entry_id = e.id and apparatus = v_app and component = 'FINAL' and staff_id <> st.id;
      insert into jo.scores (entry_id, apparatus, component, staff_id, value) values (e.id, v_app, 'FINAL', st.id, j.total)
      on conflict (entry_id, apparatus, component, staff_id) do update set value = excluded.value, updated_at = now();
      insert into jo.score_log (entry_id, apparatus, component, judge_id, old_value, new_value, changed_by, action, reason)
      values (e.id, v_app, 'FINAL', st.id, (old->>'total')::numeric, j.total, st.id,
              case when v_act = 'correct' then 'koreksi_verifikator' else 'verifikasi' end, nullif(trim(coalesce(p_note,'')),''));
    elsif old is not null and old->>'status' = 'verified' then
      delete from jo.scores where entry_id = e.id and apparatus = v_app and component = 'FINAL';
      insert into jo.score_log (entry_id, apparatus, component, judge_id, old_value, new_value, changed_by, action, reason)
      values (e.id, v_app, 'FINAL', st.id, (old->>'total')::numeric, null, st.id, 'batal_verifikasi', nullif(trim(coalesce(p_note,'')),''));
    end if;
  end if;
  if j.status = 'verified' or (old is not null and old->>'status' = 'verified') then perform jo.live_ping(v_mode); end if;

  return jsonb_build_object('ok', true, 'score', jsonb_build_object('id', j.id, 'slots', j.slots, 'flags', j.flags, 'd', j.d, 'e', j.e, 'a', j.a,
    'pen', j.pen, 'total', j.total, 'status', j.status, 'note', j.note, 'updated_at', j.updated_at,
    'verified_by', (select name from jo.staff where id = j.verified_by), 'verified_at', j.verified_at,
    'entered_by', (select name from jo.staff where id = j.entered_by)));
end $$;

-- Antrean verifikator: semua yang dikirim (dan dikembalikan) di disiplin sesi ini
create or replace function public.console_j_queue() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text; v_mode text;
begin
  st := jo.require_judging();
  select disc_group into g from jo.staff_sessions where uid = auth.uid();
  v_mode := jo.mode_of(st);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', j.id, 'entry_id', j.entry_id, 'apparatus', j.apparatus, 'slots', j.slots, 'flags', j.flags,
      'd', j.d, 'e', j.e, 'a', j.a, 'pen', j.pen, 'total', j.total, 'status', j.status, 'note', j.note,
      'submitted_at', j.submitted_at, 'updated_at', j.updated_at,
      'entered_by', (select name from jo.staff where id = j.entered_by),
      'name', jo.entry_name_mode(e.id, v_mode), 'club', jo.entry_club_label(e.id),
      'category_id', c.id, 'category', c.name_id, 'discipline', c.discipline,
      'panel', to_jsonb(jo.panel_for(c.id, j.apparatus))
    ) order by j.submitted_at nulls last, j.updated_at), '[]'::jsonb)
    from jo.jscores j join jo.entries e on e.id = j.entry_id join jo.categories c on c.id = e.category_id
    where j.mode = v_mode and j.status in ('submitted','returned') and c.discipline = any(jo.group_discs(g))
      and (st.discipline is null or c.discipline = st.discipline));
end $$;

create or replace function public.console_j_log(p_category integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; v_mode text;
begin
  st := jo.require_judging();
  select * into c from jo.categories where id = p_category;
  perform jo.check_discipline(st, c.discipline);
  v_mode := jo.mode_of(st);
  return (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'apparatus', l.apparatus,
      'name', jo.entry_name_mode(l.entry_id, v_mode), 'old', l.old_val, 'new', l.new_val,
      'by', (select name from jo.staff where id = l.by_staff), 'reason', l.reason) order by l.at desc), '[]'::jsonb)
    from (select * from jo.jscore_log where mode = v_mode and entry_id in (select id from jo.entries where category_id = c.id)
          order by at desc limit 300) l);
end $$;

-- ---------------------------------------------------------------------
-- Panel juri (tambah/hapus slot E, dst.)
-- ---------------------------------------------------------------------
create or replace function public.console_j_panels() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text;
begin
  st := jo.require_judging();
  select disc_group into g from jo.staff_sessions where uid = auth.uid();
  return (select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('category', (select name_id from jo.categories where id = p.category_id))
            order by p.discipline, p.category_id nulls first, p.apparatus nulls first), '[]'::jsonb)
            from jo.judge_panels p where p.discipline = any(jo.group_discs(g)));
end $$;

create or replace function public.console_j_panel_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_disc text := upper(p->>'discipline'); v_cat integer := nullif(p->>'category_id','')::integer;
  v_app text := nullif(upper(coalesce(p->>'apparatus','')),''); sl jsonb; out jsonb := '[]'::jsonb; keys text[] := '{}'; k text;
begin
  st := jo.require_judging(array['owner','superadmin','verifikator','td']);
  if st.is_dummy then raise exception 'Kode dummy tidak bisa mengubah panel juri.' using hint = 'ERR_FORBIDDEN'; end if;
  perform jo.check_discipline(st, v_disc);
  if v_cat is not null and not exists (select 1 from jo.categories where id = v_cat and discipline = v_disc) then raise exception 'Kategori tidak cocok dengan disiplin.'; end if;
  if p->>'delete' = 'true' then
    if v_cat is null and v_app is null then raise exception 'Panel dasar disiplin tidak bisa dihapus.'; end if;
    delete from jo.judge_panels where discipline = v_disc and coalesce(category_id,0) = coalesce(v_cat,0) and coalesce(apparatus,'') = coalesce(v_app,'');
    perform jo.log(st.id, 'panel_juri_dihapus', 'panel', v_disc || ':' || coalesce(v_cat::text,'*') || ':' || coalesce(v_app,'*'), p);
    return public.console_j_panels();
  end if;
  if jsonb_typeof(p->'slots') <> 'array' or jsonb_array_length(p->'slots') = 0 then raise exception 'Panel harus punya minimal satu isian.'; end if;
  if jsonb_array_length(p->'slots') > 20 then raise exception 'Maksimal 20 isian.'; end if;
  for sl in select * from jsonb_array_elements(p->'slots') loop
    k := upper(regexp_replace(coalesce(sl->>'key',''), '[^A-Za-z0-9]', '', 'g'));
    if k = '' then raise exception 'Kode isian kosong.'; end if;
    if k = any(keys) then raise exception 'Kode isian % dobel.', k; end if;
    if coalesce(sl->>'comp','') not in ('D','E','A','PEN') then raise exception 'Komponen isian % harus D, E, A, atau PEN.', k; end if;
    keys := keys || k;
    out := out || jsonb_build_object('key', k, 'comp', sl->>'comp', 'label', coalesce(nullif(trim(sl->>'label'),''), k));
  end loop;
  insert into jo.judge_panels (discipline, category_id, apparatus, slots, e_mode, e_base, runs, sheet, updated_at, updated_by)
  values (v_disc, v_cat, v_app, out, coalesce(nullif(p->>'e_mode',''), 'score'), coalesce(nullif(p->>'e_base','')::numeric, 10),
          least(greatest(coalesce(nullif(p->>'runs','')::integer, 1), 1), 3), coalesce(nullif(p->>'sheet',''), 'standar'), now(), st.id)
  on conflict (discipline, coalesce(category_id, 0), coalesce(apparatus, ''))
  do update set slots = excluded.slots, e_mode = excluded.e_mode, e_base = excluded.e_base, runs = excluded.runs, sheet = excluded.sheet,
    updated_at = now(), updated_by = st.id;
  perform jo.log(st.id, 'panel_juri_diubah', 'panel', v_disc || ':' || coalesce(v_cat::text,'*') || ':' || coalesce(v_app,'*'), p);
  return public.console_j_panels();
end $$;

-- ---------------------------------------------------------------------
-- Start list simulasi (kode dummy)
-- ---------------------------------------------------------------------
create or replace function public.console_sim_startlist_save(p_category integer, p_rows jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; r jsonb;
begin
  st := jo.require_judging(array['owner','superadmin','asjur','verifikator','td']);
  if not st.is_dummy and st.role not in ('owner','superadmin') then raise exception 'Start list simulasi hanya untuk kode dummy.'; end if;
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  delete from jo.sim_order where category_id = c.id;
  for r in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    insert into jo.sim_order (category_id, entry_id, group_no, start_order)
    select c.id, e.id, nullif(r->>'group_no','')::integer, nullif(r->>'start_order','')::integer
      from jo.entries e where e.id = (r->>'entry_id')::uuid and e.category_id = c.id
    on conflict do nothing;
  end loop;
  perform jo.sim_touch();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.console_sim_draw(p_category integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_judging(array['owner','superadmin','asjur','verifikator','td']);
  if not st.is_dummy and st.role not in ('owner','superadmin') then raise exception 'Start list simulasi hanya untuk kode dummy.'; end if;
  select * into c from jo.categories where id = p_category;
  perform jo.check_discipline(st, c.discipline);
  delete from jo.sim_order where category_id = c.id;
  insert into jo.sim_order (category_id, entry_id, group_no, start_order)
  select c.id, e.id, 1, row_number() over (order by random())
    from jo.entries e join jo.submissions s on s.id = e.submission_id
   where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas';
  perform jo.sim_touch();
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Layar live: kelola dari konsol juri
-- ---------------------------------------------------------------------
create or replace function public.console_live_screens() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_mode text;
begin
  st := jo.require_judging();
  v_mode := jo.mode_of(st);
  return jsonb_build_object(
    'mode', v_mode,
    'can_edit', st.role in ('owner','superadmin','td','verifikator') or st.is_dummy,
    'can_public', st.role in ('owner','superadmin'),
    'dummy_on', coalesce(jo.setting_bool('live_dummy_on'), false),
    'public_on', coalesce(jo.setting_bool('live_public_on'), true),
    'ticker', coalesce(jo.setting_text('live_ticker'), ''),
    'ticker_dummy', coalesce(jo.setting_text('live_ticker_dummy'), ''),
    'screens', (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
        'category', (select name_id from jo.categories where id = x.category_id),
        'discipline', (select discipline from jo.categories where id = x.category_id)) order by x.mode, x.sort, x.id), '[]'::jsonb)
      from jo.live_screens x where x.mode = v_mode or st.role in ('owner','superadmin')));
end $$;

create or replace function public.console_live_screen_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_mode text; x jo.live_screens; v_id integer := nullif(p->>'id','')::integer; v_cat integer := nullif(p->>'category_id','')::integer;
begin
  st := jo.require_judging();
  if not (st.role in ('owner','superadmin','td','verifikator') or st.is_dummy) then raise exception 'Peran Anda tidak bisa mengatur layar.' using hint = 'ERR_FORBIDDEN'; end if;
  v_mode := coalesce(nullif(p->>'mode',''), jo.mode_of(st));
  if st.is_dummy then v_mode := 'dummy'; end if;
  if v_mode not in ('real','dummy') then raise exception 'Mode layar tidak dikenal.'; end if;
  if v_cat is not null then perform jo.check_discipline(st, (select discipline from jo.categories where id = v_cat)); end if;
  if v_id is not null then
    select * into x from jo.live_screens where id = v_id for update;
    if x.id is null then raise exception 'Layar tidak ditemukan.'; end if;
    if x.mode <> jo.mode_of(st) and st.role not in ('owner','superadmin') then raise exception 'Layar ini bukan untuk mode Anda.'; end if;
    if p->>'delete' = 'true' then
      delete from jo.live_screens where id = x.id;
      perform jo.live_ping(x.mode);
      return public.console_live_screens();
    end if;
  end if;
  if length(trim(coalesce(p->>'name',''))) < 1 then raise exception 'Isi nama layar.'; end if;
  if v_id is null then
    insert into jo.live_screens (mode, name) values (v_mode, trim(p->>'name')) returning * into x;
  end if;
  update jo.live_screens set
    name = trim(p->>'name'),
    category_id = v_cat,
    view = coalesce(nullif(p->>'view',''), view),
    apparatus = nullif(upper(coalesce(p->>'apparatus','')),''),
    layout = coalesce(nullif(p->>'layout','')::integer, layout),
    cam1 = nullif(trim(coalesce(p->>'cam1','')),''),
    cam2 = nullif(trim(coalesce(p->>'cam2','')),''),
    first_n = coalesce(nullif(p->>'first_n','')::integer, first_n),
    next_n = coalesce(nullif(p->>'next_n','')::integer, next_n),
    page_secs = coalesce(nullif(p->>'page_secs','')::integer, page_secs),
    active = coalesce((p->>'active')::boolean, active),
    sort = coalesce(nullif(p->>'sort','')::integer, sort),
    updated_at = now(), updated_by = st.id
  where id = x.id;
  if not st.is_dummy then perform jo.log(st.id, 'layar_diubah', 'screen', x.id::text, p); end if;
  perform jo.live_ping(x.mode);
  return public.console_live_screens();
end $$;

create or replace function public.console_live_settings(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_judging();
  if p ? 'ticker' then
    if st.is_dummy then
      insert into jo.settings (key, value, updated_at, updated_by) values ('live_ticker_dummy', to_jsonb(left(coalesce(p->>'ticker',''), 600)), now(), st.id)
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    else
      if st.role not in ('owner','superadmin','td','verifikator') then raise exception 'Peran Anda tidak bisa mengubah teks berjalan.'; end if;
      insert into jo.settings (key, value, updated_at, updated_by) values ('live_ticker', to_jsonb(left(coalesce(p->>'ticker',''), 600)), now(), st.id)
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    end if;
  end if;
  if p ? 'dummy_on' then
    if not (st.is_dummy or st.role in ('owner','superadmin')) then raise exception 'Tayangan simulasi diatur oleh kode dummy, owner, atau superadmin.'; end if;
    insert into jo.settings (key, value, updated_at, updated_by) values ('live_dummy_on', to_jsonb((p->>'dummy_on')::boolean), now(), st.id)
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    perform jo.log(st.id, case when (p->>'dummy_on')::boolean then 'simulasi_tayang' else 'simulasi_disembunyikan' end, 'sim', null);
  end if;
  if p ? 'public_on' then
    if st.role not in ('owner','superadmin') then raise exception 'Tayangan publik hanya diatur owner atau superadmin.'; end if;
    insert into jo.settings (key, value, updated_at, updated_by) values ('live_public_on', to_jsonb((p->>'public_on')::boolean), now(), st.id)
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    perform jo.log(st.id, case when (p->>'public_on')::boolean then 'live_publik_dibuka' else 'live_publik_dijeda' end, 'live', null);
  end if;
  perform jo.live_ping('real'); perform jo.live_ping('dummy');
  return public.console_live_screens();
end $$;

-- ---------------------------------------------------------------------
-- TD: konfirmasi hasil resmi
--   step 'pdf'    : catat bahwa PDF hasil sudah dibuat & diperiksa
--   step 'publish': konfirmasi TD + publikasikan hasil & medali (hasil.html)
--   step 'revoke' : tarik publikasi (owner/superadmin)
-- ---------------------------------------------------------------------
create or replace function public.console_td_confirm(p_category integer, p_step text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories; v_pending integer;
begin
  st := jo.require_judging(array['owner','superadmin','td']);
  if st.is_dummy then raise exception 'Kode dummy tidak bisa mengonfirmasi hasil resmi.' using hint = 'ERR_FORBIDDEN'; end if;
  select * into c from jo.categories where id = p_category for update;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  if p_step = 'pdf' then
    update jo.categories set td_pdf_at = now() where id = c.id;
    perform jo.log(st.id, 'td_pdf_hasil', 'category', c.id::text);
  elsif p_step = 'publish' then
    select count(*) into v_pending from jo.jscores j join jo.entries e on e.id = j.entry_id
     where e.category_id = c.id and j.mode = 'real' and j.status in ('draft','submitted','returned');
    if v_pending > 0 then raise exception 'Masih ada % nilai yang belum diverifikasi di kategori ini.', v_pending; end if;
    if c.td_pdf_at is null then raise exception 'Buat dan periksa PDF hasil dulu sebelum konfirmasi.'; end if;
    update jo.categories set td_confirmed_at = now(), td_confirmed_by = st.id, results_published = true,
      results_published_at = now(), scores_locked = true where id = c.id;
    perform jo.log(st.id, 'td_konfirmasi_hasil', 'category', c.id::text);
  elsif p_step = 'revoke' then
    if st.role not in ('owner','superadmin') then raise exception 'Menarik hasil resmi hanya bisa dilakukan superadmin.'; end if;
    update jo.categories set td_confirmed_at = null, td_confirmed_by = null, td_pdf_at = null, results_published = false,
      results_published_at = null, scores_locked = false where id = c.id;
    perform jo.log(st.id, 'td_hasil_ditarik', 'category', c.id::text);
  else
    raise exception 'Langkah tidak dikenal.';
  end if;
  return public.console_td_results(c.id);
end $$;

-- Data hasil untuk PDF & layar TD (mode real, resmi). Termasuk rincian D/E/A/Pen per alat.
create or replace function public.console_td_results(p_category integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_judging();
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  return jsonb_build_object(
    'category', to_jsonb(c) || jsonb_build_object('td_confirmed_by_name', (select name from jo.staff where id = c.td_confirmed_by)),
    'apparatus', (select coalesce(jsonb_agg(x order by array_position(c.apparatus, x->>'code')), '[]'::jsonb)
                    from jo.disciplines d cross join jsonb_array_elements(d.apparatus) x
                   where d.code = c.discipline and (x->>'code') = any(c.apparatus)),
    'results', jo.category_results(c.id),
    'detail', (select coalesce(jsonb_object_agg(j.entry_id::text || ':' || j.apparatus,
                 jsonb_build_object('d', j.d, 'e', j.e, 'a', j.a, 'pen', j.pen, 'total', j.total, 'status', j.status, 'flags', j.flags)), '{}'::jsonb)
               from jo.jscores j join jo.entries e on e.id = j.entry_id where e.category_id = c.id and j.mode = 'real'),
    'pending', (select count(*) from jo.jscores j join jo.entries e on e.id = j.entry_id
                 where e.category_id = c.id and j.mode = 'real' and j.status <> 'verified'),
    'signatories', jo.setting('signatories'));
end $$;

-- ---------------------------------------------------------------------
-- PUBLIC LIVE VIEW
-- ---------------------------------------------------------------------
create or replace function public.public_live_index() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_dummy boolean;
begin
  perform jo.sim_autowipe();
  v_dummy := coalesce(jo.setting_bool('live_dummy_on'), false);
  return jsonb_build_object(
    'public_on', coalesce(jo.setting_bool('live_public_on'), true),
    'dummy_on', v_dummy,
    'screens', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'mode', x.mode, 'name', x.name,
        'category', c.name_id, 'discipline', c.discipline) order by x.mode, x.sort, x.id), '[]'::jsonb)
      from jo.live_screens x left join jo.categories c on c.id = x.category_id
      where x.active and (x.mode = 'real' or v_dummy)));
end $$;

-- Satu layar: konfigurasi + papan peringkat. p_key = kunci layar venue (prioritas; tidak ikut jeda publik)
create or replace function public.public_live_feed(p_screen integer, p_key text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare x jo.live_screens; c jo.categories; venue boolean; v_dummy boolean; apps jsonb; rows jsonb;
begin
  select * into x from jo.live_screens where id = p_screen;
  if x.id is null then return jsonb_build_object('missing', true); end if;
  venue := p_key is not null and p_key = x.vkey;
  v_dummy := coalesce(jo.setting_bool('live_dummy_on'), false);
  if not venue and not coalesce(jo.setting_bool('live_public_on'), true) then
    return jsonb_build_object('paused', true);
  end if;
  if not x.active or (x.mode = 'dummy' and not v_dummy) then
    return jsonb_build_object('off', true, 'name', x.name, 'mode', x.mode);
  end if;
  select * into c from jo.categories where id = x.category_id;

  select coalesce(jsonb_agg(jsonb_build_object('code', a->>'code', 'name', a->>'id') order by array_position(c.apparatus, a->>'code')), '[]'::jsonb)
    into apps from jo.disciplines d cross join jsonb_array_elements(d.apparatus) a
   where d.code = c.discipline and (a->>'code') = any(c.apparatus);

  with e as (
    select en.id from jo.entries en join jo.submissions s on s.id = en.submission_id
     where en.category_id = c.id and en.status = 'aktif' and s.status = 'lunas' and not en.team_only
  ), j as (
    select j.* from jo.jscores j join e on e.id = j.entry_id where j.mode = x.mode and j.status = 'verified'
  ), per as (
    select e.id,
      jsonb_object_agg(j.apparatus, jsonb_build_object('d', j.d, 'e', j.e, 'a', j.a, 'pen', j.pen, 'total', j.total,
        'at', extract(epoch from j.verified_at))) filter (where j.id is not null) as apps,
      sum(j.d) as d, sum(j.e) as e, sum(j.a) as a, sum(j.pen) as pen, round(sum(j.total), 3) as total,
      max(extract(epoch from j.verified_at)) as last_at, count(j.id) as n
    from e left join j on j.entry_id = e.id group by e.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', per.id,
      'name', jo.entry_name_mode(per.id, x.mode),
      'club', jo.entry_club_label(per.id),
      'photo', (select a.photo_path from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id
                 where ea.entry_id = per.id order by a.sort limit 1),
      'apps', per.apps, 'd', per.d, 'e', per.e, 'a', per.a, 'pen', per.pen, 'total', per.total,
      'n', per.n, 'last_at', per.last_at)), '[]'::jsonb)
    into rows from per where per.n > 0;

  return jsonb_build_object(
    'screen', jsonb_build_object('id', x.id, 'name', x.name, 'mode', x.mode, 'view', x.view, 'apparatus', x.apparatus,
      'layout', x.layout, 'cam1', x.cam1, 'cam2', x.cam2, 'first_n', x.first_n, 'next_n', x.next_n, 'page_secs', x.page_secs),
    'venue', venue,
    'category', case when c.id is null then null else jsonb_build_object('id', c.id, 'name', c.name_id, 'discipline', c.discipline,
       'competitors', (select count(*) from jo.entries en join jo.submissions s on s.id = en.submission_id
                        where en.category_id = c.id and en.status = 'aktif' and s.status = 'lunas' and not en.team_only)) end,
    'apparatus', apps,
    'rows', rows,
    'ticker', case when x.mode = 'dummy' then coalesce(nullif(jo.setting_text('live_ticker_dummy'),''), jo.setting_text('live_ticker'))
                   else jo.setting_text('live_ticker') end,
    'now', extract(epoch from now()));
end $$;

-- Pas foto atlet lunas boleh dibaca layar live (izin publikasi dari panitia, 16 Nov 2026)
create or replace function public.jo_live_photo(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from jo.athletes a join jo.submissions s on s.id = a.submission_id
                  where a.photo_path = p_name and s.status = 'lunas')
$$;
grant execute on function public.jo_live_photo(text) to anon, authenticated;

drop policy if exists "jo: live baca pas foto" on storage.objects;
create policy "jo: live baca pas foto" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'dokumen' and public.jo_live_photo(name));

create index if not exists athletes_photo_idx on jo.athletes (photo_path);

-- Konsol juri boleh membaca start list & hasil yang sudah ada (peran baru)
-- (fungsi lama memakai jo.require_staff dengan daftar peran; diperluas di bawah)

-- ---------------------------------------------------------------------
-- Peran baru boleh membaca daftar kategori (dipakai kerangka konsol)
-- ---------------------------------------------------------------------
create or replace function public.console_categories(p_discipline text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin','juri','td','pemantau','asjur','verifikator']);
  d := coalesce(st.discipline, nullif(p_discipline,''));
  return jsonb_build_object(
    'disciplines', (select coalesce(jsonb_agg(to_jsonb(x) order by x.sort), '[]'::jsonb) from jo.disciplines x
                     where (d is null or x.code = d) and (st.disc_group is null or x.code = any(jo.group_discs(st.disc_group)))),
    'team_levels', coalesce(jo.setting('team_levels'), '{}'::jsonb),
    'categories', (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
        'registered', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status <> 'dibatalkan'),
        'paid', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas'),
        'priangan', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas' and e.priangan_status = 'disetujui'),
        'delegations', (select count(distinct coalesce(s.club_id::text, s.id::text)) from jo.entries e join jo.submissions s on s.id = e.submission_id where e.category_id = c.id and e.status = 'aktif' and s.status = 'lunas')
      ) order by c.sort, c.id), '[]'::jsonb) from jo.categories c
      where (d is null or c.discipline = d) and (st.disc_group is null or c.discipline = any(jo.group_discs(st.disc_group))))
  );
end $$;

-- ---------------------------------------------------------------------
-- Kode akses: Asisten Juri, Verifikator Nilai, kode DUMMY (dibuat di konsol utama)
-- ---------------------------------------------------------------------
create or replace function jo.staff_create(st jo.staff, p jsonb) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_code text; v_role text := p->>'role'; x jo.staff; v_group text := nullif(upper(coalesce(p->>'disc_group','')),'');
  v_dummy boolean := coalesce((p->>'is_dummy')::boolean, false);
begin
  if v_role not in ('superadmin','admin','td','juri','pemantau','bendahara','asjur','verifikator') then raise exception 'Peran tidak dikenal.'; end if;
  if v_role = 'superadmin' and st.role <> 'owner' then raise exception 'Hanya owner yang bisa membuat kode superadmin.'; end if;
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama pemegang kode.'; end if;
  if nullif(p->>'discipline','') is not null and not exists (select 1 from jo.disciplines where code = p->>'discipline') then
    raise exception 'Disiplin tidak dikenal.';
  end if;
  if v_group is not null and v_group not in ('ART','RG','AER') then raise exception 'Kelompok disiplin tidak dikenal.'; end if;
  if v_dummy and v_role not in ('asjur','verifikator') then raise exception 'Kode dummy hanya untuk Asisten Juri atau Verifikator Nilai.'; end if;
  if v_role in ('asjur','verifikator') and v_group is null and nullif(p->>'discipline','') is null then
    raise exception 'Pilih disiplin untuk kode ini (Artistik, Ritmik, atau Aerobik).';
  end if;
  v_code := jo.new_staff_code();
  insert into jo.staff (name, role, discipline, apparatus, components, code_hash, code_hint, note, created_by, phone, access_windows, disc_group, is_dummy)
  values (trim(p->>'name'), v_role, case when v_role in ('asjur','verifikator') then null else nullif(p->>'discipline','') end,
    case when jsonb_typeof(p->'apparatus') = 'array' and jsonb_array_length(p->'apparatus') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'apparatus') a) end,
    case when jsonb_typeof(p->'components') = 'array' and jsonb_array_length(p->'components') > 0
         then (select array_agg(upper(a)) from jsonb_array_elements_text(p->'components') a) end,
    jo.sha256(jo.norm_code(v_code)), right(v_code, 4), nullif(trim(coalesce(p->>'note','')),''), st.id,
    nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), ''),
    case when v_role = 'juri' then jo.norm_windows(p->'access_windows') end,
    case when v_role in ('asjur','verifikator') then coalesce(v_group, jo.disc_group_of(nullif(p->>'discipline',''))) end,
    v_dummy)
  returning * into x;
  perform jo.log(st.id, 'kode_dibuat', 'staff', x.id::text, jsonb_build_object('name', x.name, 'role', x.role, 'discipline', x.discipline, 'disc_group', x.disc_group, 'dummy', x.is_dummy));
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
  if p ? 'disc_group' and nullif(upper(p->>'disc_group'),'') is not null and upper(p->>'disc_group') not in ('ART','RG','AER') then
    raise exception 'Kelompok disiplin tidak dikenal.';
  end if;
  update jo.staff set
    name = coalesce(nullif(trim(p->>'name'),''), name),
    active = coalesce((p->>'active')::boolean, active),
    discipline = case when x.role in ('asjur','verifikator') then null when p ? 'discipline' then nullif(p->>'discipline','') else discipline end,
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
    access_windows = case when x.role <> 'juri' then null when p ? 'access_windows' then jo.norm_windows(p->'access_windows') else access_windows end,
    disc_group = case when x.role in ('asjur','verifikator') and p ? 'disc_group' then coalesce(nullif(upper(p->>'disc_group'),''), disc_group) else disc_group end
  where id = x.id;
  if coalesce((p->>'active')::boolean, true) = false then
    delete from jo.staff_sessions where staff_id = x.id;
  end if;
  perform jo.log(st.id, 'kode_diubah', 'staff', x.id::text, p);
  return public.console_staff_list();
end $$;

-- Hapus kode: kode yang pernah memverifikasi / mengisi lembar nilai tidak bisa dihapus (kecuali dummy)
create or replace function jo.staff_has_jwork(p_id uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from jo.jscore_log where by_staff = p_id and mode = 'real')
$$;


-- ---------------------------------------------------------------------
-- Ganti disiplin tanpa keluar (owner, superadmin, TD tanpa batas disiplin)
-- ---------------------------------------------------------------------
create or replace function public.console_juri_switch(p_group text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_group text := upper(coalesce(p_group,''));
begin
  st := jo.require_judging(array['owner','superadmin','td']);
  if v_group not in ('ART','RG','AER') then raise exception 'Disiplin tidak dikenal.'; end if;
  if st.is_dummy or st.disc_group is not null or st.discipline is not null then
    raise exception 'Kode Anda terkunci pada satu disiplin.' using hint = 'ERR_FORBIDDEN';
  end if;
  update jo.staff_sessions set disc_group = v_group where uid = auth.uid();
  perform jo.log(st.id, 'ganti_disiplin_konsol_juri', 'staff', st.id::text, jsonb_build_object('disiplin', v_group));
  return public.console_juri_me();
end $$;

-- ---------------------------------------------------------------------
-- Log konsol juri (owner, superadmin): riwayat nilai + aktivitas konsol juri
-- ---------------------------------------------------------------------
create or replace function public.console_j_audit(p_kind text default 'nilai', p_mode text default 'real', p_limit integer default 300)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text; v_lim integer := least(greatest(coalesce(p_limit, 300), 20), 1000);
begin
  st := jo.require_judging(array['owner','superadmin']);
  select disc_group into g from jo.staff_sessions where uid = auth.uid();
  if p_kind = 'nilai' then
    return (select coalesce(jsonb_agg(x order by (x->>'at') desc), '[]'::jsonb) from (
      select jsonb_build_object('at', l.at, 'action', l.action, 'apparatus', l.apparatus, 'mode', l.mode,
        'name', jo.entry_name_mode(l.entry_id, l.mode), 'category', c.name_id,
        'old', l.old_val->>'total', 'new', l.new_val->>'total', 'status', l.new_val->>'status', 'flags', l.new_val->'flags',
        'by', s.name, 'role', s.role, 'reason', l.reason) x
      from jo.jscore_log l join jo.entries e on e.id = l.entry_id join jo.categories c on c.id = e.category_id
      left join jo.staff s on s.id = l.by_staff
      where l.mode = coalesce(nullif(p_mode,''), 'real') and c.discipline = any(jo.group_discs(g))
      order by l.at desc limit v_lim) q);
  end if;
  return (select coalesce(jsonb_agg(x order by (x->>'at') desc), '[]'::jsonb) from (
    select jsonb_build_object('at', a.at, 'action', a.action, 'target_type', a.target_type, 'target_id', a.target_id,
      'detail', a.detail, 'by', s.name, 'role', s.role, 'dummy', s.is_dummy) x
    from jo.audit a left join jo.staff s on s.id = a.staff_id
    where a.action in ('masuk_konsol_juri','ganti_disiplin_konsol_juri','panel_juri_diubah','panel_juri_dihapus','layar_diubah',
                       'simulasi_dihapus','simulasi_tayang','simulasi_disembunyikan','live_publik_dibuka','live_publik_dijeda',
                       'td_pdf_hasil','td_konfirmasi_hasil','td_hasil_ditarik')
    order by a.at desc limit v_lim) q);
end $$;

