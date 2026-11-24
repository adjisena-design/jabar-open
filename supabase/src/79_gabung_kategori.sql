-- =====================================================================
--  24/11/2026: penggabungan kategori langsung dari halaman Kategori
--  - console_category_entries: daftar atlet satu kategori (untuk dialog Gabungkan)
--  - console_merge_category: pindahkan entri terpilih ke kategori tujuan sekaligus
--    (memakai console_move_entry per entri; gagal satu = batal semua),
--    opsional menutup kategori asal bila sudah kosong (owner & superadmin)
-- =====================================================================
create or replace function public.console_category_entries(p_category integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; c jo.categories;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c from jo.categories where id = p_category;
  if c.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  perform jo.check_discipline(st, c.discipline);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'status', e.status, 'team_only', e.team_only,
      'submission_id', s.id, 'code', s.code, 'sub_status', s.status,
      'club', coalesce(k.name, 'Perorangan'),
      'scored', exists (select 1 from jo.scores sc where sc.entry_id = e.id),
      'athletes', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', a.full_name, 'gender', a.gender,
                     'birth_date', a.birth_date, 'no', a.athlete_no) order by a.full_name), '[]'::jsonb)
                     from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id where ea.entry_id = e.id)
    ) order by coalesce(k.name, 'Perorangan'), s.code), '[]'::jsonb)
    from jo.entries e join jo.submissions s on s.id = e.submission_id left join jo.clubs k on k.id = s.club_id
   where e.category_id = c.id and s.status <> 'dibatalkan' and e.status <> 'dibatalkan');
end $$;

create or replace function public.console_merge_category(p_from integer, p_to integer, p_entries uuid[], p_reason text, p_close boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; c_from jo.categories; c_to jo.categories; eid uuid; v_name text; n integer := 0;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  select * into c_from from jo.categories where id = p_from;
  select * into c_to from jo.categories where id = p_to;
  if c_from.id is null or c_to.id is null then raise exception 'Kategori tidak ditemukan.'; end if;
  if c_from.id = c_to.id then raise exception 'Pilih kategori tujuan yang berbeda.'; end if;
  perform jo.check_discipline(st, c_from.discipline);
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Tulis alasan penggabungan.'; end if;
  if coalesce(array_length(p_entries, 1), 0) = 0 and not p_close then raise exception 'Pilih minimal satu atlet.'; end if;
  foreach eid in array coalesce(p_entries, '{}') loop
    if not exists (select 1 from jo.entries where id = eid and category_id = c_from.id) then
      raise exception 'Ada entri yang sudah tidak ada di kategori ini. Muat ulang halaman.';
    end if;
    select string_agg(a.full_name, ' & ') into v_name from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id where ea.entry_id = eid;
    begin
      perform public.console_move_entry(eid, c_to.id, btrim(p_reason));
    exception when others then
      raise exception '%: %', coalesce(v_name, 'Entri'), sqlerrm;
    end;
    n := n + 1;
  end loop;
  if p_close then
    if st.role not in ('owner','superadmin') then raise exception 'Menutup kategori hanya oleh owner atau superadmin.'; end if;
    if exists (select 1 from jo.entries e join jo.submissions s on s.id = e.submission_id
                where e.category_id = c_from.id and s.status <> 'dibatalkan' and e.status <> 'dibatalkan') then
      raise exception 'Kategori asal masih berisi atlet, jadi belum bisa ditutup. Pindahkan semua atlet atau hapus centang Tutup.';
    end if;
    update jo.categories set active = false where id = c_from.id;
  end if;
  perform jo.log(st.id, 'kategori_digabung', 'category', c_from.id::text,
    jsonb_build_object('from', c_from.name_id, 'to', c_to.name_id, 'moved', n, 'closed', p_close, 'reason', btrim(p_reason)));
  return public.console_categories(c_from.discipline);
end $$;

revoke all on function public.console_category_entries(integer) from public, anon;
grant execute on function public.console_category_entries(integer) to authenticated;
revoke all on function public.console_merge_category(integer, integer, uuid[], text, boolean) from public, anon;
grant execute on function public.console_merge_category(integer, integer, uuid[], text, boolean) to authenticated;
