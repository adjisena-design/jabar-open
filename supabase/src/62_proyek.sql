-- =====================================================================
--  Modul Proyek (v10, 21/10/2026; v11 26/10/2026 RAB rekonsiliasi): Gantt, Struktur, RAB, Pendapatan
--  Pindahan dari workbook "RAB Jabar Open 2026 - Gabungan.xlsx".
--  * Tulis (tambah/ubah/arsip/unggah): hanya OWNER.
--  * Lihat & unduh Gantt/Struktur: owner, superadmin, TD, bendahara.
--  * Lihat & unduh RAB/Pendapatan: owner, superadmin, bendahara.
--  * Nilai turunan (Hari 2026, Harga 2026, Total, Hemat, Durasi, Peringatan,
--    ringkasan) dihitung di fungsi, tidak disimpan.
--  * Hapus = arsip (archived_at), jadi baris bisa dipulihkan.
-- =====================================================================

create table if not exists jo.pm_divisions (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  tier        text not null default 'divisi' check (tier in ('pengarah','pm','divisi')),
  head_name   text,
  head_title  text,
  description text,
  sort        integer not null default 0,
  updated_at  timestamptz not null default now(),
  archived_at timestamptz
);
create table if not exists jo.pm_members (
  id          uuid primary key default gen_random_uuid(),
  division_id uuid references jo.pm_divisions(id),
  name        text not null,
  role_text   text,
  phone       text,
  staff_id    uuid references jo.staff(id),
  sort        integer not null default 0,
  updated_at  timestamptz not null default now(),
  archived_at timestamptz
);
create table if not exists jo.pm_phases (
  no    integer primary key,
  name  text not null
);
create table if not exists jo.pm_tasks (
  id           uuid primary key default gen_random_uuid(),
  no           integer,
  phase        integer,
  task         text not null,
  pic          text,
  role_text    text,
  division_id  uuid references jo.pm_divisions(id),
  start_date   date,
  end_date     date,
  predecessors integer[] not null default '{}',
  critical     boolean not null default false,
  status       text not null default 'Belum mulai' check (status in ('Belum mulai','Berjalan','Selesai','Tertunda')),
  percent      numeric not null default 0 check (percent >= 0 and percent <= 1),
  note         text,
  sort         integer not null default 0,
  flagged      text,
  updated_at   timestamptz not null default now(),
  archived_at  timestamptz
);
create index if not exists pm_tasks_sort on jo.pm_tasks (phase, sort);
create table if not exists jo.pm_rab_params (
  id         integer primary key default 1 check (id = 1),
  increase   numeric not null default 0.2,
  days_2025  numeric not null default 6,
  days_2026  numeric not null default 9,
  note       text,
  updated_at timestamptz not null default now()
);
create table if not exists jo.pm_rab_sections (
  code        text primary key,
  name        text not null,
  fixed_price boolean not null default false,
  sort        integer not null default 0
);
create table if not exists jo.pm_rab_items (
  id            uuid primary key default gen_random_uuid(),
  section       text not null references jo.pm_rab_sections(code),
  sort          integer not null default 0,
  uraian        text not null,
  keterangan    text,
  vol           numeric not null default 0,
  satuan        text,
  days_2025     numeric,
  price_2025    numeric,
  price_final   numeric,
  status_sistem text check (status_sistem in ('DIHAPUS','DIKURANGI','SISTEM')),
  pct_replaced  numeric not null default 0 check (pct_replaced >= 0 and pct_replaced <= 1),
  note          text,
  flagged       text,
  updated_at    timestamptz not null default now(),
  archived_at   timestamptz
);
create table if not exists jo.pm_income_items (
  id          uuid primary key default gen_random_uuid(),
  grp         text not null check (grp in ('2025','2026')),
  sort        integer not null default 0,
  source      text,
  keterangan  text,
  vol         numeric not null default 0,
  unit        text,
  rate        numeric not null default 0,
  note        text,
  ledger_key  text,
  flagged     text,
  updated_at  timestamptz not null default now(),
  archived_at timestamptz
);
-- v11 (26/10/2026): model RAB rekonsiliasi Inda Sofia: harga final, frekuensi, hari kegiatan, dihitung/tidak
alter table jo.pm_rab_params   add column if not exists event_days numeric not null default 10;
alter table jo.pm_rab_sections add column if not exists hidden boolean not null default false;
alter table jo.pm_rab_sections add column if not exists is_note boolean not null default false;
alter table jo.pm_rab_items    add column if not exists freq numeric;
alter table jo.pm_rab_items    add column if not exists freq_unit text;
alter table jo.pm_rab_items    add column if not exists vol_days boolean not null default false;
alter table jo.pm_rab_items    add column if not exists freq_days boolean not null default false;
alter table jo.pm_rab_items    add column if not exists counted boolean not null default true;
alter table jo.pm_rab_items    add column if not exists source text;

