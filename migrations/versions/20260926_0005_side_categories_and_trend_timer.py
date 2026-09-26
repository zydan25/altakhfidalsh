"""Add trend timer/overlay fields and independent side-category navigation."""
from alembic import op
import sqlalchemy as sa


revision = "20260926_0005"
down_revision = "20260926_0004"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def _has_column(table, name):
    return name in {c["name"] for c in _inspector().get_columns(table)}


def _has_index(table, name):
    return name in {i["name"] for i in _inspector().get_indexes(table)}


def upgrade():
    # Ensure existing super admins receive the permissions required by the new UI.
    op.execute(
        """
        INSERT INTO permissions (code, name)
        VALUES
          ('side_category.view', 'عرض الفئات الجانبية'),
          ('side_category.manage', 'إدارة الفئات الجانبية')
        ON CONFLICT (code) DO NOTHING
        """
    )
    op.execute(
        """
        INSERT INTO role_permissions (role_id, permission_id)
        SELECT r.id, p.id
        FROM roles r
        JOIN permissions p
          ON p.code IN ('side_category.view', 'side_category.manage')
        WHERE r.code = 'super_admin'
        ON CONFLICT DO NOTHING
        """
    )

    if _has_table("trends"):
        additions = [
            ("timer_value", sa.Column("timer_value", sa.Integer())),
            ("timer_unit", sa.Column("timer_unit", sa.String(length=16), nullable=False, server_default="seconds")),
            ("timer_started_at", sa.Column("timer_started_at", sa.DateTime(timezone=True))),
            ("overlay_text", sa.Column("overlay_text", sa.String(length=220))),
            ("overlay_text_color", sa.Column("overlay_text_color", sa.String(length=20), nullable=False, server_default="#ffffff")),
            ("overlay_background_color", sa.Column("overlay_background_color", sa.String(length=40), nullable=False, server_default="rgba(17,24,39,.76)")),
        ]
        for name, column in additions:
            if not _has_column("trends", name):
                op.add_column("trends", column)

        # Normalize the initial default to the same HEX format accepted by the admin UI.
        op.execute(
            "UPDATE trends SET overlay_background_color = '#111827' "
            "WHERE overlay_background_color IS NULL OR overlay_background_color LIKE 'rgba(%'"
        )

        inspector = _inspector()
        checks = {c["name"] for c in inspector.get_check_constraints("trends")}
        if "ck_trend_timer_positive" not in checks:
            op.create_check_constraint(
                "ck_trend_timer_positive",
                "trends",
                "timer_value IS NULL OR timer_value > 0",
            )
        if "ck_trend_timer_unit" not in checks:
            op.create_check_constraint(
                "ck_trend_timer_unit",
                "trends",
                "timer_unit IN ('seconds','minutes')",
            )

    if not _has_table("side_categories"):
        op.create_table(
            "side_categories",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "root_category_id",
                sa.Integer(),
                sa.ForeignKey("categories.id", ondelete="RESTRICT"),
                nullable=False,
            ),
            sa.Column("name", sa.String(length=160), nullable=False),
            sa.Column("slug", sa.String(length=180), nullable=False),
            sa.Column(
                "badge_id",
                sa.Integer(),
                sa.ForeignKey("badges.id", ondelete="SET NULL"),
            ),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("root_category_id", "slug", name="uq_side_category_root_slug"),
        )

    if not _has_index("side_categories", "ix_side_category_root_sort"):
        op.create_index(
            "ix_side_category_root_sort",
            "side_categories",
            ["root_category_id", "sort_order", "is_active"],
        )

    if not _has_table("side_category_circles"):
        op.create_table(
            "side_category_circles",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "side_category_id",
                sa.Integer(),
                sa.ForeignKey("side_categories.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("name", sa.String(length=160), nullable=False),
            sa.Column("slug", sa.String(length=180), nullable=False),
            sa.Column(
                "image_asset_id",
                sa.Integer(),
                sa.ForeignKey("media_assets.id", ondelete="SET NULL"),
            ),
            sa.Column(
                "badge_id",
                sa.Integer(),
                sa.ForeignKey("badges.id", ondelete="SET NULL"),
            ),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("side_category_id", "slug", name="uq_side_category_circle_slug"),
        )

    if not _has_index("side_category_circles", "ix_side_category_circle_side_sort"):
        op.create_index(
            "ix_side_category_circle_side_sort",
            "side_category_circles",
            ["side_category_id", "sort_order", "is_active"],
        )

    if not _has_table("product_side_category_circles"):
        op.create_table(
            "product_side_category_circles",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "product_id",
                sa.Integer(),
                sa.ForeignKey("products.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column(
                "circle_id",
                sa.Integer(),
                sa.ForeignKey("side_category_circles.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("product_id", "circle_id", name="uq_product_side_category_circle"),
        )

    if not _has_index("product_side_category_circles", "ix_product_side_category_circle_product"):
        op.create_index(
            "ix_product_side_category_circle_product",
            "product_side_category_circles",
            ["product_id", "sort_order"],
        )
    if not _has_index("product_side_category_circles", "ix_product_side_category_circle_circle"):
        op.create_index(
            "ix_product_side_category_circle_circle",
            "product_side_category_circles",
            ["circle_id", "product_id"],
        )


def downgrade():
    if _has_table("product_side_category_circles"):
        for name in (
            "ix_product_side_category_circle_circle",
            "ix_product_side_category_circle_product",
        ):
            if _has_index("product_side_category_circles", name):
                op.drop_index(name, table_name="product_side_category_circles")
        op.drop_table("product_side_category_circles")

    if _has_table("side_category_circles"):
        if _has_index("side_category_circles", "ix_side_category_circle_side_sort"):
            op.drop_index("ix_side_category_circle_side_sort", table_name="side_category_circles")
        op.drop_table("side_category_circles")

    if _has_table("side_categories"):
        if _has_index("side_categories", "ix_side_category_root_sort"):
            op.drop_index("ix_side_category_root_sort", table_name="side_categories")
        op.drop_table("side_categories")

    if _has_table("trends"):
        inspector = _inspector()
        checks = {c["name"] for c in inspector.get_check_constraints("trends")}
        if "ck_trend_timer_positive" in checks:
            op.drop_constraint("ck_trend_timer_positive", "trends", type_="check")
        if "ck_trend_timer_unit" in checks:
            op.drop_constraint("ck_trend_timer_unit", "trends", type_="check")
        for name in (
            "timer_value",
            "timer_unit",
            "timer_started_at",
            "overlay_text",
            "overlay_text_color",
            "overlay_background_color",
        ):
            if _has_column("trends", name):
                op.drop_column("trends", name)
