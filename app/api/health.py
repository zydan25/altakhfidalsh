from . import api_bp

@api_bp.get("/health")
def api_health():
    return {"ok": True, "api": "v1"}
