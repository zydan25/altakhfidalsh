"""Connect Style looks to circular category destinations."""

from alembic import op
import sqlalchemy as sa

revision = "20260926_0009"
down_revision = "20260926_0008"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def upgrade():
    if not _has_table("look_circles"):
        op.create_table(
            "look_circles",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("look_id", sa.Integer(), sa.ForeignKey("looks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("circle_id", sa.Integer(), sa.ForeignKey("side_category_circles.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("look_id", "circle_id", name="uq_look_circle"),
        )
        op.create_index("ix_look_circle_sort", "look_circles", ["look_id", "sort_order"])


def downgrade():
    if _has_table("look_circles"):
        indexes = {x["name"] for x in _inspector().get_indexes("look_circles")}
        if "ix_look_circle_sort" in indexes:
            op.drop_index("ix_look_circle_sort", table_name="look_circles")
        op.drop_table("look_circles")
