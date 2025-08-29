# backend_python/app/firebase_client.py
import os
import firebase_admin
from firebase_admin import credentials, firestore

def init_firebase():
    cred_path = os.getenv("FIREBASE_CREDENTIAL", "firebase_key.json")
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
    return firestore.client()

# Usage: db = init_firebase()
