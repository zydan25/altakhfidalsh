"""Clarify SAR-first pricing, geography hierarchy and shipping rules."""

from alembic import op
import sqlalchemy as sa


revision = "20260926_0006"
down_revision = "20260926_0005"
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
    if _has_table("cities"):
        if not _has_column("cities", "direction"):
            op.add_column("cities", sa.Column("direction", sa.String(length=20), nullable=True))
        if not _has_column("cities", "source"):
            op.add_column("cities", sa.Column("source", sa.String(length=120), nullable=True))

    if not _has_table("city_areas"):
        op.create_table(
            "city_areas",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("city_id", sa.Integer(), sa.ForeignKey("cities.id", ondelete="CASCADE"), nullable=False),
            sa.Column("code", sa.String(length=60), nullable=False),
            sa.Column("name", sa.String(length=160), nullable=False),
            sa.Column("direction", sa.String(length=20), nullable=True),
            sa.Column("source", sa.String(length=120), nullable=True),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("city_id", "code", name="uq_city_area_city_code"),
        )
    if not _has_index("city_areas", "ix_city_area_city_active"):
        op.create_index("ix_city_area_city_active", "city_areas", ["city_id", "is_active"])

    if _has_table("pricing_groups"):
        additions = [
            ("percent_markup", sa.Column("percent_markup", sa.Numeric(12, 4), nullable=False, server_default="0")),
            ("fixed_markup_sar", sa.Column("fixed_markup_sar", sa.Numeric(24, 4), nullable=False, server_default="0")),
            ("rounding_rule", sa.Column("rounding_rule", sa.String(length=40), nullable=False, server_default="nearest")),
            ("decimals", sa.Column("decimals", sa.Integer(), nullable=False, server_default="2")),
        ]
        for name, column in additions:
            if not _has_column("pricing_groups", name):
                op.add_column("pricing_groups", column)

        # Backfill the new group-level defaults from the first existing currency rule.
        op.execute(
            """
            UPDATE pricing_groups pg
            SET
                percent_markup = COALESCE((
                    SELECT pgr.percent_markup
                    FROM pricing_group_rules pgr
                    WHERE pgr.group_id = pg.id
                    ORDER BY pgr.id
                    LIMIT 1
                ), 0),
                fixed_markup_sar = COALESCE((
                    SELECT pgr.fixed_markup
                    FROM pricing_group_rules pgr
                    WHERE pgr.group_id = pg.id
                    ORDER BY pgr.id
                    LIMIT 1
                ), 0),
                rounding_rule = COALESCE((
                    SELECT pgr.rounding_rule
                    FROM pricing_group_rules pgr
                    WHERE pgr.group_id = pg.id
                    ORDER BY pgr.id
                    LIMIT 1
                ), 'nearest'),
                decimals = COALESCE((
                    SELECT pgr.decimals
                    FROM pricing_group_rules pgr
                    WHERE pgr.group_id = pg.id
                    ORDER BY pgr.id
                    LIMIT 1
                ), 2)
            """
        )

    if _has_table("pricing_group_cities"):
        if not _has_column("pricing_group_cities", "area_id"):
            op.add_column(
                "pricing_group_cities",
                sa.Column("area_id", sa.Integer(), sa.ForeignKey("city_areas.id", ondelete="CASCADE")),
            )
        inspector = _inspector()
        checks = {c["name"] for c in inspector.get_check_constraints("pricing_group_cities")}
        if "ck_pricing_group_city_or_region" in checks:
            op.drop_constraint(
                "ck_pricing_group_city_or_region",
                "pricing_group_cities",
                type_="check",
            )
        checks = {c["name"] for c in _inspector().get_check_constraints("pricing_group_cities")}
        if "ck_pricing_group_location_one_target" not in checks:
            op.create_check_constraint(
                "ck_pricing_group_location_one_target",
                "pricing_group_cities",
                "((city_id IS NOT NULL)::int + (region_id IS NOT NULL)::int + (area_id IS NOT NULL)::int) = 1",
            )

    if _has_table("customers") and not _has_column("customers", "city_area_id"):
        op.add_column(
            "customers",
            sa.Column("city_area_id", sa.Integer(), sa.ForeignKey("city_areas.id", ondelete="SET NULL")),
        )

    if _has_table("customer_addresses") and not _has_column("customer_addresses", "city_area_id"):
        op.add_column(
            "customer_addresses",
            sa.Column("city_area_id", sa.Integer(), sa.ForeignKey("city_areas.id", ondelete="SET NULL")),
        )

    if _has_table("shipping_rates"):
        additions = [
            ("customer_id", sa.Column("customer_id", sa.Integer(), sa.ForeignKey("customers.id", ondelete="CASCADE"))),
            ("city_area_id", sa.Column("city_area_id", sa.Integer(), sa.ForeignKey("city_areas.id", ondelete="CASCADE"))),
            ("min_order_sar", sa.Column("min_order_sar", sa.Numeric(24, 4))),
            ("max_order_sar", sa.Column("max_order_sar", sa.Numeric(24, 4))),
            ("price_sar", sa.Column("price_sar", sa.Numeric(24, 4))),
            ("free_over_sar", sa.Column("free_over_sar", sa.Numeric(24, 4))),
            ("priority", sa.Column("priority", sa.Integer(), nullable=False, server_default="0")),
        ]
        for name, column in additions:
            if not _has_column("shipping_rates", name):
                op.add_column("shipping_rates", column)

        # Existing shipping data is interpreted as SAR so the new model remains backward compatible.
        op.execute(
            "UPDATE shipping_rates SET price_sar = COALESCE(price_sar, price), "
            "min_order_sar = COALESCE(min_order_sar, min_order), "
            "max_order_sar = COALESCE(max_order_sar, max_order), "
            "free_over_sar = COALESCE(free_over_sar, free_over)"
        )

        if not _has_index("shipping_rates", "ix_shipping_rate_location"):
            op.create_index(
                "ix_shipping_rate_location",
                "shipping_rates",
                ["city_area_id", "city_id", "region_id", "customer_id", "is_active"],
            )
        if not _has_index("shipping_rates", "ix_shipping_rate_customer"):
            op.create_index(
                "ix_shipping_rate_customer",
                "shipping_rates",
                ["customer_id", "priority"],
            )


