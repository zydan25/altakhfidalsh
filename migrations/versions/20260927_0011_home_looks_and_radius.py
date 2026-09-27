"""Add configurable home looks and category/looks styling."""
from alembic import op
import sqlalchemy as sa


revision = "20260927_0011"
down_revision = "20260927_0010"
branch_labels = None
depends_on = None


def _has_column(bind, table, column):
    return column in {c["name"] for c in sa.inspect(bind).get_columns(table)}


def _has_table(bind, table):
    return sa.inspect(bind).has_table(table)


def _has_index(bind, table, name):
    return any(i.get("name") == name for i in sa.inspect(bind).get_indexes(table))


def upgrade():
    bind = op.get_bind()

    # Extend category-home settings without breaking installations that already
    # applied migration 0010.
    if not _has_column(bind, "category_home_display_settings", "item_corner_radius"):
        op.add_column(
            "category_home_display_settings",
            sa.Column("item_corner_radius", sa.Integer(), nullable=False, server_default="16"),
        )
        bind.execute(
            sa.text(
                "UPDATE category_home_display_settings "
                "SET item_corner_radius = 16 "
                "WHERE item_corner_radius IS NULL"
            )
        )

    # Add the look presentation/scope fields individually for upgrade safety.
    look_columns = [
        ("root_category_id", sa.Column(
            "root_category_id",
            sa.Integer(),
            sa.ForeignKey("categories.id", ondelete="SET NULL"),
        )),
        ("show_on_home", sa.Column("show_on_home", sa.Boolean(), nullable=False, server_default=sa.true())),
        ("card_shape", sa.Column("card_shape", sa.String(length=20), nullable=False, server_default="rounded")),
        ("card_width", sa.Column("card_width", sa.Integer(), nullable=False, server_default="160")),
        ("card_height", sa.Column("card_height", sa.Integer(), nullable=False, server_default="220")),
        ("card_radius", sa.Column("card_radius", sa.Integer(), nullable=False, server_default="14")),
        ("card_spacing", sa.Column("card_spacing", sa.Integer(), nullable=False, server_default="8")),
        ("caption_background_color", sa.Column("caption_background_color", sa.String(length=20), nullable=False, server_default="#000000")),
        ("caption_text_color", sa.Column("caption_text_color", sa.String(length=20), nullable=False, server_default="#ffffff")),
    ]
    for column_name, column in look_columns:
        if not _has_column(bind, "looks", column_name):
            op.add_column("looks", column)

    # Existing looks remain visible in the global scope so adding the settings
    # does not silently remove existing customer-facing content.
    bind.execute(
        sa.text(
            "UPDATE looks SET show_on_home = TRUE "
            "WHERE show_on_home IS NULL"
        )
    )

    if not _has_index(bind, "looks", "ix_look_home_scope"):
        op.create_index(
            "ix_look_home_scope",
            "looks",
            ["root_category_id", "show_on_home", "sort_order"],
        )

    if not _has_table(bind, "look_targets"):
        op.create_table(
            "look_targets",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("look_id", sa.Integer(), sa.ForeignKey("looks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("target_type", sa.String(length=30), nullable=False),
            sa.Column("target_id", sa.Integer(), nullable=False),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("look_id", "target_type", "target_id", name="uq_look_target"),
            sa.CheckConstraint(
                "target_type IN ('circle','hashtag')",
                name="ck_look_target_type",
            ),
        )
    if not _has_index(bind, "look_targets", "ix_look_target_look_priority"):
        op.create_index(
            "ix_look_target_look_priority",
            "look_targets",
            ["look_id", "priority", "id"],
        )


def downgrade():
    bind = op.get_bind()
    if _has_table(bind, "look_targets"):
        op.drop_table("look_targets")
    if _has_index(bind, "looks", "ix_look_home_scope"):
        op.drop_index("ix_look_home_scope", table_name="looks")
    for column_name, _ in [
        ("caption_text_color", None),
        ("caption_background_color", None),
        ("card_spacing", None),
        ("card_radius", None),
        ("card_height", None),
        ("card_width", None),
        ("card_shape", None),
        ("show_on_home", None),
        ("root_category_id", None),
    ]:
        if _has_column(bind, "looks", column_name):
            op.drop_column("looks", column_name)
    if _has_column(bind, "category_home_display_settings", "item_corner_radius"):
        op.drop_column("category_home_display_settings", "item_corner_radius")
