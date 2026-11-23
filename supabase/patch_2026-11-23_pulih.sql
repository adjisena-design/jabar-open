-- =====================================================================
--  Jabar Open 2026 — Pemulihan Pendaftaran (portal ketiga, khusus)
--  Untuk pendaftaran yang gagal/terhapus otomatis padahal klub sudah membayar.
--  Memakai mesin Pendaftaran Massal (bulk_accounts/bulk_rows/bulk_batches) dengan
--  settings.mode = 'pulih':
--    * tanpa minimal atlet, tanpa masa berlaku, tidak terkunci batas pendaftaran
--    * baris diisi panitia dari data yang masih bisa dipulihkan; data yang hilang
--      dibiarkan kosong dan ditandai merah di lembar sampai dilengkapi
--    * owner & superadmin konsol bisa membuka lembar yang sama tanpa kode
--      (kode 'PANITIA:<id akun>', orang 'panitia')
--    * saat dikirim, kode pendaftaran & nomor atlet asli dipakai ulang
--      (data.orig.code / data.orig.athlete_no) dan ditandai di verify_note
--  Akun dibuat lewat jo.pulih_create() (SQL, bukan dari konsol).
-- =====================================================================

create or replace function jo.bulk_is_pulih(b jo.bulk_accounts)
returns boolean language sql immutable set search_path to '' as $$
  select coalesce(b.settings->>'mode', '') = 'pulih'
$$;

create or replace function jo.in_pulih()
returns boolean language sql stable set search_path to '' as $$
  select coalesce(current_setting('jo.pulih', true), '') <> ''
$$;

create or replace function jo.bulk_code_label(b jo.bulk_accounts)
returns text language sql immutable set search_path to '' as $$
  select case when coalesce(b.settings->>'mode', '') = 'pulih' then 'JO26-PL-' else 'JO26-MS-' end || lpad(b.seq::text, 3, '0')
$$;

create or replace function jo.bulk_link(b jo.bulk_accounts)
returns text language sql stable set search_path to '' as $$
  select jo.site_url() || case when jo.bulk_is_pulih(b) then 'pulih.html' else 'massal.html' end
$$;

-- panitia (owner/superadmin) yang sedang masuk konsol
create or replace function jo.pulih_staff()
returns jo.staff language sql stable security definer set search_path to '' as $$
  select s.* from jo.current_staff() s where s.id is not null and s.role in ('owner', 'superadmin')
$$;

create or replace function jo.bulk_person_name(b jo.bulk_accounts, p_person text)
returns text language plpgsql stable set search_path to '' as $$
declare v text; st jo.staff;
begin
  if p_person = 'pemilik' then return b.owner_name; end if;
  if p_person = 'panitia' then
    if not jo.bulk_is_pulih(b) then return null; end if;
    st := jo.pulih_staff();
    return case when st.id is not null then 'Panitia · ' || st.name end;
  end if;
  select x->>'name' into v from jsonb_array_elements(b.collaborators) x where x->>'id' = p_person;
  return v;
end $$;

