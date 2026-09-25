from flask import Blueprint

api_bp = Blueprint("pricing_module_api", __name__, url_prefix="/pricing")
from . import api  # noqa: E402,F401
