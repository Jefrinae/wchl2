# backend_python/app/icp_client.py
import json
import os
import shlex
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Tuple, Optional

# ------------------- Config -------------------
DFX_NETWORK = os.getenv("DFX_NETWORK", "local")  # "local" or "ic"
DFX_IDENTITY = os.getenv("DFX_IDENTITY")         # optional identity name
USE_ICP = os.getenv("USE_ICP", "true").lower() == "true"  # Enable/disable ICP

# Directory containing dfx.json for the target canister project
DFX_PROJECT_DIR = os.getenv("DFX_PROJECT_DIR")
if DFX_PROJECT_DIR:
    DFX_PROJECT_DIR = str(Path(DFX_PROJECT_DIR).resolve())

# Auto-detect canister id if not set via env
CANISTER_NAME = os.getenv("CANISTER_NAME")
if not CANISTER_NAME and USE_ICP:
    # Try to read canister_ids.json from DFX_PROJECT_DIR first, then CWD
    candidate_paths = []
    try:
        if DFX_PROJECT_DIR:
            candidate_paths.append(str(Path(DFX_PROJECT_DIR) / f".dfx/{DFX_NETWORK}/canister_ids.json"))
        candidate_paths.append(f".dfx/{DFX_NETWORK}/canister_ids.json")
        for p in candidate_paths:
            if Path(p).is_file():
                with open(p) as f:
                    ids = json.load(f)
                    # Prefer named canister key if present
                    if "emergency_canister_backend" in ids:
                        val = ids["emergency_canister_backend"].get(DFX_NETWORK)
                        if isinstance(val, str) and len(val) > 0:
                            CANISTER_NAME = val
                            break
                    # Fallback: first string entry under network
                    for _, v in ids.items():
                        if isinstance(v, dict) and isinstance(v.get(DFX_NETWORK), str):
                            CANISTER_NAME = v[DFX_NETWORK]
                            break
                    if CANISTER_NAME:
                        break
    except Exception as e:
        print(f"[WARN] Could not auto-detect canister id: {e}")
    if not CANISTER_NAME:
        CANISTER_NAME = "emergency_canister_backend"  # fallback to canister name

# Method names
ADD_SOS_METHOD = os.getenv("ADD_SOS_METHOD", "add_sos")              # (text, float64, float64, text) -> text
LIST_ACTIVE_METHOD = os.getenv("LIST_ACTIVE_METHOD", "list_active")  # () -> vec Alert
RESOLVE_SOS_METHOD = os.getenv("RESOLVE_SOS_METHOD", "resolve_sos")  # (text, text) -> bool
CANCEL_SOS_METHOD = os.getenv("CANCEL_SOS_METHOD", "cancel_sos")     # (text) -> bool


