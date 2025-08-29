# backend_python/app/main.py
import os
import logging
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from dotenv import load_dotenv

# --------------------------------------------------
# Logging setup
# --------------------------------------------------
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# --------------------------------------------------
# FastAPI App
# --------------------------------------------------
app = FastAPI(title="RapidResQ Bridge", version="1.0.0")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": f"Internal Server Error: {str(exc)}"},
    )

# --------------------------------------------------
# Environment
# --------------------------------------------------
load_dotenv()
USE_FIREBASE = os.getenv("USE_FIREBASE", "false").lower() == "true"

# --------------------------------------------------
# Firebase (optional)
# --------------------------------------------------
db = None
alerts_ref = None
if USE_FIREBASE:
    try:
        from firebase_client import init_firebase
        from firebase_admin import firestore as fb_firestore
        db = init_firebase()
        alerts_ref = db.collection("alerts")
        logger.info("Firebase initialized successfully")
    except Exception as fe:
        logger.warning(f"Firebase init failed: {fe}")
        db = None
        alerts_ref = None
        USE_FIREBASE = False  # disable to avoid runtime errors

# --------------------------------------------------
# ICP Bridge Client
# --------------------------------------------------
from icp_client import (
    send_alert_to_icp,
    get_active_alerts_from_icp,
    resolve_alert_on_icp,
    cancel_alert_on_icp,
)

# --------------------------------------------------
# Models
# --------------------------------------------------
class AlertIn(BaseModel):
    reporter: str
    message: Optional[str] = "Need Help"
    lat: float
    lon: float


class ResolveIn(BaseModel):
    alert_id: str
    responder: str


class CancelIn(BaseModel):
    alert_id: str


# --------------------------------------------------
# Routes
# --------------------------------------------------
@app.get("/health")
def health():
    return {"status": "ok", "firebase": USE_FIREBASE}


@app.get("/alerts/active")
def alerts_active():
    ok, alerts = get_active_alerts_from_icp()
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to fetch alerts from ICP")
    return {"alerts": alerts}


@app.post("/alerts/resolve")
def resolve_alert(payload: ResolveIn):
    ok, result = resolve_alert_on_icp(payload.alert_id, payload.responder)
    if not ok:
        raise HTTPException(status_code=500, detail=result)
    return {"status": "ok", **result}


@app.post("/send_alert")
def send_alert(payload: AlertIn):
    """
    1) Write to Firestore (if enabled, best-effort)
    2) Call ICP canister and return JSON
    """
    firestore_id = None

    # Firebase write (optional, non-fatal)
    if USE_FIREBASE and alerts_ref is not None:
        try:
            doc = {
                "reporter": payload.reporter,
                "message": payload.message or "Need Help",
                "lat": float(payload.lat),
                "lon": float(payload.lon),
                "timestamp": fb_firestore.SERVER_TIMESTAMP,
                "status": "active",
            }
            doc_ref = alerts_ref.add(doc)
            firestore_id = doc_ref[1].id
        except Exception as e:
            logger.warning(f"Firestore write failed: {e}")

    # ✅ ICP call (fixed: includes message)
    ok, icp_out = send_alert_to_icp(
        lat=float(payload.lat),
        lon=float(payload.lon),
        reporter=payload.reporter,
        message=payload.message or "Need Help",
    )
    if not ok:
        raise HTTPException(status_code=500, detail=icp_out)

    return {
        "status": "ok",
        "firestore_doc_id": firestore_id,
        "icp": icp_out,
    }


@app.post("/cancel_alert")
def cancel_alert(payload: CancelIn):
    ok, result = cancel_alert_on_icp(payload.alert_id)
    if not ok:
        raise HTTPException(status_code=500, detail=result)
    return {"status": "cancelled", "icp": result}