create or replace function jo.bulk_auth(p_code text, p_person text, p_write boolean)
returns jo.bulk_accounts language plpgsql set search_path to '' as $$
declare b jo.bulk_accounts; v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  if upper(coalesce(p_code, '')) like 'PANITIA:%' then
    -- owner/superadmin membuka lembar pemulihan tanpa kode akses
    if (jo.pulih_staff()).id is null then
      raise exception 'Masuk konsol sebagai owner atau superadmin untuk membuka lembar ini.' using hint = 'ERR_BULK_CODE';
    end if;
    begin v_id := substr(p_code, 9)::uuid; exception when others then v_id := null; end;
    select * into b from jo.bulk_accounts where id = v_id;
    if b.id is null or not jo.bulk_is_pulih(b) or b.status <> 'aktif' then
      raise exception 'Lembar pemulihan tidak ditemukan atau sudah dicabut.' using hint = 'ERR_BULK_CODE';
    end if;
  else
    select * into b from jo.bulk_accounts where code_hash = jo.sha256(jo.norm_code(p_code));
    if b.id is null or b.status <> 'aktif' then
      raise exception 'Kode akses tidak dikenal atau sudah tidak berlaku. Hubungi Inda untuk kode baru.' using hint = 'ERR_BULK_CODE';
    end if;
  end if;
  if p_person is not null then
    if b.owner_name is null and p_person <> 'panitia' then
      raise exception 'Data pemilik belum diisi.' using hint = 'ERR_BULK_SETUP';
    end if;
    if jo.bulk_person_name(b, p_person) is null then
      raise exception 'Pilih nama Anda dari daftar.' using hint = 'ERR_BULK_PERSON';
    end if;
  end if;
  if p_write and not jo.bulk_is_pulih(b) then   -- lembar pemulihan tidak punya masa berlaku
    if b.expires_at is not null and now() > b.expires_at then
      raise exception 'Masa pengisian sudah berakhir (%). Hubungi Inda bila perlu.', to_char(b.expires_at at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI') || ' WIB' using hint = 'ERR_BULK_EXPIRED';
    end if;
    if now() > jo.bulk_deadline() then
      raise exception 'Pendaftaran sudah ditutup.' using hint = 'ERR_CLOSED';
    end if;
  end if;
  return b;
end $$;

create or replace function jo.bulk_files_open(b jo.bulk_accounts)
returns boolean language sql stable set search_path to '' as $$
  select b.status = 'aktif' and now() < jo.bulk_event_start()
     and (jo.bulk_is_pulih(b)
          or (b.expires_at is not null and now() <= b.expires_at and now() <= jo.bulk_deadline())
          or (b.files_until is not null and now() <= b.files_until))
$$;

create or replace function jo.bulk_files_until(b jo.bulk_accounts)
returns timestamptz language sql stable set search_path to '' as $$
  select case when not jo.bulk_files_open(b) then null
              when jo.bulk_is_pulih(b) then jo.bulk_event_start()
              else least(jo.bulk_event_start(), greatest(case when now() <= jo.bulk_deadline() then least(b.expires_at, jo.bulk_deadline()) end, b.files_until)) end
$$;

create or replace function jo.bulk_public_json(b jo.bulk_accounts)
returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object(
    'code_label', jo.bulk_code_label(b), 'label', b.label, 'status', b.status,
    'opened_at', b.opened_at, 'expires_at', b.expires_at, 'extended_days', b.extended_days,
    'setup', b.owner_name is not null,
    'owner', case when b.owner_name is not null then jsonb_build_object('name', b.owner_name, 'phone', b.owner_phone, 'email', b.owner_email, 'role', b.owner_role) end,
    'collaborators', b.collaborators,
    'people', (case when b.owner_name is not null then
        jsonb_build_array(jsonb_build_object('id', 'pemilik', 'name', b.owner_name, 'role', 'Pemilik')) ||
        coalesce((select jsonb_agg(jsonb_build_object('id', x->>'id', 'name', x->>'name', 'role', 'Kolaborator')) from jsonb_array_elements(b.collaborators) x), '[]'::jsonb)
      else '[]'::jsonb end)
      || case when jo.bulk_is_pulih(b) and (jo.pulih_staff()).id is not null
              then jsonb_build_array(jsonb_build_object('id', 'panitia', 'name', jo.bulk_person_name(b, 'panitia'), 'role', 'Panitia')) else '[]'::jsonb end,
    'club', case when b.club_id is not null then (select jsonb_build_object('id', c.id, 'name', c.name, 'kab_kota', c.kab_kota, 'province', c.province, 'country', c.country) from jo.clubs c where c.id = b.club_id)
                 else b.club_new end,
    'locked', not jo.bulk_is_pulih(b) and ((b.expires_at is not null and now() > b.expires_at) or now() > jo.bulk_deadline()),
    'files_open', jo.bulk_files_open(b), 'files_until', jo.bulk_files_until(b),
    'min', jo.bulk_cfg_int(b, 'min'), 'max', jo.bulk_cfg_int(b, 'max'), 'pay_hours', jo.bulk_cfg_int(b, 'pay_hours'),
    'mode', case when jo.bulk_is_pulih(b) then 'pulih' else 'massal' end,
    'staff', jo.bulk_is_pulih(b) and (jo.pulih_staff()).id is not null,
    'sources', case when jo.bulk_is_pulih(b) then coalesce(b.settings->'sources', '[]'::jsonb) end,
    'pulih_note', case when jo.bulk_is_pulih(b) then b.settings->>'note' end,
    'missing_contact', case when jo.bulk_is_pulih(b) then to_jsonb(array_remove(array[
        case when length(regexp_replace(coalesce(b.owner_phone, ''), '[^0-9]', '', 'g')) < 9 then 'phone' end,
        case when coalesce(b.owner_email, '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'email' end,
        case when coalesce(b.owner_role, '') not in ('pemilik','admin','pelatih','manajer','lainnya') then 'role' end,
        case when b.club_id is null and (coalesce(b.club_new->>'name', '') = ''
               or (coalesce(b.club_new->>'country', 'Indonesia') = 'Indonesia'
                   and (coalesce(b.club_new->>'province', '') = '' or coalesce(b.club_new->>'kab_kota', '') = ''))) then 'club' end
      ], null)) end)
$$;

create or replace function public.public_bulk_open(p_code text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare b jo.bulk_accounts; v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  if upper(coalesce(p_code, '')) like 'PANITIA:%' then
    begin
      b := jo.bulk_auth(p_code, null, false);
    exception when others then
      return jsonb_build_object('ok', false, 'message', sqlerrm);
    end;
    return jo.bulk_public_json(b) || jsonb_build_object('ok', true);
  end if;
  -- kode salah dicatat tanpa exception agar catatannya tidak ikut dibatalkan
  if (select count(*) from jo.rate_events where uid = v_uid and action = 'bulk_fail' and at > now() - interval '15 minutes') >= 10 then
    return jsonb_build_object('ok', false, 'message', 'Terlalu banyak percobaan kode yang salah. Tunggu 15 menit lalu coba lagi.');
  end if;
  select * into b from jo.bulk_accounts where code_hash = jo.sha256(jo.norm_code(p_code));
  if b.id is null or b.status <> 'aktif' then
    insert into jo.rate_events (uid, action) values (v_uid, 'bulk_fail');
    return jsonb_build_object('ok', false, 'message', 'Kode akses tidak dikenal atau sudah tidak berlaku. Hubungi Inda untuk kode baru.');
  end if;
  if b.opened_at is null then
    if jo.bulk_is_pulih(b) then
      update jo.bulk_accounts set opened_at = now(), updated_at = now() where id = b.id returning * into b;   -- tanpa masa berlaku
    else
      update jo.bulk_accounts
         set opened_at = now(),
             expires_at = least(now() + make_interval(days => coalesce(jo.setting_int('bulk_days'), 7)), jo.bulk_deadline()),
             updated_at = now()
       where id = b.id returning * into b;
    end if;
    perform jo.bulk_add_log(b.id, null, 'kode_dibuka', jsonb_build_object('expires_at', b.expires_at));
  end if;
  return jo.bulk_public_json(b) || jsonb_build_object('ok', true);
end $$;

-- baris draf lembar pemulihan tidak ikut dibersihkan setelah batas pendaftaran
create or replace function jo.bulk_tick()
returns void language plpgsql set search_path to '' as $$
declare r record;
begin
  for r in select id from jo.bulk_accounts
            where status = 'aktif' and owner_email is not null and reminded_at is null
              and expires_at is not null and now() < expires_at and expires_at - now() <= interval '2 days'
              and coalesce(settings->>'mode', '') <> 'pulih'
            for update skip locked loop
    perform jo.queue_bulk_email(r.id, 'massal_pengingat');
    update jo.bulk_accounts set reminded_at = now() where id = r.id;
  end loop;
  if now() > jo.bulk_deadline() + interval '1 day' then
    delete from jo.bulk_rows where batch_id is null
       and bulk_id not in (select id from jo.bulk_accounts where coalesce(settings->>'mode', '') = 'pulih');
  end if;
end $$;

-- kode asli setelah pendaftaran pemulihan terbentuk
create or replace function jo.pulih_restore_sub(p_sub uuid, p_batch uuid, p_disc text, p_label text)
returns text language plpgsql set search_path to '' as $$
declare v_orig text; v_tok text; s jo.submissions; v_note text;
begin
  select * into s from jo.submissions where id = p_sub;
  select r.data->'orig'->>'code', max(r.data->'orig'->>'token') into v_orig, v_tok
    from jo.bulk_rows r
   where r.batch_id = p_batch and r.data->>'discipline' = p_disc and coalesce(r.data->'orig'->>'code', '') <> ''
   group by 1 order by count(*) desc limit 1;
  if v_orig is not null and not exists (select 1 from jo.submissions x where x.code = v_orig) then
    update jo.submissions set code = v_orig, token = coalesce(nullif(v_tok, ''), token) where id = p_sub;
    v_note := 'PEMULIHAN: kode ' || v_orig || ' dipakai ulang (pendaftaran asli terhapus otomatis). Dikirim lewat portal pemulihan ' || p_label || '.';
    perform jo.log(null, 'pendaftaran_dipulihkan', 'submission', p_sub::text, jsonb_build_object('code', v_orig, 'from', s.code, 'portal', p_label));
  elsif v_orig is not null then
    v_note := 'PEMULIHAN: tambahan untuk ' || v_orig || ', dikirim lewat portal pemulihan ' || p_label || '.';
    v_orig := s.code;
  else
    v_note := 'PEMULIHAN: pendaftaran baru lewat portal pemulihan ' || p_label || ' (tidak ada kode asli).';
    v_orig := s.code;
  end if;
  update jo.submissions set verify_note = trim(both ' ' from coalesce(verify_note || ' ', '') || v_note) where id = p_sub;
  return v_orig;
end $$;

create or replace function jo.pulih_restore_athletes(p_batch uuid)
returns void language sql set search_path to '' as $$
  update jo.athletes a set athlete_no = r.data->'orig'->>'athlete_no'
    from jo.bulk_rows r
   where a.bulk_row_id = r.id and r.batch_id = p_batch
     and coalesce(r.data->'orig'->>'athlete_no', '') <> ''
     and split_part(r.data->'orig'->>'athlete_no', '-', 1) = r.data->>'discipline'
     and not exists (select 1 from jo.athletes x where x.athlete_no = r.data->'orig'->>'athlete_no');
$$;

-- akun pemulihan baru (dipanggil dari SQL oleh panitia/Claude, tidak dibuka ke publik)
-- p: { label, club_id | club_new{name,province,kab_kota,country}, owner{name,email,phone,role},
--      note, sources[ {code, token, deleted_at, contact, email, total} ], rows[ {..data baris..} ] }
create or replace function jo.pulih_create(p jsonb)
returns jsonb language plpgsql set search_path to '' as $$
declare v_code text := 'PL-' || jo.rand_code(4) || '-' || jo.rand_code(4) || '-' || jo.rand_code(4);
        b jo.bulk_accounts; x jsonb; i integer := 0;
begin
  if length(trim(coalesce(p->>'label', ''))) < 3 then raise exception 'Isi label akun.'; end if;
  insert into jo.bulk_accounts (seq, code_hash, code_hint, label, note, owner_name, owner_phone, owner_email, owner_role,
                                club_id, club_new, settings)
  values (nextval('jo.bulk_seq'), jo.sha256(jo.norm_code(v_code)), right(v_code, 4), trim(p->>'label'), nullif(trim(coalesce(p->>'note', '')), ''),
          nullif(trim(coalesce(p->'owner'->>'name', '')), ''), nullif(trim(coalesce(p->'owner'->>'phone', '')), ''),
          nullif(lower(trim(coalesce(p->'owner'->>'email', ''))), ''), nullif(trim(coalesce(p->'owner'->>'role', '')), ''),
          nullif(p->>'club_id', '')::uuid, case when nullif(p->>'club_id', '') is null then p->'club_new' end,
          jsonb_build_object('mode', 'pulih', 'min', 1, 'max', 250, 'pay_hours', 48,
                             'sources', coalesce(p->'sources', '[]'::jsonb), 'note', p->>'note'))
  returning * into b;
  for x in select * from jsonb_array_elements(coalesce(p->'rows', '[]'::jsonb)) loop
    i := i + 1;
    insert into jo.bulk_rows (bulk_id, row_no, data, updated_by)
    values (b.id, i, jsonb_build_object('nationality', 'WNI', 'docs', '{}'::jsonb) || x, 'Panitia (dipulihkan)');
  end loop;
  perform jo.bulk_add_log(b.id, 'Panitia', 'akun_pulih_dibuat', jsonb_build_object('rows', i, 'sources', (select coalesce(jsonb_agg(s->>'code'), '[]'::jsonb) from jsonb_array_elements(coalesce(p->'sources', '[]'::jsonb)) s)));
  perform jo.log(null, 'pulih_akun_dibuat', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'label', b.label, 'rows', i));
  return jsonb_build_object('id', b.id, 'code', v_code, 'code_label', jo.bulk_code_label(b), 'rows', i,
                            'link', jo.site_url() || 'pulih.html?kode=' || v_code,
                            'staff_link', jo.site_url() || 'pulih.html?akun=' || b.id);
end $$;

-- daftar lembar pemulihan untuk owner/superadmin (halaman pulih.html)
create or replace function public.public_pulih_list()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  if (jo.pulih_staff()).id is null then return jsonb_build_object('staff', false, 'items', '[]'::jsonb); end if;
  return jsonb_build_object('staff', true, 'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', b.id, 'label', b.label, 'code_label', jo.bulk_code_label(b), 'status', b.status, 'opened_at', b.opened_at,
      'rows', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id),
      'sent', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id and r.batch_id is not null),
      'sources', coalesce(b.settings->'sources', '[]'::jsonb)) order by b.seq desc)
    from jo.bulk_accounts b where coalesce(b.settings->>'mode', '') = 'pulih'), '[]'::jsonb));
