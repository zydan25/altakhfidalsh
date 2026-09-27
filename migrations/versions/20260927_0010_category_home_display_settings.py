"""Configurable customer-home category grid settings."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0010"
down_revision = "20260926_0009"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "category_home_display_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("scope_key", sa.String(length=80), nullable=False),
        sa.Column(
            "category_id",
            sa.Integer(),
            sa.ForeignKey("categories.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("grid_rows", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("show_coupon_strip", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("item_shape", sa.String(length=20), nullable=False, server_default="circle"),
        sa.Column("item_size", sa.Integer(), nullable=False, server_default="64"),
        sa.Column("item_spacing", sa.Integer(), nullable=False, server_default="6"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("scope_key", name="uq_category_home_display_scope"),
        sa.CheckConstraint("grid_rows >= 1 AND grid_rows <= 6", name="ck_category_home_grid_rows"),
        sa.CheckConstraint("item_size >= 42 AND item_size <= 110", name="ck_category_home_item_size"),
        sa.CheckConstraint("item_spacing >= 0 AND item_spacing <= 24", name="ck_category_home_item_spacing"),
        sa.CheckConstraint(
            "item_shape IN ('circle','rounded','square')",
            name="ck_category_home_item_shape",
        ),
    )
    op.create_index(
        "ix_category_home_display_category",
        "category_home_display_settings",
        ["category_id"],
    )
    op.create_index(
        "ix_category_home_display_scope",
        "category_home_display_settings",
        ["scope_key"],
        unique=True,
    )

    # Global "all" configuration. Root categories fall back to this until
    # their own scope is configured in the admin UI.
    op.execute(
        sa.text(
            """
            INSERT INTO category_home_display_settings
                (scope_key, category_id, grid_rows, show_coupon_strip, item_shape, item_size, item_spacing)
            VALUES ('all', NULL, 2, TRUE, 'circle', 64, 6)
            """
        )
    )


def downgrade():
    op.drop_index("ix_category_home_display_scope", table_name="category_home_display_settings")
    op.drop_index("ix_category_home_display_category", table_name="category_home_display_settings")
    op.drop_table("category_home_display_settings")
