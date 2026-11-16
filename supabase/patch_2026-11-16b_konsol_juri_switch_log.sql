
-- ---------------------------------------------------------------------
-- Ganti disiplin tanpa keluar (owner, superadmin, TD tanpa batas disiplin)
-- ---------------------------------------------------------------------
create or replace function public.console_juri_switch(p_group text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_group text := upper(coalesce(p_group,''));
begin
  st := jo.require_judging(array['owner','superadmin','td']);
  if v_group not in ('ART','RG','AER') then raise exception 'Disiplin tidak dikenal.'; end if;
  if st.is_dummy or st.disc_group is not null or st.discipline is not null then
    raise exception 'Kode Anda terkunci pada satu disiplin.' using hint = 'ERR_FORBIDDEN';
  end if;
  update jo.staff_sessions set disc_group = v_group where uid = auth.uid();
  perform jo.log(st.id, 'ganti_disiplin_konsol_juri', 'staff', st.id::text, jsonb_build_object('disiplin', v_group));
  return public.console_juri_me();
end $$;

-- ---------------------------------------------------------------------
-- Log konsol juri (owner, superadmin): riwayat nilai + aktivitas konsol juri
-- ---------------------------------------------------------------------
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
        'old', l.old_val->>'total', 'new', l.new_val->>'total', 'status', l.new_val->>'status',
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

revoke all on function public.console_juri_switch(text) from public, anon;
revoke all on function public.console_j_audit(text, text, integer) from public, anon;
grant execute on function public.console_juri_switch(text) to authenticated;
grant execute on function public.console_j_audit(text, text, integer) to authenticated;
