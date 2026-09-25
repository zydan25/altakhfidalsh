from flask import Blueprint
api_bp = Blueprint("api", __name__)
from . import health, pricing  # noqa: E402,F401
