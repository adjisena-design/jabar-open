-- =====================================================================
--  FAQ (15 Okt 2026)
--  Publik: public_faq() hanya butir 'terbit' di kategori aktif.
--  Konsol: owner, superadmin, admin menulis, mengurutkan, menerbitkan,
--          menyembunyikan (draf) dan mengarsipkan. Tidak ada hapus permanen.
-- =====================================================================

create or replace function jo.faq_slug(p_text text, p_except uuid default null) returns text
language plpgsql stable set search_path = '' as $$
declare base text; s text; n integer := 1;
begin
  base := left(trim(both '-' from regexp_replace(lower(coalesce(p_text,'')), '[^a-z0-9]+', '-', 'g')), 52);
  base := trim(both '-' from base);
  if length(base) < 2 then base := 'faq'; end if;
  s := base;
  while exists (select 1 from jo.faq_items where slug = s and (p_except is null or id <> p_except)) loop
    n := n + 1; s := base || '-' || n;
  end loop;
  return s;
end $$;

create or replace function jo.faq_cat_json(p_all boolean) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'name_id', c.name_id, 'name_en', c.name_en,
           'sort', c.sort, 'active', c.active) order by c.sort, c.name_id), '[]'::jsonb)
    from jo.faq_categories c where p_all or c.active
$$;

create or replace function public.public_faq() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key', c.key, 'name_id', c.name_id, 'name_en', c.name_en) order by c.sort, c.name_id)
        from jo.faq_categories c where c.active
         and exists (select 1 from jo.faq_items i where i.category = c.key and i.status = 'terbit')), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('slug', i.slug, 'category', i.category,
          'q_id', i.q_id, 'a_id', i.a_id, 'q_en', i.q_en, 'a_en', i.a_en) order by c.sort, i.sort, i.created_at)
        from jo.faq_items i join jo.faq_categories c on c.key = i.category
       where i.status = 'terbit' and c.active), '[]'::jsonb))
$$;

create or replace function public.public_faq_count() returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from jo.faq_items i join jo.faq_categories c on c.key = i.category
   where i.status = 'terbit' and c.active
$$;

create or replace function public.console_faq() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform jo.require_staff(array['owner','superadmin','admin']);
  return jsonb_build_object(
    'categories', jo.faq_cat_json(true),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'slug', i.slug, 'category', i.category,
          'q_id', i.q_id, 'a_id', i.a_id, 'q_en', i.q_en, 'a_en', i.a_en, 'sort', i.sort, 'status', i.status,
          'updated_at', i.updated_at, 'updated_by', i.updated_by) order by c.sort, i.sort, i.created_at)
        from jo.faq_items i join jo.faq_categories c on c.key = i.category), '[]'::jsonb));
end $$;

create or replace function public.console_faq_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.faq_items; v_id uuid; v_cat text; v_slug text; v_status text; v_sort integer;
  v_q text; v_a text; v_qe text; v_ae text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  v_id := nullif(p->>'id','')::uuid;
  if v_id is not null then
    select * into x from jo.faq_items where id = v_id;
    if x.id is null then raise exception 'Pertanyaan tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
  end if;
  v_cat := coalesce(nullif(p->>'category',''), x.category);
  if not exists (select 1 from jo.faq_categories where key = v_cat) then raise exception 'Pilih kategori.'; end if;
  v_q := trim(coalesce(p->>'q_id','')); v_a := trim(coalesce(p->>'a_id',''));
  v_qe := nullif(trim(coalesce(p->>'q_en','')),''); v_ae := nullif(trim(coalesce(p->>'a_en','')),'');
  if length(v_q) < 5 then raise exception 'Isi pertanyaan (bahasa Indonesia).'; end if;
  if length(v_a) < 2 then raise exception 'Isi jawaban (bahasa Indonesia).'; end if;
  if length(v_q) > 300 or length(coalesce(v_qe,'')) > 300 then raise exception 'Pertanyaan maksimal 300 karakter.'; end if;
  if length(v_a) > 4000 or length(coalesce(v_ae,'')) > 4000 then raise exception 'Jawaban maksimal 4000 karakter.'; end if;
  if (v_qe is null) <> (v_ae is null) then raise exception 'Versi Inggris perlu pertanyaan dan jawaban sekaligus, atau kosongkan keduanya.'; end if;
  v_status := coalesce(nullif(p->>'status',''), x.status, 'draf');
  if v_status not in ('draf','terbit','arsip') then raise exception 'Status tidak dikenal.'; end if;
  v_slug := nullif(lower(trim(coalesce(p->>'slug',''))),'');
  if v_slug is null then v_slug := coalesce(x.slug, jo.faq_slug(v_q, v_id));
  elsif v_slug !~ '^[a-z0-9-]{2,60}$' then raise exception 'Tautan hanya huruf kecil, angka, dan tanda hubung (2–60 karakter).';
  elsif exists (select 1 from jo.faq_items where slug = v_slug and (v_id is null or id <> v_id)) then
    raise exception 'Tautan "%" sudah dipakai pertanyaan lain.', v_slug;
  end if;
  if v_id is null or x.category <> v_cat then
    select coalesce(max(sort), 0) + 10 into v_sort from jo.faq_items where category = v_cat;
  else v_sort := x.sort; end if;
  if v_id is null then
    insert into jo.faq_items (category, slug, q_id, a_id, q_en, a_en, sort, status, updated_by)
    values (v_cat, v_slug, v_q, v_a, v_qe, v_ae, v_sort, v_status, st.name) returning id into v_id;
    perform jo.log(st.id, 'faq_dibuat', 'faq', v_id::text, jsonb_build_object('slug', v_slug, 'status', v_status));
  else
    update jo.faq_items set category = v_cat, slug = v_slug, q_id = v_q, a_id = v_a, q_en = v_qe, a_en = v_ae,
      sort = v_sort, status = v_status, updated_at = now(), updated_by = st.name where id = v_id;
    perform jo.log(st.id, 'faq_diubah', 'faq', v_id::text, jsonb_build_object('slug', v_slug, 'status', v_status, 'was_status', x.status));
  end if;
  return public.console_faq();
