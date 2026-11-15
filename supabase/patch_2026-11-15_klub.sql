-- ---------------------------------------------------------------------
-- Dasbor: atlet per klub (grafik "Asal klub")
-- Hitungan atlet dari pendaftaran yang tidak dibatalkan, dipecah per disiplin.
-- Admin cabang hanya melihat disiplinnya sendiri.
-- ---------------------------------------------------------------------
create or replace function public.console_club_stats() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; d text;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  d := st.discipline;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'club_id', q.club_id, 'club', q.club, 'region', q.region,
      'athletes', q.athletes, 'paid', q.paid, 'submissions', q.subs, 'by_discipline', q.by_disc)
      order by q.athletes desc, q.club), '[]'::jsonb)
    from (
      select s.club_id,
             coalesce(c.name, 'Tanpa klub (perorangan)') as club,
             max(c.kab_kota) as region,
             count(a.id) as athletes,
             count(a.id) filter (where s.status = 'lunas') as paid,
             count(distinct s.id) as subs,
             (select jsonb_object_agg(z.discipline, z.n) from (
                 select s2.discipline, count(a2.id) as n
                   from jo.submissions s2 join jo.athletes a2 on a2.submission_id = s2.id
                  where s2.status <> 'dibatalkan' and s2.club_id is not distinct from s.club_id
                    and (d is null or s2.discipline = d)
                  group by s2.discipline) z) as by_disc
        from jo.submissions s
        left join jo.clubs c on c.id = s.club_id
        left join jo.athletes a on a.submission_id = s.id
       where s.status <> 'dibatalkan' and (d is null or s.discipline = d)
       group by s.club_id, c.name
      having count(a.id) > 0
    ) q);
end $$;
revoke all on function public.console_club_stats() from public, anon;
grant execute on function public.console_club_stats() to authenticated;
