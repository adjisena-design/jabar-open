# Menghasilkan 70_seed.sql: disiplin, kategori (dari Undangan 06/10/2026), pengaturan awal.
import json
Y = 2026
def yrs(age_min=None, age_max=None):
    # usia kompetisi = 2026 - tahun lahir. age_min..age_max -> tahun lahir
    bmin = Y - age_max if age_max is not None else None   # kelahiran paling tua
    bmax = Y - age_min if age_min is not None else None   # kelahiran paling muda
    return bmin, bmax

cats = []
sort = 0
def add(disc, code, level, age_label, name_id, name_en, gender, age_min, age_max, fee, app, max_club=None, entry='individual', division=None, note=None, years=None, jabar_only=False):
    global sort
    sort += 10
    bmin, bmax = years if years else yrs(age_min, age_max)
    cats.append(dict(discipline=disc, code=code, level=level, age_label=age_label, division=division,
        name_id=name_id, name_en=name_en, gender=gender, birth_year_min=bmin, birth_year_max=bmax,
        entry_type=entry, fee=fee, apparatus=app, max_per_club=max_club, sort=sort, note=note,
        allow_priangan=False, jabar_only=jabar_only))

MAG_APP = ['FX','PH','SR','VT','PB','HB']
WAG_APP = ['VT','UB','BB','FX']

# --- MAG (ALP Level 1-4 + Junior) ---
for lvl, groups in [
    (1, [('A','6 tahun ke bawah','6 & under',None,6), ('B','7–8 tahun','7–8',7,8), ('C','9 tahun ke atas','9 & over',9,None)]),
    (2, [('A','7 tahun ke bawah','7 & under',None,7), ('B','8–9 tahun','8–9',8,9), ('C','10 tahun ke atas','10 & over',10,None)]),
]:
    for g, lid, len_, a0, a1 in groups:
        add('MAG', f'MAG-L{lvl}-{g}', f'Level {lvl}', lid, f'Artistik Putra Level {lvl} ({lid})', f"Men's Artistic Level {lvl} ({len_})", 'M', a0, a1, 750000, MAG_APP, 10)
add('MAG','MAG-L3','Level 3','Usia terbuka','Artistik Putra Level 3 (usia terbuka)',"Men's Artistic Level 3 (open age)",'M',None,None,750000,MAG_APP,10)
add('MAG','MAG-L4','Level 4','Usia terbuka','Artistik Putra Level 4 (usia terbuka)',"Men's Artistic Level 4 (open age)",'M',None,None,750000,MAG_APP,10)
add('MAG','MAG-JR','Junior','12–16 tahun','Artistik Putra Junior (12–16 tahun)',"Men's Artistic Junior (12–16)",'M',12,16,750000,MAG_APP,10)

# --- WAG (ALP Level 1-6 + Pre Junior + Junior) ---
for lvl, groups in [
    (1, [('A','6 tahun ke bawah','6 & under',None,6), ('B','7–8 tahun','7–8',7,8), ('C','9 tahun ke atas','9 & over',9,None)]),
    (2, [('A','6 tahun ke bawah','6 & under',None,6), ('B','7–8 tahun','7–8',7,8), ('C','9 tahun ke atas','9 & over',9,None)]),
    (3, [('A','9 tahun ke bawah','9 & under',None,9), ('B','10 tahun ke atas','10 & over',10,None)]),
    (4, [('A','10 tahun ke bawah','10 & under',None,10), ('B','11 tahun ke atas','11 & over',11,None)]),
    (5, [('A','11 tahun ke bawah','11 & under',None,11), ('B','12 tahun ke atas','12 & over',12,None)]),
    (6, [('A','11 tahun ke bawah','11 & under',None,11), ('B','12 tahun ke atas','12 & over',12,None)]),
]:
    for g, lid, len_, a0, a1 in groups:
        add('WAG', f'WAG-L{lvl}-{g}', f'Level {lvl}', lid, f'Artistik Putri Level {lvl} ({lid})', f"Women's Artistic Level {lvl} ({len_})", 'F', a0, a1, 750000, WAG_APP, 10)
add('WAG','WAG-PJ','Pre Junior','11–13 tahun','Artistik Putri Pre Junior (11–13 tahun)',"Women's Artistic Pre Junior (11–13)",'F',11,13,750000,WAG_APP,10)
add('WAG','WAG-JR','Junior','14–15 tahun','Artistik Putri Junior (14–15 tahun)',"Women's Artistic Junior (14–15)",'F',14,15,750000,WAG_APP,10)