end $$;

create or replace function public.console_faq_set_status(p_id uuid, p_status text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.faq_items;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  if p_status not in ('draf','terbit','arsip') then raise exception 'Status tidak dikenal.'; end if;
  select * into x from jo.faq_items where id = p_id;
  if x.id is null then raise exception 'Pertanyaan tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
  update jo.faq_items set status = p_status, updated_at = now(), updated_by = st.name where id = p_id;
  perform jo.log(st.id, 'faq_status', 'faq', p_id::text, jsonb_build_object('slug', x.slug, 'from', x.status, 'to', p_status));
  return public.console_faq();
end $$;

-- geser satu langkah ke atas (-1) atau ke bawah (+1) di dalam kategorinya
create or replace function public.console_faq_move(p_id uuid, p_dir integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; x jo.faq_items; ids uuid[]; i integer; j integer; tmp uuid;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into x from jo.faq_items where id = p_id;
  if x.id is null then raise exception 'Pertanyaan tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
  select array_agg(id order by sort, created_at) into ids from jo.faq_items where category = x.category;
  i := array_position(ids, p_id); j := i + sign(p_dir)::integer;
  if j >= 1 and j <= array_length(ids, 1) then
    tmp := ids[i]; ids[i] := ids[j]; ids[j] := tmp;
  end if;
  update jo.faq_items f set sort = o.n * 10 from unnest(ids) with ordinality as o(id, n) where f.id = o.id;
  return public.console_faq();
end $$;

create or replace function public.console_faq_category_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_key text; v_name text; v_sort integer;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  v_name := trim(coalesce(p->>'name_id',''));
  if length(v_name) < 2 then raise exception 'Isi nama kategori.'; end if;
  v_key := nullif(p->>'key','');
  if v_key is not null and exists (select 1 from jo.faq_categories where key = v_key) then
    update jo.faq_categories set name_id = v_name, name_en = nullif(trim(coalesce(p->>'name_en','')),''),
      active = coalesce((p->>'active')::boolean, active) where key = v_key;
    perform jo.log(st.id, 'faq_kategori_diubah', 'faq_category', v_key, p);
  else
    v_key := left(trim(both '-' from regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g')), 36);
    if length(v_key) < 2 then v_key := 'kategori'; end if;
    while exists (select 1 from jo.faq_categories where key = v_key) loop v_key := v_key || '-2'; end loop;
    select coalesce(max(sort), 0) + 10 into v_sort from jo.faq_categories;
    insert into jo.faq_categories (key, name_id, name_en, sort, active)
    values (v_key, v_name, nullif(trim(coalesce(p->>'name_en','')),''), v_sort, coalesce((p->>'active')::boolean, true));
    perform jo.log(st.id, 'faq_kategori_dibuat', 'faq_category', v_key, p);
  end if;
  return public.console_faq();
end $$;

create or replace function public.console_faq_category_move(p_key text, p_dir integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; ks text[]; i integer; j integer; tmp text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select array_agg(key order by sort, name_id) into ks from jo.faq_categories;
  i := array_position(ks, p_key);
  if i is null then raise exception 'Kategori tidak ditemukan.' using hint = 'ERR_NOT_FOUND'; end if;
  j := i + sign(p_dir)::integer;
  if j >= 1 and j <= array_length(ks, 1) then tmp := ks[i]; ks[i] := ks[j]; ks[j] := tmp; end if;
  update jo.faq_categories c set sort = o.n * 10 from unnest(ks) with ordinality as o(key, n) where c.key = o.key;
  return public.console_faq();
end $$;
