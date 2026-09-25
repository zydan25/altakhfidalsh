from flask import Blueprint

api_bp = Blueprint("promotions_module_api", __name__, url_prefix="/promotions")
from . import api  # noqa: E402,F401
