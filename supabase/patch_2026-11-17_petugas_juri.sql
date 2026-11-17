-- =====================================================================
--  PETUGAS & PANEL JURI per sesi + alat (17 November 2026)
--  posisi: SEAT:<kunci panel> (D, E1..), KETUA, ASJUR, VERIF, TD (alat '*'), X:<n> (posisi tambahan)
-- =====================================================================
create table if not exists jo.judge_roster (
  id          bigserial primary key,
  session_id  integer not null references jo.sessions(id) on delete cascade,
  apparatus   text not null default '*',
  position    text not null,
  label       text,
  person_name text not null,
  person_ref  text,
  sort        integer not null default 0,
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  unique (session_id, apparatus, position)
);
revoke all on table jo.judge_roster from public;
do $$ begin execute 'revoke all on table jo.judge_roster from anon, authenticated'; execute 'revoke all on sequence jo.judge_roster_id_seq from anon, authenticated'; exception when others then null; end $$;

-- kursi juri dari panel dasar disiplin untuk satu alat (tanpa Pen)
create or replace function jo.roster_seats(p_disc text, p_app text) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('position', 'SEAT:' || (sl->>'key'),
      'label', case when p.sheet = 'artistik' and sl->>'comp' = 'D' and upper(sl->>'label') = 'D' then 'D1/D2' else sl->>'label' end)
      order by o), '[]'::jsonb)
  from (select * from jo.judge_panels where discipline = p_disc and category_id is null and (apparatus = p_app or apparatus is null)
         order by (apparatus is not null) desc limit 1) p
  cross join lateral jsonb_array_elements(p.slots) with ordinality as x(sl, o)
  where sl->>'comp' <> 'PEN'
$$;

-- peta nama per sesi: {session_id: {apparatus: {position: name}}}
create or replace function jo.roster_map(p_sessions integer[]) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_object_agg(sid, m), '{}'::jsonb) from (
    select session_id::text sid, jsonb_object_agg(apparatus, pm) m from (
      select session_id, apparatus, jsonb_object_agg(position, jsonb_build_object('name', person_name, 'label', label, 'sort', sort)) pm
        from jo.judge_roster where session_id = any(p_sessions) group by session_id, apparatus) a
    group by session_id) b
$$;

create or replace function public.console_roster_sessions() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; g text;
begin
  st := jo.require_judging();
  select disc_group into g from jo.staff_sessions where uid = auth.uid();
  return jsonb_build_object(
    'can_edit', st.role in ('owner','superadmin','td') and not st.is_dummy,
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'day', s.day, 'start_time', s.start_time,
        'discipline', s.discipline, 'filled', (select count(*) from jo.judge_roster r where r.session_id = s.id),
        'categories', (select string_agg(distinct c.name_id, ', ') from jo.entries e join jo.categories c on c.id = e.category_id where e.session_id = s.id))
      order by s.day nulls last, s.start_time nulls last, s.sort, s.id), '[]'::jsonb)
      from jo.sessions s where s.discipline = any(jo.group_discs(g))));
end $$;

create or replace function public.console_roster_get(p_session integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.sessions;
begin
  st := jo.require_judging();
  select * into s from jo.sessions where id = p_session;
  if s.id is null then raise exception 'Sesi tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  return jsonb_build_object(
    'session', to_jsonb(s),
    'can_edit', st.role in ('owner','superadmin','td') and not st.is_dummy,
    'apparatus', (select coalesce(jsonb_agg(jsonb_build_object('code', a->>'code', 'name', a->>'id', 'seats', jo.roster_seats(s.discipline, a->>'code')) order by o), '[]'::jsonb)
                    from jo.disciplines d cross join jsonb_array_elements(d.apparatus) with ordinality x(a, o) where d.code = s.discipline),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('apparatus', r.apparatus, 'position', r.position, 'label', r.label,
               'name', r.person_name, 'ref', r.person_ref, 'sort', r.sort) order by r.apparatus, r.sort, r.id), '[]'::jsonb)
             from jo.judge_roster r where r.session_id = s.id),
    'people', (select coalesce(jsonb_agg(distinct jsonb_build_object('name', n, 'src', src)), '[]'::jsonb) from (
        select j.full_name n, 'juri' src from jo.jury_applications j
         where j.status = 'disetujui' and (j.disciplines is null or s.discipline = any(j.disciplines) or jo.disc_group_of(s.discipline) = any(j.disciplines))
        union
        select x.name, x.role from jo.staff x
         where x.active and not x.is_dummy and x.role in ('juri','asjur','verifikator','td')
           and (x.discipline is null or x.discipline = s.discipline) and (x.disc_group is null or x.disc_group = jo.disc_group_of(s.discipline))
      ) q),
    'others', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'day', o.day, 'start_time', o.start_time) order by o.day, o.start_time, o.id), '[]'::jsonb)
               from jo.sessions o where o.discipline = s.discipline and o.id <> s.id and exists (select 1 from jo.judge_roster r where r.session_id = o.id)));
