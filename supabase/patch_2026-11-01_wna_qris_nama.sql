-- =====================================================================
--  Patch 1 Nov 2026
--  1) Atlet WNA membayar lewat QRIS seperti WNI (tidak ada lagi pembayaran terpisah).
--  2) Nama orang dirapikan: kata HURUF BESAR SEMUA menjadi Huruf Awal Kapital
--     (jo.name_case). Nama klub/tim memakai jo.org_case: singkatan seperti PPOP/DKI
--     tetap, kecuali seluruh nama diketik huruf besar.
--  3) Data: semua nama orang yang sudah tersimpan dirapikan.
--  Aman dijalankan ulang.
-- =====================================================================

-- huruf kapital di awal setiap kata (setelah spasi, -, (, /, ., ')
create or replace function jo.cap_words(p text) returns text
language plpgsql immutable set search_path = '' as $$
declare s text := regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'); r text := ''; c text; prev text := ' '; i integer;
begin
  if p is null then return null; end if;
  for i in 1 .. length(s) loop
    c := substr(s, i, 1);
    if prev in (' ', '-', '(', '/', '.', '''') and c <> upper(c) then c := upper(c); end if;
    r := r || c; prev := c;
  end loop;
  return r;
end $$;

-- nama orang: kata tanpa huruf kecil (mis. PUTU, DANILOVA) diturunkan dulu, lalu huruf awal kapital
create or replace function jo.name_case(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null else jo.cap_words((
    select coalesce(string_agg(case when w ~ '[[:lower:]]' then w else lower(w) end, ' ' order by o), '')
    from regexp_split_to_table(regexp_replace(btrim(p), '\s+', ' ', 'g'), ' ') with ordinality as t(w, o))) end
$$;

-- nama klub/tim: singkatan dipertahankan; hanya nama yang seluruhnya huruf besar yang diturunkan
create or replace function jo.org_case(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null
              when p ~ '[[:lower:]]' then jo.cap_words(p)
              else jo.cap_words(lower(p)) end
$$;

-- tempel perubahan ke fungsi yang sudah ada (dengan pemeriksaan jumlah kemunculan)
do $$
declare d text; n integer;
begin
  d := pg_get_functiondef('public.public_register(jsonb)'::regprocedure);
  n := (select count(*) from regexp_matches(d, $x$v_pm := 'manual';$x$, 'g'));
  if n > 0 then
    d := replace(d, $x$v_pm := 'manual';$x$, $x$null; -- WNA juga membayar lewat QRIS (patch 1 Nov 2026)$x$);
  end if;
  d := replace(d, $x$jo.name_case(p->'club'->'new'->>'name')$x$, $x$jo.org_case(p->'club'->'new'->>'name')$x$);
  d := replace(d, $x$v_tname := jo.name_case($x$, $x$v_tname := jo.org_case($x$);
  execute d;

  d := pg_get_functiondef('public.console_save_club(jsonb)'::regprocedure);
  d := replace(d, 'jo.name_case(p->>''name'')', 'jo.org_case(p->>''name'')');
  execute d;
end $$;

-- FAQ atlet asing
update jo.faq_items set
  a_id = 'Atlet WNA mendaftar lewat formulir yang sama dengan mengunggah paspor dan pas foto, lalu membayar lewat QRIS seperti atlet WNI. Kategori Ritmik Priangan hanya untuk WNI.',
  a_en = 'Foreign athletes use the same form, upload a passport and a passport photo, and pay by QRIS like Indonesian athletes. The Rhythmic Priangan level is for Indonesian citizens only.'
where slug = 'atlet-asing';

-- rapikan nama orang yang sudah tersimpan
update jo.athletes set full_name = jo.name_case(full_name) where full_name is distinct from jo.name_case(full_name);
update jo.athletes set guardian_name = jo.name_case(guardian_name) where guardian_name is not null and guardian_name is distinct from jo.name_case(guardian_name);
update jo.submissions set contact_name = jo.name_case(contact_name) where contact_name is distinct from jo.name_case(contact_name);
update jo.jury_applications set full_name = jo.name_case(full_name) where full_name is distinct from jo.name_case(full_name);
update jo.clubs set name = jo.org_case(name) where name is distinct from jo.org_case(name);
