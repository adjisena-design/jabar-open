-- =====================================================================
--  Notifikasi WhatsApp untuk admin pendaftaran (v9)
--  Database menyusun ringkasan tiap N menit (default 15) bila ada bukti bayar
--  baru; Google Apps Script mengambil antrean (wa_claim), mengirim lewat
--  gateway WhatsApp (token gateway hanya disimpan di Apps Script), lalu
--  melaporkan hasilnya (wa_report). Diamankan dengan secret yang sama
--  dengan pengirim email.
-- =====================================================================

create or replace function jo.wa_phone(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when d ~ '^0' then '62' || substr(d, 2)
    when d ~ '^8' then '62' || d
    else d end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) x
$$;

-- jumlah yang perlu ditindaklanjuti admin, per disiplin (null = semua)
create or replace function jo.action_counts(p_disc text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'to_verify', (select count(*) from jo.submissions s where s.status = 'menunggu_verifikasi' and (p_disc is null or s.discipline = p_disc)),
    'to_verify_athletes', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
                            where s.status = 'menunggu_verifikasi' and (p_disc is null or s.discipline = p_disc)),
    'docs_pending', (select count(*) from jo.athletes a join jo.submissions s on s.id = a.submission_id
                      where s.status <> 'dibatalkan' and a.doc_status = 'menunggu' and (p_disc is null or s.discipline = p_disc)),
    'priangan_pending', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id
                          where s.status <> 'dibatalkan' and e.priangan_status = 'menunggu' and (p_disc is null or s.discipline = p_disc)),
    'music_pending', (select count(*) from jo.entries e join jo.submissions s on s.id = e.submission_id
                       where s.status <> 'dibatalkan' and e.status <> 'dibatalkan' and e.music_status = 'menunggu'
                         and (p_disc is null or s.discipline = p_disc)))
$$;

-- susun ringkasan untuk setiap penerima aktif bila ada bukti bayar baru sejak ringkasan terakhir
create or replace function jo.wa_digest() returns integer
language plpgsql volatile set search_path = '' as $$
declare
  v_int   integer := greatest(coalesce(jo.setting_int('wa_interval_min'), 15), 5);
  v_last  timestamptz := coalesce((jo.setting_text('wa_last_digest'))::timestamptz, now() - interval '1 day');
  v_now   timestamptz := now();
  v_site  text := jo.site_url();
  r       jo.wa_recipients;
  v_list  text;
  v_n     integer;
  v_c     jsonb;
  v_msg   text;
  v_q     integer := 0;
