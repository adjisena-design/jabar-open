-- 27/11/2026: Pendaftaran Susulan (susulan.html) — akses khusus berkode untuk kelompok yang terlambat
-- setelah penutupan awal Artistik & Ritmik. Mesin lembar = pendaftaran massal/pemulihan:
--   settings.mode = 'susulan', min 10 atlet, hanya disiplin di settings.disciplines (MAG, WAG, RG),
--   melewati sakelar penutupan disiplin, tetapi tetap tunduk pada masa berlaku (expires_at = batas pendaftaran,
--   30 Nov 2026 23.59 WIB) untuk isi, kirim, dan unggah bukti bayar. Batch tanpa pembayaran dibatalkan
--   otomatis oleh jo.deadline_tick() setelah bulk_pay_until (bisa dipulihkan).
--   Akun dibuat lewat jo.susulan_create() (SQL). Owner/superadmin yang masuk konsol bisa membuka semua lembar.

create or replace function jo.bulk_mode(b jo.bulk_accounts) returns text
language sql immutable set search_path = '' as $$ select coalesce(nullif(b.settings->>'mode', ''), 'massal') $$;
create or replace function jo.bulk_is_special(b jo.bulk_accounts) returns boolean
language sql immutable set search_path = '' as $$ select jo.bulk_mode(b) in ('pulih', 'susulan') $$;
create or replace function jo.bulk_is_susulan(b jo.bulk_accounts) returns boolean
language sql immutable set search_path = '' as $$ select jo.bulk_mode(b) = 'susulan' $$;

create or replace function jo.bulk_code_label(b jo.bulk_accounts) returns text
language sql stable set search_path = '' as $$
  select case jo.bulk_mode(b) when 'pulih' then 'JO26-PL-' when 'susulan' then 'JO26-SL-' else 'JO26-MS-' end || lpad(b.seq::text, 3, '0')
$$;
create or replace function jo.bulk_link(b jo.bulk_accounts) returns text
language sql stable set search_path = '' as $$
  select jo.site_url() || case jo.bulk_mode(b) when 'pulih' then 'pulih.html' when 'susulan' then 'susulan.html' else 'massal.html' end
$$;