# ------------------- Helpers -------------------
def _run(cmd: str, timeout: int = 20, cwd: Optional[str] = None) -> Tuple[bool, str]:
    """Run a shell command safely. Returns (success, stdout_or_stderr)."""
    try:
        proc = subprocess.run(
            shlex.split(cmd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            text=True,
            check=False,
            cwd=cwd,
        )
        if proc.returncode == 0:
            return True, proc.stdout.strip()
        else:
            err = (proc.stderr or "") + "\n" + (proc.stdout or "")
            return False, err.strip()
    except Exception as e:
        return False, str(e)


def _dfx_base() -> str:
    base = f"dfx canister --network {DFX_NETWORK}"
    if DFX_IDENTITY:
        base += f" --identity {DFX_IDENTITY}"
    return base


def _call_icp_json(method: str, candid_args: str = "") -> Tuple[bool, Any]:
    """Calls ICP canister with --output json and returns parsed JSON."""
    # Add --ingress-expiry to fix time synchronization issues
    cmd = f"{_dfx_base()} call {CANISTER_NAME} {method} {candid_args} --output json --ingress-expiry 300"
    ok, out = _run(cmd, cwd=DFX_PROJECT_DIR)
    if not ok:
        return False, {"error": out}

    try:
        data = json.loads(out)
        return True, data
    except json.JSONDecodeError:
        return False, {"error": "JSON parse failed", "raw": out}


def ensure_canister_id() -> Tuple[bool, str]:
    """Optional helper: Get canister id to confirm connectivity."""
    cmd = f"{_dfx_base()} id {CANISTER_NAME}"
    return _run(cmd, cwd=DFX_PROJECT_DIR)


# ------------------- Mock implementations for testing -------------------
def _mock_send_alert(reporter: str, lat: float, lon: float, message: str) -> Tuple[bool, Dict[str, Any]]:
    """Mock implementation when ICP is disabled"""
    import time
    alert_id = f"mock_{int(time.time())}_{hash((reporter, lat, lon, message)) % 10000}"
    return True, {"id": alert_id}

def _mock_get_active_alerts() -> Tuple[bool, List[Dict[str, Any]]]:
    """Mock implementation when ICP is disabled"""
    return True, []

def _mock_resolve_alert(alert_id: str, responder: str) -> Tuple[bool, Dict[str, Any]]:
    """Mock implementation when ICP is disabled"""
    return True, {"resolved": True}

def _mock_cancel_alert(alert_id: str) -> Tuple[bool, Dict[str, Any]]:
    """Mock implementation when ICP is disabled"""
    return True, {"cancelled": True}


# ------------------- High-level functions -------------------
def send_alert_to_icp(reporter: str, lat: float, lon: float, message: str) -> Tuple[bool, Dict[str, Any]]:
    """Calls add_sos(reporter: text, lat: float64, lon: float64, message: text) -> text"""
    if not USE_ICP:
        return _mock_send_alert(reporter, lat, lon, message)

    args = f"'(\"{reporter}\", {float(lat)}, {float(lon)}, \"{message}\")'"
    ok, data = _call_icp_json(ADD_SOS_METHOD, args)
    if not ok:
        return False, {"error": data}

    # Normalize return
    if isinstance(data, list) and len(data) == 1 and isinstance(data[0], str):
        return True, {"id": data[0]}
    if isinstance(data, dict):
        for k in ("Ok", "ok", "result", "value"):
            if k in data and isinstance(data[k], str):
                return True, {"id": data[k]}
    return True, {"raw": data}


def get_active_alerts_from_icp() -> Tuple[bool, List[Dict[str, Any]]]:
    """Calls list_active() -> vec Alert"""
    if not USE_ICP:
        return _mock_get_active_alerts()

    ok, data = _call_icp_json(LIST_ACTIVE_METHOD, "")
    if not ok:
        return False, []

    alerts: List[Dict[str, Any]] = []

    def _coerce_alert(x: Any) -> Optional[Dict[str, Any]]:
        if isinstance(x, dict) and "lat" in x and "lon" in x:
            return {
                "id": x.get("id") or "",
                "reporter": x.get("reporter") or "",
                "lat": float(x.get("lat", 0.0)),
                "lon": float(x.get("lon", 0.0)),
                "timestamp": int(x.get("timestamp", 0)),
                "message": x.get("message", ""),
            }
        return None

    if isinstance(data, list):
        items = data[0] if (len(data) == 1 and isinstance(data[0], list)) else data
        for item in items:
            a = _coerce_alert(item)
            if a:
                alerts.append(a)

    elif isinstance(data, dict):
        for key in ("Ok", "ok", "value", "result"):
            if key in data and isinstance(data[key], list):
                for item in data[key]:
                    a = _coerce_alert(item)
                    if a:
                        alerts.append(a)
                break

    return True, alerts


def resolve_alert_on_icp(alert_id: str, responder: str) -> Tuple[bool, Dict[str, Any]]:
    """Calls resolve_sos(id: text, responder: text) -> bool"""
    if not USE_ICP:
        return _mock_resolve_alert(alert_id, responder)

    args = f"'(\"{alert_id}\", \"{responder}\")'"
    ok, data = _call_icp_json(RESOLVE_SOS_METHOD, args)
    if not ok:
        return False, {"error": data}

    result = None
    if isinstance(data, list) and len(data) == 1 and isinstance(data[0], bool):
        result = data[0]
    elif isinstance(data, dict):
        for k in ("Ok", "ok", "value", "result"):
            if k in data and isinstance(data[k], bool):
                result = data[k]
                break

    if isinstance(result, bool):
        return True, {"resolved": result}
    return True, {"raw": data}


def cancel_alert_on_icp(alert_id: str) -> Tuple[bool, Dict[str, Any]]:
    """Calls cancel_sos(id: text) -> bool"""
    if not USE_ICP:
        return _mock_cancel_alert(alert_id)

    args = f"'(\"{alert_id}\")'"
    ok, data = _call_icp_json(CANCEL_SOS_METHOD, args)
    if not ok:
        return False, {"error": data}

    result = None
    if isinstance(data, list) and len(data) == 1 and isinstance(data[0], bool):
        result = data[0]
    elif isinstance(data, dict):
        for k in ("Ok", "ok", "value", "result"):
            if k in data and isinstance(data[k], bool):
                result = data[k]
                break

    if isinstance(result, bool):
        return True, {"cancelled": result}
    return True, {"raw": data}
