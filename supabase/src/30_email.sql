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
  '<!doctype html><html><body style="margin:0;padding:0;background:#f4f6fa;font-family:Arial,Helvetica,sans-serif;color:#34476a">'
  || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6fa;padding:24px 0"><tr><td align="center">'
  || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:10px;overflow:hidden">'
  || '<tr><td style="background:#13284a;padding:22px 28px;color:#ffffff">'
  || '<div style="font-size:13px;color:#e4c87d">' || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || '</div>'
  || '<div style="font-size:21px;font-weight:bold;margin-top:4px">' || jo.h(p_title) || '</div></td></tr>'
  || '<tr><td style="height:4px;background:#e4c87d"></td></tr>'
  || '<tr><td style="padding:26px 28px;font-size:15px;line-height:1.6">' || p_body || '</td></tr>'
  || '<tr><td style="padding:18px 28px;background:#f4f6fa;font-size:12px;color:#5b6b88;line-height:1.5">'
  || jo.h(coalesce(jo.setting_text('event_name'),'Jabar Open 2026')) || ' &middot; Gimnastik Indonesia (GI) Jawa Barat<br>'
  || jo.tr(p_lang, 'Pertanyaan: ', 'Questions: ') || jo.h(coalesce(jo.setting_text('contact_email'),'')) || '<br>'
  || case when coalesce(jo.setting_text('pm_email'),'') <> '' then
       jo.tr(p_lang, 'Permintaan khusus atau belum ada balasan: Project Manager, ', 'Special requests or no reply yet: Project Manager, ')
       || jo.h(jo.setting_text('pm_email')) || '<br>' else '' end
  || jo.tr(p_lang, 'Email ini dikirim otomatis. Simpan email ini sebagai bukti pendaftaran.',
                   'This email was sent automatically. Keep it as your registration record.')
  || '</td></tr></table></td></tr></table></body></html>'
$$;

create or replace function jo.email_button(p_url text, p_label text) returns text
language sql immutable set search_path = '' as $$
  select '<p style="margin:22px 0"><a href="' || jo.h(p_url) || '" style="display:inline-block;background:#2c4c7b;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 22px;border-radius:999px">'
    || jo.h(p_label) || '</a></p>'
$$;

-- Tautan unduh AIC langsung (halaman status mengunduh otomatis; hanya berfungsi bila lunas)
create or replace function jo.aic_link(p_code text, p_token text, p_which text) returns text
language sql stable set search_path = '' as $$
  select jo.status_link(p_code, p_token) || '&aic=' || p_which
$$;

