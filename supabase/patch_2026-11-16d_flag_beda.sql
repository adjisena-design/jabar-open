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
        if ov is distinct from e_auto then
          flags := flags || jsonb_build_object('field', 'RERATA', 'run', r, 'auto', e_auto, 'manual', ov);
        end if;
      end if;
    end if;
    ak_auto := case when have_r = 0 then null else round(coalesce(d,0) + coalesce(e,0) + coalesce(a,0) - pen, 3) end;
    ak := ak_auto;
    if p.sheet = 'artistik' then
      ov := nullif(s->>('AKHIR' || sfx), '')::numeric;
      if ov is not null then
        ak := ov;
        if ov is distinct from ak_auto then
          flags := flags || jsonb_build_object('field', 'AKHIR', 'run', r, 'auto', ak_auto, 'manual', ov);
        end if;
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
