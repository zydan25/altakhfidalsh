from flask import Blueprint

api_bp = Blueprint("commerce_module_api", __name__, url_prefix="/commerce")
from . import api  # noqa: E402,F401
