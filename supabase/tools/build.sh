#!/bin/sh
# Menggabungkan supabase/src/*.sql menjadi satu file setup.sql untuk ditempel di SQL Editor.
cd "$(dirname "$0")/.."
python3 tools/gen_seed.py >/dev/null
cat src/10_tables.sql src/20_helpers.sql src/30_email.sql src/40_public.sql src/50_console.sql src/70_seed.sql src/80_storage_grants.sql > setup.sql
echo "setup.sql: $(wc -l < setup.sql) baris"
