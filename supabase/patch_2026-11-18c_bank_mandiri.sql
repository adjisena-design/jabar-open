-- 18 Nov 2026 (c): rekening Inda adalah Mandiri (bukan BCA); nomor tetap. Sudah diterapkan.
update jo.settings set value = jsonb_set(value, '{bank}', '"Mandiri"') where key = 'bulk_bank';
