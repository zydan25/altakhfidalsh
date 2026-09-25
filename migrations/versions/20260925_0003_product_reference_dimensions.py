"""Persist product-level reusable color and size selections.

Existing products are backfilled from their variants so the wizard exposes the
same dimensions immediately after deployment.
"""
from alembic import op
import sqlalchemy as sa


revision = "20260925_0003"
down_revision = "20260925_0002"
branch_labels = None
depends_on = None


def _has_table(table_name):
    return sa.inspect(op.get_bind()).has_table(table_name)


def _has_index(table_name, index_name):
    return index_name in {x["name"] for x in sa.inspect(op.get_bind()).get_indexes(table_name)}


def upgrade():
    if not _has_table("product_color_references"):
        op.create_table(
        "product_color_references",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="CASCADE"), nullable=False),
        sa.Column("color_id", sa.Integer(), sa.ForeignKey("colors.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("product_id", "color_id", name="uq_product_color_reference"),
    )
    if not _has_index("product_color_references", "ix_product_color_reference_product"):
        op.create_index(
            "ix_product_color_reference_product",
            "product_color_references",
            ["product_id", "sort_order"],
        )

    if not _has_table("product_size_references"):
        op.create_table(
        "product_size_references",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="CASCADE"), nullable=False),
        sa.Column("size_id", sa.Integer(), sa.ForeignKey("sizes.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("product_id", "size_id", name="uq_product_size_reference"),
    )
    if not _has_index("product_size_references", "ix_product_size_reference_product"):
        op.create_index(
            "ix_product_size_reference_product",
            "product_size_references",
            ["product_id", "sort_order"],
        )

    bind = op.get_bind()
    bind.execute(sa.text("""
        INSERT INTO product_color_references
            (product_id, color_id, sort_order, created_at, updated_at)
        SELECT DISTINCT
            pv.product_id, pv.color_id, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM product_variants pv
        WHERE pv.color_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM product_color_references pcr
              WHERE pcr.product_id = pv.product_id
                AND pcr.color_id = pv.color_id
          )
    """))
    bind.execute(sa.text("""
        INSERT INTO product_size_references
            (product_id, size_id, sort_order, created_at, updated_at)
        SELECT DISTINCT
            pv.product_id, pv.size_id, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM product_variants pv
        WHERE pv.size_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM product_size_references psr
              WHERE psr.product_id = pv.product_id
                AND psr.size_id = pv.size_id
          )
    """))


def downgrade():
    if _has_table("product_size_references"):
        if _has_index("product_size_references", "ix_product_size_reference_product"):
            op.drop_index("ix_product_size_reference_product", table_name="product_size_references")
        op.drop_table("product_size_references")
    if _has_table("product_color_references"):
        if _has_index("product_color_references", "ix_product_color_reference_product"):
            op.drop_index("ix_product_color_reference_product", table_name="product_color_references")
        op.drop_table("product_color_references")
