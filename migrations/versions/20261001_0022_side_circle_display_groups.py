"""Add global side-circle presentation settings and editorial display groups."""

from alembic import op
import sqlalchemy as sa

revision = "20261001_0022"
down_revision = "20261001_0021"
branch_labels = None
depends_on = None


def _has_table(bind, name):
    return sa.inspect(bind).has_table(name)


def _has_index(bind, table, name):
    return any(i.get("name") == name for i in sa.inspect(bind).get_indexes(table))


def upgrade():
    bind = op.get_bind()

    if not _has_table(bind, "side_circle_display_settings"):
        op.create_table(
            "side_circle_display_settings",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("scope_key", sa.String(length=40), nullable=False, server_default="all"),
            sa.Column("grid_columns", sa.Integer(), nullable=False, server_default="3"),
            sa.Column("item_width", sa.Integer(), nullable=False, server_default="88"),
            sa.Column("item_height", sa.Integer(), nullable=False, server_default="88"),
            sa.Column("item_shape", sa.String(length=20), nullable=False, server_default="circle"),
            sa.Column("item_corner_radius", sa.Integer(), nullable=False, server_default="18"),
            sa.Column("item_spacing", sa.Integer(), nullable=False, server_default="8"),
            sa.Column("item_label_font_size", sa.Integer(), nullable=False, server_default="10"),
            sa.Column("item_label_bold", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("section_spacing", sa.Integer(), nullable=False, server_default="14"),
            sa.Column("title_font_size", sa.Integer(), nullable=False, server_default="15"),
            sa.Column("show_empty_state", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("scope_key", name="uq_side_circle_display_scope"),
            sa.CheckConstraint("grid_columns >= 2 AND grid_columns <= 5", name="ck_side_circle_grid_columns"),
            sa.CheckConstraint("item_width >= 48 AND item_width <= 180", name="ck_side_circle_item_width"),
            sa.CheckConstraint("item_height >= 48 AND item_height <= 180", name="ck_side_circle_item_height"),
            sa.CheckConstraint("item_spacing >= 0 AND item_spacing <= 30", name="ck_side_circle_item_spacing"),
            sa.CheckConstraint("item_shape IN ('circle','rounded','square')", name="ck_side_circle_item_shape"),
        )

    if not _has_table(bind, "side_circle_display_groups"):
        op.create_table(
            "side_circle_display_groups",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("root_category_id", sa.Integer(), sa.ForeignKey("categories.id", ondelete="SET NULL"), nullable=True),
            sa.Column("name", sa.String(length=160), nullable=False),
            sa.Column("slug", sa.String(length=180), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("show_view_all", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("slug", name="uq_side_circle_display_group_slug"),
        )

    if not _has_index(bind, "side_circle_display_groups", "ix_side_circle_group_scope_sort"):
        op.create_index(
            "ix_side_circle_group_scope_sort",
            "side_circle_display_groups",
            ["root_category_id", "sort_order", "is_active"],
        )

    if not _has_table(bind, "side_circle_display_group_items"):
        op.create_table(
            "side_circle_display_group_items",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("group_id", sa.Integer(), sa.ForeignKey("side_circle_display_groups.id", ondelete="CASCADE"), nullable=False),
            sa.Column("circle_id", sa.Integer(), sa.ForeignKey("side_category_circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("group_id", "circle_id", name="uq_side_circle_display_group_item"),
        )

    if not _has_index(bind, "side_circle_display_group_items", "ix_side_circle_display_group_item_group_sort"):
        op.create_index(
            "ix_side_circle_display_group_item_group_sort",
            "side_circle_display_group_items",
            ["group_id", "sort_order"],
        )

    row = bind.execute(
        sa.text("SELECT id FROM side_circle_display_settings WHERE scope_key = 'all' LIMIT 1")
    ).first()
    if row is None:
        bind.execute(
            sa.text(
                """
                INSERT INTO side_circle_display_settings
                (scope_key, grid_columns, item_width, item_height, item_shape,
                 item_corner_radius, item_spacing, item_label_font_size,
                 item_label_bold, section_spacing, title_font_size, show_empty_state)
                VALUES ('all', 3, 88, 88, 'circle', 18, 8, 10, TRUE, 14, 15, TRUE)
                """
            )
        )


def downgrade():
    bind = op.get_bind()
    if _has_table(bind, "side_circle_display_group_items"):
        if _has_index(bind, "side_circle_display_group_items", "ix_side_circle_display_group_item_group_sort"):
            op.drop_index("ix_side_circle_display_group_item_group_sort", table_name="side_circle_display_group_items")
        op.drop_table("side_circle_display_group_items")
    if _has_table(bind, "side_circle_display_groups"):
        if _has_index(bind, "side_circle_display_groups", "ix_side_circle_group_scope_sort"):
            op.drop_index("ix_side_circle_group_scope_sort", table_name="side_circle_display_groups")
        op.drop_table("side_circle_display_groups")
    if _has_table(bind, "side_circle_display_settings"):
        op.drop_table("side_circle_display_settings")
