from flask import Blueprint

api_bp = Blueprint("catalog_module_api", __name__, url_prefix="/catalog")
from . import api  # noqa: E402,F401
