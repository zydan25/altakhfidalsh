"""Add the e-commerce accounting core: chart of accounts, journals and vouchers.

Revision ID: 20261012_0035
Revises: 20261012_0034
"""
from alembic import op
import sqlalchemy as sa


revision = "20261012_0035"
down_revision = "20261012_0034"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "ledger_accounts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("code", sa.String(60), nullable=False),
        sa.Column("name", sa.String(180), nullable=False),
        sa.Column("account_type", sa.String(24), nullable=False),
        sa.Column("parent_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT")),
        sa.Column("is_group", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("allow_manual_posting", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("system_key", sa.String(140), unique=True),
        sa.Column("description", sa.String(300)),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("code", name="uq_ledger_accounts_code"),
        sa.CheckConstraint(
            "account_type IN ('asset','liability','equity','revenue','expense')",
            name="ck_ledger_account_type",
        ),
        sa.CheckConstraint(
            "NOT (is_group = TRUE AND allow_manual_posting = TRUE)",
            name="ck_ledger_group_not_postable",
        ),
    )
    op.create_index("ix_ledger_accounts_code", "ledger_accounts", ["code"], unique=True)

    op.create_table(
        "accounting_journal_entries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("number", sa.String(48), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("description", sa.String(500), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="posted"),
        sa.Column("source_type", sa.String(50), nullable=False, server_default="manual"),
        sa.Column("source_id", sa.Integer()),
        sa.Column("currency_code", sa.String(16), nullable=False, server_default="SAR"),
        sa.Column("created_by_admin_id", sa.Integer(), sa.ForeignKey("admins.id", ondelete="SET NULL")),
        sa.Column("posted_at", sa.DateTime(timezone=True)),
        sa.Column("reversed_entry_id", sa.Integer(), sa.ForeignKey("accounting_journal_entries.id", ondelete="SET NULL")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("number", name="uq_accounting_journal_entries_number"),
        sa.UniqueConstraint("source_type", "source_id", name="uq_accounting_journal_source"),
        sa.CheckConstraint("status IN ('posted','draft','void')", name="ck_accounting_journal_status"),
    )
    op.create_index("ix_accounting_journal_entries_number", "accounting_journal_entries", ["number"], unique=True)
    op.create_index("ix_accounting_journal_entries_entry_date", "accounting_journal_entries", ["entry_date"])

    op.create_table(
        "accounting_journal_lines",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("entry_id", sa.Integer(), sa.ForeignKey("accounting_journal_entries.id", ondelete="CASCADE"), nullable=False),
        sa.Column("account_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("description", sa.String(500)),
        sa.Column("debit", sa.Numeric(24, 4), nullable=False, server_default="0"),
        sa.Column("credit", sa.Numeric(24, 4), nullable=False, server_default="0"),
        sa.Column("reference", sa.String(120)),
        sa.CheckConstraint("debit >= 0 AND credit >= 0", name="ck_accounting_line_nonnegative"),
        sa.CheckConstraint("(debit = 0) <> (credit = 0)", name="ck_accounting_line_one_side"),
    )
    op.create_index("ix_accounting_journal_lines_entry_id", "accounting_journal_lines", ["entry_id"])
    op.create_index("ix_accounting_journal_lines_account_id", "accounting_journal_lines", ["account_id"])

    op.create_table(
        "accounting_vouchers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("number", sa.String(48), nullable=False),
        sa.Column("voucher_type", sa.String(24), nullable=False),
        sa.Column("voucher_date", sa.Date(), nullable=False),
        sa.Column("amount", sa.Numeric(24, 4), nullable=False),
        sa.Column("currency_code", sa.String(16), nullable=False, server_default="SAR"),
        sa.Column("from_account_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT")),
        sa.Column("to_account_id", sa.Integer(), sa.ForeignKey("ledger_accounts.id", ondelete="RESTRICT")),
        sa.Column("beneficiary", sa.String(180)),
        sa.Column("description", sa.String(500), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="posted"),
        sa.Column("journal_entry_id", sa.Integer(), sa.ForeignKey("accounting_journal_entries.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("created_by_admin_id", sa.Integer(), sa.ForeignKey("admins.id", ondelete="SET NULL")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("number", name="uq_accounting_vouchers_number"),
        sa.CheckConstraint("voucher_type IN ('receipt','payment','transfer','adjustment')", name="ck_accounting_voucher_type"),
        sa.CheckConstraint("status IN ('posted','void')", name="ck_accounting_voucher_status"),
        sa.CheckConstraint("amount > 0", name="ck_accounting_voucher_positive_amount"),
    )
    op.create_index("ix_accounting_vouchers_number", "accounting_vouchers", ["number"], unique=True)
    op.create_index("ix_accounting_vouchers_voucher_date", "accounting_vouchers", ["voucher_date"])

    op.add_column("customers", sa.Column("ledger_account_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_customers_ledger_account_id",
        "customers",
        "ledger_accounts",
        ["ledger_account_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint("uq_customers_ledger_account_id", "customers", ["ledger_account_id"])

    op.add_column("admins", sa.Column("ledger_account_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_admins_ledger_account_id",
        "admins",
        "ledger_accounts",
        ["ledger_account_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint("uq_admins_ledger_account_id", "admins", ["ledger_account_id"])


def downgrade():
    op.drop_constraint("uq_admins_ledger_account_id", "admins", type_="unique")
    op.drop_constraint("fk_admins_ledger_account_id", "admins", type_="foreignkey")
    op.drop_column("admins", "ledger_account_id")
    op.drop_constraint("uq_customers_ledger_account_id", "customers", type_="unique")
    op.drop_constraint("fk_customers_ledger_account_id", "customers", type_="foreignkey")
    op.drop_column("customers", "ledger_account_id")

    op.drop_index("ix_accounting_vouchers_voucher_date", table_name="accounting_vouchers")
    op.drop_index("ix_accounting_vouchers_number", table_name="accounting_vouchers")
    op.drop_table("accounting_vouchers")
    op.drop_index("ix_accounting_journal_lines_account_id", table_name="accounting_journal_lines")
    op.drop_index("ix_accounting_journal_lines_entry_id", table_name="accounting_journal_lines")
    op.drop_table("accounting_journal_lines")
    op.drop_index("ix_accounting_journal_entries_entry_date", table_name="accounting_journal_entries")
    op.drop_index("ix_accounting_journal_entries_number", table_name="accounting_journal_entries")
    op.drop_table("accounting_journal_entries")
    op.drop_index("ix_ledger_accounts_code", table_name="ledger_accounts")
    op.drop_table("ledger_accounts")
