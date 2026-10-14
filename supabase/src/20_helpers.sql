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

-- Hasil satu kategori. Aturan dari medal_rule:
--   places (medali 1-3), aa_places (peringkat serba bisa yang dihargai, 4-6 = medali mini),
--   apparatus_medals (medali 1-3 per alat), club_cap (maks. pesenam per klub untuk setiap penghargaan;
--   pesenam ke-3 dst. dari klub yang sama dilewati dan penghargaan turun ke pesenam berikutnya).
create or replace function jo.category_results(p_cat integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare c jo.categories; places integer; aa_places integer; cap integer; app_med boolean; res jsonb;
begin
  select * into c from jo.categories where id = p_cat;
  if c.id is null then return '[]'::jsonb; end if;
  places    := coalesce((c.medal_rule->>'places')::integer, 3);
  aa_places := greatest(places, coalesce((c.medal_rule->>'aa_places')::integer, places));
  cap       := nullif((c.medal_rule->>'club_cap')::integer, 0);
  app_med   := coalesce((c.medal_rule->>'apparatus_medals')::boolean, false);

  with e as (
    select en.id, (en.priangan_status = 'disetujui' and not en.team_only) as pri, en.team_only as tonly,
           en.start_order, en.group_no, coalesce(s.club_id::text, en.id::text) as clubkey
    from jo.entries en join jo.submissions s on s.id = en.submission_id
    where en.category_id = p_cat and en.status = 'aktif' and s.status = 'lunas'
  ),
  ap as (select unnest(c.apparatus) as app),
  sc as (
    select e.id, e.tonly, e.clubkey, ap.app, jo.apparatus_score(e.id, ap.app) as score from e cross join ap
  ),
  apr as (
    select id, app, score, tonly, clubkey,
      case when score is not null then rank() over (partition by app, (score is null) order by score desc) end as arank,
      case when score is not null and not tonly
           then row_number() over (partition by app, clubkey, (score is null or tonly) order by score desc) end as club_n
    from sc
  ),
  apa as (
    -- peringkat penghargaan per alat (setelah batas per klub)
    select id, app, score, arank,
      case when score is not null and not tonly and (cap is null or club_n <= cap)
           then rank() over (partition by app, (score is null or tonly or (cap is not null and club_n > cap)) order by score desc) end as award
    from apr
  ),
  tot as (
    select id, round(sum(score), 3) as total, count(score) as n_scored,
      jsonb_object_agg(app, score) as scores,
      jsonb_object_agg(app, arank) as app_ranks,
      case when app_med then coalesce(jsonb_object_agg(app,
          case award when 1 then 'emas' when 2 then 'perak' when 3 then 'perunggu' end)
        filter (where award between 1 and 3), '{}'::jsonb) else '{}'::jsonb end as app_medals
    from apa group by id
  ),
  rk as (
    -- anggota "khusus beregu" dinilai tetapi tidak ikut peringkat perorangan
    select e.id, e.pri, e.tonly, e.clubkey, e.start_order, e.group_no, t.total, t.n_scored, t.scores, t.app_ranks, t.app_medals,
      case when t.total is not null and not e.tonly then rank() over (partition by (t.total is null or e.tonly) order by t.total desc) end as rnk,
      case when t.total is not null and not e.tonly
           then row_number() over (partition by e.clubkey, (t.total is null or e.tonly) order by t.total desc, e.start_order nulls last) end as club_n,
      case when e.pri and t.total is not null
           then rank() over (partition by (e.pri and t.total is not null) order by t.total desc) end as prnk
    from e join tot t on t.id = e.id
  ),
  rk2 as (
    select rk.*,
      case when rnk is not null and (cap is null or club_n <= cap)
           then rank() over (partition by (rnk is null or (cap is not null and club_n > cap)) order by total desc) end as award
    from rk
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
      'award_rank', case when rk.award <= aa_places then rk.award end,
      'capped', rk.rnk is not null and cap is not null and rk.club_n > cap and rk.rnk <= aa_places,
      'medal', case when c.exhibition or rk.award is null or rk.award > places then null
                    when rk.award = 1 then 'emas' when rk.award = 2 then 'perak' else 'perunggu' end,
      'mini', not c.exhibition and rk.award is not null and rk.award > places and rk.award <= aa_places,
      'app_medals', case when c.exhibition then '{}'::jsonb else rk.app_medals end,
      'team_only', rk.tonly,
      'priangan', rk.pri,
      'priangan_rank', rk.prnk,
      'priangan_medal', case when c.exhibition or rk.prnk is null or rk.prnk > places then null
                    when rk.prnk = 1 then 'emas' when rk.prnk = 2 then 'perak' else 'perunggu' end
    ) order by rk.rnk nulls last, rk.tonly, rk.start_order nulls last), '[]'::jsonb)
  into res
  from rk2 rk;
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
    union all
    -- medali per alat (hanya tabel Jabar Open, bukan Priangan)
    select r.discipline, r.x->>'club', r.x->>'region', am.value
    from rows r cross join lateral jsonb_each_text(coalesce(r.x->'app_medals', '{}'::jsonb)) am
    where not p_priangan
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
