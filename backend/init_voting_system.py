import sqlite3
import hashlib
import os

DB_PATH = os.path.join(os.path.dirname(__file__), 'smart_voter_db.sqlite')

def hash_aadhaar(aadhaar_num):
    clean = str(aadhaar_num).replace(" ", "").strip()
    return hashlib.sha256(clean.encode()).hexdigest()

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

# 1. Create voters table
c.execute('''
    CREATE TABLE IF NOT EXISTS voters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        aadhaar_hash TEXT UNIQUE NOT NULL,
        aadhaar_masked TEXT NOT NULL,
        full_name TEXT NOT NULL,
        age INTEGER,
        gender TEXT,
        district TEXT NOT NULL,
        taluka TEXT NOT NULL,
        ward_no INTEGER NOT NULL,
        booth_no INTEGER NOT NULL,
        has_voted INTEGER DEFAULT 0,
        voted_at TIMESTAMP,
        fingerprint_registered INTEGER DEFAULT 1
    )
''')

# 2. Create ballot_votes table (Anonymous Secret Ballot)
c.execute('''
    CREATE TABLE IF NOT EXISTS ballot_votes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vote_token TEXT UNIQUE NOT NULL,
        district TEXT NOT NULL,
        ward_no INTEGER NOT NULL,
        candidate_id INTEGER NOT NULL,
        candidate_name TEXT NOT NULL,
        party_name TEXT NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
''')

# 3. Seed Sample Voters
sample_voters = [
    ("123456789012", "XXXX XXXX 9012", "રાણવા હરસુખભાઈ મુળજીભાઈ", 48, "પુરુષ (Male)", "જૂનાગઢ", "જૂનાગઢ", 15, 102),
    ("987654321098", "XXXX XXXX 1098", "ગીતાબેન રમેશભાઈ પટેલ", 42, "સ્ત્રી (Female)", "જૂનાગઢ", "જૂનાગઢ", 15, 102),
    ("111122223333", "XXXX XXXX 3333", "વિજયભાઈ નારણભાઈ ચાવડા", 35, "પુરુષ (Male)", "જૂનાગઢ", "જૂનાગઢ", 9, 55),
    ("444455556666", "XXXX XXXX 6666", "અનિલભાઈ કે. સોલંકી", 29, "પુરુષ (Male)", "જૂનાગઢ", "જૂનાગઢ", 4, 32),
    ("777788889999", "XXXX XXXX 9999", "પ્રિયાબેન મહેશભાઈ ઠાકોર", 31, "સ્ત્રી (Female)", "ગાંધીનગર", "ગાંધીનગર", 1, 12),
]

for num, masked, name, age, gender, dist, tal, ward, booth in sample_voters:
    a_hash = hash_aadhaar(num)
    c.execute('''
        INSERT OR IGNORE INTO voters (aadhaar_hash, aadhaar_masked, full_name, age, gender, district, taluka, ward_no, booth_no, has_voted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    ''', (a_hash, masked, name, age, gender, dist, tal, ward, booth))

conn.commit()

c.execute('SELECT count(*) FROM voters')
print(f'Total voters registered in database: {c.fetchone()[0]}')
conn.close()
