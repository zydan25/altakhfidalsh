"""Add product-level storefront card overrides, delivery badges and recommendations.

Revision ID: 20261003_0026
Revises: 20261003_0025
"""
from alembic import op
import sqlalchemy as sa

revision = "20261003_0026"
down_revision = "20261003_0025"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("product_display_settings")}
    if "card_overrides_json" not in columns:
        op.add_column("product_display_settings", sa.Column("card_overrides_json", sa.JSON(), nullable=False, server_default="{}"))
    if "delivery_badges_json" not in columns:
        op.add_column("product_display_settings", sa.Column("delivery_badges_json", sa.JSON(), nullable=False, server_default="[]"))
    if "recommendation_settings_json" not in columns:
        op.add_column("product_display_settings", sa.Column("recommendation_settings_json", sa.JSON(), nullable=False, server_default="{}"))

def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("product_display_settings")}
    for name in ("recommendation_settings_json", "delivery_badges_json", "card_overrides_json"):
        if name in columns:
            op.drop_column("product_display_settings", name)
