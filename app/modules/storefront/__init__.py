from flask import Blueprint

api_bp = Blueprint("storefront_module_api", __name__, url_prefix="/storefront")
from . import api  # noqa: E402,F401