do $$ declare t text; begin
  foreach t in array array['pm_divisions','pm_members','pm_phases','pm_tasks','pm_rab_params','pm_rab_sections','pm_rab_items','pm_income_items'] loop
    execute format('alter table jo.%I enable row level security', t);
  end loop;
end $$;
insert into jo.pm_rab_params (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Akses
-- ---------------------------------------------------------------------
create or replace function jo.pm_require(p_area text) returns jo.staff
language plpgsql stable set search_path = '' as $$
declare st jo.staff;
begin
  if p_area = 'tulis' then
    st := jo.require_staff(array['owner']);
  elsif p_area = 'keuangan' then
    st := jo.require_staff(array['owner','superadmin','bendahara']);
  else
    st := jo.require_staff(array['owner','superadmin','td','bendahara']);
  end if;
  if not coalesce(jo.setting_bool('pm_enabled'), true) and st.role <> 'owner' then
    raise exception 'Modul proyek sedang dinonaktifkan owner.' using hint = 'ERR_FORBIDDEN';
  end if;
  return st;
end $$;

create or replace function jo.pm_today() returns date
language sql stable set search_path = '' as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function jo.pm_warning(t jo.pm_tasks) returns text
language sql stable set search_path = '' as $$
  select case
    when t.end_date is null or t.status = 'Selesai' then null
    when t.end_date < jo.pm_today() then 'TERLAMBAT'
    when t.start_date <= jo.pm_today() and t.status = 'Belum mulai' then 'HARUS MULAI'
  end
$$;

-- ---------------------------------------------------------------------
-- Baca: Gantt & Struktur
-- ---------------------------------------------------------------------
create or replace function public.console_pm_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.pm_require('lihat');
  return jsonb_build_object(
    'can_edit', st.role = 'owner',
    'can_finance', st.role in ('owner','superadmin','bendahara'),
    'enabled', coalesce(jo.setting_bool('pm_enabled'), true),
    'today', jo.pm_today(),
    'phases', (select coalesce(jsonb_agg(jsonb_build_object('no', no, 'name', name) order by no), '[]'::jsonb) from jo.pm_phases),
    'divisions', (select coalesce(jsonb_agg(to_jsonb(d) - 'archived_at' order by d.sort, d.name), '[]'::jsonb)
                    from jo.pm_divisions d where d.archived_at is null),
    'members', (select coalesce(jsonb_agg(to_jsonb(m) - 'archived_at' order by m.sort, m.name), '[]'::jsonb)
                  from jo.pm_members m where m.archived_at is null),
    'tasks', (select coalesce(jsonb_agg(to_jsonb(t) - 'archived_at' || jsonb_build_object(
                  'duration', case when t.start_date is not null and t.end_date is not null then t.end_date - t.start_date + 1 end,
                  'warning', jo.pm_warning(t)) order by coalesce(t.phase, 99), t.sort, t.no), '[]'::jsonb)
                from jo.pm_tasks t where t.archived_at is null));
end $$;

-- ---------------------------------------------------------------------
-- Baca: RAB & Pendapatan (rumus sama dengan workbook)
-- ---------------------------------------------------------------------
drop function if exists jo.pm_rab_calc();
create or replace function jo.pm_rab_calc() returns table (
  id uuid, section text, days_2026 numeric, price_2026 numeric, total numeric, saved numeric, vol_eff numeric, freq_eff numeric)
language sql stable set search_path = '' as $$
  select i.id, i.section, x.d26, x.p26,
         x.v * coalesce(x.f, 1) * coalesce(x.p26, 0),
         x.v * coalesce(x.f, 1) * coalesce(x.p26, 0) * i.pct_replaced,
         x.v, x.f
    from jo.pm_rab_items i
    join jo.pm_rab_sections s on s.code = i.section
    cross join jo.pm_rab_params p
    cross join lateral (select
        case when s.fixed_price or i.days_2025 is null then null
             else ceil(i.days_2025 * p.days_2026 / nullif(p.days_2025, 0)) end as d26,
        case when s.fixed_price then i.price_final
             when i.price_2025 is null then null
             else ceil(i.price_2025 * (1 + p.increase) / 1000) * 1000 end as p26,
        case when i.vol_days then p.event_days else i.vol end as v,
        case when not s.fixed_price then ceil(i.days_2025 * p.days_2026 / nullif(p.days_2025, 0))
             when i.freq_days then p.event_days else i.freq end as f) x
   where i.archived_at is null
$$;

create or replace function public.console_pm_finance() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; v_total numeric; v_ref numeric; v_eff numeric; v_sys numeric; v_income numeric;
begin
  st := jo.pm_require('keuangan');
  select coalesce(sum(c.total) filter (where i.counted and not s.is_note), 0),
         coalesce(sum(c.total) filter (where not i.counted and not s.is_note), 0),
         coalesce(sum(c.total) filter (where s.is_note), 0) + coalesce(sum(c.saved) filter (where not s.is_note), 0),
         coalesce(sum(c.total) filter (where i.counted and not s.is_note and s.fixed_price and upper(s.name) like '%SISTEM%'), 0)
    into v_total, v_ref, v_eff, v_sys
    from jo.pm_rab_calc() c join jo.pm_rab_items i on i.id = c.id join jo.pm_rab_sections s on s.code = c.section;
  select coalesce(sum(vol * rate), 0) into v_income from jo.pm_income_items where archived_at is null;
  return jsonb_build_object(
    'can_edit', st.role = 'owner',
    'params', (select to_jsonb(p) from jo.pm_rab_params p where id = 1),
    'sections', (select coalesce(jsonb_agg(to_jsonb(s) order by s.sort, s.code), '[]'::jsonb) from jo.pm_rab_sections s where not s.hidden),
    'items', (select coalesce(jsonb_agg(to_jsonb(i) - 'archived_at' || jsonb_build_object(
                 'days_2026', c.days_2026, 'price_2026', c.price_2026, 'total', c.total, 'saved', c.saved,
                 'vol_eff', c.vol_eff, 'freq_eff', c.freq_eff)
                 order by s.sort, i.sort), '[]'::jsonb)
                from jo.pm_rab_items i join jo.pm_rab_calc() c on c.id = i.id join jo.pm_rab_sections s on s.code = i.section),
    'summary', jsonb_build_object(
        'total', v_total, 'reference', v_ref, 'efficiency', v_eff, 'system', v_sys,
        -- kunci lama tetap dikirim untuk halaman Pendapatan
        'ops', v_total - v_sys, 'saved', v_eff, 'after_saving', v_total,
        'income', v_income, 'balance', v_income - v_total),
    'income', (select coalesce(jsonb_agg(to_jsonb(i) - 'archived_at' || jsonb_build_object('total', i.vol * i.rate) order by i.grp, i.sort), '[]'::jsonb)
                 from jo.pm_income_items i where i.archived_at is null),
    -- pendaftaran 2026 yang sudah lunas, untuk dibandingkan dengan target (dasar 2025)
    'actual', jsonb_build_object(
        'by_discipline', (select coalesce(jsonb_object_agg(d.code, jsonb_build_object(
             'athletes_paid', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.discipline = d.code and s.status = 'lunas'),
             'athletes_registered', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id where s.discipline = d.code and s.status <> 'dibatalkan'),
             'paid', (select coalesce(sum(coalesce(s.paid_amount, s.total_amount)), 0) from jo.submissions s where s.discipline = d.code and s.status = 'lunas'),
             'pairs_paid', (select count(*) from jo.entries e join jo.categories c on c.id = e.category_id join jo.submissions s on s.id = e.submission_id
                              where s.discipline = d.code and s.status = 'lunas' and c.entry_type = 'pair' and e.status <> 'dibatalkan'),
             'pair_fees', (select coalesce(sum(e.fee), 0) from jo.entries e join jo.categories c on c.id = e.category_id join jo.submissions s on s.id = e.submission_id
                              where s.discipline = d.code and s.status = 'lunas' and c.entry_type = 'pair' and e.status <> 'dibatalkan'))), '{}'::jsonb)
             from jo.disciplines d),
        'paid_total', (select coalesce(sum(coalesce(paid_amount, total_amount)), 0) from jo.submissions where status = 'lunas'),
        'outstanding', (select coalesce(sum(total_amount), 0) from jo.submissions where status in ('menunggu_pembayaran','menunggu_verifikasi','perlu_perbaikan'))));
