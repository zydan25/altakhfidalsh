from flask import render_template

from .context import build_admin_context


def register_whatsapp_admin(admin_bp):
    @admin_bp.get("/whatsapp")
    def whatsapp():
        from flask import current_app
        return render_template(
            "admin/whatsapp.html",
            title="WhatsApp",
            whatsapp_session=current_app.config.get("WHATSAPP_SESSION", "basheer"),
            whatsapp_base_url=current_app.config.get("WHATSAPP_BASE_URL", "https://whatsapp.alattab.site"),
            **build_admin_context(),
        )
