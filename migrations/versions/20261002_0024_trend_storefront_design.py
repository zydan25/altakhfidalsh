"""Add dynamic responsive storefront settings and explicit trend slot images."""
from alembic import op
import sqlalchemy as sa


revision = "20261002_0024"
down_revision = "20261002_0023"
branch_labels = None
depends_on = None


def _columns(table_name):
    return {c["name"] for c in sa.inspect(op.get_bind()).get_columns(table_name)}


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if "trends" in inspector.get_table_names():
        cols = _columns("trends")
        if "settings_json" not in cols:
            op.add_column(
                "trends",
                sa.Column(
                    "settings_json",
                    sa.JSON(),
                    nullable=False,
                    server_default=sa.text("'{}'"),
                ),
            )

    if "trend_products" in inspector.get_table_names():
        cols = _columns("trend_products")
        if "image_asset_id" not in cols:
            op.add_column(
                "trend_products",
                sa.Column(
                    "image_asset_id",
                    sa.Integer(),
                    sa.ForeignKey("media_assets.id", ondelete="SET NULL"),
                    nullable=True,
                ),
            )
        if "settings_json" not in cols:
            op.add_column(
                "trend_products",
                sa.Column(
                    "settings_json",
                    sa.JSON(),
                    nullable=False,
                    server_default=sa.text("'{}'"),
                ),
            )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if "trend_products" in inspector.get_table_names():
        cols = _columns("trend_products")
        if "settings_json" in cols:
            op.drop_column("trend_products", "settings_json")
        if "image_asset_id" in cols:
            op.drop_column("trend_products", "image_asset_id")

    if "trends" in inspector.get_table_names():
        cols = _columns("trends")
        if "settings_json" in cols:
            op.drop_column("trends", "settings_json")
