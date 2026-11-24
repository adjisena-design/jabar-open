-- =====================================================================
--  24/11/2026: Data final (owner & superadmin)
--  Satu panggilan untuk Excel (Pendaftaran, Atlet, Nomor lomba, Klub,
--  Kategori) dan PDF daftar atlet per disiplin dan kategori.
--  Semua pendaftaran ikut, termasuk yang dibatalkan (ditandai statusnya).
-- =====================================================================
create or replace function public.console_final_data() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v jsonb;
begin
  st := jo.require_staff(array['owner','superadmin']);
  perform jo.expire_unpaid();
  with
  s as (select s.*, c.name club_name, c.kind club_kind, c.kab_kota club_kab, c.province club_prov, c.country club_country,
               bt.code batch_code
          from jo.submissions s left join jo.clubs c on c.id = s.club_id left join jo.bulk_batches bt on bt.id = s.bulk_batch_id)
  select jsonb_build_object(
    'generated_at', now(), 'generated_by', st.name,
    'submissions', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', s.code, 'created_at', s.created_at, 'discipline', s.discipline, 'type', s.registrant_type,
        'club', coalesce(s.club_name, 'Perorangan'), 'club_kind', s.club_kind, 'kab_kota', s.club_kab, 'province', s.club_prov, 'country', s.club_country,
        'contact_name', s.contact_name, 'contact_role', s.contact_role, 'contact_phone', s.contact_phone, 'contact_email', s.contact_email,
        'athletes', (select count(*) from jo.athletes a where a.submission_id = s.id),
        'entries', (select count(*) from jo.entries e where e.submission_id = s.id and e.status = 'aktif'),
        'method', s.payment_method, 'batch', s.batch_code, 'total', s.total_amount, 'paid', s.paid_amount,
        'status', s.status, 'proof_at', s.proof_uploaded_at, 'paid_at', s.paid_at, 'note', s.verify_note, 'cancel_reason', s.cancel_reason
      ) order by s.created_at), '[]'::jsonb) from s),
    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'no', a.athlete_no, 'name', a.full_name, 'gender', a.gender, 'birth_date', a.birth_date,
        'nationality', a.nationality, 'country', a.country, 'province', a.province, 'kab_kota', a.kab_kota,
        'club', coalesce(s.club_name, 'Perorangan'), 'discipline', s.discipline,
        'categories', (select string_agg(c.name_id, '; ' order by c.sort) from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id
                         join jo.categories c on c.id = e.category_id where ea.athlete_id = a.id and e.status = 'aktif'),
        'team', (select string_agg(t.name || ' (' || t.level || ')', '; ') from jo.team_members tm join jo.teams t on t.id = tm.team_id where tm.athlete_id = a.id),
        'submission', s.code, 'status', s.status, 'method', s.payment_method, 'doc_status', a.doc_status,
        'bpjs', a.bpjs_path is not null, 'photo', a.photo_path is not null or a.photo_thumb is not null,
        'guardian_name', a.guardian_name, 'guardian_relation', a.guardian_relation, 'guardian_phone', a.guardian_phone, 'guardian_email', a.guardian_email,
        'registered_at', s.created_at, 'paid_at', s.paid_at
      ) order by s.discipline, coalesce(s.club_name, 'Perorangan'), a.full_name), '[]'::jsonb)
      from jo.athletes a join s on s.id = a.submission_id),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'discipline', c.discipline, 'cat_id', c.id, 'cat_code', c.code, 'category', c.name_id, 'cat_sort', c.sort,
        'athletes', (select jsonb_agg(jsonb_build_object('no', a.athlete_no, 'name', a.full_name, 'gender', a.gender, 'birth_date', a.birth_date,
                       'kab_kota', a.kab_kota, 'province', a.province, 'country', a.country) order by a.full_name)
                       from jo.entry_athletes ea join jo.athletes a on a.id = ea.athlete_id where ea.entry_id = e.id),
        'club', coalesce(s.club_name, 'Perorangan'), 'submission', s.code, 'status', s.status, 'entry_status', e.status,
        'team_only', e.team_only, 'priangan', e.priangan_status, 'fee', e.fee
      ) order by c.discipline, c.sort, c.id, coalesce(s.club_name, 'Perorangan')), '[]'::jsonb)
      from jo.entries e join s on s.id = e.submission_id join jo.categories c on c.id = e.category_id),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'discipline', c.discipline, 'code', c.code, 'name', c.name_id,
        'level', c.level, 'birth_year_min', c.birth_year_min, 'birth_year_max', c.birth_year_max, 'fee', c.fee,
        'active', c.active, 'exhibition', c.exhibition, 'sort', c.sort) order by c.discipline, c.sort, c.id), '[]'::jsonb) from jo.categories c)
  ) into v;
  perform jo.log(st.id, 'data_final_diunduh', 'laporan', null,
    jsonb_build_object('submissions', jsonb_array_length(v->'submissions'), 'athletes', jsonb_array_length(v->'athletes')));
  return v;
end $$;
revoke all on function public.console_final_data() from public, anon;
grant execute on function public.console_final_data() to authenticated;
