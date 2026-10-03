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
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("product_badges")}

    # The project's initial bootstrap migration creates tables from the current
    # SQLAlchemy metadata. These guards keep this normal revision compatible
    # with fresh databases and with databases where the new fields already
    # exist because of that bootstrap.
    if "sort_order" not in columns:
        op.add_column(
            "product_badges",
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        )
    if "settings_json" not in columns:
        op.add_column(
            "product_badges",
            sa.Column("settings_json", sa.JSON(), nullable=False, server_default="{}"),
        )

    op.execute(
        sa.text(
            "UPDATE product_badges "
            "SET sort_order = CAST(position AS INTEGER) "
            "WHERE position IS NOT NULL AND position <> ''"
        )
    )

    indexes = {index["name"] for index in inspector.get_indexes("product_badges")}
    if "ix_product_badge_product_sort" not in indexes:
        op.create_index(
            "ix_product_badge_product_sort",
            "product_badges",
            ["product_id", "sort_order", "id"],
            unique=False,
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    indexes = {index["name"] for index in inspector.get_indexes("product_badges")}
    columns = {column["name"] for column in inspector.get_columns("product_badges")}
    if "ix_product_badge_product_sort" in indexes:
        op.drop_index("ix_product_badge_product_sort", table_name="product_badges")
    if "settings_json" in columns:
        op.drop_column("product_badges", "settings_json")
    if "sort_order" in columns:
        op.drop_column("product_badges", "sort_order")