# --- RG (Kategori A Profesional, B Amatir, C Priangan khusus Jawa Barat; revisi 14/10/2026) ---
rg_groups = [
    ('KU56','KU 5–6','KU 5–6',(2020,2021),['FH','BALL']),
    ('KU78','KU 7–8','KU 7–8',(2018,2019),['FH','HOOP']),
    ('KU910','KU 9–10','KU 9–10',(2016,2017),['FH','HOOP','BALL']),
    ('KU1112','KU 11–12','KU 11–12',(2014,2015),['FH','BALL','CLUBS']),
    ('JR','Junior','Junior',(2011,2013),['HOOP','BALL','CLUBS','RIBBON']),
]
for div, div_id, div_en in [('A','Profesional','Professional'),('B','Amatir','Amateur'),('C','Priangan','Priangan')]:
    for g, lid, len_, years, app in rg_groups:
        add('RG', f'RG-{div}-{g}', lid, f'Kelahiran {years[0]}–{years[1]}', f'Ritmik {div_id} {lid}', f'Rhythmic {div_en} {len_}', 'F', None, None, 750000, app, None, division=div_id, years=years,
            note='Khusus atlet WNI beralamat di Jawa Barat dari klub di Jawa Barat' if div == 'C' else None, jabar_only=(div == 'C'))

# --- AER ---
aer = [
    ('JR','Junior','15–17 tahun','15–17',15,17,['IM','IW','MP']),
    ('YT','Youth','12–14 tahun','12–14',12,14,['IM','IW','MP']),
    ('ND','National Development','9–11 tahun','9–11',9,11,['IM','IW']),
    ('PND','Pre National Development','6–8 tahun','6–8',6,8,['IM','IW']),
]
ev = {'IM':('Perorangan Putra',"Individual Men",'M','individual',300000),
      'IW':('Perorangan Putri',"Individual Women",'F','individual',300000),
      'MP':('Pasangan Campuran',"Mixed Pair",'X','pair',400000)}
for g, lvl, lid, len_, a0, a1, evs in aer:
    for e in evs:
        nid, nen, gender, et, fee = ev[e]
        add('AER', f'AER-{g}-{e}', lvl, lid, f'Aerobik {lvl} {nid} ({e})', f'Aerobic {lvl} {nen} ({e})', gender, a0, a1, fee, ['RTN'], 4, entry=et)

# Aturan penghargaan (lampiran Medali & Piala Artistik 12/10/2026)
#  aa_places: peringkat serba bisa yang dihargai (1-3 medali, 4-6 medali mini)
#  apparatus_medals: medali per alat 1-3;  club_cap: maks. pesenam per klub untuk setiap penghargaan
APP_MEDAL = {'WAG-L4-A','WAG-L4-B','WAG-L5-A','WAG-L5-B','WAG-L6-A','WAG-L6-B','WAG-PJ','WAG-JR','MAG-JR'}
CLUB_CAP = {'WAG-L4-A','WAG-L4-B','WAG-L5-A','WAG-L5-B','WAG-L6-A','WAG-L6-B','WAG-PJ','WAG-JR'}
for c in cats:
    r = {'type':'rank','places':3}
    if c['discipline'] in ('MAG','WAG'):
        r['aa_places'] = 6
        if c['code'] in APP_MEDAL: r['apparatus_medals'] = True
        if c['code'] in CLUB_CAP: r['club_cap'] = 2
    c['medal_rule'] = r

def q(v):
    if v is None: return 'null'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, int): return str(v)
    if isinstance(v, list): return "array[" + ",".join("'"+x+"'" for x in v) + "]::text[]"
    return "'" + str(v).replace("'", "''") + "'"

out = []
out.append("-- =====================================================================")
out.append("--  Data awal: disiplin, kategori (Undangan 06/10/2026), pengaturan")
out.append("--  'on conflict do nothing' -> perubahan dari konsol tidak tertimpa")
out.append("-- =====================================================================\n")

