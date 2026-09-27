"""Add home coupon strip settings and cards."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0015"
down_revision = "20260927_0014"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "home_coupon_display_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("scope_key", sa.String(80), nullable=False, unique=True),
        sa.Column("root_category_id", sa.Integer(), sa.ForeignKey("categories.id", ondelete="CASCADE")),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("auto_flip", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("flip_seconds", sa.Integer(), nullable=False, server_default="4"),
        sa.Column("cards_per_slide", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("card_height", sa.Integer(), nullable=False, server_default="96"),
        sa.Column("card_radius", sa.Integer(), nullable=False, server_default="18"),
        sa.Column("card_spacing", sa.Integer(), nullable=False, server_default="8"),
        sa.Column("title_font_size", sa.Integer(), nullable=False, server_default="16"),
        sa.Column("subtitle_font_size", sa.Integer(), nullable=False, server_default="11"),
        sa.Column("badge_font_size", sa.Integer(), nullable=False, server_default="10"),
        sa.Column("default_background_color", sa.String(20), nullable=False, server_default="#E2EFDA"),
        sa.Column("default_text_color", sa.String(20), nullable=False, server_default="#1B5E20"),
        sa.Column("default_badge_background_color", sa.String(20), nullable=False, server_default="#166534"),
        sa.Column("default_badge_text_color", sa.String(20), nullable=False, server_default="#ffffff"),
        sa.CheckConstraint("flip_seconds >= 1 AND flip_seconds <= 120", name="ck_coupon_display_flip_seconds"),
        sa.CheckConstraint("cards_per_slide IN (1, 2)", name="ck_coupon_display_cards_per_slide"),
        sa.CheckConstraint("card_height >= 40 AND card_height <= 300", name="ck_coupon_display_height"),
        sa.CheckConstraint("card_radius >= 0 AND card_radius <= 100", name="ck_coupon_display_radius"),
        sa.CheckConstraint("card_spacing >= 0 AND card_spacing <= 40", name="ck_coupon_display_spacing"),
        sa.CheckConstraint("title_font_size >= 8 AND title_font_size <= 32", name="ck_coupon_display_title_font"),
        sa.CheckConstraint("subtitle_font_size >= 7 AND subtitle_font_size <= 24", name="ck_coupon_display_subtitle_font"),
        sa.CheckConstraint("badge_font_size >= 7 AND badge_font_size <= 22", name="ck_coupon_display_badge_font"),
    )
    op.create_index("ix_coupon_display_scope", "home_coupon_display_settings", ["root_category_id", "enabled"])

    op.create_table(
        "home_coupon_cards",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("name", sa.String(180), nullable=False),
        sa.Column("root_category_id", sa.Integer(), sa.ForeignKey("categories.id", ondelete="SET NULL")),
        sa.Column("display_type", sa.String(20), nullable=False, server_default="code"),
        sa.Column("code", sa.String(120)),
        sa.Column("headline", sa.String(220), nullable=False),
        sa.Column("subtitle", sa.String(300)),
        sa.Column("badge_text", sa.String(120)),
        sa.Column("icon_type", sa.String(40), nullable=False, server_default="percent"),
        sa.Column("target_type", sa.String(30)),
        sa.Column("target_id", sa.Integer()),
        sa.Column("target_url", sa.String(1000)),
        sa.Column("background_color", sa.String(20), nullable=False, server_default="#E2EFDA"),
        sa.Column("text_color", sa.String(20), nullable=False, server_default="#1B5E20"),
        sa.Column("badge_background_color", sa.String(20), nullable=False, server_default="#166534"),
        sa.Column("badge_text_color", sa.String(20), nullable=False, server_default="#ffffff"),
        sa.Column("border_color", sa.String(20)),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("duration", sa.Integer()),
        sa.Column("starts_at", sa.DateTime(timezone=True)),
        sa.Column("ends_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("display_type IN ('code','redirect')", name="ck_home_coupon_display_type"),
        sa.CheckConstraint("target_type IS NULL OR target_type IN ('category','product','hashtag','url')", name="ck_home_coupon_target_type"),
        sa.CheckConstraint("duration IS NULL OR (duration >= 1 AND duration <= 120)", name="ck_home_coupon_duration"),
    )
    op.create_index("ix_home_coupon_scope_sort", "home_coupon_cards", ["root_category_id", "is_active", "sort_order", "id"])


def downgrade():
    op.drop_index("ix_home_coupon_scope_sort", table_name="home_coupon_cards")
    op.drop_table("home_coupon_cards")
    op.drop_index("ix_coupon_display_scope", table_name="home_coupon_display_settings")
    op.drop_table("home_coupon_display_settings")
