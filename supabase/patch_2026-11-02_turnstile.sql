-- =====================================================================
--  Jabar Open 2026 — Turnstile (Cloudflare) untuk pendaftaran
--  Dipasang 2 Nov 2026, dicatat ke repo 4 Nov 2026 (salinan persis dari database live).
--
--  WAJIB dijalankan ulang SETIAP KALI setelah supabase/setup.sql dijalankan:
--  setup.sql memberi anon/authenticated hak execute ke semua fungsi public_*,
--  termasuk public_register, sehingga Turnstile bisa dilewati bila patch ini tidak diulang.
--
--  Pasangan Edge Function: supabase/functions/guarded-submit/index.ts
--  (secret TURNSTILE_SECRET_KEY di Supabase → Edge Functions → Secrets).
--  Kill switch: pengaturan 'turnstile_enabled' (false = lewati verifikasi Turnstile).
-- =====================================================================

create or replace function jo.assume_uid(p_uid uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if p_uid is null then
    raise exception 'Sesi browser belum siap. Muat ulang halaman.' using hint = 'ERR_SESSION';
  end if;
  if not exists (select 1 from auth.users where id = p_uid) then
    raise exception 'Sesi browser tidak valid.' using hint = 'ERR_SESSION';
  end if;
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $function$;

create or replace function public.register_verified(p jsonb, p_uid uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform jo.assume_uid(p_uid);
  return public.public_register(p);
end $function$;

create or replace function public.resend_link_verified(p_code text, p_email text, p_uid uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform jo.assume_uid(p_uid);
  return public.public_resend_link(p_code, p_email);
end $function$;

create or replace function public.turnstile_enabled()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(jo.setting_bool('turnstile_enabled'), true)
$function$;

-- Hak akses: hanya Edge Function (service_role) yang boleh memanggil jalur pendaftaran.
revoke all on function jo.assume_uid(uuid) from public, anon, authenticated, service_role;
revoke all on function public.public_register(jsonb) from public, anon, authenticated;
revoke all on function public.register_verified(jsonb, uuid) from public, anon, authenticated;
revoke all on function public.resend_link_verified(text, text, uuid) from public, anon, authenticated;
revoke all on function public.turnstile_enabled() from public, anon, authenticated;
grant execute on function public.public_register(jsonb) to service_role;
grant execute on function public.register_verified(jsonb, uuid) to service_role;
grant execute on function public.resend_link_verified(text, text, uuid) to service_role;
grant execute on function public.turnstile_enabled() to service_role;
