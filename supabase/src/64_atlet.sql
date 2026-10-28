-- =====================================================================
--  Direktori atlet publik (v12, 28/10/2026) — halaman atlet.html
--  * Tertutup selama masa pendaftaran. Mode 'auto' membuka otomatis pada
--    athletes_release_at (12 Des 2026 00:00 WIB); owner/superadmin bisa
--    memaksa 'on' atau 'off' dari Konsol > Pengaturan.
--  * Hanya atlet terdaftar penuh: pendaftaran lunas, dokumen valid, dan
--    minimal satu nomor yang tidak dibatalkan. Tanggal lahir tidak pernah
--    dikirim; pas foto atlet yang berusia di bawah 10 tahun pada hari
--    pertama kejuaraan tidak pernah dikirim.
--  * Tim beregu tampil sebagai kartu sendiri.
--  * Rincian (jadwal & medali) hanya muncul setelah jadwal pertandingan
--    atau hasil kategori terkait dipublikasikan.
-- =====================================================================
insert into jo.settings (key, value) values
  ('athletes_directory', '"auto"'::jsonb),
  ('athletes_release_at', '"2026-12-12T00:00:00+07:00"'::jsonb)
on conflict (key) do nothing;

create or replace function jo.athletes_open() returns boolean
language sql stable set search_path = '' as $$
  select case coalesce(jo.setting_text('athletes_directory'), 'auto')
    when 'on' then true
    when 'off' then false
    else now() >= coalesce(nullif(jo.setting_text('athletes_release_at'), '')::timestamptz,
                           timestamptz '2026-12-12 00:00:00+07')
  end
$$;

-- batas usia pas foto: lahir paling lambat 10 tahun sebelum hari pertama kejuaraan
create or replace function jo.photo_ok(p_birth date) returns boolean
language sql immutable set search_path = '' as $$
  select p_birth is not null and p_birth <= date '2016-12-12'
$$;

-- atlet yang boleh tampil
create or replace function jo.dir_athlete_visible(p_athlete uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from jo.athletes a
      join jo.submissions s on s.id = a.submission_id
      join jo.entry_athletes ea on ea.athlete_id = a.id
      join jo.entries en on en.id = ea.entry_id
     where a.id = p_athlete and s.status = 'lunas' and a.doc_status = 'valid' and en.status <> 'dibatalkan')
$$;

-- semua kartu (atlet + tim beregu) dalam satu bentuk
create or replace function jo.dir_cards() returns table (
  kind text, id uuid, name text, gender text, discipline text, club text, region text,
  cats_id text[], cats_en text[], photo text, members text[], has_detail boolean, haystack text)
language sql stable set search_path = '' as $$
  with ath as (
    select a.id, a.full_name, a.gender, a.birth_date, a.photo_thumb, s.discipline,
           coalesce(k.name, 'Perorangan') as club,
           coalesce(k.kab_kota, a.kab_kota, k.country, a.country, 'Tidak diketahui') as region
      from jo.athletes a
      join jo.submissions s on s.id = a.submission_id
      left join jo.clubs k on k.id = s.club_id
     where s.status = 'lunas' and a.doc_status = 'valid'
  ),
  ent as (
    select ea.athlete_id, c.name_id, c.name_en, c.sort, c.id as cat_id,
           (c.startlist_published or c.results_published) as pub
      from jo.entry_athletes ea
      join jo.entries en on en.id = ea.entry_id and en.status <> 'dibatalkan'
      join jo.categories c on c.id = en.category_id
  ),
  acard as (
    select 'athlete'::text as kind, ath.id, ath.full_name as name, ath.gender, ath.discipline, ath.club, ath.region,
           array_agg(distinct e.name_id) as cats_id, array_agg(distinct e.name_en) as cats_en,
           case when jo.photo_ok(ath.birth_date) then ath.photo_thumb end as photo,
           null::text[] as members,
           bool_or(e.pub) as has_detail
      from ath join ent e on e.athlete_id = ath.id
     group by ath.id, ath.full_name, ath.gender, ath.discipline, ath.club, ath.region, ath.birth_date, ath.photo_thumb
  ),
  tcard as (
    select 'team'::text as kind, t.id, t.name, case when t.discipline = 'WAG' then 'F' when t.discipline = 'MAG' then 'M' else 'X' end as gender,
           t.discipline, coalesce(k.name, 'Perorangan') as club, coalesce(k.kab_kota, k.country, 'Tidak diketahui') as region,
           array['Beregu ' || t.level] as cats_id, array['Team ' || t.level] as cats_en,
           null::text as photo,
           array(select a.full_name from jo.team_members tm join jo.athletes a on a.id = tm.athlete_id
                  where tm.team_id = t.id and jo.dir_athlete_visible(a.id) order by tm.sort, a.full_name) as members,
           (coalesce((select tl.published from jo.team_levels tl where tl.discipline = t.discipline and tl.level = t.level), false)
            or exists (select 1 from jo.team_members tm join jo.entries en on en.id = tm.entry_id
                        join jo.categories c on c.id = en.category_id
                        where tm.team_id = t.id and (c.startlist_published or c.results_published))) as has_detail
      from jo.teams t
      join jo.submissions s on s.id = t.submission_id
      left join jo.clubs k on k.id = s.club_id
     where s.status = 'lunas'
       and exists (select 1 from jo.team_members tm where tm.team_id = t.id and jo.dir_athlete_visible(tm.athlete_id))
  )
  select x.*, lower(x.name || ' ' || x.club || ' ' || x.region || ' ' || coalesce(array_to_string(x.members, ' '), '')) as haystack
    from (select * from acard union all select * from tcard) x