disc = [
 ('MAG','Artistik Putra',"Men's Artistic",'2026-12-12','2026-12-15',
  [('FX','Lantai','Floor'),('PH','Kuda Pelana','Pommel Horse'),('SR','Gelang-gelang','Rings'),('VT','Meja Lompat','Vault'),('PB','Palang Sejajar','Parallel Bars'),('HB','Palang Tunggal','High Bar')],
  [('D','Nilai D (kesulitan)','D score (difficulty)'),('E','Nilai E (eksekusi)','E score (execution)'),('PEN','Pengurangan netral','Neutral deductions')],
  'Fegie Rizkia Mulyana','0811-2348-753',1),
 ('WAG','Artistik Putri',"Women's Artistic",'2026-12-12','2026-12-15',
  [('VT','Meja Lompat','Vault'),('UB','Palang Bertingkat','Uneven Bars'),('BB','Balok Keseimbangan','Balance Beam'),('FX','Lantai','Floor')],
  [('D','Nilai D (kesulitan)','D score (difficulty)'),('E','Nilai E (eksekusi)','E score (execution)'),('PEN','Pengurangan netral','Neutral deductions')],
  'Vicy Ayu','0856-2383-455',2),
 ('RG','Ritmik','Rhythmic','2026-12-16','2026-12-18',
  [('FH','Tanpa Alat (Floor)','Freehand'),('ROPE','Tali','Rope'),('HOOP','Simpai','Hoop'),('BALL','Bola','Ball'),('CLUBS','Gada','Clubs'),('RIBBON','Pita','Ribbon')],
  [('D','Nilai D (kesulitan)','D score (difficulty)'),('A','Nilai A (artistik)','A score (artistry)'),('E','Nilai E (eksekusi)','E score (execution)'),('PEN','Penalti','Penalties')],
  'Yuanita Vidya M','0815-6361-1403',3),
 ('AER','Aerobik','Aerobic','2026-12-19','2026-12-20',
  [('RTN','Rangkaian','Routine')],
  [('A','Nilai A (artistik)','A score (artistry)'),('E','Nilai E (eksekusi)','E score (execution)'),('D','Nilai D (kesulitan)','D score (difficulty)'),('PEN','Penalti','Penalties')],
  'Mustika Fitri','0816-605-281',4),
]
out.append("insert into jo.disciplines (code, name_id, name_en, date_start, date_end, apparatus, components, contact_name, contact_phone, sort) values")
rows=[]
for code,nid,nen,ds,de,app,comp,cn,cp,so in disc:
    appj = json.dumps([{'code':a,'id':b,'en':c} for a,b,c in app], ensure_ascii=False)
    compj = json.dumps([{'code':a,'id':b,'en':c} for a,b,c in comp], ensure_ascii=False)
    rows.append(f"  ({q(code)}, {q(nid)}, {q(nen)}, {q(ds)}, {q(de)}, {q(appj)}::jsonb, {q(compj)}::jsonb, {q(cn)}, {q(cp)}, {so})")
out.append(",\n".join(rows) + "\non conflict (code) do nothing;\n")

cols = ['discipline','code','level','age_label','division','name_id','name_en','gender','birth_year_min','birth_year_max','entry_type','fee','apparatus','max_per_club','sort','note','medal_rule','allow_priangan','jabar_only']
out.append("insert into jo.categories (" + ", ".join(cols) + ") values")
rows=[]
for c in cats:
    rows.append("  (" + ", ".join((q(json.dumps(c[k]))+'::jsonb') if k == 'medal_rule' else q(c[k]) for k in cols) + ")")
out.append(",\n".join(rows) + "\non conflict (code) do nothing;\n")

settings = {
 'event_name': 'Jabar Open 2026',
 'event_year': 2026,
 'site_url': 'https://adjisena-design.github.io/jabar-open/',
 'registration_open': True,
 'registration_deadline': '2026-11-12T23:59:59+07:00',
 'payment_deadline_label': '12 November 2026',
 'priangan_fee': 150000,
 'qris_cap': 10000000,
 'max_athletes': 5,
 'qris_image_url': None,
 'qris_merchant': 'Jabar Open 2026',
 'payment_note': 'Scan QRIS dengan aplikasi bank atau dompet digital apa pun, lalu ketik nominal persis seperti tertera (termasuk tiga digit kode unik).',
 'contact_email': 'jabaropen2026@gmail.com',
 'pm_email': 'adjisena.daffa@gmail.com',
 'team_fee': 650000,
 'team_max': 6,
 'team_counting': 4,
 'team_levels': {'WAG': ['Level 1','Level 2','Level 3','Level 4','Level 5','Level 6']},
 'instagram': 'gimnastikjabar',
 'email_guardians': True,
 'venue': {'name':'Gymnasium Arcamanik','address':'Jl. Pacuan Kuda No. 15b, Sukamiskin, Arcamanik, Kota Bandung, Jawa Barat 40231'},
 'signatories': [
   {'name':'Andi Juliandi','title':'Ketua Pelaksana Jabar Open 2026'},
   {'name':'Dika Chrisna Irzandi, S.A.B., M.B.A','title':'Ketua Gimnastik Indonesia (GI) Jawa Barat','sig':'assets/img/ttd/dika.png'}],
}
out.append("insert into jo.settings (key, value) values")
rows=[]
for k,v in settings.items():
    rows.append(f"  ({q(k)}, {q(json.dumps(v, ensure_ascii=False))}::jsonb)")
out.append(",\n".join(rows) + "\non conflict (key) do nothing;\n")

open('/home/claude/jabar-open/supabase/src/70_seed.sql','w').write("\n".join(out))
# urutan & tahun lahir untuk migrasi v6 (dipakai 75_migrate)
json.dump([{'code': c['code'], 'sort': c['sort'], 'bmin': c['birth_year_min'], 'bmax': c['birth_year_max']} for c in cats],
          open('/home/claude/jabar-open/supabase/tools/cat_sort.json','w'))
print(len(cats), 'categories')
for c in cats: print(c['code'], c['birth_year_min'], c['birth_year_max'], c['gender'], c['fee'], c['apparatus'])
