"""Seed friendly defaults for the home coupon strip."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0016"
down_revision = "20260927_0015"
branch_labels = None
depends_on = None


def _has_table(bind, table):
    return sa.inspect(bind).has_table(table)


def upgrade():
    bind = op.get_bind()
    if not _has_table(bind, "home_coupon_display_settings") or not _has_table(bind, "home_coupon_cards"):
        return

    bind.execute(
        sa.text(
            """
            INSERT INTO home_coupon_display_settings
                (scope_key, root_category_id, enabled, auto_flip, flip_seconds,
                 cards_per_slide, card_height, card_radius, card_spacing,
                 title_font_size, subtitle_font_size, badge_font_size,
                 default_background_color, default_text_color,
                 default_badge_background_color, default_badge_text_color)
            SELECT
                'all', NULL, TRUE, TRUE, 4,
                2, 96, 18, 8,
                16, 11, 10,
                '#E2EFDA', '#1B5E20', '#166534', '#FFFFFF'
            WHERE NOT EXISTS (
                SELECT 1 FROM home_coupon_display_settings WHERE scope_key = 'all'
            )
            """
        )
    )

    bind.execute(
        sa.text(
            """
            INSERT INTO home_coupon_cards
                (is_active, name, root_category_id, display_type, code,
                 headline, subtitle, badge_text, icon_type,
                 background_color, text_color, badge_background_color,
                 badge_text_color, border_color, sort_order, duration)
            SELECT
                TRUE, 'بطاقة العرض #1', NULL, 'code', 'SAVE20',
                'خصم 20%', 'للطلبات المؤهلة', 'عرض خاص وحصري', 'percent',
                '#E2EFDA', '#1B5E20', '#166534', '#FFFFFF', '#B7D9A6', 10, NULL
            WHERE NOT EXISTS (
                SELECT 1 FROM home_coupon_cards WHERE code = 'SAVE20'
            )
            """
        )
    )
    bind.execute(
        sa.text(
            """
            INSERT INTO home_coupon_cards
                (is_active, name, root_category_id, display_type, code,
                 headline, subtitle, badge_text, icon_type,
                 background_color, text_color, badge_background_color,
                 badge_text_color, border_color, sort_order, duration)
            SELECT
                TRUE, 'بطاقة العرض #2', NULL, 'code', 'BONUS',
                'هدية مجانية', 'مع كل طلب جديد', 'مفاجأة لك 🎁', 'gift',
                '#FFF4E8', '#7A3E00', '#D97706', '#FFFFFF', '#F3D1A7', 20, NULL
            WHERE NOT EXISTS (
                SELECT 1 FROM home_coupon_cards WHERE code = 'BONUS'
            )
            """
        )
    )


def downgrade():
    bind = op.get_bind()
    if not _has_table(bind, "home_coupon_cards") or not _has_table(bind, "home_coupon_display_settings"):
        return
    bind.execute(sa.text("DELETE FROM home_coupon_cards WHERE code IN ('SAVE20', 'BONUS')"))
    bind.execute(
        sa.text(
            "DELETE FROM home_coupon_display_settings "
            "WHERE scope_key = 'all' "
            "AND enabled = TRUE AND auto_flip = TRUE AND flip_seconds = 4 "
            "AND cards_per_slide = 2 AND card_height = 96 AND card_radius = 18 "
            "AND card_spacing = 8 AND title_font_size = 16 AND subtitle_font_size = 11 "
            "AND badge_font_size = 10 AND default_background_color = '#E2EFDA' "
            "AND default_text_color = '#1B5E20'"
        )
    )