$$;

create or replace function public.public_athletes_open() returns boolean
language sql stable security definer set search_path = '' as $$
  select jo.athletes_open()
$$;

-- daftar kartu, disaring dan dipotong per halaman (pas foto dikirim hanya untuk halaman yang diminta)
create or replace function public.public_athletes(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_q text := lower(btrim(coalesce(p->>'q', '')));
  v_disc text := nullif(p->>'discipline', '');
  v_region text := nullif(p->>'region', '');
  v_club text := nullif(p->>'club', '');
  v_gender text := nullif(p->>'gender', '');
  v_off integer := greatest(coalesce((p->>'offset')::integer, 0), 0);
  v_lim integer := least(greatest(coalesce((p->>'limit')::integer, 24), 1), 48);
  res jsonb;
begin
  if not jo.athletes_open() then return jsonb_build_object('open', false); end if;
  if length(v_q) > 80 then v_q := left(v_q, 80); end if;
  with f as (
    select * from jo.dir_cards() c
     where (v_q = '' or c.haystack like '%' || v_q || '%')
       and (v_disc is null or c.discipline = v_disc)
       and (v_region is null or c.region = v_region)
       and (v_club is null or c.club = v_club)
       and (v_gender is null or c.gender = v_gender)
  ), pg as (
    select * from f order by lower(f.name), f.kind, f.id offset v_off limit v_lim
  )
  select jsonb_build_object(
    'open', true,
    'total', (select count(*) from f),
    'athletes', (select count(*) from f where kind = 'athlete'),
    'teams', (select count(*) from f where kind = 'team'),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
        'kind', pg.kind, 'id', pg.id, 'name', pg.name, 'gender', pg.gender, 'discipline', pg.discipline,
        'club', pg.club, 'region', pg.region, 'cats_id', pg.cats_id, 'cats_en', pg.cats_en,
        'photo', pg.photo, 'members', pg.members, 'has_detail', pg.has_detail)
        order by lower(pg.name), pg.kind, pg.id), '[]'::jsonb) from pg))
  into res;
  return res;
end $$;

-- pilihan saringan: kab/kota dan klub yang punya atlet tampil
create or replace function public.public_athletes_filters() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not jo.athletes_open() then return jsonb_build_object('open', false); end if;
  return (with c as (select * from jo.dir_cards())
    select jsonb_build_object('open', true,
      'regions', (select coalesce(jsonb_agg(r order by r), '[]'::jsonb) from (select distinct region as r from c) x),
      'clubs', (select coalesce(jsonb_agg(jsonb_build_object('name', k, 'region', rg) order by lower(k)), '[]'::jsonb)
                  from (select club as k, min(region) as rg from c group by club) y)));
end $$;

