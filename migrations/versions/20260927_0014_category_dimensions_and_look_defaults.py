"""Add independent home category dimensions and normalize compact look defaults."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0014"
down_revision = "20260927_0013"
branch_labels = None
depends_on = None


def _columns(bind, table):
    return {c["name"] for c in sa.inspect(bind).get_columns(table)}


def upgrade():
    bind = op.get_bind()
    cols = _columns(bind, "category_home_display_settings")

    if "item_width" not in cols:
        op.add_column(
            "category_home_display_settings",
            sa.Column("item_width", sa.Integer(), nullable=False, server_default="64"),
        )
    if "item_height" not in cols:
        op.add_column(
            "category_home_display_settings",
            sa.Column("item_height", sa.Integer(), nullable=False, server_default="64"),
        )

    bind.execute(sa.text(
        "UPDATE category_home_display_settings "
        "SET item_width = COALESCE(item_size, 64) "
        "WHERE item_width IS NULL OR item_width <= 0"
    ))
    bind.execute(sa.text(
        "UPDATE category_home_display_settings "
        "SET item_height = COALESCE(item_size, 64) "
        "WHERE item_height IS NULL OR item_height <= 0"
    ))

    # The previous application defaults were 160x220. Normalize only rows
    # that still carry that exact untouched pair to the new 90x110 defaults.
    bind.execute(sa.text(
        "UPDATE looks SET card_width = 90, card_height = 110 "
        "WHERE card_width = 160 AND card_height = 220"
    ))


def downgrade():
    bind = op.get_bind()
    cols = _columns(bind, "category_home_display_settings")
    if "item_height" in cols:
        op.drop_column("category_home_display_settings", "item_height")
    if "item_width" in cols:
        op.drop_column("category_home_display_settings", "item_width")
