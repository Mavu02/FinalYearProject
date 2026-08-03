import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta

# 1. Initialize Admin SDK
# Ensure "service_key.json" is in the same directory as this script
cred = credentials.Certificate("service_key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("🔒 Admin SDK connected.\n")

def clear_collections():
    print("🧹 Clearing existing data for a clean slate...")
    # List of collections to wipe
    collections = ['sessions', 'attendance', 'qr_codes', 'attendance_pings', 'users', 'classes']
    for coll in collections:
        docs = db.collection(coll).stream()
        count = 0
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
            count += 1
            if count % 500 == 0:
                batch.commit()
                batch = db.batch()
        batch.commit()
        if count > 0:
            print(f"   - Deleted {count} documents from '{coll}'")
    print("✨ Firebase is now clean.\n")

def seed_data():
    clear_collections()
    print("🚀 Seeding specific test data...")

    # --- 1. USERS ---
    users = {
        "auth_uid_lecB_jeremy_LEC1904001": {
            "user_id": 3,
            "university_id": "LEC1904001",
            "name": "Dr. Jeremy",
            "role": "Lecturer",
            "email": "jeremy@uni.edu"
        },
        "auth_uid_stu_bit_25": {
            "user_id": 25,
            "university_id": "SWE2404004",
            "name": "Bit",
            "role": "Student",
            "email": "bit@uni.edu"
        },
        "auth_uid_stu_dough_26": {
            "user_id": 26,
            "university_id": "SWE2404005",
            "name": "Dough",
            "role": "Student",
            "email": "dough@uni.edu"
        }
    }

    for uid, data in users.items():
        db.collection("users").document(uid).set({
            **data,
            "last_updated": firestore.SERVER_TIMESTAMP
        })
        print(f"   - Created user: {data['name']}")

    # --- 2. CLASSES ---
    # Computer Graphics (class_id 3)
    class_data = {
        "class_id": 3,
        "lecturer_id": 3,
        "course_name": "Computer Graphics",
        "course_code": "SWE304",
        "semester": "2026-04-06",
        "enrolled_student_ids": [25, 26] # Bit and Dough
    }
    db.collection("classes").document("class_3").set({
        **class_data,
        "last_updated": firestore.SERVER_TIMESTAMP
    })
    print(f"   - Created class: {class_data['course_name']}")

    # --- 3. SESSION ---
    # One session on 07/07/2026 (10:00 - 11:00)
    session_id = "test_session_20260707"
    session_payload = {
        "class_id": 3,
        "session_date": "2026-07-07",
        "start_time": "18:45:00",
        "end_time": "20:45:00",
        "room_number": "Graphics Lab 1"
    }
    db.collection("sessions").document(session_id).set(session_payload)
    print(f"   - Created session for 2026-07-07: {session_id}")

    print("\n🎯 SEEDING COMPLETE!")
    print("User Logins:")
    print(" - Jeremy: jeremy@uni.edu (Pass: JeremyPass)")
    print(" - Bit: bit@uni.edu (Pass: BitPass)")
    print(" - Dough: dough@uni.edu (Pass: DoughPass)")

if __name__ == "__main__":
    seed_data()
