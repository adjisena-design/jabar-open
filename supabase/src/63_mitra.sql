-- =====================================================================
--  Calon mitra / sponsor (v11, 21/10/2026)
--  Formulir singkat di beranda (#mitra): nama, perusahaan, WhatsApp,
--  kebutuhan. Panitia melihat dan menindaklanjuti di Konsol > Calon mitra
--  (owner, superadmin, bendahara).
-- =====================================================================
create table if not exists jo.partner_leads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  company     text not null,
  phone       text not null,
  inquiry     text,
  lang        text not null default 'id',
  status      text not null default 'baru' check (status in ('baru','dihubungi','deal','tidak_lanjut')),
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references jo.staff(id)
);
create index if not exists partner_leads_created on jo.partner_leads (created_at desc);
alter table jo.partner_leads enable row level security;

-- dipanggil dari beranda tanpa sesi (kunci anon); dibatasi per nomor dan total per jam
create or replace function public.public_partner_lead(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_phone text; v_id uuid;
begin
  -- kolom jebakan bot: bila terisi, pura-pura berhasil
  if length(coalesce(p->>'website', '')) > 0 then return jsonb_build_object('ok', true); end if;
  if length(btrim(coalesce(p->>'name', ''))) < 2 then raise exception 'Isi nama Anda.' using hint = 'ERR_NAME'; end if;
  if length(btrim(coalesce(p->>'company', ''))) < 2 then raise exception 'Isi nama perusahaan atau lembaga.' using hint = 'ERR_COMPANY'; end if;
  v_phone := regexp_replace(coalesce(p->>'phone', ''), '[^0-9]', '', 'g');
  if v_phone like '62%' then v_phone := '0' || substr(v_phone, 3); end if;
  if length(v_phone) < 9 or length(v_phone) > 15 then raise exception 'Nomor WhatsApp tidak valid.' using hint = 'ERR_PHONE'; end if;
  if length(coalesce(p->>'inquiry', '')) > 2000 then raise exception 'Pesan terlalu panjang (maks. 2000 karakter).' using hint = 'ERR_LONG'; end if;
  if (select count(*) from jo.partner_leads where phone = v_phone and created_at > now() - interval '1 day') >= 3 then
    raise exception 'Pesan dari nomor ini sudah kami terima. Tim kami akan menghubungi Anda.' using hint = 'ERR_RATE';
  end if;
  if (select count(*) from jo.partner_leads where created_at > now() - interval '1 hour') >= 40 then
    raise exception 'Sedang banyak pesan masuk. Coba lagi beberapa saat lagi atau hubungi kami lewat WhatsApp.' using hint = 'ERR_RATE';
  end if;
  insert into jo.partner_leads (name, company, phone, inquiry, lang)
  values (left(btrim(p->>'name'), 120), left(btrim(p->>'company'), 160), v_phone,
          nullif(left(btrim(coalesce(p->>'inquiry', '')), 2000), ''), case when p->>'lang' = 'en' then 'en' else 'id' end)
  returning id into v_id;
  perform jo.log(null, 'calon_mitra_masuk', 'partner_lead', v_id::text, jsonb_build_object('perusahaan', left(btrim(p->>'company'), 160)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.console_partner_leads() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','bendahara']);
  return jsonb_build_object(
    'can_edit', true,
    'counts', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from jo.partner_leads group by status) x),
    'items', (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('updated_by_name', (select name from jo.staff where id = l.updated_by))
               order by l.created_at desc), '[]'::jsonb) from jo.partner_leads l));
end $$;

create or replace function public.console_partner_lead_update(p_id uuid, p_status text, p_note text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare st jo.staff;
begin
  st := jo.require_staff(array['owner','superadmin','bendahara']);
  if p_status not in ('baru','dihubungi','deal','tidak_lanjut') then raise exception 'Status tidak dikenal.'; end if;
  update jo.partner_leads set status = p_status, note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now(), updated_by = st.id
   where id = p_id;
  if not found then raise exception 'Data tidak ditemukan.'; end if;
  perform jo.log(st.id, 'calon_mitra_status', 'partner_lead', p_id::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('ok', true);
end $$;