begin
  if not coalesce(jo.setting_bool('wa_enabled'), true) then return 0; end if;
  if v_now - v_last < make_interval(mins => v_int) then return 0; end if;
  perform pg_advisory_xact_lock(4242099);
  -- ulangi pemeriksaan setelah kunci (dua pemanggil bersamaan)
  v_last := coalesce((jo.setting_text('wa_last_digest'))::timestamptz, now() - interval '1 day');
  if v_now - v_last < make_interval(mins => v_int) then return 0; end if;

  for r in select * from jo.wa_recipients where active order by name loop
    select count(*), string_agg('- ' || s.code || ' · ' || coalesce(k.name, s.contact_name) || ' · '
             || (select count(*) from jo.athletes a where a.submission_id = s.id) || ' atlet'
             || case when (select count(*) from jo.teams t where t.submission_id = s.id) > 0
                     then ' + ' || (select count(*) from jo.teams t where t.submission_id = s.id) || ' tim' else '' end
             || ' · ' || to_char(coalesce(s.proof_uploaded_at, s.created_at) at time zone 'Asia/Jakarta', 'DD/MM HH24.MI'),
             E'\n' order by coalesce(s.proof_uploaded_at, s.created_at))
      into v_n, v_list
      from jo.submissions s left join jo.clubs k on k.id = s.club_id
     where (r.discipline is null or s.discipline = r.discipline)
       and ((s.status = 'menunggu_verifikasi' and s.proof_uploaded_at > v_last and s.proof_uploaded_at <= v_now)
         or (s.payment_method = 'manual' and s.status = 'menunggu_pembayaran' and s.created_at > v_last and s.created_at <= v_now));
    continue when coalesce(v_n, 0) = 0;
    if v_n > 8 then
      v_list := (select string_agg(x, E'\n') from (select unnest(string_to_array(v_list, E'\n')) x limit 8) y)
                || E'\n- dan ' || (v_n - 8) || ' lainnya';
    end if;
    v_c := jo.action_counts(r.discipline);
    v_msg := 'Jabar Open 2026 · Konsol panitia' || E'\n'
      || v_n || ' pendaftaran baru perlu diperiksa'
      || coalesce(' (' || (select name_id from jo.disciplines where code = r.discipline) || ')', '') || ':' || E'\n'
      || v_list || E'\n\n'
      || 'Total menunggu: ' || (v_c->>'to_verify') || ' verifikasi bayar (' || (v_c->>'to_verify_athletes') || ' atlet), '
      || (v_c->>'docs_pending') || ' dokumen atlet belum diperiksa.' || E'\n'
      || 'Buka konsol: ' || v_site || 'panitia/#/pendaftaran?s=menunggu_verifikasi'
      || coalesce('&d=' || r.discipline, '');
    insert into jo.wa_outbox (kind, recipient_id, to_phone, message) values ('digest', r.id, jo.wa_phone(r.phone), v_msg);
    v_q := v_q + 1;
  end loop;

  insert into jo.settings (key, value) values ('wa_last_digest', to_jsonb(v_now))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return v_q;
end $$;

create or replace function public.wa_claim(p_secret text, p_limit integer default 10) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r jsonb;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  insert into jo.settings (key, value) values ('wa_last_poll', to_jsonb(now()))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform jo.wa_digest();
  with picked as (
    select id from jo.wa_outbox
     where status = 'pending'
        or (status = 'sending' and claimed_at < now() - interval '10 minutes')
        or (status = 'error' and attempts < 3 and claimed_at < now() - interval '15 minutes')
     order by id limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked
  ), upd as (
    update jo.wa_outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
      from picked where o.id = picked.id
    returning o.id, o.to_phone, o.message
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'to', to_phone, 'message', message) order by id), '[]'::jsonb)
    into r from upd;
  return r;
end $$;

create or replace function public.wa_report(p_secret text, p_results jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; n integer := 0;
begin
  if jo.setting_text('outbox_secret_hash') is null or jo.sha256(coalesce(p_secret,'')) <> jo.setting_text('outbox_secret_hash') then
    raise exception 'Secret salah.' using hint = 'ERR_SECRET';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if coalesce((x->>'ok')::boolean, false) then
      update jo.wa_outbox set status = 'sent', sent_at = now(), last_error = null where id = (x->>'id')::bigint;
    else
      update jo.wa_outbox set status = 'error', last_error = left(coalesce(x->>'error','tidak diketahui'), 500)
       where id = (x->>'id')::bigint;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('updated', n);
end $$;

-- ---------------------------------------------------------------------
-- Konsol: pengaturan penerima notifikasi (owner & superadmin)
-- ---------------------------------------------------------------------
create or replace function public.console_wa() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin']);
  return jsonb_build_object(
    'enabled', coalesce(jo.setting_bool('wa_enabled'), true),
    'interval_min', greatest(coalesce(jo.setting_int('wa_interval_min'), 15), 5),
    'last_poll', jo.setting('wa_last_poll'),
    'last_digest', jo.setting('wa_last_digest'),
    'recipients', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'phone', r.phone,
        'discipline', r.discipline, 'active', r.active) order by r.active desc, r.name), '[]'::jsonb) from jo.wa_recipients r),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'created_at', o.created_at, 'kind', o.kind,
        'to', o.to_phone, 'name', (select name from jo.wa_recipients r where r.id = o.recipient_id),
        'status', o.status, 'sent_at', o.sent_at, 'error', o.last_error, 'message', o.message) order by o.id desc), '[]'::jsonb)
        from (select * from jo.wa_outbox order by id desc limit 20) o),
    'counts', jsonb_build_object(
        'pending', (select count(*) from jo.wa_outbox where status in ('pending','sending')),
        'error', (select count(*) from jo.wa_outbox where status = 'error'),
        'sent', (select count(*) from jo.wa_outbox where status = 'sent')));
