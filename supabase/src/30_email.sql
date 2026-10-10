-- =====================================================================
--  Email: dibuat di database, dikirim oleh Google Apps Script (Gmail)
--  yang mengambil antrean (jo.outbox) secara berkala.
-- =====================================================================

create or replace function jo.h(t text) returns text
language sql immutable set search_path = '' as $$
  select replace(replace(replace(replace(replace(coalesce(t,''),
    '&','&amp;'), '<','&lt;'), '>','&gt;'), '"','&quot;'), '''','&#39;')
$$;

create or replace function jo.tr(l text, id text, en text) returns text
language sql immutable set search_path = '' as $$
  select case when l = 'en' then en else id end
$$;

create or replace function jo.fmt_rp(n integer) returns text
language sql immutable set search_path = '' as $$
  select 'Rp' || replace(to_char(coalesce(n,0), 'FM999,999,999,999'), ',', '.')
$$;

create or replace function jo.site_url() returns text
language sql stable set search_path = '' as $$
  select rtrim(coalesce(jo.setting_text('site_url'), 'https://adjisena-design.github.io/jabar-open/'), '/') || '/'
$$;

create or replace function jo.status_link(p_code text, p_token text) returns text
language sql stable set search_path = '' as $$
  select jo.site_url() || 'status.html?k=' || p_code || '&t=' || p_token
$$;

create or replace function jo.email_layout(p_title text, p_body text, p_lang text) returns text
language sql stable set search_path = '' as $$
  select
  '<!doctype html><html><body style="margin:0;padding:0;background:#f2f4f8;font-family:Arial,Helvetica,sans-serif;color:#1a2236">'
  || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f4f8;padding:24px 0"><tr><td align="center">'
  || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:10px;overflow:hidden">'
  || '<tr><td style="background:#0b1525;padding:22px 28px;color:#ffffff">'
  || '<div style="font-size:13px;color:#a8bfe0">' || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || '</div>'
  || '<div style="font-size:21px;font-weight:bold;margin-top:4px">' || jo.h(p_title) || '</div></td></tr>'
  || '<tr><td style="height:4px;background:#ff5a3c"></td></tr>'
  || '<tr><td style="padding:26px 28px;font-size:15px;line-height:1.6">' || p_body || '</td></tr>'
  || '<tr><td style="padding:18px 28px;background:#f2f4f8;font-size:12px;color:#6b7a92;line-height:1.5">'
  || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || ' &middot; Gimnastik Indonesia (GI) Jawa Barat<br>'
  || jo.tr(p_lang, 'Pertanyaan: ', 'Questions: ') || jo.h(coalesce(jo.setting_text('contact_email'),'')) || '<br>'
  || jo.tr(p_lang, 'Email ini dikirim otomatis. Simpan email ini sebagai bukti pendaftaran.',
                   'This email was sent automatically. Keep it as your registration record.')
  || '</td></tr></table></td></tr></table></body></html>'
$$;

create or replace function jo.email_button(p_url text, p_label text) returns text
language sql immutable set search_path = '' as $$
  select '<p style="margin:22px 0"><a href="' || jo.h(p_url) || '" style="display:inline-block;background:#ff5a3c;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 22px;border-radius:8px">'
    || jo.h(p_label) || '</a></p>'
$$;

-- Ringkasan atlet & kategori untuk email
create or replace function jo.email_roster(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:8px 0 4px">'
    || coalesce(string_agg(
      '<tr><td style="padding:8px 0;border-bottom:1px solid #e4e8f0;vertical-align:top"><b>' || jo.h(a.full_name) || '</b>'
      || '<div style="font-size:13px;color:#6b7a92">' || jo.h(coalesce(a.athlete_no,'')) || '</div></td>'
      || '<td style="padding:8px 0;border-bottom:1px solid #e4e8f0;text-align:right;font-size:13px;vertical-align:top">'
      || coalesce((select string_agg(jo.h(case when p_lang = 'en' then c.name_en else c.name_id end)
                     || case when e.priangan_requested then ' + Priangan' else '' end, '<br>')
                   from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id
                   join jo.categories c on c.id = e.category_id
                   where ea.athlete_id = a.id and e.status <> 'dibatalkan'), '')
      || '</td></tr>', '' order by a.sort), '')
    || '</table>'
  from jo.athletes a where a.submission_id = p_sub
$$;

create or replace function jo.queue_email(p_sub uuid, p_kind text, p_to text, p_cc text, p_subject text, p_html text)
returns void language sql volatile set search_path = '' as $$
  insert into jo.outbox (kind, submission_id, to_email, cc, subject, html)
  values (p_kind, p_sub, p_to, nullif(p_cc,''), p_subject, p_html);
$$;

create or replace function jo.queue_registration_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; d jo.disciplines; l text; body text; link text;
begin
  select * into s from jo.submissions where id = p_sub;
  select * into d from jo.disciplines where code = s.discipline;
  l := s.lang;
  link := jo.status_link(s.code, s.token);
  body := '<p>' || jo.tr(l, 'Halo ', 'Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l, 'Pendaftaran ', 'Your ')
    || jo.h(case when l = 'en' then d.name_en else d.name_id end)
    || jo.tr(l, ' sudah kami terima. Kode pendaftaran Anda:', ' registration has been received. Your registration code:')
    || '</p><p style="font-size:22px;font-weight:bold;letter-spacing:1px;margin:6px 0 14px">' || jo.h(s.code) || '</p>'
    || jo.email_roster(s.id, l)
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:14px 0;font-size:14px">'
    || '<tr><td style="padding:3px 0">' || jo.tr(l,'Biaya pendaftaran','Entry fees') || '</td><td align="right">' || jo.fmt_rp(s.base_amount) || '</td></tr>'
    || case when s.priangan_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kategori Priangan','Priangan category') || '</td><td align="right">' || jo.fmt_rp(s.priangan_amount) || '</td></tr>' else '' end
    || case when s.unique_code > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kode unik','Unique code') || '</td><td align="right">' || jo.fmt_rp(s.unique_code) || '</td></tr>' else '' end
    || '<tr><td style="padding:10px 0 0;font-weight:bold;font-size:16px">' || jo.tr(l,'Total yang harus dibayar','Total to pay') || '</td>'
    || '<td align="right" style="padding:10px 0 0;font-weight:bold;font-size:20px;color:#ff3131">' || jo.fmt_rp(s.total_amount) || '</td></tr></table>';
  if s.payment_method = 'qris' then
    body := body || '<p>' || jo.tr(l,
      'Bayar lewat QRIS Jabar Open 2026 yang tampil di halaman status, lalu ketik nominal <b>tepat ',
      'Pay with the Jabar Open 2026 QRIS shown on the status page and type the <b>exact amount ')
      || jo.fmt_rp(s.total_amount) || '</b>. '
      || jo.tr(l,'Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Setelah membayar, unggah bukti pembayaran di halaman status.',
                 'The last three digits are a unique code that matches your payment to this registration. After paying, upload the payment proof on the status page.')
      || '</p>';
  else
    body := body || '<p>' || jo.tr(l,
      'Pendaftaran atlet internasional dibayar terpisah. Panitia akan menghubungi Anda melalui email ini untuk cara pembayaran.',
      'International registrations are paid separately. The committee will contact you at this email with payment instructions.')
      || '</p>';
  end if;
  body := body || jo.email_button(link, jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#6b7a92">' || jo.tr(l,'Batas pembayaran: ','Payment deadline: ')
    || jo.h(coalesce(jo.setting_text('payment_deadline_label'), '12 November 2026')) || '<br>'
    || jo.tr(l,'Simpan tautan di atas. Siapa pun yang memegang tautan ini dapat melihat data pendaftaran Anda.',
               'Keep the link above private. Anyone with it can see your registration details.')
    || '</p>';
  perform jo.queue_email(s.id, 'pendaftaran', s.contact_email, null,
    jo.tr(l,'Pendaftaran diterima — ','Registration received — ') || s.code,
    jo.email_layout(jo.tr(l,'Pendaftaran diterima','Registration received'), body, l));
end $$;

create or replace function jo.queue_paid_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text; cc text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  if coalesce(jo.setting_bool('email_guardians'), true) then
    select string_agg(distinct lower(a.guardian_email), ',') into cc
      from jo.athletes a where a.submission_id = s.id and a.guardian_email is not null
       and lower(a.guardian_email) <> lower(s.contact_email);
  end if;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Pembayaran untuk pendaftaran ','Payment for registration ') || '<b>' || jo.h(s.code) || '</b> '
    || jo.tr(l,'sudah kami verifikasi. Status: <b style="color:#1b8a4b">LUNAS</b>.','has been verified. Status: <b style="color:#1b8a4b">PAID</b>.') || '</p>'
    || jo.email_roster(s.id, l)
    || '<p>' || jo.tr(l,'E-ticket (PDF) untuk setiap atlet dapat diunduh di halaman status. Tidak ada registrasi ulang: cukup datang sesuai jadwal yang diumumkan di Instagram dan situs Jabar Open 2026.',
                      'Each athlete''s e-ticket (PDF) can be downloaded from the status page. There is no on-site check-in: just come at the schedule announced on Instagram and the Jabar Open 2026 website.') || '</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Unduh e-ticket','Download e-tickets'));
  perform jo.queue_email(s.id, 'lunas', s.contact_email, cc,
    jo.tr(l,'Pembayaran lunas — e-ticket ','Payment confirmed — e-tickets ') || s.code,
    jo.email_layout(jo.tr(l,'Pembayaran lunas','Payment confirmed'), body, l));
end $$;

create or replace function jo.queue_fix_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Bukti pembayaran untuk ','The payment proof for ') || '<b>' || jo.h(s.code) || '</b> '
    || jo.tr(l,'belum bisa kami verifikasi. Catatan panitia:','could not be verified yet. Committee note:') || '</p>'
    || '<p style="background:#fff4ee;border-left:4px solid #ff914d;padding:10px 14px">' || jo.h(coalesce(s.verify_note,'-')) || '</p>'
    || '<p>' || jo.tr(l,'Nominal yang harus dibayar: ','Amount due: ') || '<b>' || jo.fmt_rp(s.total_amount) || '</b>. '
    || jo.tr(l,'Silakan unggah ulang bukti yang benar di halaman status.','Please upload the correct proof on the status page.') || '</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Unggah ulang bukti','Upload proof again'));
  perform jo.queue_email(s.id, 'perbaikan', s.contact_email, null,
    jo.tr(l,'Bukti pembayaran perlu diperbaiki — ','Payment proof needs attention — ') || s.code,
    jo.email_layout(jo.tr(l,'Bukti pembayaran perlu diperbaiki','Payment proof needs attention'), body, l));
end $$;

create or replace function jo.queue_link_email(p_sub uuid) returns void
language plpgsql volatile set search_path = '' as $$
declare s jo.submissions; l text; body text;
begin
  select * into s from jo.submissions where id = p_sub;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>'
    || '<p>' || jo.tr(l,'Berikut tautan halaman status untuk pendaftaran ','Here is the status page link for registration ')
    || '<b>' || jo.h(s.code) || '</b>.</p>'
    || jo.email_button(jo.status_link(s.code, s.token), jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#6b7a92">' || jo.tr(l,'Jika Anda tidak meminta email ini, abaikan saja.','If you did not request this email, you can ignore it.') || '</p>';
  perform jo.queue_email(s.id, 'tautan', s.contact_email, null,
    jo.tr(l,'Tautan status pendaftaran — ','Registration status link — ') || s.code,
    jo.email_layout(jo.tr(l,'Tautan halaman status','Status page link'), body, l));
end $$;
