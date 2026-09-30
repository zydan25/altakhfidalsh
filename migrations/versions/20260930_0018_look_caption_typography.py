"""Add configurable look caption height and font size."""
from alembic import op
import sqlalchemy as sa

revision = "20260930_0018"
down_revision = "20260927_0017"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("looks"):
        return

    existing = {column["name"] for column in inspector.get_columns("looks")}
    columns = [
        ("caption_height", sa.Column("caption_height", sa.Integer(), nullable=False, server_default="28")),
        ("caption_font_size", sa.Column("caption_font_size", sa.Integer(), nullable=False, server_default="12")),
    ]
    for name, column in columns:
        if name not in existing:
            op.add_column("looks", column)

    existing_constraints = {
        x["name"] for x in inspector.get_check_constraints("looks")
    }
    if "ck_look_caption_height" not in existing_constraints:
        op.create_check_constraint(
            "ck_look_caption_height",
            "looks",
            "caption_height >= 12 AND caption_height <= 120",
        )
    if "ck_look_caption_font_size" not in existing_constraints:
        op.create_check_constraint(
            "ck_look_caption_font_size",
            "looks",
            "caption_font_size >= 6 AND caption_font_size <= 40",
        )

    op.alter_column("looks", "caption_height", server_default=None)
    op.alter_column("looks", "caption_font_size", server_default=None)


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("looks"):
        return

    constraints = {x["name"] for x in inspector.get_check_constraints("looks")}
    for name in ("ck_look_caption_font_size", "ck_look_caption_height"):
        if name in constraints:
            op.drop_constraint(name, "looks", type_="check")

    columns = {column["name"] for column in inspector.get_columns("looks")}
    for name in ("caption_font_size", "caption_height"):
        if name in columns:
            op.drop_column("looks", name)