end $$;

-- ---------------------------------------------------------------------
-- Tulis (owner): simpan satu baris
-- ---------------------------------------------------------------------
create or replace function jo.pm_num(v jsonb) returns numeric
language sql immutable set search_path = '' as $$
  select case when v is null or jsonb_typeof(v) = 'null' or btrim(v #>> '{}') = '' then null
              else replace(regexp_replace(v #>> '{}', '[^0-9,.\-]', '', 'g'), ',', '.')::numeric end
$$;

create or replace function jo.pm_save_row(p_kind text, p jsonb) returns uuid
language plpgsql volatile set search_path = '' as $$
declare v_id uuid := nullif(p->>'id','')::uuid; v_div uuid; v_pred integer[];
begin
  if p_kind = 'task' then
    if length(btrim(coalesce(p->>'task',''))) < 2 then raise exception 'Isi nama tugas.'; end if;
    v_div := coalesce(nullif(p->>'division_id','')::uuid,
                      (select id from jo.pm_divisions where name = btrim(coalesce(p->>'division','')) and archived_at is null));
    select coalesce(array_agg(x::integer order by x::integer), '{}') into v_pred
      from regexp_split_to_table(coalesce(p->>'predecessors',''), '[^0-9]+') x where x <> '';
    if v_id is null then
      insert into jo.pm_tasks (no, phase, task, pic, role_text, division_id, start_date, end_date, predecessors, critical, status, percent, note, sort)
      values (coalesce(nullif(p->>'no','')::integer, (select coalesce(max(no), 0) + 1 from jo.pm_tasks)),
              nullif(p->>'phase','')::integer, btrim(p->>'task'), nullif(btrim(coalesce(p->>'pic','')),''), nullif(btrim(coalesce(p->>'role_text','')),''),
              v_div, nullif(p->>'start_date','')::date, nullif(p->>'end_date','')::date, v_pred,
              coalesce((p->>'critical')::boolean, false), coalesce(nullif(p->>'status',''), 'Belum mulai'),
              least(greatest(coalesce(jo.pm_num(p->'percent'), 0), 0), 1), nullif(btrim(coalesce(p->>'note','')),''),
              coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 10 from jo.pm_tasks)))
      returning id into v_id;
    else
      update jo.pm_tasks set
        no = coalesce(nullif(p->>'no','')::integer, no), phase = nullif(p->>'phase','')::integer, task = btrim(p->>'task'),
        pic = nullif(btrim(coalesce(p->>'pic','')),''), role_text = nullif(btrim(coalesce(p->>'role_text','')),''),
        division_id = v_div, start_date = nullif(p->>'start_date','')::date, end_date = nullif(p->>'end_date','')::date,
        predecessors = v_pred, critical = coalesce((p->>'critical')::boolean, false),
        status = coalesce(nullif(p->>'status',''), status),
        percent = least(greatest(coalesce(jo.pm_num(p->'percent'), 0), 0), 1),
        note = nullif(btrim(coalesce(p->>'note','')),''), sort = coalesce(nullif(p->>'sort','')::integer, sort),
        flagged = null, archived_at = null, updated_at = now()
       where id = v_id;
      if not found then raise exception 'Tugas tidak ditemukan.'; end if;
    end if;
  elsif p_kind = 'rab_item' then
    if length(btrim(coalesce(p->>'uraian',''))) < 2 then raise exception 'Isi uraian.'; end if;
    if not exists (select 1 from jo.pm_rab_sections where code = p->>'section') then raise exception 'Seksi RAB tidak dikenal.'; end if;
    if v_id is null then
      insert into jo.pm_rab_items (section, sort, uraian, keterangan, vol, satuan, days_2025, price_2025, price_final, status_sistem, pct_replaced, note,
                                   freq, freq_unit, vol_days, freq_days, counted, source)
      values (p->>'section', coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 10 from jo.pm_rab_items where section = p->>'section')),
              btrim(p->>'uraian'), nullif(btrim(coalesce(p->>'keterangan','')),''), coalesce(jo.pm_num(p->'vol'), 0), nullif(btrim(coalesce(p->>'satuan','')),''),
              jo.pm_num(p->'days_2025'), jo.pm_num(p->'price_2025'), jo.pm_num(p->'price_final'),
              nullif(upper(btrim(coalesce(p->>'status_sistem',''))),''), least(greatest(coalesce(jo.pm_num(p->'pct_replaced'), 0), 0), 1),
              nullif(btrim(coalesce(p->>'note','')),''),
              jo.pm_num(p->'freq'), nullif(btrim(coalesce(p->>'freq_unit','')),''), coalesce((p->>'vol_days')::boolean, false),
              coalesce((p->>'freq_days')::boolean, false), coalesce((p->>'counted')::boolean, true), nullif(btrim(coalesce(p->>'source','')),''))
      returning id into v_id;
    else
      update jo.pm_rab_items set section = p->>'section', sort = coalesce(nullif(p->>'sort','')::integer, sort),
        uraian = btrim(p->>'uraian'), keterangan = nullif(btrim(coalesce(p->>'keterangan','')),''),
        vol = coalesce(jo.pm_num(p->'vol'), 0), satuan = nullif(btrim(coalesce(p->>'satuan','')),''),
        days_2025 = jo.pm_num(p->'days_2025'), price_2025 = jo.pm_num(p->'price_2025'), price_final = jo.pm_num(p->'price_final'),
        status_sistem = nullif(upper(btrim(coalesce(p->>'status_sistem',''))),''),
        pct_replaced = least(greatest(coalesce(jo.pm_num(p->'pct_replaced'), 0), 0), 1),
        note = nullif(btrim(coalesce(p->>'note','')),''),
        freq = jo.pm_num(p->'freq'), freq_unit = nullif(btrim(coalesce(p->>'freq_unit','')),''),
        vol_days = coalesce((p->>'vol_days')::boolean, false), freq_days = coalesce((p->>'freq_days')::boolean, false),
        counted = coalesce((p->>'counted')::boolean, counted), source = nullif(btrim(coalesce(p->>'source','')),''),
        flagged = null, archived_at = null, updated_at = now()
       where id = v_id;
      if not found then raise exception 'Baris RAB tidak ditemukan.'; end if;
    end if;
  elsif p_kind = 'income_item' then
    if coalesce(p->>'grp','') not in ('2025','2026') then raise exception 'Kelompok pendapatan harus 2025 atau 2026.'; end if;
    if v_id is null then
      insert into jo.pm_income_items (grp, sort, source, keterangan, vol, unit, rate, note, ledger_key)
      values (p->>'grp', coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 10 from jo.pm_income_items where grp = p->>'grp')),
              nullif(btrim(coalesce(p->>'source','')),''), nullif(btrim(coalesce(p->>'keterangan','')),''),
              coalesce(jo.pm_num(p->'vol'), 0), nullif(btrim(coalesce(p->>'unit','')),''), coalesce(jo.pm_num(p->'rate'), 0),
              nullif(btrim(coalesce(p->>'note','')),''), nullif(p->>'ledger_key',''))
      returning id into v_id;
    else
      update jo.pm_income_items set grp = p->>'grp', sort = coalesce(nullif(p->>'sort','')::integer, sort),
        source = nullif(btrim(coalesce(p->>'source','')),''), keterangan = nullif(btrim(coalesce(p->>'keterangan','')),''),
        vol = coalesce(jo.pm_num(p->'vol'), 0), unit = nullif(btrim(coalesce(p->>'unit','')),''), rate = coalesce(jo.pm_num(p->'rate'), 0),
        note = nullif(btrim(coalesce(p->>'note','')),''), ledger_key = coalesce(nullif(p->>'ledger_key',''), ledger_key),
        flagged = null, archived_at = null, updated_at = now()
       where id = v_id;
      if not found then raise exception 'Baris pendapatan tidak ditemukan.'; end if;
    end if;
  elsif p_kind = 'division' then
    if length(btrim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama divisi.'; end if;
    if v_id is null then
      insert into jo.pm_divisions (name, tier, head_name, head_title, description, sort)
      values (btrim(p->>'name'), coalesce(nullif(p->>'tier',''), 'divisi'), nullif(btrim(coalesce(p->>'head_name','')),''),
              nullif(btrim(coalesce(p->>'head_title','')),''), nullif(btrim(coalesce(p->>'description','')),''),
              coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 10 from jo.pm_divisions)))
      returning id into v_id;
    else
      update jo.pm_divisions set name = btrim(p->>'name'), tier = coalesce(nullif(p->>'tier',''), tier),
        head_name = nullif(btrim(coalesce(p->>'head_name','')),''), head_title = nullif(btrim(coalesce(p->>'head_title','')),''),
        description = nullif(btrim(coalesce(p->>'description','')),''), sort = coalesce(nullif(p->>'sort','')::integer, sort),
        archived_at = null, updated_at = now()
       where id = v_id;
      if not found then raise exception 'Divisi tidak ditemukan.'; end if;
    end if;
  elsif p_kind = 'member' then
    if length(btrim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama anggota.'; end if;
    if v_id is null then
      insert into jo.pm_members (division_id, name, role_text, phone, sort)
      values (nullif(p->>'division_id','')::uuid, jo.name_case(p->>'name'), nullif(btrim(coalesce(p->>'role_text','')),''),
              nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), ''),
              coalesce(nullif(p->>'sort','')::integer, (select coalesce(max(sort), 0) + 10 from jo.pm_members)))
      returning id into v_id;
    else
      update jo.pm_members set division_id = nullif(p->>'division_id','')::uuid, name = jo.name_case(p->>'name'),
        role_text = nullif(btrim(coalesce(p->>'role_text','')),''), phone = nullif(regexp_replace(coalesce(p->>'phone',''), '[^0-9+]', '', 'g'), ''),
        sort = coalesce(nullif(p->>'sort','')::integer, sort), archived_at = null, updated_at = now()
       where id = v_id;
      if not found then raise exception 'Anggota tidak ditemukan.'; end if;
    end if;
  elsif p_kind = 'params' then
    update jo.pm_rab_params set
      increase = coalesce(jo.pm_num(p->'increase'), increase), days_2025 = coalesce(jo.pm_num(p->'days_2025'), days_2025),
      days_2026 = coalesce(jo.pm_num(p->'days_2026'), days_2026), event_days = coalesce(jo.pm_num(p->'event_days'), event_days),
      note = coalesce(p->>'note', note), updated_at = now()
     where id = 1;
    if (select days_2025 from jo.pm_rab_params where id = 1) <= 0 then raise exception 'Hari 2025 harus lebih dari 0.'; end if;
    if (select event_days from jo.pm_rab_params where id = 1) <= 0 then raise exception 'Jumlah hari kegiatan harus lebih dari 0.'; end if;
    v_id := null;
  else
    raise exception 'Jenis data tidak dikenal: %', p_kind;
  end if;
  return v_id;
