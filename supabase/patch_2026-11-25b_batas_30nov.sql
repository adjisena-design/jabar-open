-- 25/11/2026: batas pendaftaran diperpanjang dari 27 November ke 30 November 2026 pukul 23.59 WIB.
-- Kode pendaftaran massal tidak diubah di sini: masa berlakunya diatur per klub di konsol.

update jo.settings set value = '"2026-11-30T23:59:59+07:00"'::jsonb, updated_at = now()
 where key = 'registration_deadline';
update jo.settings set value = '"30 November 2026"'::jsonb, updated_at = now()
 where key = 'payment_deadline_label';

-- FAQ
update jo.faq_items set
  a_id = replace(a_id, '27 November 2026', '30 November 2026'),
  a_en = replace(a_en, '27 November 2026', '30 November 2026'),
  updated_at = now()
 where a_id like '%27 November 2026%' or a_en like '%27 November 2026%';

-- Laporan konsol: batas dibaca dari pengaturan, tidak lagi ditulis mati.
do $$
declare d text := pg_get_functiondef('public.console_report'::regproc);
begin
  if position('''deadline'', ''2026-11-27T23:59:00+07:00''' in d) > 0 then
    execute replace(d, '''deadline'', ''2026-11-27T23:59:00+07:00''',
      '''deadline'', coalesce(jo.setting_text(''registration_deadline''), ''2026-11-30T23:59:59+07:00'')');
  end if;
end $$;

-- Gantt
update jo.pm_tasks set start_date = '2026-11-30', end_date = '2026-11-30' where task = 'Pendaftaran atlet ditutup';
update jo.pm_tasks set end_date = '2026-11-30' where task = 'Kampanye pendaftaran (IG, WA klub, pengkab/pengkot)';
update jo.pm_tasks set note = 'Tambahan ukuran setelah pendaftaran ditutup 30 Nov.' where note = 'Tambahan ukuran setelah pendaftaran ditutup 27 Nov.';
