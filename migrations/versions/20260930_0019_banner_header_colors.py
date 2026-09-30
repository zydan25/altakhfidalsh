"""Add configurable banner fixed-header and overscroll colors."""
from alembic import op
import sqlalchemy as sa

revision = "20260930_0019"
down_revision = "20260930_0018"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return

    existing = {column["name"] for column in inspector.get_columns("banners")}
    columns = [
        (
            "header_top_background_color",
            sa.Column(
                "header_top_background_color",
                sa.String(length=20),
                nullable=False,
                server_default="#111827",
            ),
        ),
        (
            "header_category_text_color",
            sa.Column(
                "header_category_text_color",
                sa.String(length=20),
                nullable=False,
                server_default="#ffffff",
            ),
        ),
        (
            "header_category_active_color",
            sa.Column(
                "header_category_active_color",
                sa.String(length=20),
                nullable=False,
                server_default="#ffffff",
            ),
        ),
    ]
    for name, column in columns:
        if name not in existing:
            op.add_column("banners", column)

    op.alter_column(
        "banners",
        "header_top_background_color",
        server_default=None,
    )
    op.alter_column(
        "banners",
        "header_category_text_color",
        server_default=None,
    )
    op.alter_column(
        "banners",
        "header_category_active_color",
        server_default=None,
    )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return

    columns = {column["name"] for column in inspector.get_columns("banners")}
    for name in (
        "header_category_active_color",
        "header_category_text_color",
        "header_top_background_color",
    ):
        if name in columns:
            op.drop_column("banners", name)
