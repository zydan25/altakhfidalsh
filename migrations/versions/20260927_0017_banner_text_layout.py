"""Add independent banner text/button placement and typography settings."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0017"
down_revision = "20260927_0016"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return

    existing = {column["name"] for column in inspector.get_columns("banners")}
    columns = [
        ("button_position", sa.Column("button_position", sa.String(40), nullable=False, server_default="same")),
        ("overlay_font_size", sa.Column("overlay_font_size", sa.Integer(), nullable=False, server_default="13")),
        ("title_font_size", sa.Column("title_font_size", sa.Integer(), nullable=False, server_default="28")),
        ("description_font_size", sa.Column("description_font_size", sa.Integer(), nullable=False, server_default="16")),
        ("button_font_size", sa.Column("button_font_size", sa.Integer(), nullable=False, server_default="11")),
        ("button_radius", sa.Column("button_radius", sa.Integer(), nullable=False, server_default="0")),
        ("content_padding", sa.Column("content_padding", sa.Integer(), nullable=False, server_default="18")),
    ]
    for name, column in columns:
        if name not in existing:
            op.add_column("banners", column)

    checks = [
        ("ck_banner_overlay_font", "overlay_font_size >= 8 AND overlay_font_size <= 36"),
        ("ck_banner_title_font", "title_font_size >= 10 AND title_font_size <= 60"),
        ("ck_banner_description_font", "description_font_size >= 8 AND description_font_size <= 40"),
        ("ck_banner_button_font", "button_font_size >= 8 AND button_font_size <= 30"),
        ("ck_banner_button_radius", "button_radius >= 0 AND button_radius <= 40"),
        ("ck_banner_content_padding", "content_padding >= 0 AND content_padding <= 80"),
    ]
    existing_constraints = {x["name"] for x in inspector.get_check_constraints("banners")}
    for name, condition in checks:
        if name not in existing_constraints:
            op.create_check_constraint(name, "banners", condition)

    op.alter_column("banners", "button_position", server_default=None)
    op.alter_column("banners", "overlay_font_size", server_default=None)
    op.alter_column("banners", "title_font_size", server_default=None)
    op.alter_column("banners", "description_font_size", server_default=None)
    op.alter_column("banners", "button_font_size", server_default=None)
    op.alter_column("banners", "button_radius", server_default=None)
    op.alter_column("banners", "content_padding", server_default=None)


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return
    existing = {x["name"] for x in inspector.get_check_constraints("banners")}
    for name in [
        "ck_banner_content_padding",
        "ck_banner_button_radius",
        "ck_banner_button_font",
        "ck_banner_description_font",
        "ck_banner_title_font",
        "ck_banner_overlay_font",
    ]:
        if name in existing:
            op.drop_constraint(name, "banners", type_="check")

    columns = {column["name"] for column in inspector.get_columns("banners")}
    for name in [
        "content_padding",
        "button_radius",
        "button_font_size",
        "description_font_size",
        "title_font_size",
        "overlay_font_size",
        "button_position",
    ]:
        if name in columns:
            op.drop_column("banners", name)
