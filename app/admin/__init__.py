from flask import Blueprint
from .routes import register_admin_routes

admin_bp = Blueprint("admin", __name__, template_folder="templates", static_folder="static")
register_admin_routes(admin_bp)
