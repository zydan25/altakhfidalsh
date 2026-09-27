"""Configurable customer-home category display settings."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0010"
down_revision = "20260926_0009"
branch_labels = None
depends_on = None


TABLE = "category_home_display_settings"


def _has_table(bind):
    return sa.inspect(bind).has_table(TABLE)


def _index_names(bind):
    return {
        index.get("name")
        for index in sa.inspect(bind).get_indexes(TABLE)
        if index.get("name")
    }


def upgrade():
    bind = op.get_bind()

    # This migration is intentionally idempotent. It protects CI/deployment
    # runs where the same schema may already contain the table.
    if not _has_table(bind):
        op.create_table(
            TABLE,
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
            sa.Column("show_looks_strip", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("item_shape", sa.String(length=20), nullable=False, server_default="circle"),
            sa.Column("item_size", sa.Integer(), nullable=False, server_default="64"),
            sa.Column("item_spacing", sa.Integer(), nullable=False, server_default="6"),
            sa.Column("item_corner_radius", sa.Integer(), nullable=False, server_default="16"),
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

    existing_indexes = _index_names(bind)
    if "ix_category_home_display_category" not in existing_indexes:
        op.create_index(
            "ix_category_home_display_category",
            TABLE,
            ["category_id"],
        )

    # The unique constraint is the canonical uniqueness mechanism for scope_key.
    # Do not create a duplicate unique index on the same column.
    columns = {column["name"] for column in sa.inspect(bind).get_columns(TABLE)}
    if "show_looks_strip" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET show_looks_strip = TRUE "
                "WHERE show_looks_strip IS NULL"
            )
        )
    if "item_corner_radius" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET item_corner_radius = 16 "
                "WHERE item_corner_radius IS NULL"
            )
        )
    if "item_label_font_size" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET item_label_font_size = 9 "
                "WHERE item_label_font_size IS NULL"
            )
        )
    if "item_label_bold" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET item_label_bold = TRUE "
                "WHERE item_label_bold IS NULL"
            )
        )
    # Later schema revisions add independent dimensions. Some deployment/PR
    # histories can already contain these NOT NULL columns when this migration
    # first creates/repairs the default "all" row. Populate them before any
    # insert so the migration remains safe across both schema shapes.
    if "item_width" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET item_width = COALESCE(item_size, 64) "
                "WHERE item_width IS NULL OR item_width <= 0"
            )
        )
    if "item_height" in columns:
        bind.execute(
            sa.text(
                f"UPDATE {TABLE} SET item_height = COALESCE(item_size, 64) "
                "WHERE item_height IS NULL OR item_height <= 0"
            )
        )

    existing_scopes = bind.execute(
        sa.text(f"SELECT scope_key FROM {TABLE}")
    ).scalars().all()

    if "all" not in set(existing_scopes):
        columns = {
            column["name"]
            for column in sa.inspect(bind).get_columns(TABLE)
        }
        insert_columns = [
            "scope_key",
            "category_id",
            "grid_rows",
            "show_coupon_strip",
            "item_shape",
            "item_size",
            "item_spacing",
        ]
        insert_values = [
            "'all'",
            "NULL",
            "2",
            "TRUE",
            "'circle'",
            "64",
            "6",
        ]

        if "show_looks_strip" in columns:
            insert_columns.append("show_looks_strip")
            insert_values.append("TRUE")
        if "item_corner_radius" in columns:
            insert_columns.append("item_corner_radius")
            insert_values.append("16")
        if "item_label_font_size" in columns:
            insert_columns.append("item_label_font_size")
            insert_values.append("9")
        if "item_label_bold" in columns:
            insert_columns.append("item_label_bold")
            insert_values.append("TRUE")
        if "item_width" in columns:
            insert_columns.append("item_width")
            insert_values.append("64")
        if "item_height" in columns:
            insert_columns.append("item_height")
            insert_values.append("64")

        bind.execute(
            sa.text(
                f"INSERT INTO {TABLE} ({', '.join(insert_columns)}) "
                f"VALUES ({', '.join(insert_values)})"
            )
        )


def downgrade():
    if _has_table(op.get_bind()):
        op.drop_table(TABLE)