create or replace function jo.email_aic_links(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:8px 0 4px">'
    || coalesce(string_agg(
      '<tr><td style="padding:8px 0;border-bottom:1px solid #e2e8f1"><b>' || jo.h(a.full_name) || '</b>'
      || '<div style="font-size:13px;color:#5b6b88">' || jo.h(coalesce(a.athlete_no,'')) || '</div></td>'
      || '<td style="padding:8px 0;border-bottom:1px solid #e2e8f1;text-align:right">'
      || '<a href="' || jo.h(jo.aic_link(s.code, s.token, a.id::text)) || '" style="color:#2c4c7b;font-weight:bold">'
      || jo.tr(p_lang,'Unduh AIC','Download AIC') || '</a></td></tr>', '' order by a.sort), '')
    || '</table>'
  from jo.submissions s join jo.athletes a on a.submission_id = s.id
  where s.id = p_sub and a.ticket_code is not null
$$;

-- Ringkasan atlet & kategori untuk email
create or replace function jo.email_roster(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:8px 0 4px">'
    || coalesce(string_agg(
      '<tr><td style="padding:8px 0;border-bottom:1px solid #e2e8f1;vertical-align:top"><b>' || jo.h(a.full_name) || '</b>'
      || '<div style="font-size:13px;color:#5b6b88">' || jo.h(coalesce(a.athlete_no,'')) || '</div>'
      || case when a.nationality = 'WNI' and a.bpjs_path is null then '<div style="font-size:12px;color:#9a6200">'
           || jo.tr(p_lang, 'BPJS Ketenagakerjaan belum diunggah: bawa ke meja panitia di venue sebelum bertanding.',
                            'BPJS Ketenagakerjaan not uploaded: bring it to the committee desk at the venue before competing.') || '</div>' else '' end
      || '</td>'
      || '<td style="padding:8px 0;border-bottom:1px solid #e2e8f1;text-align:right;font-size:13px;vertical-align:top">'
      || coalesce((select string_agg(jo.h(case when p_lang = 'en' then c.name_en else c.name_id end), '<br>')
                   from jo.entry_athletes ea join jo.entries e on e.id = ea.entry_id
                   join jo.categories c on c.id = e.category_id
                   where ea.athlete_id = a.id and e.status <> 'dibatalkan'), '')
      || '</td></tr>', '' order by a.sort), '')
    || '</table>'
  from jo.athletes a where a.submission_id = p_sub
$$;

-- Ringkasan tim beregu untuk email
create or replace function jo.email_team(p_sub uuid, p_lang text) returns text
language sql stable set search_path = '' as $$
  select '<p style="margin:10px 0 2px"><b>' || jo.h(t.name) || '</b> &middot; '
    || jo.h(case when p_lang = 'en' then d.name_en else d.name_id end) || ' ' || jo.h(t.level) || '</p>'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:4px 0">'
    || coalesce((select string_agg(
         '<tr><td style="padding:7px 0;border-bottom:1px solid #e2e8f1"><b>' || jo.h(a.full_name) || '</b>'
         || '<div style="font-size:13px;color:#5b6b88">' || jo.h(coalesce(a.athlete_no,'')) || '</div></td>'
         || '<td style="padding:7px 0;border-bottom:1px solid #e2e8f1;text-align:right;font-size:13px">'
         || case when m.team_only then jo.tr(p_lang,'Khusus beregu','Team only') else jo.tr(p_lang,'Juga perorangan','Also individual') end
         || '<br><span style="color:#5b6b88">' || jo.h(case when p_lang = 'en' then c.name_en else c.name_id end) || '</span></td></tr>', '' order by m.sort)
       from jo.team_members m join jo.athletes a on a.id = m.athlete_id
       join jo.entries e on e.id = m.entry_id join jo.categories c on c.id = e.category_id
       where m.team_id = t.id), '')
    || '</table>'
  from jo.teams t join jo.disciplines d on d.code = t.discipline
  where t.submission_id = p_sub
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
    || case when s.registrant_type = 'beregu' then coalesce(jo.email_team(s.id, l), '') else jo.email_roster(s.id, l) end
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:14px 0;font-size:14px">'
    || '<tr><td style="padding:3px 0">' || case when s.registrant_type = 'beregu' then jo.tr(l,'Biaya beregu (per tim)','Team fee (per team)') else jo.tr(l,'Biaya pendaftaran','Entry fees') end || '</td><td align="right">' || jo.fmt_rp(s.base_amount) || '</td></tr>'
    || case when s.priangan_amount > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kategori Priangan','Priangan category') || '</td><td align="right">' || jo.fmt_rp(s.priangan_amount) || '</td></tr>' else '' end
    || case when s.unique_code > 0 then '<tr><td style="padding:3px 0">' || jo.tr(l,'Kode unik','Unique code') || '</td><td align="right">' || jo.fmt_rp(s.unique_code) || '</td></tr>' else '' end
    || '<tr><td style="padding:10px 0 0;font-weight:bold;font-size:16px">' || jo.tr(l,'Total yang harus dibayar','Total to pay') || '</td>'
    || '<td align="right" style="padding:10px 0 0;font-weight:bold;font-size:20px;color:#13284a">' || jo.fmt_rp(s.total_amount) || '</td></tr></table>';
  if s.payment_method = 'qris' then
    body := body || '<p>' || jo.tr(l,
      'Bayar lewat QRIS Jabar Open 2026 yang tampil di halaman status, lalu ketik nominal <b>tepat ',
      'Pay with the Jabar Open 2026 QRIS shown on the status page and type the <b>exact amount ')
      || jo.fmt_rp(s.total_amount) || '</b>. '
      || jo.tr(l,'Tiga digit terakhir adalah kode unik yang mencocokkan pembayaran Anda dengan pendaftaran ini. Setelah membayar, unggah bukti pembayaran di halaman status.',
                 'The last three digits are a unique code that matches your payment to this registration. After paying, upload the payment proof on the status page.')
      || '</p><p style="background:#fdf3dc;border-left:4px solid #e4c87d;padding:10px 14px"><b>'
      || jo.tr(l,'Penting: unggah bukti bayar paling lambat 15 menit setelah mendaftar','Important: upload the payment proof within 15 minutes of registering')
      || '</b> (' || to_char(s.created_at at time zone 'Asia/Jakarta' + interval '15 minutes', 'HH24:MI') || ' WIB). '
      || jo.tr(l,'Bila tidak, pendaftaran ini dihapus otomatis dan Anda perlu mendaftar ulang.',
                 'Otherwise this registration is deleted automatically and you will need to register again.') || '</p>';
  else
    body := body || '<p>' || jo.tr(l,
      'Pendaftaran atlet internasional dibayar terpisah. Panitia akan menghubungi Anda melalui email ini untuk cara pembayaran.',
      'International registrations are paid separately. The committee will contact you at this email with payment instructions.')
      || '</p>';
  end if;
  body := body || jo.email_button(link, jo.tr(l,'Buka halaman status','Open status page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Batas pembayaran: ','Payment deadline: ')
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
    || case when s.registrant_type = 'beregu' then coalesce(jo.email_team(s.id, l), '') else jo.email_roster(s.id, l) end
    || '<p>' || jo.tr(l,'Athlete Identification Card (AIC) Jabar Open 2026 sudah bisa diunduh. Tekan tautan di bawah; AIC terunduh otomatis sebagai PDF. AIC wajib ditunjukkan secara digital (dari ponsel, tanpa dicetak) di venue. Tidak ada registrasi ulang: cukup datang sesuai jadwal yang diumumkan di Instagram dan situs Jabar Open 2026.',
                      'The Athlete Identification Cards (AIC) Jabar Open 2026 are ready. Tap a link below and the AIC downloads as a PDF. Show it digitally (on a phone, no printing) at the venue. There is no on-site check-in: just come at the schedule announced on Instagram and the Jabar Open 2026 website.') || '</p>'
    || jo.email_aic_links(s.id, l)
    || case when (select count(*) from jo.athletes a where a.submission_id = s.id and a.ticket_code is not null) > 1
         then jo.email_button(jo.aic_link(s.code, s.token, 'all'), jo.tr(l,'Unduh semua AIC (1 PDF)','Download all AICs (1 PDF)'))
         else '' end
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Tautan ini juga bisa dibuka lagi kapan saja. Halaman status: ','You can open these links again at any time. Status page: ')
    || '<a href="' || jo.h(jo.status_link(s.code, s.token)) || '" style="color:#2c4c7b">' || jo.tr(l,'buka','open') || '</a>.</p>';
  perform jo.queue_email(s.id, 'lunas', s.contact_email, cc,
    jo.tr(l,'Pembayaran lunas — Athlete Identification Card (AIC) ','Payment confirmed — Athlete Identification Cards (AIC) ') || s.code,
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
    || '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(coalesce(s.verify_note,'-')) || '</p>'
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
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Jika Anda tidak meminta email ini, abaikan saja.','If you did not request this email, you can ignore it.') || '</p>';
  perform jo.queue_email(s.id, 'tautan', s.contact_email, null,
    jo.tr(l,'Tautan status pendaftaran — ','Registration status link — ') || s.code,
    jo.email_layout(jo.tr(l,'Tautan halaman status','Status page link'), body, l));
end $$;

-- ---------------------------------------------------------------------
-- Musik Ritmik: konfirmasi perubahan tautan & permintaan perbaikan berbagi
-- ---------------------------------------------------------------------
create or replace function jo.music_link() returns text
language sql stable set search_path = '' as $$
  select jo.site_url() || 'musik.html'
$$;

create or replace function jo.queue_music_email(p_entry uuid, p_kind text) returns void
language plpgsql volatile set search_path = '' as $$
declare e jo.entries; s jo.submissions; a jo.athletes; c jo.categories; l text; body text; subj text; title text;
begin
  select * into e from jo.entries where id = p_entry;
  select * into s from jo.submissions where id = e.submission_id;
  select a2.* into a from jo.entry_athletes ea join jo.athletes a2 on a2.id = ea.athlete_id where ea.entry_id = e.id limit 1;
  select * into c from jo.categories where id = e.category_id;
  l := s.lang;
  body := '<p>' || jo.tr(l,'Halo ','Hello ') || jo.h(s.contact_name) || ',</p>';
  if p_kind = 'musik_perbaiki' then
    title := jo.tr(l,'Tautan musik perlu diperbaiki','Music link needs fixing');
    subj := title || ' — ' || a.full_name;
    body := body || '<p>' || jo.tr(l,'Tautan musik untuk ','The music link for ') || '<b>' || jo.h(a.full_name) || '</b> ('
      || jo.h(case when l = 'en' then c.name_en else c.name_id end) || ') '
      || jo.tr(l,'tidak bisa dibuka panitia. Catatan:','could not be opened by the committee. Note:') || '</p>'
      || '<p style="background:#fbf4e1;border-left:4px solid #e4c87d;padding:10px 14px">' || jo.h(coalesce(e.music_note,'-')) || '</p>'
      || '<p>' || jo.tr(l,'Pastikan folder Google Drive dibagikan sebagai <b>"Siapa saja yang memiliki link"</b>, lalu kirim ulang tautannya. Perbaikan ini <b>tidak</b> memakai kesempatan ganti musik.',
                       'Make sure the Google Drive folder is shared as <b>"Anyone with the link"</b>, then submit the link again. Fixing this does <b>not</b> use up the music change.') || '</p>';
  else
    title := jo.tr(l,'Tautan musik diterima','Music link received');
    subj := title || ' — ' || a.full_name;
    body := body || '<p>' || jo.tr(l,'Tautan musik untuk ','The music link for ') || '<b>' || jo.h(a.full_name) || '</b> ('
      || jo.h(case when l = 'en' then c.name_en else c.name_id end) || ') '
      || jo.tr(l,'sudah tersimpan:','has been saved:') || '</p>'
      || '<table role="presentation" cellpadding="0" cellspacing="0" style="font-size:14px;margin:6px 0 12px">'
      || coalesce((select string_agg('<tr><td style="padding:3px 12px 3px 0;white-space:nowrap"><b>' || jo.h(jo.apparatus_label('RG', x)) || '</b></td>'
           || '<td style="padding:3px 0;word-break:break-all"><a href="' || jo.h(e.music->>x) || '">' || jo.h(e.music->>x) || '</a></td></tr>', '' order by ord)
           from unnest(c.apparatus) with ordinality as u(x, ord) where coalesce(e.music->>x,'') <> ''), '') || '</table>'
      || '<p>' || case when e.music_changes >= 1
           then jo.tr(l,'Kesempatan ganti musik untuk atlet ini sudah dipakai.','The music change for this athlete has now been used.')
           else jo.tr(l,'Musik dapat diganti satu kali sampai start list kategori ini terbit.','The music can be changed once until this category''s start list is published.') end
      || ' ' || jo.tr(l,'Panitia akan memeriksa bahwa tautan bisa dibuka.','The committee will check that the link opens.') || '</p>';
  end if;
  body := body || jo.email_button(jo.music_link(), jo.tr(l,'Buka halaman musik Ritmik','Open the Rhythmic music page'))
    || '<p style="font-size:13px;color:#5b6b88">' || jo.tr(l,'Kode pendaftaran: ','Registration code: ') || jo.h(s.code) || '</p>';
  perform jo.queue_email(s.id, p_kind, s.contact_email, null, subj, jo.email_layout(title, body, l));
end $$;
