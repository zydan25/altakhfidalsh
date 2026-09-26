"""Add Style tab look collections for banner and storefront targeting."""

from alembic import op
import sqlalchemy as sa


revision = "20260926_0008"
down_revision = "20260926_0007"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def upgrade():
    if not _has_table("looks"):
        op.create_table(
            "looks",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("name", sa.String(length=180), nullable=False),
            sa.Column("slug", sa.String(length=200), nullable=False, unique=True),
            sa.Column("cover_asset_id", sa.Integer(), sa.ForeignKey("media_assets.id", ondelete="SET NULL")),
            sa.Column("description", sa.Text()),
            sa.Column("status", sa.String(length=40), nullable=False, server_default="draft"),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("starts_at", sa.DateTime(timezone=True)),
            sa.Column("ends_at", sa.DateTime(timezone=True)),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_look_active_sort", "looks", ["is_active", "status", "sort_order", "starts_at", "ends_at"])
    if not _has_table("look_products"):
        op.create_table(
            "look_products",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("look_id", sa.Integer(), sa.ForeignKey("looks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("look_id", "product_id", name="uq_look_product"),
        )
        op.create_index("ix_look_product_sort", "look_products", ["look_id", "sort_order"])


def downgrade():
    if _has_table("look_products"):
        indexes = {x["name"] for x in _inspector().get_indexes("look_products")}
        if "ix_look_product_sort" in indexes:
            op.drop_index("ix_look_product_sort", table_name="look_products")
        op.drop_table("look_products")
    if _has_table("looks"):
        indexes = {x["name"] for x in _inspector().get_indexes("looks")}
        if "ix_look_active_sort" in indexes:
            op.drop_index("ix_look_active_sort", table_name="looks")
        op.drop_table("looks")