end $$;

create or replace function public.console_pm_save(p_kind text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_id uuid;
begin
  st := jo.pm_require('tulis');
  v_id := jo.pm_save_row(p_kind, p);
  perform jo.log(st.id, 'proyek_simpan', 'pm_' || p_kind, coalesce(v_id::text, p_kind),
    jsonb_build_object('nama', coalesce(p->>'task', p->>'uraian', p->>'source', p->>'name', p_kind)));
  return jsonb_build_object('id', v_id);
end $$;

-- arsip (= hapus dari tampilan, bisa dipulihkan dari Log/backup)
create or replace function public.console_pm_archive(p_kind text, p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.pm_require('tulis');
  if p_kind = 'task' then update jo.pm_tasks set archived_at = now() where id = p_id;
  elsif p_kind = 'rab_item' then update jo.pm_rab_items set archived_at = now() where id = p_id;
  elsif p_kind = 'income_item' then update jo.pm_income_items set archived_at = now() where id = p_id;
  elsif p_kind = 'division' then
    if exists (select 1 from jo.pm_tasks where division_id = p_id and archived_at is null) then
      raise exception 'Divisi masih punya tugas. Pindahkan tugasnya dulu.';
    end if;
    update jo.pm_divisions set archived_at = now() where id = p_id;
  elsif p_kind = 'member' then update jo.pm_members set archived_at = now() where id = p_id;
  else raise exception 'Jenis data tidak dikenal.';
  end if;
  if not found then raise exception 'Data tidak ditemukan.'; end if;
  perform jo.log(st.id, 'proyek_arsip', 'pm_' || p_kind, p_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Unggah xlsx (owner): diterapkan sekaligus atau tidak sama sekali
--   p = {params:{...}, tasks:[...], rab_items:[...], income_items:[...],
--        missing:{tasks:[id], rab_items:[id], income_items:[id]}, file:'nama.xlsx'}
-- ---------------------------------------------------------------------
create or replace function public.console_pm_import(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jsonb; n_ins integer := 0; n_upd integer := 0; n_flag integer := 0; n_one integer; v_tag text;
begin
  st := jo.pm_require('tulis');
  v_tag := 'Tidak ada di unggahan ' || to_char(now() at time zone 'Asia/Jakarta', 'DD/MM/YYYY HH24.MI');
  if jsonb_typeof(p->'params') = 'object' then perform jo.pm_save_row('params', p->'params'); end if;
  for x in select * from jsonb_array_elements(coalesce(p->'tasks','[]'::jsonb)) loop
    if nullif(x->>'id','') is null then n_ins := n_ins + 1; else n_upd := n_upd + 1; end if;
    perform jo.pm_save_row('task', x);
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'rab_items','[]'::jsonb)) loop
    if nullif(x->>'id','') is null then n_ins := n_ins + 1; else n_upd := n_upd + 1; end if;
    perform jo.pm_save_row('rab_item', x);
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'income_items','[]'::jsonb)) loop
    if nullif(x->>'id','') is null then n_ins := n_ins + 1; else n_upd := n_upd + 1; end if;
    perform jo.pm_save_row('income_item', x);
  end loop;
  update jo.pm_tasks set flagged = v_tag where archived_at is null and id in (select (jsonb_array_elements_text(coalesce(p->'missing'->'tasks','[]'::jsonb)))::uuid);
  get diagnostics n_one = row_count; n_flag := n_flag + n_one;
  update jo.pm_rab_items set flagged = v_tag where archived_at is null and id in (select (jsonb_array_elements_text(coalesce(p->'missing'->'rab_items','[]'::jsonb)))::uuid);
  get diagnostics n_one = row_count; n_flag := n_flag + n_one;
  update jo.pm_income_items set flagged = v_tag where archived_at is null and id in (select (jsonb_array_elements_text(coalesce(p->'missing'->'income_items','[]'::jsonb)))::uuid);
  get diagnostics n_one = row_count; n_flag := n_flag + n_one;
  perform jo.log(st.id, 'proyek_unggah', 'pm_import', coalesce(p->>'file', 'xlsx'),
    jsonb_build_object('baru', n_ins, 'diubah', n_upd, 'ditandai', n_flag));
  return jsonb_build_object('inserted', n_ins, 'updated', n_upd, 'flagged', n_flag);
end $$;

-- saklar modul (owner)
create or replace function public.console_pm_toggle(p_on boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner']);
  insert into jo.settings (key, value) values ('pm_enabled', to_jsonb(coalesce(p_on, true)))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform jo.log(st.id, 'proyek_saklar', 'settings', 'pm_enabled', jsonb_build_object('aktif', coalesce(p_on, true)));
  return jsonb_build_object('enabled', coalesce(p_on, true));
end $$;
