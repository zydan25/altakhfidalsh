from flask import Blueprint

from .operations import register_operation_routes
from .routes import register_admin_routes
from .security import init_admin_security

admin_bp = Blueprint(
    "admin",
    __name__,
    template_folder="templates",
    static_folder="static",
)
register_admin_routes(admin_bp)
register_operation_routes(admin_bp)
init_admin_security(admin_bp)
