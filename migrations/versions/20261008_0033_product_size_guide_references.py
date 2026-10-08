"""Add product-to-size-guide assignments with display ordering.

Revision ID: 20261008_0033
Revises: 20261007_0032
"""
from alembic import op
import sqlalchemy as sa


revision = "20261008_0033"
down_revision = "20261007_0032"
branch_labels = None
depends_on = None


def _has_table(table_name):
    return sa.inspect(op.get_bind()).has_table(table_name)


def _has_index(table_name, index_name):
    return index_name in {
        x["name"] for x in sa.inspect(op.get_bind()).get_indexes(table_name)
    }


def upgrade():
    if not _has_table("product_size_guide_references"):
        op.create_table(
            "product_size_guide_references",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "product_id",
                sa.Integer(),
                sa.ForeignKey("products.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "guide_id",
                sa.Integer(),
                sa.ForeignKey("size_guides.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.func.now(),
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.func.now(),
            ),
            sa.UniqueConstraint(
                "product_id",
                "guide_id",
                name="uq_product_size_guide_reference",
            ),
        )
    if not _has_index(
        "product_size_guide_references",
        "ix_product_size_guide_reference_product",
    ):
        op.create_index(
            "ix_product_size_guide_reference_product",
            "product_size_guide_references",
            ["product_id", "sort_order"],
        )


def downgrade():
    if _has_table("product_size_guide_references"):
        if _has_index(
            "product_size_guide_references",
            "ix_product_size_guide_reference_product",
        ):
            op.drop_index(
                "ix_product_size_guide_reference_product",
                table_name="product_size_guide_references",
            )
        op.drop_table("product_size_guide_references")
