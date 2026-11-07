import os
import re
import sqlite3
import numpy as np
import faiss
import face_recognition
from PIL import Image, ImageOps
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE = os.path.join(BASE_DIR, "smart_voter_db.sqlite")
INDEX_FILE = os.path.join(BASE_DIR, "faces_faiss_idmap.index")
UPLOAD_FOLDER = os.path.join(BASE_DIR, "temp_uploads")
KNOWN_FACES_DIR = os.path.join(BASE_DIR, "known_faces")

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(KNOWN_FACES_DIR, exist_ok=True)

# FAISS IndexIDMap લોડ અથવા નવું શરૂ કરો
if os.path.exists(INDEX_FILE):
    faiss_index = faiss.read_index(INDEX_FILE)
else:
    base_index = faiss.IndexFlatL2(128)
    faiss_index = faiss.IndexIDMap(base_index)
    faiss.write_index(faiss_index, INDEX_FILE)

def get_db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def fetch_report_card(politician_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM politicians WHERE id = ?", (politician_id,))
    leader = cursor.fetchone()
    if not leader:
        conn.close()
        return None
    data = dict(leader)

    cursor.execute("SELECT * FROM assets_liabilities WHERE politician_id = ?", (politician_id,))
    data["assets"] = [dict(r) for r in cursor.fetchall()]

    cursor.execute("SELECT * FROM criminal_cases WHERE politician_id = ?", (politician_id,))
    data["criminal_cases"] = [dict(r) for r in cursor.fetchall()]

    cursor.execute("SELECT * FROM parliament_performance WHERE politician_id = ?", (politician_id,))
    perf = cursor.fetchone()
    data["performance"] = dict(perf) if perf else {}
    conn.close()
    return data

@app.route("/", methods=["GET", "POST"])
@app.route("/api/health", methods=["GET"])
def health_check():
    if request.method == "POST":
        return scan_poster()
    return jsonify({
        "status": "online",
        "service": "Smart Voter Backend API",
        "faiss_total_faces": faiss_index.ntotal if 'faiss_index' in globals() else 0
    }), 200

@app.route("/api/politicians", methods=["GET"])
def get_politicians():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id, full_name, party_name, constituency FROM politicians")
    leaders = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify({"status": "success", "data": leaders})

def normalize_gujarati_search(text):
    if not text:
        return ""
    # Map Gujarati numerals to English
    guj_nums = "૦૧૨૩૪૫૬૭૮૯"
    for i, g in enumerate(guj_nums):
        text = text.replace(g, str(i))
    # Normalize common spelling variations
    text = text.replace("જુનાગઢ", "જૂનાગઢ")
    text = text.replace("વોડ", "વોર્ડ")
    return text.strip()

@app.route("/api/search", methods=["GET"])
def search_politicians():
    q = request.args.get("q", "").strip()
    param_name = request.args.get("name", "").strip()
    param_dist = request.args.get("district", "").strip()
    param_tal = request.args.get("taluka", "").strip()
    param_vil = request.args.get("village", "").strip()
    param_ward = request.args.get("ward", "").strip()
    param_party = request.args.get("party", "").strip()

    if not q and not param_name and not param_dist and not param_tal and not param_vil and not param_ward and not param_party:
        return jsonify({"status": "success", "total": 0, "results": []}), 200

    conn = get_db()
    cursor = conn.cursor()

    noise_words = {
        'જિલ્લો', 'જિલ્લા', 'ગામ', 'તાલુકો', 'તાલુકા', 'વોડ', 'વોર્ડ', 'નંબર', 'નં', 
        'નામ', 'શહેર', 'મનપા', 'મહાનગરપાલિકા', 'કોર્પોરેટર', 'district', 'village', 
        'taluka', 'ward', 'number', 'no', 'name'
    }

    where_clauses = []
    params = []

    # 1. Handle Explicit Filters
    if param_name:
        pname = normalize_gujarati_search(param_name)
        where_clauses.append("p.full_name LIKE ?")
        params.append(f"%{pname}%")
    if param_dist:
        pdist = normalize_gujarati_search(param_dist)
        where_clauses.append("(p.district LIKE ? OR p.constituency LIKE ?)")
        params.extend([f"%{pdist}%", f"%{pdist}%"])
    if param_tal:
        ptal = normalize_gujarati_search(param_tal)
        where_clauses.append("(p.taluka LIKE ? OR p.constituency LIKE ?)")
        params.extend([f"%{ptal}%", f"%{ptal}%"])
    if param_vil:
        pvil = normalize_gujarati_search(param_vil)
        where_clauses.append("(p.village LIKE ? OR p.constituency LIKE ?)")
        params.extend([f"%{pvil}%", f"%{pvil}%"])
    if param_ward:
        pward = normalize_gujarati_search(param_ward)
        where_clauses.append("(p.ward_no = ? OR p.constituency LIKE ?)")
        try:
            params.append(int(pward))
        except:
            params.append(0)
        params.append(f"%{pward}%")
    if param_party:
        where_clauses.append("p.party_name LIKE ?")
        params.append(f"%{param_party}%")

    # 2. Handle Freeform Search Query `q`
    if q:
        norm_q = normalize_gujarati_search(q)
        raw_tokens = re.split(r'[,.\s\-_/]+', norm_q)
        tokens = [t for t in raw_tokens if t and t.lower() not in noise_words]
        
        if not tokens:
            tokens = [norm_q]

        for t in tokens:
            token_param = f"%{t}%"
            # Party alias detection
            if any(k in t.lower() for k in ['કોંગ્રેસ', 'કોગ્રેસ', 'congress', 'inc']):
                where_clauses.append("(p.party_name LIKE '%INC%' OR p.party_name LIKE '%કોંગ્રેસ%' OR p.party_name LIKE '%Congress%')")
            elif any(k in t.lower() for k in ['ભાજપ', 'ભાજપા', 'bjp']):
                where_clauses.append("(p.party_name LIKE '%BJP%' OR p.party_name LIKE '%ભાજપ%')")
            elif any(k in t.lower() for k in ['આપ', 'aap']):
                where_clauses.append("(p.party_name LIKE '%AAP%' OR p.party_name LIKE '%આપ%')")
            elif t.isdigit():
                where_clauses.append("(p.ward_no = ? OR p.constituency LIKE ? OR p.full_name LIKE ?)")
                params.extend([int(t), token_param, token_param])
            else:
                where_clauses.append("""(
                    p.full_name LIKE ? OR 
                    p.constituency LIKE ? OR 
                    p.party_name LIKE ? OR 
                    p.district LIKE ? OR 
                    p.taluka LIKE ? OR 
                    p.village LIKE ?
                )""")
                params.extend([token_param, token_param, token_param, token_param, token_param, token_param])

    where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

    query_sql = f"""
        SELECT p.id, p.full_name, p.party_name, p.constituency, p.education, p.photo_url,
               p.district, p.taluka, p.village, p.ward_no,
               COALESCE(a.total_liabilities, 0) as liabilities,
               COALESCE(a.movable_assets + a.immovable_assets, 0) as total_assets,
               COALESCE(c.case_status, 'Clean Record') as case_status,
               COALESCE(perf.attendance_percentage, 0) as attendance_percentage
        FROM politicians p
        LEFT JOIN assets_liabilities a ON p.id = a.politician_id
        LEFT JOIN criminal_cases c ON p.id = c.politician_id
        LEFT JOIN parliament_performance perf ON p.id = perf.politician_id
        WHERE {where_sql}
        GROUP BY p.id
        ORDER BY p.id ASC
        LIMIT 60
    """

    cursor.execute(query_sql, params)
    rows = [dict(r) for r in cursor.fetchall()]

    # Fallback to OR if no results from strict AND
    if not rows and q and len(tokens) > 1:
        or_clauses = []
        or_params = []
        for t in tokens:
            token_param = f"%{t}%"
            if any(k in t.lower() for k in ['કોંગ્રેસ', 'કોગ્રેસ', 'congress', 'inc']):
                or_clauses.append("(p.party_name LIKE '%INC%' OR p.party_name LIKE '%કોંગ્રેસ%')")
            elif any(k in t.lower() for k in ['ભાજપ', 'ભાજપા', 'bjp']):
                or_clauses.append("(p.party_name LIKE '%BJP%' OR p.party_name LIKE '%ભાજપ%')")
            elif any(k in t.lower() for k in ['આપ', 'aap']):
                or_clauses.append("(p.party_name LIKE '%AAP%' OR p.party_name LIKE '%આપ%')")
            elif t.isdigit():
                or_clauses.append("(p.ward_no = ? OR p.constituency LIKE ?)")
                or_params.extend([int(t), token_param])
            else:
                or_clauses.append("(p.full_name LIKE ? OR p.constituency LIKE ?)")
                or_params.extend([token_param, token_param])

        if or_clauses:
            fallback_sql = f"""
                SELECT p.id, p.full_name, p.party_name, p.constituency, p.education, p.photo_url,
                       p.district, p.taluka, p.village, p.ward_no,
                       COALESCE(a.total_liabilities, 0) as liabilities,
                       COALESCE(a.movable_assets + a.immovable_assets, 0) as total_assets,
                       COALESCE(c.case_status, 'Clean Record') as case_status,
                       COALESCE(perf.attendance_percentage, 0) as attendance_percentage
                FROM politicians p
                LEFT JOIN assets_liabilities a ON p.id = a.politician_id
                LEFT JOIN criminal_cases c ON p.id = c.politician_id
                LEFT JOIN parliament_performance perf ON p.id = perf.politician_id
                WHERE {" OR ".join(or_clauses)}
                GROUP BY p.id
                ORDER BY p.id ASC
                LIMIT 60
            """
            cursor.execute(fallback_sql, or_params)
            rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify({"status": "success", "total": len(rows), "results": rows}), 200

@app.route("/api/politician/<int:politician_id>", methods=["GET"])
def get_politician_detail(politician_id):
    report = fetch_report_card(politician_id)
    if not report:
        return jsonify({"status": "error", "message": "નેતા/કોર્પોરેટર મળ્યા નથી"}), 404
    return jsonify({"status": "success", "data": report}), 200

@app.route("/api/register-leader-face", methods=["POST"])
def register_leader_face():
    """known_faces ફોલ્ડરમાંથી નવો ચહેરો FAISS માં એડ કરવાનો એન્ડપોઇન્ટ"""
    if "image" not in request.files or "politician_id" not in request.form:
        return jsonify({"status": "error", "message": "ઇમેજ અને politician_id જરૂરી છે"}), 400

    try:
        politician_id = int(request.form["politician_id"])
    except ValueError:
        return jsonify({"status": "error", "message": "માન્ય politician_id આપો"}), 400

    file = request.files["image"]
    filename = secure_filename(file.filename)
    path = os.path.join(KNOWN_FACES_DIR, filename)
    file.save(path)

    try:
        img = face_recognition.load_image_file(path)
        encs = face_recognition.face_encodings(img)
        if not encs:
            return jsonify({"status": "error", "message": "કોઈ ચહેરો મળ્યો નથી"}), 400

        vec = np.array([encs[0]]).astype('float32')
        ids = np.array([politician_id], dtype=np.int64)
        faiss_index.add_with_ids(vec, ids)
        faiss.write_index(faiss_index, INDEX_FILE)

        return jsonify({"status": "success", "message": f"ID {politician_id} FAISS માં રજીસ્ટર થયો", "total": faiss_index.ntotal})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/api/scan-poster", methods=["GET", "POST"])
def scan_poster():
    if request.method == "GET":
        return jsonify({
            "status": "online",
            "message": "Smart Voter Scan API is ready. Please send a POST request with an image file to scan."
        }), 200

    if "image" not in request.files:
        return jsonify({"status": "error", "message": "ઇમેજ ફાઇલ મળી નથી"}), 400

    file = request.files["image"]
    filename = secure_filename(file.filename)
    file_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(file_path)

    try:
        pil_img = Image.open(file_path)
        pil_img = ImageOps.exif_transpose(pil_img)

        orig_w, orig_h = pil_img.size
        max_dim = 1024

        if orig_w > max_dim or orig_h > max_dim:
            if orig_w > orig_h:
                new_w = max_dim
                new_h = int(orig_h * (max_dim / orig_w))
            else:
                new_h = max_dim
                new_w = int(orig_w * (max_dim / orig_h))
            scale_x = orig_w / new_w
            scale_y = orig_h / new_h
            resized_pil = pil_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
            img = np.array(resized_pil.convert('RGB'))
        else:
            scale_x = 1.0
            scale_y = 1.0
            img = np.array(pil_img.convert('RGB'))

        locations = face_recognition.face_locations(img, model="hog")
        if not locations:
            return jsonify({"status": "success", "total_faces_found": 0, "leaders": []}), 200

        encodings = face_recognition.face_encodings(img, locations)
        results = []
        THRESHOLD = 0.38  # L2 Distance Threshold

        for idx, (enc, loc) in enumerate(zip(encodings, locations)):
            top, right, bottom, left = loc
            query_vec = np.array([enc]).astype('float32')

            distances, ids = faiss_index.search(query_vec, 1)
            matched_id = int(ids[0][0])
            dist = float(distances[0][0])

            face_obj = {
                "face_index": idx + 1,
                "box": {
                    "top": int(top * scale_y),
                    "right": int(right * scale_x),
                    "bottom": int(bottom * scale_y),
                    "left": int(left * scale_x)
                }
            }

            if dist <= THRESHOLD and matched_id != -1:
                report = fetch_report_card(matched_id)
                if report:
                    confidence = round(float((1 - (dist / THRESHOLD)) * 100), 1)
                    face_obj["identified"] = True
                    face_obj["confidence_percentage"] = max(confidence, 50.0)
                    face_obj["report_card"] = report
                else:
                    face_obj["identified"] = False
                    face_obj["confidence_percentage"] = 0.0
                    face_obj["report_card"] = None
            else:
                face_obj["identified"] = False
                face_obj["confidence_percentage"] = 0.0
                face_obj["report_card"] = None

            results.append(face_obj)

        return jsonify({
            "status": "success",
            "total_faces_found": len(locations),
            "leaders": results
        }), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if os.path.exists(file_path):
            os.remove(file_path)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
