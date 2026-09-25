from flask import Blueprint

api_bp = Blueprint("support_module_api", __name__)
from . import api  # noqa: E402,F401
