"""Checkout/payment snapshots.

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
    order_columns = {c["name"] for c in inspector.get_columns("orders")}
    payment_columns = {c["name"] for c in inspector.get_columns("payment_methods")}

    if "customer_note" not in order_columns:
        op.add_column("orders", sa.Column("customer_note", sa.Text(), nullable=True))

    if "payment_method_id" not in order_columns:
        op.add_column(
            "orders",
            sa.Column(
                "payment_method_id",
                sa.Integer(),
                sa.ForeignKey("payment_methods.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )

    if "shipping_rule_ids_json" not in order_columns:
        op.add_column(
            "orders",
            sa.Column(
                "shipping_rule_ids_json",
                sa.JSON(),
                nullable=False,
                server_default="[]",
            ),
        )

    if "settings_json" not in payment_columns:
        op.add_column(
            "payment_methods",
            sa.Column(
                "settings_json",
                sa.JSON(),
                nullable=False,
                server_default="{}",
            ),
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    order_columns = {c["name"] for c in inspector.get_columns("orders")}
    payment_columns = {c["name"] for c in inspector.get_columns("payment_methods")}

    if "settings_json" in payment_columns:
        op.drop_column("payment_methods", "settings_json")
    if "shipping_rule_ids_json" in order_columns:
        op.drop_column("orders", "shipping_rule_ids_json")
    if "payment_method_id" in order_columns:
        op.drop_column("orders", "payment_method_id")
    if "customer_note" in order_columns:
        op.drop_column("orders", "customer_note")
