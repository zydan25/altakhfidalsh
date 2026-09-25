from flask import Blueprint

api_bp = Blueprint("customer_module_api", __name__, url_prefix="/customer")
from . import api  # noqa: E402,F401
