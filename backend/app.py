import os
import sqlite3
import numpy as np
import faiss
import face_recognition
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
        img = face_recognition.load_image_file(file_path)
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
                "box": {"top": top, "right": right, "bottom": bottom, "left": left}
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
