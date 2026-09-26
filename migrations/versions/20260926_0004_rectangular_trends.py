"""Create rectangular trend content and its three product slots."""
from alembic import op
import sqlalchemy as sa


revision = "20260926_0004"
down_revision = "20260925_0003"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(table_name):
    return _inspector().has_table(table_name)


def _has_index(table_name, index_name):
    return index_name in {item["name"] for item in _inspector().get_indexes(table_name)}


def upgrade():
    if not _has_table("trends"):
        op.create_table(
            "trends",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "hashtag_id",
                sa.Integer(),
                sa.ForeignKey("hashtags.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("promo_text", sa.String(length=300), nullable=False),
            sa.Column("duration_days", sa.Integer(), nullable=False, server_default="8"),
            sa.Column(
                "background_asset_id",
                sa.Integer(),
                sa.ForeignKey("media_assets.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("status", sa.String(length=40), nullable=False, server_default="draft"),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )

    if not _has_index("trends", "ix_trend_active_sort"):
        op.create_index(
            "ix_trend_active_sort",
            "trends",
            ["is_active", "status", "sort_order"],
        )
    if not _has_index("trends", "ix_trend_hashtag"):
        op.create_index(
            "ix_trend_hashtag",
            "trends",
            ["hashtag_id", "is_active"],
        )

    if not _has_table("trend_products"):
        op.create_table(
            "trend_products",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "trend_id",
                sa.Integer(),
                sa.ForeignKey("trends.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "product_id",
                sa.Integer(),
                sa.ForeignKey("products.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("slot", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("trend_id", "slot", name="uq_trend_product_slot"),
            sa.UniqueConstraint("trend_id", "product_id", name="uq_trend_product_product"),
            sa.CheckConstraint("slot >= 0 AND slot < 3", name="ck_trend_product_slot"),
        )

    if not _has_index("trend_products", "ix_trend_product_trend"):
        op.create_index(
            "ix_trend_product_trend",
            "trend_products",
            ["trend_id", "slot"],
        )


def downgrade():
    if _has_table("trend_products"):
        if _has_index("trend_products", "ix_trend_product_trend"):
            op.drop_index("ix_trend_product_trend", table_name="trend_products")
        op.drop_table("trend_products")
    if _has_table("trends"):
        if _has_index("trends", "ix_trend_hashtag"):
            op.drop_index("ix_trend_hashtag", table_name="trends")
        if _has_index("trends", "ix_trend_active_sort"):
            op.drop_index("ix_trend_active_sort", table_name="trends")
        op.drop_table("trends")
