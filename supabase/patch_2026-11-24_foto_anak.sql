-- 24/11/2026: tanda pas foto disembunyikan (atlet < 10 th, UU PDP) di direktori atlet publik
drop function if exists jo.dir_cards();
create function jo.dir_cards() returns table (
  kind text, id uuid, name text, gender text, discipline text, club text, region text,
  cats_id text[], cats_en text[], photo text, members text[], has_detail boolean, haystack text, photo_hidden boolean)
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
           bool_or(e.pub) as has_detail,
           not jo.photo_ok(ath.birth_date) as photo_hidden
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
                        where tm.team_id = t.id and (c.startlist_published or c.results_published))) as has_detail,
           false as photo_hidden
      from jo.teams t
      join jo.submissions s on s.id = t.submission_id
      left join jo.clubs k on k.id = s.club_id
     where s.status = 'lunas'
       and exists (select 1 from jo.team_members tm where tm.team_id = t.id and jo.dir_athlete_visible(tm.athlete_id))
  )
  select x.kind, x.id, x.name, x.gender, x.discipline, x.club, x.region, x.cats_id, x.cats_en, x.photo, x.members, x.has_detail,
         lower(x.name || ' ' || x.club || ' ' || x.region || ' ' || coalesce(array_to_string(x.members, ' '), '')) as haystack,
         x.photo_hidden
    from (select * from acard union all select * from tcard) x
$$;

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
        'photo', pg.photo, 'photo_hidden', pg.photo_hidden, 'members', pg.members, 'has_detail', pg.has_detail)
        order by lower(pg.name), pg.kind, pg.id), '[]'::jsonb) from pg))
  into res;
  return res;
end $$;

revoke all on function jo.dir_cards() from public, anon, authenticated;
