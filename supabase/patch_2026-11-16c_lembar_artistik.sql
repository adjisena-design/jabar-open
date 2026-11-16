alter table jo.judge_panels add column if not exists runs integer not null default 1;
alter table jo.judge_panels add column if not exists sheet text not null default 'standar';
alter table jo.judge_panels drop constraint if exists judge_panels_runs_check;
alter table jo.judge_panels add constraint judge_panels_runs_check check (runs between 1 and 3);
alter table jo.judge_panels drop constraint if exists judge_panels_sheet_check;
alter table jo.judge_panels add constraint judge_panels_sheet_check check (sheet in ('standar','artistik'));

alter table jo.jscores add column if not exists flags jsonb not null default '[]'::jsonb;

-- Lembar Artistik (form kertas): D1/D2, E1–E3, Rerata (otomatis), Pinalti, Nilai Akhir (otomatis);
-- Meja Lompat: 2 lompatan, nilai alat = rata-rata Nilai Akhir kedua lompatan
update jo.judge_panels set sheet = 'artistik' where discipline in ('MAG','WAG') and sheet = 'standar' and category_id is null and apparatus is null;
insert into jo.judge_panels (discipline, apparatus, slots, runs, sheet)
select p.discipline, 'VT', p.slots, 2, 'artistik' from jo.judge_panels p
 where p.discipline in ('MAG','WAG') and p.category_id is null and p.apparatus is null
   and not exists (select 1 from jo.judge_panels x where x.discipline = p.discipline and x.category_id is null and x.apparatus = 'VT');

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

revoke all on function jo.calc_slots(jo.judge_panels, jsonb) from public;
revoke all on function jo.panel_keys(jo.judge_panels) from public;
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
grant execute on function public.console_j_audit(text, text, integer) to authenticated;
