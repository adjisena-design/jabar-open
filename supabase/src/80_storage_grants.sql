-- =====================================================================
--  Penyimpanan berkas (Supabase Storage)
--   dokumen : identitas & foto atlet (privat)
--   bukti   : bukti pembayaran (privat)
--   publik  : gambar QRIS & aset yang boleh dilihat siapa saja
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('dokumen', 'dokumen', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('bukti',   'bukti',   false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('publik',  'publik',  true,  5242880, array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Dipakai oleh aturan storage: apakah pengguna sesi ini panitia dengan peran tertentu?
create or replace function public.jo_is_staff(p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from jo.staff s join jo.staff_sessions ss on ss.staff_id = s.id
     where ss.uid = auth.uid() and ss.expires_at > now() and s.active and s.role = any(p_roles))
$$;

drop policy if exists "jo: unggah ke folder sendiri" on storage.objects;
create policy "jo: unggah ke folder sendiri" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('dokumen','bukti') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "jo: baca unggahan sendiri" on storage.objects;
create policy "jo: baca unggahan sendiri" on storage.objects
  for select to authenticated
  using (bucket_id in ('dokumen','bukti') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "jo: panitia baca dokumen" on storage.objects;
create policy "jo: panitia baca dokumen" on storage.objects
  for select to authenticated
  using (bucket_id in ('dokumen','bukti') and public.jo_is_staff(array['owner','superadmin','admin']));

-- v6: owner & superadmin menghapus berkas saat membersihkan data (tercatat di Log)
drop policy if exists "jo: superadmin hapus berkas" on storage.objects;
create policy "jo: superadmin hapus berkas" on storage.objects
  for delete to authenticated
  using (bucket_id in ('dokumen','bukti') and public.jo_is_staff(array['owner','superadmin']));

drop policy if exists "jo: superadmin unggah publik" on storage.objects;
create policy "jo: superadmin unggah publik" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'publik' and public.jo_is_staff(array['owner','superadmin']));

drop policy if exists "jo: superadmin baca publik" on storage.objects;
create policy "jo: superadmin baca publik" on storage.objects
  for select to authenticated
  using (bucket_id = 'publik' and public.jo_is_staff(array['owner','superadmin']));

-- =====================================================================
--  Hak eksekusi fungsi
--   public_*  & outbox_* : pengunjung (anon) dan pengguna sesi (authenticated)
--   console_* & jo_*     : hanya pengguna sesi (authenticated); hak dicek di dalam fungsi
--   skema jo             : tertutup sepenuhnya
-- =====================================================================
revoke all on all tables in schema jo from public;
revoke all on all sequences in schema jo from public;
revoke all on all functions in schema jo from public;
do $$ begin
  execute 'revoke all on all tables in schema jo from anon, authenticated';
  execute 'revoke all on all sequences in schema jo from anon, authenticated';
  execute 'revoke all on all functions in schema jo from anon, authenticated';
exception when others then null; end $$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname like 'public\_%' or p.proname like 'console\_%'
            or p.proname like 'outbox\_%' or p.proname like 'jo\_%')
  loop
    execute format('revoke all on function %s from public', f.sig);
    begin
      execute format('revoke all on function %s from anon, authenticated', f.sig);
    exception when others then null; end;
    if f.proname like 'public\_%' or f.proname like 'outbox\_%' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    else
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- =====================================================================
--  Setup pertama: membuat kode OWNER dan secret email (sekali saja)
-- =====================================================================
create or replace function jo.bootstrap(p_owner_name text) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_code text; v_secret text; r jsonb := '{}'::jsonb;
begin
  if not exists (select 1 from jo.staff where role = 'owner') then
    v_code := jo.new_staff_code();
    insert into jo.staff (name, role, code_hash, code_hint, note)
    values (p_owner_name, 'owner', jo.sha256(jo.norm_code(v_code)), right(v_code, 4), 'Dibuat saat setup');
    r := r || jsonb_build_object('kode_owner', v_code);
  else
    r := r || jsonb_build_object('kode_owner', 'sudah dibuat sebelumnya (tidak ditampilkan lagi)');
  end if;
  if jo.setting_text('outbox_secret_hash') is null then
    v_secret := jo.rand_code(32, '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ');
    insert into jo.settings (key, value) values ('outbox_secret_hash', to_jsonb(jo.sha256(v_secret)))
    on conflict (key) do update set value = excluded.value;
    r := r || jsonb_build_object('secret_email', v_secret);
  else
    r := r || jsonb_build_object('secret_email', 'sudah dibuat sebelumnya (ganti lewat konsol bila perlu)');
  end if;
  return r;
end $$;
revoke all on function jo.bootstrap(text) from public;

notify pgrst, 'reload schema';

-- Baris terakhir: tampilkan kode owner & secret email. SIMPAN keduanya.
select jo.bootstrap('Daffa Adjisena') as hasil_setup;