end $$;
grant execute on function public.public_pulih_list() to anon, authenticated;

-- ---------------------------------------------------------------------
--  Penyesuaian fungsi yang sudah ada (ganti potongan teks, diperiksa)
-- ---------------------------------------------------------------------
do $$
declare d text; o text; f regprocedure;
begin
  -- public_register: pemulihan tidak terhalang penutupan pendaftaran
  f := 'public.public_register(jsonb)'::regprocedure; d := pg_get_functiondef(f); o := d;
  d := replace(d, E'  if not jo.reg_is_open()\n     or now() > coalesce((jo.setting_text(''registration_deadline''))::timestamptz, now()) then',
                  E'  if not jo.in_pulih() and (not jo.reg_is_open()\n     or now() > coalesce((jo.setting_text(''registration_deadline''))::timestamptz, now())) then');
  d := replace(d, '  if not v_disc.registration_open then', '  if not v_disc.registration_open and not jo.in_pulih() then');
  if d = o or (length(d) - length(o)) <> length('not jo.in_pulih() and () and not jo.in_pulih()') then
    raise exception 'patch public_register gagal';
  end if;
  execute d;

  -- public_bulk_submit: tanpa cek buka/tutup untuk pemulihan, lalu pakai ulang kode asli
  f := 'public.public_bulk_submit(text,text,integer[],jsonb,text)'::regprocedure; d := pg_get_functiondef(f); o := d;
  d := replace(d, '  if not jo.reg_is_open() then', '  if not jo.reg_is_open() and not jo.bulk_is_pulih(b) then');
  d := replace(d, E'  perform set_config(''jo.bulk'', v_batch.id::text, true);\n',
                  E'  perform set_config(''jo.bulk'', v_batch.id::text, true);\n  perform set_config(''jo.pulih'', case when jo.bulk_is_pulih(b) then ''1'' else '''' end, true);\n');
  d := replace(d, E'    select * into v_sub from jo.submissions where code = v_res->>''code'';\n    update jo.submissions set bulk_batch_id = v_batch.id where id = v_sub.id;\n',
                  E'    select * into v_sub from jo.submissions where code = v_res->>''code'';\n    update jo.submissions set bulk_batch_id = v_batch.id where id = v_sub.id;\n    if jo.bulk_is_pulih(b) then\n      perform jo.pulih_restore_sub(v_sub.id, v_batch.id, v_disc, jo.bulk_code_label(b));\n      select * into v_sub from jo.submissions where id = v_sub.id;\n    end if;\n');
  d := replace(d, E'  perform set_config(''jo.bulk'', '''', true);\n  perform jo.bulk_link_rows(v_batch.id);\n',
                  E'  perform set_config(''jo.bulk'', '''', true);\n  perform set_config(''jo.pulih'', '''', true);\n  perform jo.bulk_link_rows(v_batch.id);\n  if jo.bulk_is_pulih(b) then perform jo.pulih_restore_athletes(v_batch.id); end if;\n');
  if (select count(*) from regexp_matches(d, 'pulih', 'g')) <> 8 then
    raise exception 'patch public_bulk_submit gagal (%)', (select count(*) from regexp_matches(d, 'pulih', 'g'));
  end if;
  execute d;

  -- public_bulk_pay: bukti transfer lama (sebelum lembar pemulihan dibuat) boleh diunggah
  f := 'public.public_bulk_pay(text,text,uuid,integer,date,text)'::regprocedure; d := pg_get_functiondef(f); o := d;
  d := replace(d, 'or p_date < (bt.created_at at time zone ''Asia/Jakarta'')::date - 1 then',
                  'or (p_date < (bt.created_at at time zone ''Asia/Jakarta'')::date - 1 and not jo.bulk_is_pulih(b)) then');
  if d = o then raise exception 'patch public_bulk_pay gagal'; end if;
  execute d;

  -- public_bulk_setup: panitia boleh mengubah data kontak/klub lembar pemulihan
  f := 'public.public_bulk_setup(text,text,jsonb)'::regprocedure; d := pg_get_functiondef(f); o := d;
  d := replace(d, E'  if not v_first and coalesce(p_person,'''') <> ''pemilik'' then',
                  E'  if not v_first and coalesce(p_person,'''') <> ''pemilik''\n     and not (coalesce(p_person,'''') = ''panitia'' and jo.bulk_person_name(b, ''panitia'') is not null) then');
  if d = o then raise exception 'patch public_bulk_setup gagal'; end if;
  execute d;

  -- email: tautan ke portal yang sesuai (massal.html / pulih.html)
  f := 'jo.queue_bulk_email(uuid,text,jsonb)'::regprocedure; d := pg_get_functiondef(f); o := d;
  d := replace(d, 'jo.bulk_portal_link()', 'jo.bulk_link(b)');
  if d = o then raise exception 'patch queue_bulk_email gagal'; end if;
  execute d;
end $$;
