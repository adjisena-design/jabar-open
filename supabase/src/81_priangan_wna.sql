-- 25/11/2026: Priangan boleh untuk atlet WNA bila klubnya dari provinsi klub Priangan (Jawa Barat).
-- Kunci aturan baru: reg_rules.priangan.wna_club (boolean). Atlet WNA tidak dicek alamat identitasnya.

create or replace function jo.rule_defaults() returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'guardian_age', 18,
    'proof_minutes', 15,
    'rate_per_hour', 12,
    'pair_with_individual', jsonb_build_array('AER'),
    'priangan', jsonb_build_object('wni', true, 'athlete_province', 'Jawa Barat', 'club_province', 'Jawa Barat', 'wna_club', false),
    'docs', jsonb_build_object(
      'WNI', jsonb_build_object('akte','wajib','ktp','opsional','ijazah','opsional','bpjs','opsional','passport','tidak','photo','wajib'),
      'WNA', jsonb_build_object('akte','tidak','ktp','tidak','ijazah','tidak','bpjs','tidak','passport','wajib','photo','wajib')))
$$;

create or replace function jo.priangan_reason(p_nat text, p_province text, p_club_province text) returns text
language plpgsql stable set search_path = '' as $$
declare r jsonb := jo.rules()->'priangan';
  ap text := nullif(trim(coalesce(r->>'athlete_province','')), '');
  cp text := nullif(trim(coalesce(r->>'club_province','')), '');
begin
  -- atlet WNA: cukup klubnya dari provinsi klub Priangan (bila diizinkan)
  if coalesce(p_nat, 'WNI') <> 'WNI' and coalesce((r->>'wna_club')::boolean, false) then
    if cp is not null and coalesce(p_club_province, '') <> cp then
      return 'atlet WNA hanya boleh bila klubnya dari ' || cp;
    end if;
    return null;
  end if;
  if coalesce((r->>'wni')::boolean, true) and coalesce(p_nat, 'WNI') <> 'WNI' then
    return 'khusus atlet WNI';
  end if;
  if ap is not null and coalesce(p_province, '') <> ap then
    return 'alamat identitas atlet harus di ' || ap;
  end if;
  if cp is not null and p_club_province is not null and p_club_province <> cp then
    return 'klub harus dari ' || cp;
  end if;
  return null;
end $$;

create or replace function jo.priangan_desc() returns text
language plpgsql stable set search_path = '' as $$
declare r jsonb := jo.rules()->'priangan'; parts text[] := '{}';
  ap text := nullif(trim(coalesce(r->>'athlete_province','')), '');
  cp text := nullif(trim(coalesce(r->>'club_province','')), '');
begin
  if ap is not null then parts := parts || ('alamat identitas di ' || ap); end if;
  if cp is not null then parts := parts || ('klub di ' || cp); end if;
  return 'Khusus atlet' || case when coalesce((r->>'wni')::boolean, true) then ' WNI' else '' end
    || case when array_length(parts, 1) > 0 then ' dengan ' || array_to_string(parts, ' dan ') else '' end
    || case when coalesce((r->>'wna_club')::boolean, false) and coalesce((r->>'wni')::boolean, true)
            then '; atlet WNA boleh bila klubnya ' || coalesce('di ' || cp, 'memenuhi syarat') else '' end;
end $$;

-- Konsol → Aturan pendaftaran: simpan kunci wna_club
do $do$
declare d text := pg_get_functiondef('public.console_save_rules(jsonb)'::regprocedure);
  a text := $a$'club_province', trim(coalesce(r->'priangan'->>'club_province',''))));$a$;
  b text := $b$'club_province', trim(coalesce(r->'priangan'->>'club_province','')),
      'wna_club', coalesce((r->'priangan'->>'wna_club')::boolean, coalesce((v_old->'priangan'->>'wna_club')::boolean, false))));$b$;
begin
  if position(a in d) = 0 then raise exception 'console_save_rules: pola priangan tidak ditemukan'; end if;
  execute replace(d, a, b);
end $do$;

-- aktifkan untuk Jabar Open 2026 (keputusan panitia 25/11/2026)
insert into jo.settings (key, value, updated_at)
values ('reg_rules', jsonb_build_object('priangan', (jo.rules()->'priangan') || '{"wna_club": true}'::jsonb), now())
on conflict (key) do update
  set value = jo.settings.value || jsonb_build_object('priangan', (jo.rules()->'priangan') || '{"wna_club": true}'::jsonb), updated_at = now();

update jo.faq_items set
  a_id = $t$Atlet **WNI** yang alamat pada identitasnya di **Jawa Barat** dan didaftarkan lewat **klub dari Jawa Barat**. Atlet **WNA** juga boleh bila didaftarkan lewat **klub dari Jawa Barat**. Asal pelatih atau penanggung jawab yang mengisi formulir tidak berpengaruh. Biayanya sama, Rp750.000, tanpa biaya tambahan. Priangan punya tabel medali sendiri.$t$,
  a_en = $t$**Indonesian** athletes whose ID address is in **West Java**, entered through a **West Java club**. **Foreign** athletes may also enter when they are entered through a **West Java club**. Where the coach or contact person filling in the form comes from does not matter. The fee is the same Rp750,000, with no extra charge. Priangan has its own medal table.$t$,
  updated_at = now()
where slug = 'priangan';
update jo.faq_items set
  a_id = $t$Atlet WNA mendaftar lewat formulir yang sama dengan mengunggah paspor dan pas foto, lalu membayar lewat QRIS seperti atlet WNI. Kategori Ritmik Priangan terbuka untuk atlet WNA bila klubnya dari Jawa Barat.$t$,
  a_en = $t$Foreign athletes use the same form, upload a passport and a passport photo, and pay by QRIS like Indonesian athletes. The Rhythmic Priangan level is open to foreign athletes entered through a West Java club.$t$,
  updated_at = now()
where slug = 'atlet-asing';
update jo.faq_items set
  a_id = replace(a_id, 'hanya untuk atlet Jawa Barat', 'hanya untuk atlet Jawa Barat (atlet WNA boleh bila klubnya dari Jawa Barat)'),
  a_en = replace(a_en, 'only for West Java athletes', 'only for West Java athletes (foreign athletes may enter through a West Java club)'),
  updated_at = now()
where slug = 'ritmik-level';
