import firebase_admin
from firebase_admin import credentials, firestore

# 1. Connect to your Firebase Cloud Instance
cred = credentials.Certificate("service_key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("🚀 Connection successful! Initializing Firestore seeding...")

# =========================================================================
# DATA SEED BLOCK: Derived from your structural SQL script
# =========================================================================

# 1. Users Collection (Keyed by Firebase Auth UID)
users_data = {
    "auth_uid_admin_amy_492kLpXq": {"user_id": 1, "university_id": "ADN-001", "name": "Amy", "role": "Admin"},
    "auth_uid_lecA_alice_103mNqRt": {"user_id": 2, "university_id": "LEC-001", "name": "Dr. Alice", "role": "Lecturer"},
    "auth_uid_lecB_jeremy_504pStV": {"user_id": 3, "university_id": "LEC-002", "name": "Dr. Jeremy", "role": "Lecturer"},
    "auth_uid_lecC_sam_918vWxYzAb": {"user_id": 4, "university_id": "LEC-003", "name": "Dr. Sam", "role": "Lecturer"},
    "auth_uid_stu01_john_382kLpQm": {"user_id": 5, "university_id": "STU-101", "name": "John Doe", "role": "Student"},
    "auth_uid_stu02_jane_749mNqRt": {"user_id": 6, "university_id": "STU-102", "name": "Jane Smith", "role": "Student"},
    "auth_uid_stu03_max_105pStVwX": {"user_id": 7, "university_id": "STU-103", "name": "Max Jay", "role": "Student"},
    "auth_uid_stu04_kain_837vWxYz": {"user_id": 8, "university_id": "STU-104", "name": "Kain Rogers", "role": "Student"},
    "auth_uid_stu05_tom_294kLpQmZ": {"user_id": 9, "university_id": "STU-105", "name": "Tom Tommy", "role": "Student"},
    "auth_uid_stu06_mace_830mNqRt": {"user_id": 10, "university_id": "STU-106", "name": "Mace Tin", "role": "Student"},
    "auth_uid_stu07_kim_472pStVwX": {"user_id": 11, "university_id": "STU-107", "name": "Kim Pam", "role": "Student"},
    "auth_uid_stu08_mann_193vWxYz": {"user_id": 12, "university_id": "STU-108", "name": "Mannny Yo", "role": "Student"}
}

# 2. Departments Collection
departments_data = {
    "dept_1": {"department_id": 1, "department_name": "Computer Science"},
    "dept_2": {"department_id": 2, "department_name": "Data Science"},
    "dept_3": {"department_id": 3, "department_name": "Digital Media Technology"},
    "dept_4": {"department_id": 4, "department_name": "Cyber Security"}
}

# 3. User-Departments Bridge (Array structure optimization for NoSQL)
user_departments_links = {
    "auth_uid_lecA_alice_103mNqRt": [1],
    "auth_uid_lecB_jeremy_504pStV": [1, 2],
    "auth_uid_lecC_sam_918vWxYzAb": [3, 4],
    "auth_uid_stu01_john_382kLpQm": [1],
    "auth_uid_stu02_jane_749mNqRt": [1],
    "auth_uid_stu03_max_105pStVwX": [1],
    "auth_uid_stu04_kain_837vWxYz": [2],
    "auth_uid_stu05_tom_294kLpQmZ": [2],
    "auth_uid_stu06_mace_830mNqRt": [4],
    "auth_uid_stu07_kim_472pStVwX": [4],
    "auth_uid_stu08_mann_193vWxYz": [4]
}

# 4. Classes Collection
classes_data = {
    "class_1": {"class_id": 1, "lecturer_id": 2, "course_name": "Mobile Application Development", "course_code": "CS-302", "semester": "2026/04", "department_ids": [1]},
    "class_2": {"class_id": 2, "lecturer_id": 2, "course_name": "Internet of Things", "course_code": "CS-405", "semester": "2026/04", "department_ids": [1, 2]},
    "class_3": {"class_id": 3, "lecturer_id": 3, "course_name": "Computer Graphics", "course_code": "CS-219", "semester": "2026/04", "department_ids": [1, 2, 3]},
    "class_4": {"class_id": 4, "lecturer_id": 3, "course_name": "C++", "course_code": "CS-001", "semester": "2026/09", "department_ids": [1, 2, 3, 4]},
    "class_5": {"class_id": 5, "lecturer_id": 3, "course_name": "Python", "course_code": "CS-002", "semester": "2026/09", "department_ids": []}
}

# 6. Enrollment Matrix Map (Denormalized into Class arrays for simple syncing queries)
enrollments_map = {
    "class_1": [5, 6, 7, 8, 12],
    "class_2": [5, 6, 8, 9, 10, 11],
    "class_3": [5, 8, 9, 11],
    "class_4": [8, 9, 10, 11],
    "class_5": [7, 12]
}

# 7. Sessions Collection (Keyed by UUID)
sessions_data = {
    "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61": {"class_id": 1, "session_date": "2026-06-22", "start_time": "10:00:00", "end_time": "12:00:00", "room_number": "Lab 1A"},
    "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f": {"class_id": 1, "session_date": "2026-06-24", "start_time": "10:00:00", "end_time": "11:00:00", "room_number": "Lab 1B"},
    "14b7e3d9-5a2e-4c1f-bc8d-9e0f1a2b3c4d": {"class_id": 2, "session_date": "2026-06-24", "start_time": "10:00:00", "end_time": "13:00:00", "room_number": "Lab 1A"},
    "8e9f0a1b-2c3d-4e5f-a6b7-c8d9e0f1a2b3": {"class_id": 3, "session_date": "2026-06-25", "start_time": "10:00:00", "end_time": "12:00:00", "room_number": "Lab 2B"},
    "f5e4d3c2-b1a0-9f8e-7d6c-543210fedcba": {"class_id": 4, "session_date": "2026-06-26", "start_time": "10:00:00", "end_time": "11:00:00", "room_number": "Lab 1A"}
}

# 8. Raw Attendance Keep-Alive Pings (Root Level Collection)
pings_data = [
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "10:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "10:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "10:45:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "11:00:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "11:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "11:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "ping_time": "11:45:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 6, "ping_time": "10:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 6, "ping_time": "10:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 6, "ping_time": "10:45:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 8, "ping_time": "11:00:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 8, "ping_time": "11:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 8, "ping_time": "11:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 8, "ping_time": "11:45:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "10:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "10:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "10:45:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "11:00:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "11:15:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "11:30:00"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "ping_time": "11:45:00"}
]

# 9. Attendance Summary State Ledger
attendance_data = [
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 5, "status": "Present", "qr_check_in_time": "2026-06-22 10:02:14"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 6, "status": "Left Early", "qr_check_in_time": "2026-06-22 10:01:55"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 7, "status": "Absent", "qr_check_in_time": None},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 8, "status": "Late", "qr_check_in_time": "2026-06-22 10:56:40"},
    {"session_id": "6af23b1a-7b3d-4bad-9bdd-2b0d7b3dcb61", "student_id": 12, "status": "Present", "qr_check_in_time": "2026-06-22 10:03:02"},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 5, "status": "Attending", "qr_check_in_time": "2026-06-24 10:01:12"},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 6, "status": "Late", "qr_check_in_time": "2026-06-24 10:22:05"},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 8, "status": "Upcoming", "qr_check_in_time": None},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 9, "status": "Upcoming", "qr_check_in_time": None},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 10, "status": "Upcoming", "qr_check_in_time": None},
    {"session_id": "a3f89c2e-1c5d-4f6b-8e1a-3a4b5c6d7e8f", "student_id": 11, "status": "Upcoming", "qr_check_in_time": None}
]

# =========================================================================
# EXECUTION WORKFLOW LAYER
# =========================================================================

# Push Users
for uid, profile in users_data.items():
    profile["department_ids"] = user_departments_links.get(uid, [])
    db.collection("users").document(uid).set(profile)

# Push Departments
for dept_id, payload in departments_data.items():
    db.collection("departments").document(dept_id).set(payload)

# Push Classes with Nested Rosters
for class_id, payload in classes_data.items():
    payload["enrolled_student_ids"] = enrollments_map.get(class_id, [])
    db.collection("classes").document(class_id).set(payload)

# Push Sessions
for session_id, payload in sessions_data.items():
    db.collection("sessions").document(session_id).set(payload)

# Push Attendance Sheets (Using composite key strings for NoSQL isolation mapping)
for index, record in enumerate(attendance_data):
    doc_id = f"{record['session_id']}_{record['student_id']}"
    db.collection("attendance").document(doc_id).set(record)

# Push Keep-Alive Raw Pings
for index, ping in enumerate(pings_data):
    doc_id = f"ping_{index + 1}"
    db.collection("attendance_pings").document(doc_id).set(ping)

print("🎯 Cloud database successfully populated with all testing conditions!")