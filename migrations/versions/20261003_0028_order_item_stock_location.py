"""Store inventory location reserved for each order item.
Revision ID: 20261003_0028
Revises: 20261003_0027
"""
from alembic import op
import sqlalchemy as sa

revision = "20261003_0028"
down_revision = "20261003_0027"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("order_items")}
    if "stock_location_id" not in columns:
        op.add_column(
            "order_items",
            sa.Column(
                "stock_location_id",
                sa.Integer(),
                sa.ForeignKey("inventory_locations.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )

def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("order_items")}
    if "stock_location_id" in columns:
        op.drop_column("order_items", "stock_location_id")
