"""Add configurable product/body columns to size guides.

Revision ID: 20261006_0030
Revises: 20261003_0029
"""
from alembic import op
import sqlalchemy as sa

revision = "20261006_0030"
down_revision = "20261003_0029"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("size_guides")}
    if "product_columns_json" not in columns:
        op.add_column(
            "size_guides",
            sa.Column("product_columns_json", sa.JSON(), nullable=False, server_default="[]"),
        )
    if "body_columns_json" not in columns:
        op.add_column(
            "size_guides",
            sa.Column("body_columns_json", sa.JSON(), nullable=False, server_default="[]"),
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("size_guides")}
    for name in ("body_columns_json", "product_columns_json"):
        if name in columns:
            op.drop_column("size_guides", name)
