-- 25/11/2026: Struktur (ketua, jabatan, keterangan divisi, anggota & nomornya) hanya untuk owner.
-- Peran lain tetap menerima nama dan tingkat divisi (dipakai kolom Divisi di Gantt).
create or replace function public.console_pm_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff; v_own boolean;
begin
  st := jo.pm_require('lihat');
  v_own := st.role = 'owner';
  return jsonb_build_object(
    'can_edit', v_own,
    'can_finance', st.role in ('owner','superadmin','bendahara'),
    'can_structure', v_own,
    'enabled', coalesce(jo.setting_bool('pm_enabled'), true),
    'today', jo.pm_today(),
    'phases', (select coalesce(jsonb_agg(jsonb_build_object('no', no, 'name', name) order by no), '[]'::jsonb) from jo.pm_phases),
    'divisions', (select coalesce(jsonb_agg(
                    case when v_own then to_jsonb(d) - 'archived_at'
                         else jsonb_build_object('id', d.id, 'name', d.name, 'tier', d.tier, 'sort', d.sort) end
                    order by d.sort, d.name), '[]'::jsonb)
                    from jo.pm_divisions d where d.archived_at is null),
    'members', case when v_own then (select coalesce(jsonb_agg(to_jsonb(m) - 'archived_at' order by m.sort, m.name), '[]'::jsonb)
                  from jo.pm_members m where m.archived_at is null) else '[]'::jsonb end,
    'tasks', (select coalesce(jsonb_agg(to_jsonb(t) - 'archived_at' || jsonb_build_object(
                  'duration', case when t.start_date is not null and t.end_date is not null then t.end_date - t.start_date + 1 end,
                  'warning', jo.pm_warning(t)) order by coalesce(t.phase, 99), t.sort, t.no), '[]'::jsonb)
                from jo.pm_tasks t where t.archived_at is null));
end $$;
