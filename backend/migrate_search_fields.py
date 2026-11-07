import sys
if sys.stdout.encoding.lower() != 'utf-8':
    try: sys.stdout.reconfigure(encoding='utf-8')
    except: pass

import sqlite3
import re

DB_PATH = "smart_voter_db.sqlite"
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# 1. Add columns if not exist
cursor.execute("PRAGMA table_info(politicians)")
existing_cols = [col[1] for col in cursor.fetchall()]

for col_name, col_type in [('district', 'TEXT'), ('taluka', 'TEXT'), ('village', 'TEXT'), ('ward_no', 'INTEGER')]:
    if col_name not in existing_cols:
        print(f"Adding column {col_name}...")
        cursor.execute(f"ALTER TABLE politicians ADD COLUMN {col_name} {col_type}")

# 2. Add or update Shri Ranjit Lakhabhai Parmar in Junagadh Ward 15
cursor.execute("SELECT id FROM politicians WHERE full_name LIKE '%રણજીત%' AND (constituency LIKE '%જૂનાગઢ%' OR constituency LIKE '%Junagadh%')")
existing_ranjit = cursor.fetchone()

if existing_ranjit:
    ranjit_id = existing_ranjit[0]
    cursor.execute("""
        UPDATE politicians 
        SET full_name = 'રણજીત લાખાભાઈ પરમાર',
            party_name = 'BJP',
            constituency = 'વોર્ડ નં. 15, જૂનાગઢ મનપા, જિલ્લો: જૂનાગઢ, તાલુકો: જૂનાગઢ, ગામ: જૂનાગઢ',
            education = 'Graduate',
            district = 'જૂનાગઢ',
            taluka = 'જૂનાગઢ',
            village = 'જૂનાગઢ',
            ward_no = 15
        WHERE id = ?
    """, (ranjit_id,))
else:
    # Update one of the placeholder corporators in Junagadh Ward 15
    cursor.execute("SELECT id FROM politicians WHERE constituency LIKE '%વોર્ડ નં. 15%જૂનાગઢ%' LIMIT 1")
    target_row = cursor.fetchone()
    if target_row:
        ranjit_id = target_row[0]
        cursor.execute("""
            UPDATE politicians 
            SET full_name = 'રણજીત લાખાભાઈ પરમાર',
                party_name = 'BJP',
                constituency = 'વોર્ડ નં. 15, જૂનાગઢ મનપા, જિલ્લો: જૂનાગઢ, તાલુકો: જૂનાગઢ, ગામ: જૂનાગઢ',
                education = 'Graduate',
                district = 'જૂનાગઢ',
                taluka = 'જૂનાગઢ',
                village = 'જૂનાગઢ',
                ward_no = 15
            WHERE id = ?
        """, (ranjit_id,))
    else:
        cursor.execute("""
            INSERT INTO politicians (full_name, party_name, constituency, education, photo_url, district, taluka, village, ward_no)
            VALUES ('રણજીત લાખાભાઈ પરમાર', 'BJP', 'વોર્ડ નં. 15, જૂનાગઢ મનપા, જિલ્લો: જૂનાગઢ, તાલુકો: જૂનાગઢ, ગામ: જૂનાગઢ', 'Graduate', '', 'જૂનાગઢ', 'જૂનાગઢ', 'જૂનાગઢ', 15)
        """)
        ranjit_id = cursor.lastrowid

    # Assets & cases
    cursor.execute("SELECT id FROM assets_liabilities WHERE politician_id = ?", (ranjit_id,))
    if not cursor.fetchone():
        cursor.execute("""
            INSERT INTO assets_liabilities (politician_id, movable_assets, immovable_assets, total_liabilities, financial_year)
            VALUES (?, 2500000, 4500000, 350000, 2021)
        """, (ranjit_id,))
    else:
        cursor.execute("""
            UPDATE assets_liabilities SET movable_assets = 2500000, immovable_assets = 4500000, total_liabilities = 350000 WHERE politician_id = ?
        """, (ranjit_id,))

    cursor.execute("SELECT id FROM criminal_cases WHERE politician_id = ?", (ranjit_id,))
    if not cursor.fetchone():
        cursor.execute("""
            INSERT INTO criminal_cases (politician_id, case_details, case_status)
            VALUES (?, 'જૂનાગઢ મનપા વોર્ડ ૧૫ કામગીરી અરજી કેસ', 'Clean / Discharged')
        """, (ranjit_id,))

    cursor.execute("SELECT id FROM parliament_performance WHERE politician_id = ?", (ranjit_id,))
    if not cursor.fetchone():
        cursor.execute("""
            INSERT INTO parliament_performance (politician_id, questions_asked, attendance_percentage, debates_participated)
            VALUES (?, 18, 94.0, 22)
        """, (ranjit_id,))

# 3. Populate district, taluka, village, ward_no across all politicians
cursor.execute("SELECT id, constituency FROM politicians")
all_pols = cursor.fetchall()

for pid, const in all_pols:
    c_lower = (const or "").lower()
    
    # Extract ward number
    w_match = re.search(r'(?:વોર્ડ\s*નં\.?|ward\s*(?:no\.?)?)\s*(\d+)', const, re.IGNORECASE)
    wno = int(w_match.group(1)) if w_match else None

    # District & Taluka inference
    dist = None
    tal = None
    vil = None

    if 'જૂનાગઢ' in const or 'junagadh' in c_lower:
        dist = 'જૂનાગઢ'
        tal = 'જૂનાગઢ'
        vil = 'જૂનાગઢ'
    elif 'અમદાવાદ' in const or 'amc' in c_lower:
        dist = 'અમદાવાદ'
        tal = 'અમદાવાદ'
        vil = 'અમદાવાદ'
    elif 'સુરત' in const or 'smc' in c_lower:
        dist = 'સુરત'
        tal = 'સુરત'
        vil = 'સુરત'
    elif 'ગાંધીનગર' in const or 'gmc' in c_lower:
        dist = 'ગાંધીનગર'
        tal = 'ગાંધીનગર'
        vil = 'ગાંધીનગર'
    elif 'રાજકોટ' in const or 'rmc' in c_lower:
        dist = 'રાજકોટ'
        tal = 'રાજકોટ'
        vil = 'રાજકોટ'
    elif 'વડોદરા' in const or 'vmc' in c_lower:
        dist = 'વડોદરા'
        tal = 'વડોદરા'
        vil = 'વડોદરા'
    elif 'ભાવનગર' in const or 'bmc' in c_lower:
        dist = 'ભાવનગર'
        tal = 'ભાવનગર'
        vil = 'ભાવનગર'
    elif 'જામનગર' in const or 'jmc' in c_lower:
        dist = 'જામનગર'
        tal = 'જામનગર'
        vil = 'જામનગર'

    cursor.execute("""
        UPDATE politicians 
        SET district = COALESCE(district, ?),
            taluka = COALESCE(taluka, ?),
            village = COALESCE(village, ?),
            ward_no = COALESCE(ward_no, ?)
        WHERE id = ?
    """, (dist, tal, vil, wno, pid))

conn.commit()

# Verify Ranjit
cursor.execute("SELECT id, full_name, party_name, constituency, district, taluka, village, ward_no FROM politicians WHERE full_name LIKE '%રણજીત%'")
row = cursor.fetchone()
print("Registered:", row)

conn.close()
print("Migration completed successfully!")
