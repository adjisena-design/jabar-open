-- =====================================================================
--  Laporan pendaftaran (20 Nov 2026)
--  Satu fungsi baca-saja untuk tombol "Unduh laporan" di konsol (owner & superadmin).
--  Isi: rekap atlet, pembayaran (lunas / menunggu verifikasi / perlu perbaikan / belum bayar,
--  QRIS vs transfer massal), disiplin, kategori, putra/putri, usia, wilayah, klub, dokumen,
--  Priangan, musik Ritmik, draf massal yang belum dikirim, tren mingguan, dan daftar atlet.
--  Hitungan atlet sama dengan Ringkasan: atlet di pendaftaran yang tidak dibatalkan.
--  Setiap unduhan tercatat di Log ('laporan_diunduh').
-- =====================================================================
create or replace function public.console_report() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v jsonb; v_now timestamptz := now();
begin
  st := jo.require_staff(array['owner','superadmin']);
  perform jo.expire_unpaid();

  with
  s as (select s.*, c.name club_name, c.kind club_kind, c.kab_kota club_kab, c.province club_prov, c.country club_country
          from jo.submissions s left join jo.clubs c on c.id = s.club_id
         where s.status <> 'dibatalkan'),
  a as (select a.*, s.discipline, s.status sst, s.payment_method pm, s.code sub_code, s.club_id, s.club_name,
               s.created_at sub_at, s.paid_at sub_paid_at,
               2026 - extract(year from a.birth_date)::int age
          from jo.athletes a join s on s.id = a.submission_id),
  e as (select e.*, s.discipline, s.status sst, s.club_id
          from jo.entries e join s on s.id = e.submission_id where e.status = 'aktif'),
  ea as (select ea.athlete_id, e.category_id, e.sst, e.id entry_id
           from jo.entry_athletes ea join e on e.id = ea.entry_id),
  -- status pembayaran pendaftaran
  pay as (select x.status, x.payment_method, count(*) subs, sum(x.na) athletes, sum(x.amt) amount
            from (select s.status, s.payment_method, (select count(*) from a where a.submission_id = s.id) na,
                         case when s.status = 'lunas' then coalesce(s.paid_amount, s.total_amount) else s.total_amount end amt
                    from s) x
           group by x.status, x.payment_method)
  select jsonb_build_object(
    'generated_at', v_now,
    'generated_by', st.name,
    'deadline', coalesce(jo.setting_text('registration_deadline'), '2026-11-30T23:59:59+07:00'),
    'event_start', '2026-12-12',
    'opened', (select min(created_at) from jo.submissions),

    'totals', jsonb_build_object(
      'submissions', (select count(*) from s),
      'athletes', (select count(*) from a),
      'people', (select count(distinct (jo.norm_name(full_name), birth_date)) from a),
      'athletes_paid', (select count(*) from a where sst = 'lunas'),
      'entries', (select count(*) from e),
      'teams', (select count(*) from jo.teams t join s on s.id = t.submission_id),
      'teams_paid', (select count(*) from jo.teams t join s on s.id = t.submission_id where s.status = 'lunas'),
      'clubs', (select count(distinct club_id) from s where club_id is not null),
      'male', (select count(*) from a where gender = 'M'),
      'female', (select count(*) from a where gender = 'F'),
      'wna', (select count(*) from a where nationality = 'WNA'),
      'under10', (select count(*) from a where age < 10),
      'paid_amount', (select coalesce(sum(coalesce(paid_amount, total_amount)),0) from s where status = 'lunas'),
      'outstanding', (select coalesce(sum(total_amount),0) from s where status <> 'lunas'),
      'cancelled_submissions', (select count(*) from jo.submissions where status = 'dibatalkan'),
      'cancelled_entries', (select count(*) from jo.entries x join s on s.id = x.submission_id where x.status = 'dibatalkan')),

    'by_discipline', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', d.code, 'name', d.name_id,
        'submissions', (select count(*) from s where s.discipline = d.code),
        'athletes', (select count(*) from a where a.discipline = d.code),
        'athletes_paid', (select count(*) from a where a.discipline = d.code and a.sst = 'lunas'),
        'athletes_pending', (select count(*) from a where a.discipline = d.code and a.sst <> 'lunas'),
        'male', (select count(*) from a where a.discipline = d.code and a.gender = 'M'),
        'female', (select count(*) from a where a.discipline = d.code and a.gender = 'F'),
        'entries', (select count(*) from e where e.discipline = d.code),
        'teams', (select count(*) from jo.teams t join s on s.id = t.submission_id where t.discipline = d.code),
        'clubs', (select count(distinct club_id) from s where s.discipline = d.code and club_id is not null),
        'categories_used', (select count(distinct category_id) from e where e.discipline = d.code),
        'categories_total', (select count(*) from jo.categories c where c.discipline = d.code and c.active),
        'paid_amount', (select coalesce(sum(coalesce(paid_amount, total_amount)),0) from s where s.discipline = d.code and s.status = 'lunas'),
        'outstanding', (select coalesce(sum(total_amount),0) from s where s.discipline = d.code and s.status <> 'lunas'),
        'registration_open', d.registration_open
      ) order by d.sort), '[]'::jsonb) from jo.disciplines d),

    'payment', jsonb_build_object(
      'by_status', (select coalesce(jsonb_agg(jsonb_build_object('status', status, 'method', payment_method,
          'submissions', subs, 'athletes', athletes, 'amount', amount)), '[]'::jsonb) from pay),
      'open', (select coalesce(jsonb_agg(jsonb_build_object(
          'code', s.code, 'status', s.status, 'method', s.payment_method, 'discipline', s.discipline,
          'club', coalesce(s.club_name, '-'), 'contact', s.contact_name,
          'athletes', (select count(*) from a where a.submission_id = s.id),
          'amount', s.total_amount, 'created_at', s.created_at, 'proof_at', s.proof_uploaded_at,
          'note', s.verify_note) order by s.created_at), '[]'::jsonb)
        from s where s.status <> 'lunas'),
      'verify_hours', (select round(avg(extract(epoch from (verified_at - proof_uploaded_at)) / 3600)::numeric, 1)
          from s where s.status = 'lunas' and verified_at is not null and proof_uploaded_at is not null and verified_at > proof_uploaded_at),
      'refund_due', (select coalesce(sum(refund_due),0) from jo.bulk_batches)),

    'bulk', (select coalesce(jsonb_agg(jsonb_build_object(
        'label', coalesce(c.name, b.label), 'opened_at', b.opened_at, 'expires_at', b.expires_at,
        'completed', b.completed_at is not null,
        'draft_rows', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id and r.batch_id is null and coalesce(r.data->>'full_name','') <> ''),
        'batches_paid', (select count(*) from jo.bulk_batches x where x.bulk_id = b.id and x.status = 'lunas'),
        'batches_open', (select count(*) from jo.bulk_batches x where x.bulk_id = b.id and x.status = 'menunggu'),
        'athletes_submitted', (select count(*) from a join jo.submissions s2 on s2.id = a.submission_id join jo.bulk_batches x on x.id = s2.bulk_batch_id where x.bulk_id = b.id),
        'amount_open', (select coalesce(sum(x.total),0) from jo.bulk_batches x where x.bulk_id = b.id and x.status = 'menunggu'),
        'refund_due', (select coalesce(sum(x.refund_due),0) from jo.bulk_batches x where x.bulk_id = b.id)
      ) order by b.seq), '[]'::jsonb)
      from jo.bulk_accounts b left join jo.clubs c on c.id = b.club_id
      where b.status = 'aktif' and lower(b.label) <> 'system owner'),

    'categories', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'discipline', c.discipline, 'name', c.name_id, 'level', c.level, 'age', c.age_label,
        'gender', c.gender, 'type', c.entry_type, 'max_per_club', c.max_per_club, 'exhibition', c.exhibition,
        'entries', n.reg, 'entries_paid', n.paid, 'clubs', n.clubs, 'top_club', n.top_club,
        'athletes', n.ath
      ) order by c.discipline, c.sort), '[]'::jsonb)
      from jo.categories c
      cross join lateral (select count(*) reg, count(*) filter (where e.sst = 'lunas') paid,
                                 count(distinct e.club_id) clubs,
                                 coalesce((select max(k) from (select count(*) k from e e2 where e2.category_id = c.id group by e2.club_id) z), 0) top_club,
                                 (select count(*) from ea where ea.category_id = c.id) ath
                            from e where e.category_id = c.id) n
      where c.active),

    'ages', (select coalesce(jsonb_agg(jsonb_build_object('age', age, 'male', m, 'female', f) order by age), '[]'::jsonb)
      from (select age, count(*) filter (where gender = 'M') m, count(*) filter (where gender = 'F') f from a group by age) q),

    'regions', (select coalesce(jsonb_agg(jsonb_build_object('province', prov, 'kab_kota', kab, 'athletes', n, 'clubs', k) order by n desc, kab), '[]'::jsonb)
      from (select coalesce(nullif(a.province,''), case when a.nationality = 'WNA' then 'Luar negeri' else 'Tidak diisi' end) prov,
                   coalesce(nullif(a.kab_kota,''), case when a.nationality = 'WNA' then a.country else 'Tidak diisi' end) kab,
                   count(*) n, count(distinct a.club_id) k
              from a group by 1, 2) q),

    'clubs', (select coalesce(jsonb_agg(jsonb_build_object(
        'name', q.name, 'kind', q.kind, 'kab_kota', q.kab, 'province', q.prov, 'country', q.country,
        'submissions', q.subs, 'athletes', q.ath, 'paid', q.paid, 'pending', q.ath - q.paid,
        'male', q.m, 'female', q.f, 'entries', q.ent, 'teams', q.teams,
        'paid_amount', q.paid_amt, 'outstanding', q.out_amt, 'disciplines', q.discs, 'first_at', q.first_at
      ) order by q.ath desc, q.name), '[]'::jsonb)
      from (select s.club_id, coalesce(max(s.club_name), 'Tanpa klub') name, max(s.club_kind) kind,
                   coalesce(max(s.club_kab), (select a.kab_kota from a where a.club_id is not distinct from s.club_id and a.kab_kota is not null group by a.kab_kota order by count(*) desc limit 1)) kab,
                   coalesce(max(s.club_prov), (select a.province from a where a.club_id is not distinct from s.club_id and a.province is not null group by a.province order by count(*) desc limit 1)) prov, max(s.club_country) country, count(*) subs,
                   (select count(*) from a where a.club_id is not distinct from s.club_id) ath,
                   (select count(*) from a where a.club_id is not distinct from s.club_id and a.sst = 'lunas') paid,
                   (select count(*) from a where a.club_id is not distinct from s.club_id and a.gender = 'M') m,
                   (select count(*) from a where a.club_id is not distinct from s.club_id and a.gender = 'F') f,
                   (select count(*) from e where e.club_id is not distinct from s.club_id) ent,
                   (select count(*) from jo.teams t join s s2 on s2.id = t.submission_id where s2.club_id is not distinct from s.club_id) teams,
                   coalesce(sum(coalesce(s.paid_amount, s.total_amount)) filter (where s.status = 'lunas'), 0) paid_amt,
                   coalesce(sum(s.total_amount) filter (where s.status <> 'lunas'), 0) out_amt,
                   (select jsonb_object_agg(z.discipline, z.n) from (select a.discipline, count(*) n from a where a.club_id is not distinct from s.club_id group by a.discipline) z) discs,
                   min(s.created_at) first_at
              from s group by s.club_id) q
      where q.ath > 0),

    'compliance', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', d.code,
        'docs_waiting', (select count(*) from a where a.discipline = d.code and a.doc_status = 'menunggu'),
        'docs_invalid', (select count(*) from a where a.discipline = d.code and a.doc_status = 'tidak_valid'),
        'docs_valid', (select count(*) from a where a.discipline = d.code and a.doc_status = 'valid'),
        'no_bpjs', (select count(*) from a where a.discipline = d.code and a.bpjs_path is null),
        'no_photo', (select count(*) from a where a.discipline = d.code and a.photo_path is null),
        'no_akte', (select count(*) from a where a.discipline = d.code and a.nationality = 'WNI' and a.akte_path is null),
        'priangan_waiting', (select count(*) from e where e.discipline = d.code and e.priangan_status = 'menunggu'),
        'priangan_ok', (select count(*) from e where e.discipline = d.code and e.priangan_status = 'disetujui'),
        'priangan_rejected', (select count(*) from e where e.discipline = d.code and e.priangan_status = 'ditolak'),
        'music_ok', (select count(*) from e where e.discipline = d.code and e.music_status = 'ok'),
        'music_waiting', (select count(*) from e where e.discipline = d.code and e.music_status = 'menunggu'),
        'music_missing', (select count(*) from e where e.discipline = d.code and e.music_status = 'belum'),
        'music_broken', (select count(*) from e where e.discipline = d.code and e.music_status = 'tidak_bisa')
      ) order by d.sort), '[]'::jsonb) from jo.disciplines d),

    -- tren: per minggu (Senin–Minggu, WIB) dan per hari 14 hari terakhir, berdasarkan waktu pendaftaran
    'weekly', (select coalesce(jsonb_agg(jsonb_build_object('week', wk, 'submissions', subs, 'athletes', ath, 'paid', paid) order by wk), '[]'::jsonb)
      from (select date_trunc('week', a.sub_at at time zone 'Asia/Jakarta')::date wk, count(distinct a.submission_id) subs, count(*) ath,
                   count(*) filter (where a.sst = 'lunas') paid from a group by 1) q),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', dy, 'athletes', coalesce(n, 0)) order by dy), '[]'::jsonb)
      from (select g::date dy, (select count(*) from a where (a.sub_at at time zone 'Asia/Jakarta')::date = g::date) n
              from generate_series((v_now at time zone 'Asia/Jakarta')::date - 13, (v_now at time zone 'Asia/Jakarta')::date, interval '1 day') g) q),

    'athletes', (select coalesce(jsonb_agg(jsonb_build_object(
        'no', a.athlete_no, 'name', a.full_name, 'gender', a.gender, 'birth_date', a.birth_date, 'age', a.age,
        'nationality', a.nationality, 'kab_kota', a.kab_kota, 'province', a.province, 'country', a.country,
        'club', coalesce(a.club_name, '-'), 'discipline', a.discipline,
        'categories', (select string_agg(c.name_id, '; ' order by c.sort) from ea join jo.categories c on c.id = ea.category_id where ea.athlete_id = a.id),
        'team', (select string_agg(t.name || ' (' || t.level || ')', '; ') from jo.team_members tm join jo.teams t on t.id = tm.team_id where tm.athlete_id = a.id),
        'submission', a.sub_code, 'status', a.sst, 'method', a.pm, 'doc_status', a.doc_status,
        'bpjs', a.bpjs_path is not null, 'registered_at', a.sub_at, 'paid_at', a.sub_paid_at
      ) order by a.discipline, a.club_name, a.full_name), '[]'::jsonb) from a)
  ) into v;

  perform jo.log(st.id, 'laporan_diunduh', 'laporan', null, jsonb_build_object('athletes', v->'totals'->'athletes'));
  return v;
end $$;

revoke all on function public.console_report() from public, anon;
grant execute on function public.console_report() to authenticated;
