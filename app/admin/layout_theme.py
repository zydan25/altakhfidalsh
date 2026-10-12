from flask import render_template, request

from ..extensions import db
from ..models import AppSetting
from .context import build_admin_context


def register_layout_theme_route(admin_bp):
    @admin_bp.route("/system/layout", methods=["GET", "POST"])
    def layout_theme():
        error = None
        success = None
        current_theme = "classic"

        try:
            row = AppSetting.query.filter_by(
                group_code="theme", key="layout_theme"
            ).first()
            if row and row.value in {"classic", "water"}:
                current_theme = row.value

            if request.method == "POST":
                selected = (request.form.get("layout_theme") or "").strip()
                if selected not in {"classic", "water"}:
                    raise ValueError("اختر أحد الثيمين المتاحين.")

                if row is None:
                    row = AppSetting(
                        group_code="theme",
                        key="layout_theme",
                        value=selected,
                        value_type="text",
                    )
                    db.session.add(row)
                else:
                    row.value = selected
                    row.value_type = "text"

                db.session.commit()
                current_theme = selected
                success = "تم حفظ مظهر لوحة الإدارة."

        except (ValueError, TypeError) as exc:
            db.session.rollback()
            error = str(exc)
        except Exception:
            db.session.rollback()
            error = "تعذر حفظ المظهر. أعد المحاولة."

        return render_template(
            "admin/layout_theme.html",
            title="مظهر لوحة الإدارة",
            current_theme=current_theme,
            error=error,
            success=success,
            **build_admin_context(),
        )