end $$;

create or replace function public.console_roster_save(p_session integer, p_rows jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; s jo.sessions; r jsonb; n integer := 0; i integer := 0;
begin
  st := jo.require_judging(array['owner','superadmin','td']);
  if st.is_dummy then raise exception 'Kode dummy tidak bisa mengubah petugas.' using hint = 'ERR_FORBIDDEN'; end if;
  select * into s from jo.sessions where id = p_session for update;
  if s.id is null then raise exception 'Sesi tidak ditemukan.'; end if;
  perform jo.check_discipline(st, s.discipline);
  delete from jo.judge_roster where session_id = s.id;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    i := i + 1;
    if length(trim(coalesce(r->>'name',''))) = 0 or length(trim(coalesce(r->>'position',''))) = 0 then continue; end if;
    insert into jo.judge_roster (session_id, apparatus, position, label, person_name, person_ref, sort, updated_by)
    values (s.id, coalesce(nullif(upper(trim(r->>'apparatus')),''), '*'), left(trim(r->>'position'), 40),
            left(nullif(trim(coalesce(r->>'label','')),''), 60), left(trim(r->>'name'), 120), nullif(r->>'ref',''), i, st.id)
    on conflict (session_id, apparatus, position) do update set label = excluded.label, person_name = excluded.person_name,
      person_ref = excluded.person_ref, sort = excluded.sort, updated_at = now(), updated_by = st.id;
    n := n + 1;
  end loop;
  perform jo.log(st.id, 'petugas_juri_disimpan', 'session', s.id::text, jsonb_build_object('sesi', s.name, 'jumlah', n));
  return public.console_roster_get(s.id);
end $$;

create or replace function public.console_roster_copy(p_from integer, p_to integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; a jo.sessions; b jo.sessions;
begin
  st := jo.require_judging(array['owner','superadmin','td']);
  if st.is_dummy then raise exception 'Kode dummy tidak bisa mengubah petugas.' using hint = 'ERR_FORBIDDEN'; end if;
  select * into a from jo.sessions where id = p_from; select * into b from jo.sessions where id = p_to;
  if a.id is null or b.id is null then raise exception 'Sesi tidak ditemukan.'; end if;
  perform jo.check_discipline(st, b.discipline);
  if a.discipline <> b.discipline then raise exception 'Hanya bisa menyalin dari sesi disiplin yang sama.'; end if;
  delete from jo.judge_roster where session_id = b.id;
  insert into jo.judge_roster (session_id, apparatus, position, label, person_name, person_ref, sort, updated_by)
  select b.id, apparatus, position, label, person_name, person_ref, sort, st.id from jo.judge_roster where session_id = a.id;
  perform jo.log(st.id, 'petugas_juri_disalin', 'session', b.id::text, jsonb_build_object('dari', a.name, 'ke', b.name));
  return public.console_roster_get(b.id);
end $$;

revoke all on function jo.roster_seats(text, text) from public;
revoke all on function jo.roster_map(integer[]) from public;
revoke all on function public.console_roster_sessions() from public, anon;
revoke all on function public.console_roster_get(integer) from public, anon;
revoke all on function public.console_roster_save(integer, jsonb) from public, anon;
revoke all on function public.console_roster_copy(integer, integer) from public, anon;
grant execute on function public.console_roster_sessions() to authenticated;
grant execute on function public.console_roster_get(integer) to authenticated;
grant execute on function public.console_roster_save(integer, jsonb) to authenticated;
grant execute on function public.console_roster_copy(integer, integer) to authenticated;
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
    'roster', jo.roster_map(array(select distinct x.session_id from jo.entries x where x.category_id = c.id and x.session_id is not null)),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'entry_id', e.id, 'name', jo.entry_name_mode(e.id, v_mode), 'club', jo.entry_club_label(e.id), 'session_id', e.session_id,
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
    'signatories', jo.setting('signatories'),
    'roster', jo.roster_map(array(select distinct x.session_id from jo.entries x where x.category_id = c.id and x.session_id is not null)),
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object('id', ss.id, 'name', ss.name, 'day', ss.day, 'start_time', ss.start_time) order by ss.day, ss.start_time), '[]'::jsonb)
                 from jo.sessions ss where ss.id in (select distinct x.session_id from jo.entries x where x.category_id = c.id)));
end $$;
