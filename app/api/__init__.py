from flask import Blueprint

api_bp = Blueprint("api", __name__)

from . import catalog, health, pricing  # noqa: E402,F401
