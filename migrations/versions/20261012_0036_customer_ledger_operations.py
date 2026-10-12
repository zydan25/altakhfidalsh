"""Add customer-account insurance, daybook and order payment records.

Revision ID: 20261012_0036
Revises: 20261012_0035
"""
from alembic import op
import sqlalchemy as sa


revision = "20261012_0036"
down_revision = "20261012_0035"
branch_labels = None
depends_on = None


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def _has_index(table, name):
    if not _has_table(table):
        return False
    return name in {item["name"] for item in _inspector().get_indexes(table)}


def upgrade():
    if not _has_table("customer_ledger_operations"):
        op.create_table(
            "customer_ledger_operations",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("operation_type", sa.String(30), nullable=False),
            sa.Column("customer_id", sa.Integer(), sa.ForeignKey("customers.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("order_id", sa.Integer(), sa.ForeignKey("orders.id", ondelete="RESTRICT")),
            sa.Column("operation_date", sa.Date(), nullable=False),
            sa.Column("amount_yer", sa.Numeric(24, 4), nullable=False),
            sa.Column("entered_amount", sa.Numeric(24, 4), nullable=False),
            sa.Column("entered_currency_code", sa.String(16), nullable=False, server_default="YER"),
            sa.Column("exchange_rate_to_yer", sa.Numeric(24, 12), nullable=False, server_default="1"),
            sa.Column("cash_account_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT")),
            sa.Column("contra_account_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT")),
            sa.Column("journal_entry_id", sa.Integer(), sa.ForeignKey("accounting_journal_entries.id", ondelete="RESTRICT"), unique=True),
            sa.Column("description", sa.String(500)),
            sa.Column("status", sa.String(20), nullable=False, server_default="posted"),
            sa.Column("created_by_admin_id", sa.Integer(), sa.ForeignKey("admins.id", ondelete="SET NULL")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.CheckConstraint("operation_type IN ('insurance','daybook','order_sale','order_payment')", name="ck_customer_ledger_operation_type"),
            sa.CheckConstraint("amount_yer > 0 AND entered_amount > 0", name="ck_customer_ledger_operation_amount"),
            sa.CheckConstraint("status IN ('posted','void')", name="ck_customer_ledger_operation_status"),
        )
    if not _has_index("customer_ledger_operations", "ix_customer_ledger_operations_operation_type"):
        op.create_index("ix_customer_ledger_operations_operation_type", "customer_ledger_operations", ["operation_type"])
    if not _has_index("customer_ledger_operations", "ix_customer_ledger_operations_customer_id"):
        op.create_index("ix_customer_ledger_operations_customer_id", "customer_ledger_operations", ["customer_id"])
    if not _has_index("customer_ledger_operations", "ix_customer_ledger_operations_order_id"):
        op.create_index("ix_customer_ledger_operations_order_id", "customer_ledger_operations", ["order_id"])
    if not _has_index("customer_ledger_operations", "ix_customer_ledger_operations_operation_date"):
        op.create_index("ix_customer_ledger_operations_operation_date", "customer_ledger_operations", ["operation_date"])
    if not _has_index("customer_ledger_operations", "ix_customer_ledger_operation_customer_date"):
        op.create_index("ix_customer_ledger_operation_customer_date", "customer_ledger_operations", ["customer_id", "operation_date", "id"])


def downgrade():
    if _has_table("customer_ledger_operations"):
        for name in [
            "ix_customer_ledger_operation_customer_date",
            "ix_customer_ledger_operations_operation_date",
            "ix_customer_ledger_operations_order_id",
            "ix_customer_ledger_operations_customer_id",
            "ix_customer_ledger_operations_operation_type",
        ]:
            if _has_index("customer_ledger_operations", name):
                op.drop_index(name, table_name="customer_ledger_operations")
        op.drop_table("customer_ledger_operations")