end $$;

create or replace function public.console_wa_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_id uuid := nullif(p->>'id','')::uuid; v_phone text; v_disc text := nullif(p->>'discipline','');
begin
  st := jo.require_staff(array['owner','superadmin']);
  v_phone := jo.wa_phone(p->>'phone');
  if length(trim(coalesce(p->>'name',''))) < 2 then raise exception 'Isi nama penerima.'; end if;
  if length(v_phone) < 10 or length(v_phone) > 15 then raise exception 'Nomor WhatsApp tidak valid.'; end if;
  if v_disc is not null and not exists (select 1 from jo.disciplines where code = v_disc) then raise exception 'Disiplin tidak dikenal.'; end if;
  if v_id is null then
    insert into jo.wa_recipients (name, phone, discipline, active)
    values (trim(p->>'name'), v_phone, v_disc, coalesce((p->>'active')::boolean, true)) returning id into v_id;
  else
    update jo.wa_recipients set name = trim(p->>'name'), phone = v_phone, discipline = v_disc,
      active = coalesce((p->>'active')::boolean, active), updated_at = now() where id = v_id;
    if not found then raise exception 'Penerima tidak ditemukan.'; end if;
  end if;
  perform jo.log(st.id, 'wa_penerima_disimpan', 'wa_recipient', v_id::text,
    jsonb_build_object('name', trim(p->>'name'), 'discipline', v_disc, 'active', coalesce((p->>'active')::boolean, true)));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.console_wa_settings(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_int integer;
begin
  st := jo.require_staff(array['owner','superadmin']);
  if p ? 'enabled' then
    insert into jo.settings (key, value) values ('wa_enabled', to_jsonb(coalesce((p->>'enabled')::boolean, true)))
      on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  if p ? 'interval_min' then
    v_int := (p->>'interval_min')::integer;
    if v_int is null or v_int < 5 or v_int > 240 then raise exception 'Interval 5 sampai 240 menit.'; end if;
    insert into jo.settings (key, value) values ('wa_interval_min', to_jsonb(v_int))
      on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  perform jo.log(st.id, 'wa_pengaturan', 'settings', 'wa', p);
  return public.console_wa();
end $$;

create or replace function public.console_wa_test(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; r jo.wa_recipients;
begin
  st := jo.require_staff(array['owner','superadmin']);
  select * into r from jo.wa_recipients where id = p_id;
  if r.id is null then raise exception 'Penerima tidak ditemukan.'; end if;
  insert into jo.wa_outbox (kind, recipient_id, to_phone, message)
  values ('tes', r.id, jo.wa_phone(r.phone),
    'Jabar Open 2026 · Konsol panitia' || E'\n' || 'Tes notifikasi WhatsApp untuk ' || r.name || '.'
    || E'\n' || 'Anda akan menerima ringkasan setiap ada bukti bayar baru yang perlu diverifikasi'
    || coalesce(' (' || (select name_id from jo.disciplines where code = r.discipline) || ')', '') || '.'
    || E'\n' || 'Dikirim atas permintaan ' || st.name || '.');
  perform jo.log(st.id, 'wa_tes', 'wa_recipient', r.id::text, jsonb_build_object('name', r.name));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Penanda "perlu tindakan" di konsol (titik merah, judul tab)
-- ---------------------------------------------------------------------
create or replace function public.console_actions() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','admin']);
  return jo.action_counts(st.discipline);
end $$;
