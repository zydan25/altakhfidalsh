from flask import Blueprint

api_bp = Blueprint("system_module_api", __name__, url_prefix="/system")
from . import api  # noqa: E402,F401