-- rincian satu kartu: jadwal (bila jadwal kategori terbit) dan hasil/medali (bila hasil terbit)
create or replace function jo.dir_entry_json(p_entry uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare en jo.entries; c jo.categories; ses jo.sessions; r jsonb; out jsonb;
begin
  select * into en from jo.entries where id = p_entry;
  select * into c from jo.categories where id = en.category_id;
  out := jsonb_build_object('category_id', c.id, 'discipline', c.discipline, 'name_id', c.name_id, 'name_en', c.name_en,
                            'team_only', en.team_only, 'dns', en.status = 'dns');
  if c.startlist_published then
    select * into ses from jo.sessions where id = en.session_id;
    out := out || jsonb_build_object('schedule', jsonb_build_object(
      'session', ses.name, 'day', ses.day, 'start_time', ses.start_time, 'group_no', en.group_no, 'start_order', en.start_order));
  end if;
  if c.results_published then
    select x into r from jsonb_array_elements(jo.category_results(c.id)) x where x->>'entry_id' = p_entry::text;
    if r is not null then
      out := out || jsonb_build_object('result', jsonb_build_object(
        'rank', r->'rank', 'total', r->'total', 'medal', r->'medal', 'mini', r->'mini', 'award_rank', r->'award_rank',
        'app_medals', r->'app_medals', 'priangan_rank', r->'priangan_rank', 'priangan_medal', r->'priangan_medal',
        'exhibition', c.exhibition));
    end if;
  end if;
  return out;
end $$;

create or replace function jo.dir_team_result(p_team uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare t jo.teams; r jsonb;
begin
  select * into t from jo.teams where id = p_team;
  if not coalesce((select tl.published from jo.team_levels tl where tl.discipline = t.discipline and tl.level = t.level), false) then
    return null;
  end if;
  select x into r from jsonb_array_elements(jo.team_results(t.discipline, t.level, false)) x where x->>'team_id' = p_team::text;
  if r is null then return null; end if;
  return jsonb_build_object('rank', r->'rank', 'total', r->'total', 'trophy', r->'trophy');
end $$;

create or replace function public.public_athlete_detail(p_kind text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t jo.teams;
begin
  if not jo.athletes_open() then return jsonb_build_object('open', false); end if;
  if p_kind = 'athlete' then
    if not jo.dir_athlete_visible(p_id) then raise exception 'Data atlet tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
    return jsonb_build_object('open', true,
      'entries', (select coalesce(jsonb_agg(jo.dir_entry_json(en.id) order by c.sort, c.id), '[]'::jsonb)
                    from jo.entry_athletes ea join jo.entries en on en.id = ea.entry_id and en.status <> 'dibatalkan'
                    join jo.categories c on c.id = en.category_id
                   where ea.athlete_id = p_id),
      'teams', (select coalesce(jsonb_agg(jsonb_build_object('name', tm.name, 'level', tm.level, 'discipline', tm.discipline,
                        'result', jo.dir_team_result(tm.id)) order by tm.name), '[]'::jsonb)
                  from jo.teams tm join jo.submissions s on s.id = tm.submission_id
                 where s.status = 'lunas' and exists (select 1 from jo.team_members x where x.team_id = tm.id and x.athlete_id = p_id)));
  elsif p_kind = 'team' then
    select tm.* into t from jo.teams tm join jo.submissions s on s.id = tm.submission_id where tm.id = p_id and s.status = 'lunas';
    if t.id is null then raise exception 'Data tim tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
    return jsonb_build_object('open', true,
      'result', jo.dir_team_result(t.id),
      'members', (select coalesce(jsonb_agg(jo.dir_entry_json(tm.entry_id) || jsonb_build_object('name', a.full_name)
                        order by tm.sort, a.full_name), '[]'::jsonb)
                    from jo.team_members tm join jo.athletes a on a.id = tm.athlete_id
                   where tm.team_id = t.id and jo.dir_athlete_visible(a.id)));
  end if;
  raise exception 'Permintaan tidak dikenal.' using hint = 'ERR_KIND';
end $$;

-- Konsol: lihat dan ubah mode direktori (owner, superadmin)
create or replace function public.console_athletes_directory() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'mode', coalesce(jo.setting_text('athletes_directory'), 'auto'),
    'release_at', jo.setting_text('athletes_release_at'),
    'open', jo.athletes_open(),
    'visible', (select count(*) from jo.dir_cards() where kind = 'athlete'),
    'teams', (select count(*) from jo.dir_cards() where kind = 'team'),
    'hidden_photos', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
                       where s.status = 'lunas' and a.doc_status = 'valid' and not jo.photo_ok(a.birth_date)));
end $$;

create or replace function public.console_set_athletes_directory(p_mode text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  if p_mode not in ('auto','on','off') then raise exception 'Mode tidak dikenal.' using hint = 'ERR_MODE'; end if;
  insert into jo.settings (key, value, updated_at, updated_by) values ('athletes_directory', to_jsonb(p_mode), now(), st.id)
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
  perform jo.log(st.id, 'pengaturan_diubah', 'setting', 'athletes_directory', jsonb_build_object('value', p_mode));
  return public.console_athletes_directory();
end $$;
