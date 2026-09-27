"""Add per-scope visibility for the customer-home looks strip."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0012"
down_revision = "20260927_0011"
branch_labels = None
depends_on = None


def _has_column(bind, table, column):
    return column in {c["name"] for c in sa.inspect(bind).get_columns(table)}


def upgrade():
    bind = op.get_bind()
    if not _has_column(bind, "category_home_display_settings", "show_looks_strip"):
        op.add_column(
            "category_home_display_settings",
            sa.Column(
                "show_looks_strip",
                sa.Boolean(),
                nullable=False,
                server_default=sa.true(),
            ),
        )
        bind.execute(
            sa.text(
                "UPDATE category_home_display_settings "
                "SET show_looks_strip = TRUE "
                "WHERE show_looks_strip IS NULL"
            )
        )


def downgrade():
    bind = op.get_bind()
    if _has_column(bind, "category_home_display_settings", "show_looks_strip"):
        op.drop_column("category_home_display_settings", "show_looks_strip")
