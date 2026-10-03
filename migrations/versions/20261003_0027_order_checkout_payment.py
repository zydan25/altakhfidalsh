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
    op.add_column("orders", sa.Column("customer_note", sa.Text(), nullable=True))
    op.add_column("orders", sa.Column("shipping_rule_ids_json", sa.JSON(), nullable=False, server_default="[]"))
    op.add_column("payment_methods", sa.Column("settings_json", sa.JSON(), nullable=False, server_default="{}"))

def downgrade():
    op.drop_column("payment_methods", "settings_json")
    op.drop_column("orders", "shipping_rule_ids_json")
    op.drop_column("orders", "customer_note")
