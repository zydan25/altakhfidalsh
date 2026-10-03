"""add per-product badge visual controls and ordering

Revision ID: 20261003_0025
Revises: 20261002_0024
"""

from alembic import op
import sqlalchemy as sa


revision = "20261003_0025"
down_revision = "20261002_0024"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "product_badges",
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "product_badges",
        sa.Column("settings_json", sa.JSON(), nullable=False, server_default="{}"),
    )
    op.execute(
        "UPDATE product_badges "
        "SET sort_order = CAST(position AS INTEGER) "
        "WHERE position IS NOT NULL AND position <> ''"
    )
    op.create_index(
        "ix_product_badge_product_sort",
        "product_badges",
        ["product_id", "sort_order", "id"],
        unique=False,
    )


def downgrade():
    op.drop_index("ix_product_badge_product_sort", table_name="product_badges")
    op.drop_column("product_badges", "settings_json")
    op.drop_column("product_badges", "sort_order")
