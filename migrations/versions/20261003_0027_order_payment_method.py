"""Add selected payment method to orders.
Revision ID: 20261003_0027
Revises: 20261003_0026
"""
from alembic import op
import sqlalchemy as sa

revision = "20261003_0027"
down_revision = "20261003_0026"
branch_labels = None
depends_on = None

def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns("orders")}
    if "payment_method_id" not in columns:
        op.add_column(
            "orders",
            sa.Column(
                "payment_method_id",
                sa.Integer(),
                sa.ForeignKey("payment_methods.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )

def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "payment_method_id" in {c["name"] for c in inspector.get_columns("orders")}:
        op.drop_column("orders", "payment_method_id")
