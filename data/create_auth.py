import firebase_admin
from firebase_admin import credentials, auth

# 1. Initialize admin privileges with your service key passport
cred = credentials.Certificate("service_key.json")
firebase_admin.initialize_app(cred)

print("🔒 Admin SDK connected. Initializing user creation inside Firebase Auth Vault...\n")

# 2. Complete mapping dataset from our normalized design specs
# We pass the EXACT same matching keys to tie into your current Firestore data!
users_to_authenticate = [
    {"uid": "auth_uid_admin_amy_492kLpXq", "email": "amy@uni.edu", "password": "AmySecurePass123!"},
    {"uid": "auth_uid_lecA_alice_103mNqRt", "email": "alice@uni.edu", "password": "AliceSecurePass123!"},
    {"uid": "auth_uid_lecB_jeremy_504pStV", "email": "jeremy@uni.edu", "password": "JeremySecurePass123!"},
    {"uid": "auth_uid_lecC_sam_918vWxYzAb", "email": "sam@uni.edu", "password": "SamSecurePass123!"},
    {"uid": "auth_uid_stu01_john_382kLpQm", "email": "john@uni.edu", "password": "JohnSecurePass123!"},
    {"uid": "auth_uid_stu02_jane_749mNqRt", "email": "jane@uni.edu", "password": "JaneSecurePass123!"},
    {"uid": "auth_uid_stu03_max_105pStVwX", "email": "max@uni.edu", "password": "MaxSecurePass123!"},
    {"uid": "auth_uid_stu04_kain_837vWxYz", "email": "kain@uni.edu", "password": "KainSecurePass123!"},
    {"uid": "auth_uid_stu05_tom_294kLpQmZ", "email": "tom@uni.edu", "password": "TomSecurePass123!"},
    {"uid": "auth_uid_stu06_mace_830mNqRt", "email": "mace@uni.edu", "password": "MaceSecurePass123!"},
    {"uid": "auth_uid_stu07_kim_472pStVwX", "email": "kim@uni.edu", "password": "KimSecurePass123!"},
    {"uid": "auth_uid_stu08_mann_193vWxYz", "email": "mannny@uni.edu", "password": "MannnySecurePass123!"}
]

# 3. Loop through and execute provisioning handshakes
success_count = 0
for account in users_to_authenticate:
    try:
        # Bypassing normal registration checks to explicitly define our own UID strings
        user_record = auth.create_user(
            uid=account["uid"],
            email=account["email"],
            password=account["password"]
        )
        print(f"✅ Account Provisioned: {user_record.email} ──> Matches UID: {user_record.uid}")
        success_count += 1
        
    except Exception as e:
        # Prevents crashing if you accidentally run the script twice for an existing user
        print(f"⚠️ Skipping account entry for {account['email']}: User already exists or error occurred.")

print(f"\n🎯 Provisioning Finished. Successfully initialized {success_count}/12 login vaults.")