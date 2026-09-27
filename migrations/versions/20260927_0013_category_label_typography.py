"""Add configurable typography for home category-circle labels."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0013"
down_revision = "20260927_0012"
branch_labels = None
depends_on = None


def _has_column(bind, table, column):
    return column in {c["name"] for c in sa.inspect(bind).get_columns(table)}


def upgrade():
    bind = op.get_bind()
    if not _has_column(bind, "category_home_display_settings", "item_label_font_size"):
        op.add_column(
            "category_home_display_settings",
            sa.Column(
                "item_label_font_size",
                sa.Integer(),
                nullable=False,
                server_default="9",
            ),
        )
    if not _has_column(bind, "category_home_display_settings", "item_label_bold"):
        op.add_column(
            "category_home_display_settings",
            sa.Column(
                "item_label_bold",
                sa.Boolean(),
                nullable=False,
                server_default=sa.true(),
            ),
        )
    bind.execute(
        sa.text(
            "UPDATE category_home_display_settings "
            "SET item_label_font_size = 9 "
            "WHERE item_label_font_size IS NULL"
        )
    )
    bind.execute(
        sa.text(
            "UPDATE category_home_display_settings "
            "SET item_label_bold = TRUE "
            "WHERE item_label_bold IS NULL"
        )
    )


def downgrade():
    bind = op.get_bind()
    if _has_column(bind, "category_home_display_settings", "item_label_bold"):
        op.drop_column("category_home_display_settings", "item_label_bold")
    if _has_column(bind, "category_home_display_settings", "item_label_font_size"):
        op.drop_column("category_home_display_settings", "item_label_font_size")
