-- Patch 15 Nov 2026: teks berjalan beranda + buka/tutup pendaftaran terjadwal
-- Status buka/tutup pendaftaran yang berlaku sekarang.
-- Sakelar manual (setting registration_open) adalah dasar. Jadwal reg_close_at / reg_reopen_at
-- yang sudah lewat dan lebih baru dari perubahan sakelar terakhir menimpa sakelar (yang terakhir menang).
-- Batas pendaftaran (registration_deadline) dicek terpisah oleh pemanggil.
create or replace function jo.reg_is_open() returns boolean
language sql stable set search_path = '' as $$
  with s as (
    select coalesce((select (value #>> '{}')::boolean from jo.settings where key = 'registration_open'), false) as man,
           coalesce((select updated_at from jo.settings where key = 'registration_open'), '-infinity'::timestamptz) as at,
           (select nullif(value #>> '{}', '')::timestamptz from jo.settings where key = 'reg_close_at') as c,
           (select nullif(value #>> '{}', '')::timestamptz from jo.settings where key = 'reg_reopen_at') as o)
  select coalesce((select e.v from (values (s.c, false), (s.o, true)) e(t, v)
                    where e.t is not null and e.t <= now() and e.t > s.at order by e.t desc limit 1), s.man)
    from s
$$;

-- Waktu pendaftaran dibuka kembali (hanya bila sekarang tertutup dan jadwal buka masih di depan).
create or replace function jo.reg_reopen_at() returns timestamptz
language sql stable set search_path = '' as $$
  select case when not jo.reg_is_open() and o > now() then o end
    from (select (select nullif(value #>> '{}', '')::timestamptz from jo.settings where key = 'reg_reopen_at') as o) x
$$;

do $do$
declare f regprocedure; def text;
begin
  foreach f in array array['public.public_config()','public.public_register(jsonb)','public.public_bulk_submit(text,text,integer[],jsonb,text)','public.public_bulk_info()']::regprocedure[] loop
    def := pg_get_functiondef(f);
    if position($q$coalesce(jo.setting_bool('registration_open'), false)$q$ in def) = 0 then raise exception 'pola tidak ditemukan di %', f; end if;
    def := replace(def, $q$coalesce(jo.setting_bool('registration_open'), false)$q$, 'jo.reg_is_open()');
    if f = 'public.public_config()'::regprocedure then
      if position($q$'deadline', jo.setting_text('registration_deadline'),$q$ in def) = 0 then raise exception 'pola deadline tidak ditemukan'; end if;
      def := replace(def, $q$'deadline', jo.setting_text('registration_deadline'),$q$, $q$'deadline', jo.setting_text('registration_deadline'),
      'reopen_at', jo.reg_reopen_at(),$q$);
    end if;
    execute def;
  end loop;
end $do$;
-- ---------------------------------------------------------------------
-- Teks berjalan di beranda + buka/tutup pendaftaran (manual & terjadwal)
-- Hanya owner & superadmin. Pembayaran, unggah bukti, status, musik tetap berjalan saat tutup.
-- ---------------------------------------------------------------------

-- Publik & ringan: dipanggil beranda (teks berjalan) tanpa memuat konfigurasi lengkap.
create or replace function public.public_site_notice() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ticker', (select case when coalesce((t->>'enabled')::boolean, false) and coalesce(btrim(t->>'text'), '') <> ''
                           then jsonb_build_object('text', btrim(t->>'text'), 'link', nullif(btrim(coalesce(t->>'link', '')), '')) end
                 from (select value as t from jo.settings where key = 'ticker') x),
    'registration', jsonb_build_object(
      'open', jo.reg_is_open() and now() <= coalesce((jo.setting_text('registration_deadline'))::timestamptz, now()),
      'reopen_at', jo.reg_reopen_at(),
      'deadline', jo.setting_text('registration_deadline')))
$$;

create or replace function public.console_reg_control() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; dl timestamptz;
begin
  st := jo.require_staff(array['owner','superadmin']);
  dl := (jo.setting_text('registration_deadline'))::timestamptz;
  return jsonb_build_object(
    'manual_open', coalesce(jo.setting_bool('registration_open'), false),
    'manual_at', (select updated_at from jo.settings where key = 'registration_open'),
    'manual_by', (select s.name from jo.settings x join jo.staff s on s.id = x.updated_by where x.key = 'registration_open'),
    'close_at', nullif(jo.setting_text('reg_close_at'), ''),
    'reopen_at', nullif(jo.setting_text('reg_reopen_at'), ''),
    'schedule_open', jo.reg_is_open(),
    'deadline', dl,
    'past_deadline', dl is not null and now() > dl,
    'open', jo.reg_is_open() and (dl is null or now() <= dl),
    'now', now(),
    'ticker', coalesce((select value from jo.settings where key = 'ticker'), '{}'::jsonb),
    'ticker_at', (select updated_at from jo.settings where key = 'ticker'),
    'ticker_by', (select s.name from jo.settings x join jo.staff s on s.id = x.updated_by where x.key = 'ticker'));
end $$;

-- p: { open?: bool, close_at?: text|null, reopen_at?: text|null, ticker?: {enabled, text, link} }
create or replace function public.console_reg_control_save(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff; v_txt text; v_link text; v_t timestamptz; k text;
begin
  st := jo.require_staff(array['owner','superadmin']);
  p := coalesce(p, '{}'::jsonb);

  if p ? 'open' then
    insert into jo.settings (key, value, updated_at, updated_by) values ('registration_open', to_jsonb((p->>'open')::boolean), now(), st.id)
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    perform jo.log(st.id, case when (p->>'open')::boolean then 'pendaftaran_dibuka' else 'pendaftaran_ditutup' end, 'setting', 'registration_open', '{}'::jsonb);
  end if;

  foreach k in array array['close_at','reopen_at'] loop
    if p ? k then
      v_t := nullif(btrim(coalesce(p->>k, '')), '')::timestamptz;
      if v_t is not null and v_t <= now() then
        raise exception 'Waktu jadwal harus di masa depan.' using hint = 'ERR_INPUT';
      end if;
      insert into jo.settings (key, value, updated_at, updated_by)
      values ('reg_' || k, case when v_t is null then to_jsonb(''::text) else to_jsonb(to_char(v_t at time zone 'Asia/Jakarta', 'YYYY-MM-DD"T"HH24:MI:SS') || '+07:00') end, now(), st.id)
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
      perform jo.log(st.id, 'jadwal_pendaftaran_diubah', 'setting', 'reg_' || k, jsonb_build_object('value', v_t));
    end if;
  end loop;

  if p ? 'ticker' then
    v_txt := btrim(regexp_replace(coalesce(p->'ticker'->>'text', ''), '\s+', ' ', 'g'));
    v_link := nullif(btrim(coalesce(p->'ticker'->>'link', '')), '');
    if length(v_txt) > 300 then raise exception 'Teks berjalan maksimal 300 karakter.' using hint = 'ERR_INPUT'; end if;
    if v_link is not null and v_link !~* '^(https://|[a-z0-9_-]+\.html|#)' then
      raise exception 'Tautan harus diawali https:// atau nama halaman situs (mis. daftar.html).' using hint = 'ERR_INPUT';
    end if;
    if coalesce((p->'ticker'->>'enabled')::boolean, false) and v_txt = '' then
      raise exception 'Isi teks sebelum menayangkan.' using hint = 'ERR_INPUT';
    end if;
    insert into jo.settings (key, value, updated_at, updated_by)
    values ('ticker', jsonb_build_object('enabled', coalesce((p->'ticker'->>'enabled')::boolean, false), 'text', v_txt, 'link', v_link), now(), st.id)
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = st.id;
    perform jo.log(st.id, 'teks_berjalan_diubah', 'setting', 'ticker', jsonb_build_object('enabled', (p->'ticker'->>'enabled')::boolean, 'text', v_txt));
  end if;

  return public.console_reg_control();
end $$;

revoke all on function public.public_site_notice() from public;
grant execute on function public.public_site_notice() to anon, authenticated;
revoke all on function public.console_reg_control() from public, anon;
grant execute on function public.console_reg_control() to authenticated;
revoke all on function public.console_reg_control_save(jsonb) from public, anon;
grant execute on function public.console_reg_control_save(jsonb) to authenticated;
