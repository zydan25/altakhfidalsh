from flask import Flask

from config import Config
from .extensions import db, migrate


def create_app(config_class=Config):
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )
    app.config.from_object(config_class)

    db.init_app(app)
    migrate.init_app(app, db)

    from . import models  # noqa: F401
    from .api import api_bp
    from .admin import admin_bp

    app.register_blueprint(api_bp, url_prefix="/api/v1")
    app.register_blueprint(admin_bp, url_prefix="/admin")

    @app.get("/health")
    def health():
        return {
            "ok": True,
            "service": "altakhfidalsh",
            "version": "0.2.0",
        }

    return app