do $do$
declare d text; o text;
begin
  -- akses panitia (PANITIA:<id>) untuk lembar pemulihan dan susulan
  d := pg_get_functiondef('jo.bulk_auth(text,text,boolean)'::regprocedure); o := d;
  d := replace(d, 'if b.id is null or not jo.bulk_is_pulih(b) or b.status <> ''aktif'' then
      raise exception ''Lembar pemulihan tidak ditemukan', 'if b.id is null or not jo.bulk_is_special(b) or b.status <> ''aktif'' then
      raise exception ''Lembar khusus tidak ditemukan');
  if d = o then raise exception 'bulk_auth: pola'; end if;
  execute d;

  d := pg_get_functiondef('jo.bulk_public_json(jo.bulk_accounts)'::regprocedure); o := d;
  d := replace(d, '|| case when jo.bulk_is_pulih(b) and (jo.pulih_staff()).id is not null', '|| case when jo.bulk_is_special(b) and (jo.pulih_staff()).id is not null');
  d := replace(d, '''mode'', case when jo.bulk_is_pulih(b) then ''pulih'' else ''massal'' end,',
                  '''mode'', jo.bulk_mode(b), ''disciplines'', case when jo.bulk_is_susulan(b) then b.settings->''disciplines'' end, ''until'', case when jo.bulk_is_susulan(b) then b.expires_at end,');
  d := replace(d, '''staff'', jo.bulk_is_pulih(b) and (jo.pulih_staff()).id is not null,', '''staff'', jo.bulk_is_special(b) and (jo.pulih_staff()).id is not null,');
  if (length(o) - length(replace(o, 'jo.bulk_is_pulih', ''))) - (length(d) - length(replace(d, 'jo.bulk_is_pulih', ''))) <> 3 * length('jo.bulk_is_pulih') then
    raise exception 'bulk_public_json: pola';
  end if;
  execute d;

  -- kirim batch: lembar khusus melewati sakelar disiplin; lembar susulan dibatasi daftar disiplinnya
  d := pg_get_functiondef('public.public_bulk_submit(text,text,integer[],jsonb,text)'::regprocedure); o := d;
  d := replace(d, '  if not jo.reg_is_open() and not jo.bulk_is_pulih(b) then', '  if not jo.reg_is_open() and not jo.bulk_is_special(b) then');
  d := replace(d, '  perform set_config(''jo.pulih'', case when jo.bulk_is_pulih(b) then ''1'' else '''' end, true);',
                  '  perform set_config(''jo.pulih'', case when jo.bulk_is_special(b) then ''1'' else '''' end, true);
  perform set_config(''jo.susulan'', case when jo.bulk_is_susulan(b) then coalesce((select string_agg(x, '','') from jsonb_array_elements_text(b.settings->''disciplines'') x), '''') else '''' end, true);');
  d := replace(d, '  perform set_config(''jo.pulih'', '''', true);', '  perform set_config(''jo.pulih'', '''', true);
  perform set_config(''jo.susulan'', '''', true);');
  if (length(d) - length(replace(d, 'jo.susulan', ''))) <> 2 * length('jo.susulan') or position('not jo.bulk_is_special(b) then' in d) = 0 then
    raise exception 'public_bulk_submit: pola';
  end if;
  execute d;
end $do$;

do $do$
declare d text; o text;
begin
  -- formulir dari lembar susulan hanya untuk disiplin yang diizinkan
  d := pg_get_functiondef('public.public_register(jsonb)'::regprocedure); o := d;
  d := replace(d, '  if not v_disc.registration_open and not jo.in_pulih() then',
'  if coalesce(current_setting(''jo.susulan'', true), '''') <> ''''
     and not (v_disc.code = any(string_to_array(current_setting(''jo.susulan'', true), '',''))) then
    raise exception ''Pendaftaran susulan hanya untuk %.'', (select string_agg(x.name_id, '', '' order by x.sort) from jo.disciplines x
      where x.code = any(string_to_array(current_setting(''jo.susulan'', true), '','')));
  end if;
  if not v_disc.registration_open and not jo.in_pulih() then');
  if d = o then raise exception 'public_register: pola'; end if;
  execute d;
end $do$;

-- buat akun susulan (dijalankan dari SQL oleh owner)
create or replace function jo.susulan_create(p jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare v_code text := 'SL-' || jo.rand_code(4) || '-' || jo.rand_code(4) || '-' || jo.rand_code(4);
        b jo.bulk_accounts; v_until timestamptz := coalesce(nullif(p->>'until', '')::timestamptz, jo.bulk_deadline());
begin
  if length(trim(coalesce(p->>'label', ''))) < 3 then raise exception 'Isi label akun.'; end if;
  insert into jo.bulk_accounts (seq, code_hash, code_hint, label, note, owner_name, owner_phone, owner_email, owner_role,
                                club_id, club_new, expires_at, settings)
  values (nextval('jo.bulk_seq'), jo.sha256(jo.norm_code(v_code)), right(v_code, 4), trim(p->>'label'), nullif(trim(coalesce(p->>'note', '')), ''),
          nullif(trim(coalesce(p->'owner'->>'name', '')), ''), nullif(trim(coalesce(p->'owner'->>'phone', '')), ''),
          nullif(lower(trim(coalesce(p->'owner'->>'email', ''))), ''), nullif(trim(coalesce(p->'owner'->>'role', '')), ''),
          nullif(p->>'club_id', '')::uuid, case when nullif(p->>'club_id', '') is null then p->'club_new' end, v_until,
          jsonb_build_object('mode', 'susulan', 'min', coalesce((p->>'min')::int, 10), 'max', 250, 'pay_hours', 48,
                             'disciplines', coalesce(p->'disciplines', '["MAG","WAG","RG"]'::jsonb), 'note', p->>'note'))
  returning * into b;
  perform jo.bulk_add_log(b.id, 'Panitia', 'akun_susulan_dibuat', jsonb_build_object('until', v_until));
  perform jo.log(null, 'susulan_akun_dibuat', 'bulk', b.id::text, jsonb_build_object('code', jo.bulk_code_label(b), 'label', b.label, 'until', v_until));
  return jsonb_build_object('id', b.id, 'code', v_code, 'code_label', jo.bulk_code_label(b), 'until', v_until,
                            'link', jo.site_url() || 'susulan.html?kode=' || v_code,
                            'staff_link', jo.site_url() || 'susulan.html?akun=' || b.id);
end $$;
revoke all on function jo.susulan_create(jsonb) from public, anon, authenticated;

-- daftar lembar khusus per jenis untuk owner/superadmin (pulih.html / susulan.html)
create or replace function public.public_special_list(p_mode text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_mode not in ('pulih', 'susulan') or (jo.pulih_staff()).id is null then
    return jsonb_build_object('staff', false, 'items', '[]'::jsonb);
  end if;
  return jsonb_build_object('staff', true, 'items', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'label', b.label, 'code_label', jo.bulk_code_label(b), 'status', b.status,
      'rows', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id),
      'sent', (select count(*) from jo.bulk_rows r where r.bulk_id = b.id and r.batch_id is not null),
      'sources', coalesce(b.settings->'sources', '[]'::jsonb), 'until', b.expires_at) order by b.seq), '[]'::jsonb)
    from jo.bulk_accounts b where jo.bulk_mode(b) = p_mode and b.status = 'aktif'));
end $$;
grant execute on function public.public_special_list(text) to anon, authenticated;
