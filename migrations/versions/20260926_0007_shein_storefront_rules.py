"""Storefront-grade geo pricing shipping rules and banner presentation."""

from alembic import op
import sqlalchemy as sa


revision = "20260926_0007"
down_revision = "20260926_0006"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def _has_column(table, name):
    return name in {c["name"] for c in _inspector().get_columns(table)}


def upgrade():
    if _has_table("city_areas") and not _has_column("city_areas", "direction_id"):
        op.add_column(
            "city_areas",
            sa.Column("direction_id", sa.Integer(), sa.ForeignKey("geo_directions.id", ondelete="SET NULL")),
        )

    if not _has_table("geo_directions"):
        op.create_table(
            "geo_directions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("code", sa.String(length=20), nullable=False, unique=True),
            sa.Column("name_ar", sa.String(length=80), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.bulk_insert(
            sa.table(
                "geo_directions",
                sa.column("code", sa.String()),
                sa.column("name_ar", sa.String()),
                sa.column("sort_order", sa.Integer()),
                sa.column("is_active", sa.Boolean()),
            ),
            [
                {"code": "north", "name_ar": "شمال", "sort_order": 1, "is_active": True},
                {"code": "south", "name_ar": "جنوب", "sort_order": 2, "is_active": True},
                {"code": "east", "name_ar": "شرق", "sort_order": 3, "is_active": True},
                {"code": "west", "name_ar": "غرب", "sort_order": 4, "is_active": True},
                {"code": "center", "name_ar": "وسط", "sort_order": 5, "is_active": True},
            ],
        )

    if _has_table("pricing_location_adjustments"):
        # already created by an interrupted deployment; leave it intact.
        pass
    else:
        op.create_table(
            "pricing_location_adjustments",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("city_id", sa.Integer(), sa.ForeignKey("cities.id", ondelete="CASCADE")),
            sa.Column("region_id", sa.Integer(), sa.ForeignKey("regions.id", ondelete="CASCADE")),
            sa.Column("area_id", sa.Integer(), sa.ForeignKey("city_areas.id", ondelete="CASCADE")),
            sa.Column("percent_adjustment", sa.Numeric(12, 4), nullable=False, server_default="0"),
            sa.Column("fixed_adjustment_sar", sa.Numeric(24, 4), nullable=False, server_default="0"),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("starts_at", sa.DateTime(timezone=True)),
            sa.Column("ends_at", sa.DateTime(timezone=True)),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.CheckConstraint(
                "((CASE WHEN city_id IS NOT NULL THEN 1 ELSE 0 END) + "
                "(CASE WHEN region_id IS NOT NULL THEN 1 ELSE 0 END) + "
                "(CASE WHEN area_id IS NOT NULL THEN 1 ELSE 0 END)) = 1",
                name="ck_pricing_location_adjustment_one_target",
            ),
            sa.CheckConstraint(
                "percent_adjustment > -100",
                name="ck_pricing_location_adjustment_percent_gt_minus_100",
            ),
        )
    indexes = {x["name"] for x in _inspector().get_indexes("pricing_location_adjustments")} if _has_table("pricing_location_adjustments") else set()
    if "ix_pricing_location_adjustment_lookup" not in indexes:
        op.create_index(
            "ix_pricing_location_adjustment_lookup",
            "pricing_location_adjustments",
            ["area_id", "city_id", "region_id", "priority", "is_active"],
        )

    if _has_table("banners"):
        banner_additions = [
            ("root_category_id", sa.Column("root_category_id", sa.Integer(), sa.ForeignKey("categories.id", ondelete="SET NULL"))),
            ("title", sa.Column("title", sa.String(length=220))),
            ("description", sa.Column("description", sa.Text())),
            ("button_label", sa.Column("button_label", sa.String(length=120))),
            ("title_color", sa.Column("title_color", sa.String(length=20), nullable=False, server_default="#ffffff")),
            ("description_color", sa.Column("description_color", sa.String(length=20), nullable=False, server_default="#ffffff")),
            ("button_text_color", sa.Column("button_text_color", sa.String(length=20), nullable=False, server_default="#ffffff")),
            ("button_background_color", sa.Column("button_background_color", sa.String(length=20), nullable=False, server_default="#111827")),
            ("overlay_background_color", sa.Column("overlay_background_color", sa.String(length=20), nullable=False, server_default="#111827")),
            ("overlay_opacity", sa.Column("overlay_opacity", sa.Numeric(4, 3), nullable=False, server_default="0")),
            ("sort_order", sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0")),
            ("starts_at", sa.Column("starts_at", sa.DateTime(timezone=True))),
            ("ends_at", sa.Column("ends_at", sa.DateTime(timezone=True))),
        ]
        for name, column in banner_additions:
            if not _has_column("banners", name):
                op.add_column("banners", column)
        if not _has_column("banners", "position_text"):
            op.add_column("banners", sa.Column("position_text", sa.String(length=40), nullable=False, server_default="center"))
        if not _has_column("banners", "duration"):
            op.add_column("banners", sa.Column("duration", sa.Integer(), nullable=False, server_default="6"))
        if _has_column("banners", "duration"):
            op.execute("UPDATE banners SET duration = 6 WHERE duration IS NULL OR duration <= 0")
        checks = {c["name"] for c in _inspector().get_check_constraints("banners")}
        if "ck_banner_overlay_opacity" not in checks:
            op.create_check_constraint(
                "ck_banner_overlay_opacity",
                "banners",
                "overlay_opacity >= 0 AND overlay_opacity <= 1",
            )
        indexes = {x["name"] for x in _inspector().get_indexes("banners")}
        if "ix_banner_active_schedule" not in indexes:
            op.create_index(
                "ix_banner_active_schedule",
                "banners",
                ["is_active", "status", "sort_order", "starts_at", "ends_at"],
            )

    if _has_table("banner_targets") and not _has_column("banner_targets", "config_json"):
        op.add_column(
            "banner_targets",
            sa.Column("config_json", sa.JSON(), nullable=False, server_default="{}"),
        )

    if not _has_table("shipping_rules"):
        op.create_table(
            "shipping_rules",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("method_id", sa.Integer(), sa.ForeignKey("shipping_methods.id", ondelete="CASCADE"), nullable=False),
            sa.Column("rule_type", sa.String(length=40), nullable=False),
            sa.Column("min_order_sar", sa.Numeric(24, 4)),
            sa.Column("max_order_sar", sa.Numeric(24, 4)),
            sa.Column("value", sa.Numeric(24, 4), nullable=False, server_default="0"),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("stackable", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("stop_processing", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("applies_to_all", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.CheckConstraint(
                "rule_type IN ('free_shipping','percent_discount','fixed_discount','surcharge','set_price')",
                name="ck_shipping_rule_type",
            ),
            sa.CheckConstraint("value >= 0", name="ck_shipping_rule_value_nonnegative"),
            sa.CheckConstraint(
                "max_order_sar IS NULL OR min_order_sar IS NULL OR max_order_sar >= min_order_sar",
                name="ck_shipping_rule_order_range",
            ),
        )
    if not _has_table("shipping_rule_targets"):
        op.create_table(
            "shipping_rule_targets",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("rule_id", sa.Integer(), sa.ForeignKey("shipping_rules.id", ondelete="CASCADE"), nullable=False),
            sa.Column("target_type", sa.String(length=20), nullable=False),
            sa.Column("target_id", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("rule_id", "target_type", "target_id", name="uq_shipping_rule_target"),
        )
    if _has_table("shipping_rules"):
        indexes = {x["name"] for x in _inspector().get_indexes("shipping_rules")}
        if "ix_shipping_rule_lookup" not in indexes:
            op.create_index("ix_shipping_rule_lookup", "shipping_rules", ["method_id", "is_active", "priority"])
    if _has_table("shipping_rule_targets"):
        indexes = {x["name"] for x in _inspector().get_indexes("shipping_rule_targets")}
        if "ix_shipping_rule_target_lookup" not in indexes:
            op.create_index("ix_shipping_rule_target_lookup", "shipping_rule_targets", ["target_type", "target_id", "rule_id"])


def downgrade():
    if _has_table("shipping_rule_targets"):
        indexes = {x["name"] for x in _inspector().get_indexes("shipping_rule_targets")}
        if "ix_shipping_rule_target_lookup" in indexes:
            op.drop_index("ix_shipping_rule_target_lookup", table_name="shipping_rule_targets")
        op.drop_table("shipping_rule_targets")
    if _has_table("shipping_rules"):
        indexes = {x["name"] for x in _inspector().get_indexes("shipping_rules")}
        if "ix_shipping_rule_lookup" in indexes:
            op.drop_index("ix_shipping_rule_lookup", table_name="shipping_rules")
        op.drop_table("shipping_rules")
    if _has_table("banner_targets") and _has_column("banner_targets", "config_json"):
        op.drop_column("banner_targets", "config_json")
    if _has_table("banners"):
        indexes = {x["name"] for x in _inspector().get_indexes("banners")}
        if "ix_banner_active_schedule" in indexes:
            op.drop_index("ix_banner_active_schedule", table_name="banners")
        for name in (
            "ends_at", "starts_at", "sort_order", "overlay_opacity", "overlay_background_color",
            "button_background_color", "button_text_color", "description_color", "title_color",
            "button_label", "description", "title", "root_category_id",
        ):
            if _has_column("banners", name):
                op.drop_column("banners", name)
    if _has_table("pricing_location_adjustments"):
        indexes = {x["name"] for x in _inspector().get_indexes("pricing_location_adjustments")}
        if "ix_pricing_location_adjustment_lookup" in indexes:
            op.drop_index("ix_pricing_location_adjustment_lookup", table_name="pricing_location_adjustments")
        op.drop_table("pricing_location_adjustments")
    if _has_table("city_areas") and _has_column("city_areas", "direction_id"):
        op.drop_column("city_areas", "direction_id")
    if _has_table("geo_directions"):
        op.drop_table("geo_directions")
