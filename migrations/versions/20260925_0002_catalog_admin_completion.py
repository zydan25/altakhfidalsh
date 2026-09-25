"""Complete catalog/admin schema additions.

Adds product slugs and color-specific product media while remaining safe for
databases where the bootstrap migration already created the columns.
"""
from alembic import op
import sqlalchemy as sa


revision = "20260925_0002"
down_revision = "20260925_0001"
branch_labels = None
depends_on = None


def _has_column(table_name, column_name):
    inspector = sa.inspect(op.get_bind())
    return column_name in {c["name"] for c in inspector.get_columns(table_name)}


def upgrade():
    bind = op.get_bind()

    if not _has_column("products", "slug"):
        op.add_column("products", sa.Column("slug", sa.String(length=220), nullable=True))
        bind.execute(sa.text("UPDATE products SET slug = 'product-' || id WHERE slug IS NULL OR slug = ''"))
        op.alter_column("products", "slug", nullable=False)
        inspector = sa.inspect(bind)
        unique_names = {c["name"] for c in inspector.get_unique_constraints("products")}
        if "uq_products_slug" not in unique_names:
            op.create_unique_constraint("uq_products_slug", "products", ["slug"])

    if not _has_column("product_media", "color_id"):
        op.add_column(
            "product_media",
            sa.Column("color_id", sa.Integer(), nullable=True),
        )
        op.create_foreign_key(
            "fk_product_media_color_id",
            "product_media",
            "colors",
            ["color_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if _has_column("product_media", "color_id"):
        fks = {fk["name"] for fk in inspector.get_foreign_keys("product_media") if fk.get("name")}
        if "fk_product_media_color_id" in fks:
            op.drop_constraint("fk_product_media_color_id", "product_media", type_="foreignkey")
        op.drop_column("product_media", "color_id")
    if _has_column("products", "slug"):
        uniques = {c["name"] for c in inspector.get_unique_constraints("products") if c.get("name")}
        if "uq_products_slug" in uniques:
            op.drop_constraint("uq_products_slug", "products", type_="unique")
        op.drop_column("products", "slug")
