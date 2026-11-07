import os
import sqlite3

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE = os.path.join(BASE_DIR, "smart_voter_db.sqlite")

def init_database():
    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()

    # નેતાઓની મૂળભૂત માહિતી
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS politicians (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name TEXT NOT NULL,
        party_name TEXT,
        constituency TEXT,
        education TEXT,
        photo_url TEXT
    )
    """)

    # સંપત્તિ અને દેવું
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS assets_liabilities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        politician_id INTEGER,
        movable_assets REAL,
        immovable_assets REAL,
        total_liabilities REAL,
        financial_year INTEGER,
        FOREIGN KEY (politician_id) REFERENCES politicians(id) ON DELETE CASCADE
    )
    """)

    # ફોજદારી કેસો
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS criminal_cases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        politician_id INTEGER,
        case_details TEXT,
        case_status TEXT,
        FOREIGN KEY (politician_id) REFERENCES politicians(id) ON DELETE CASCADE
    )
    """)

    # સંસદીય કામગીરી
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS parliament_performance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        politician_id INTEGER,
        questions_asked INTEGER,
        attendance_percentage REAL,
        debates_participated INTEGER,
        FOREIGN KEY (politician_id) REFERENCES politicians(id) ON DELETE CASCADE
    )
    """)

    # ટેસ્ટ ડેટા ઇન્સર્ટ કરવો
    cursor.execute("SELECT COUNT(*) FROM politicians")
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO politicians (full_name, party_name, constituency, education) VALUES (?, ?, ?, ?)",
                       ("ભૂપેન્દ્ર પટેલ", "ભાજપ", "ઘાટલોડિયા", "ડિપ્લોમા સિવિલ એન્જિનિયરિંગ"))
        p1_id = cursor.lastrowid
        cursor.execute("INSERT INTO assets_liabilities (politician_id, movable_assets, immovable_assets, total_liabilities, financial_year) VALUES (?, ?, ?, ?, ?)",
                       (p1_id, 32000000.0, 50000000.0, 1500000.0, 2022))
        cursor.execute("INSERT INTO parliament_performance (politician_id, questions_asked, attendance_percentage, debates_participated) VALUES (?, ?, ?, ?)",
                       (p1_id, 0, 94.5, 12))

        cursor.execute("INSERT INTO politicians (full_name, party_name, constituency, education) VALUES (?, ?, ?, ?)",
                       ("શક્તિસિંહ ગોહિલ", "કોંગ્રેસ", "રાજ્યસભા", "બી.કોમ, એલ.એલ.બી"))
        p2_id = cursor.lastrowid
        cursor.execute("INSERT INTO assets_liabilities (politician_id, movable_assets, immovable_assets, total_liabilities, financial_year) VALUES (?, ?, ?, ?, ?)",
                       (p2_id, 18000000.0, 42000000.0, 2200000.0, 2020))
        cursor.execute("INSERT INTO criminal_cases (politician_id, case_details, case_status) VALUES (?, ?, ?)",
                       (p2_id, "રાજકીય વિરોધ પ્રદર્શન અંગેનો કેસ", "પેન્ડિંગ"))
        cursor.execute("INSERT INTO parliament_performance (politician_id, questions_asked, attendance_percentage, debates_participated) VALUES (?, ?, ?, ?)",
                       (p2_id, 86, 91.2, 45))

    conn.commit()
    conn.close()
    print("ડેટાબેઝ smart_voter_db.sqlite સફળતાપૂર્વક તૈયાર થયો!")

if __name__ == "__main__":
    init_database()
