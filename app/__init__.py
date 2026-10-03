from pathlib import Path

from flask import Flask, render_template, send_from_directory
from flask_cors import CORS

from config import Config
from .extensions import db, migrate


def create_app(config_class=Config):
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )
    app.config.from_object(config_class)
    CORS(
        app,
        resources={r"/api/*": {"origins": app.config.get("CORS_ORIGINS", "*")}},
        supports_credentials=True,
    )

    db.init_app(app)
    migrate.init_app(app, db)

    from . import models  # noqa: F401
    from .api import api_bp
    from .admin import admin_bp
    from .modules import register_module_blueprints
    from .webhooks import webhooks_bp

    app.register_blueprint(api_bp, url_prefix="/api/v1")
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(webhooks_bp)
    register_module_blueprints(app)

    @app.get("/policies")
    def policies_page():
        from .models import AppSetting, ShippingPolicy, ReturnPolicy
        privacy=AppSetting.query.filter_by(group_code="storefront",key="privacy_policy").first()
        shipping=ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.id.desc()).first()
        returns=ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.id.desc()).first()
        return render_template("policies.html",privacy=privacy.value if privacy and privacy.value else "نحترم خصوصيتك ونستخدم بياناتك لتشغيل الطلبات وخدمة العملاء وتحسين تجربة المتجر.",shipping_policy=shipping,return_policy=returns)

    @app.get("/health")
    def health():
        return {
            "ok": True,
            "service": "altakhfidalsh",
            "version": "0.3.0",
        }

    @app.get("/media/<path:asset_path>")
    def media(asset_path):
        root = Path(app.config["MEDIA_ROOT"]).resolve()
        return send_from_directory(root, asset_path)

    return app