def downgrade():
    if _has_table("shipping_rates"):
        for name in ("ix_shipping_rate_customer", "ix_shipping_rate_location"):
            if _has_index("shipping_rates", name):
                op.drop_index(name, table_name="shipping_rates")
        for name in ("priority", "free_over_sar", "price_sar", "max_order_sar", "min_order_sar", "city_area_id", "customer_id"):
            if _has_column("shipping_rates", name):
                op.drop_column("shipping_rates", name)

    if _has_table("customer_addresses") and _has_column("customer_addresses", "city_area_id"):
        op.drop_column("customer_addresses", "city_area_id")

    if _has_table("customers") and _has_column("customers", "city_area_id"):
        op.drop_column("customers", "city_area_id")

    if _has_table("pricing_group_cities"):
        checks = {c["name"] for c in _inspector().get_check_constraints("pricing_group_cities")}
        if "ck_pricing_group_location_one_target" in checks:
            op.drop_constraint("ck_pricing_group_location_one_target", "pricing_group_cities", type_="check")
        checks = {c["name"] for c in _inspector().get_check_constraints("pricing_group_cities")}
        if "ck_pricing_group_city_or_region" not in checks:
            op.create_check_constraint(
                "ck_pricing_group_city_or_region",
                "pricing_group_cities",
                "(city_id IS NOT NULL) <> (region_id IS NOT NULL)",
            )
        if _has_column("pricing_group_cities", "area_id"):
            op.drop_column("pricing_group_cities", "area_id")

    if _has_table("pricing_groups"):
        for name in ("decimals", "rounding_rule", "fixed_markup_sar", "percent_markup"):
            if _has_column("pricing_groups", name):
                op.drop_column("pricing_groups", name)

    if _has_table("city_areas"):
        if _has_index("city_areas", "ix_city_area_city_active"):
            op.drop_index("ix_city_area_city_active", table_name="city_areas")
        op.drop_table("city_areas")

    if _has_table("cities"):
        for name in ("source", "direction"):
            if _has_column("cities", name):
                op.drop_column("cities", name)
