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


def _inspector():
    return sa.inspect(op.get_bind())


def _has_table(name):
    return _inspector().has_table(name)


def _columns(table):
    if not _has_table(table):
        return set()
    return {col["name"] for col in _inspector().get_columns(table)}


def _has_index(table, name):
    if not _has_table(table):
        return False
    return name in {item["name"] for item in _inspector().get_indexes(table)}


def _has_unique(table, columns):
    if not _has_table(table):
        return False
    expected = list(columns)
    for item in _inspector().get_unique_constraints(table):
        if item.get("column_names") == expected:
            return True
    for item in _inspector().get_indexes(table):
        if item.get("unique") and item.get("column_names") == expected:
            return True
    return False


def _has_fk(table, columns, referred_table):
    if not _has_table(table):
        return False
    for item in _inspector().get_foreign_keys(table):
        if item.get("constrained_columns") == list(columns) and item.get("referred_table") == referred_table:
            return True
    return False


def upgrade():
    # The repository's bootstrap revision creates current model metadata on a new
    # database. Every operation here is therefore idempotent by design.
    if not _has_table("ledger_accounts"):
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
    if not _has_index("ledger_accounts", "ix_ledger_accounts_code"):
        op.create_index("ix_ledger_accounts_code", "ledger_accounts", ["code"], unique=True)

    if not _has_table("accounting_journal_entries"):
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
    if not _has_index("accounting_journal_entries", "ix_accounting_journal_entries_number"):
        op.create_index("ix_accounting_journal_entries_number", "accounting_journal_entries", ["number"], unique=True)
    if not _has_index("accounting_journal_entries", "ix_accounting_journal_entries_entry_date"):
        op.create_index("ix_accounting_journal_entries_entry_date", "accounting_journal_entries", ["entry_date"])

    if not _has_table("accounting_journal_lines"):
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
    if not _has_index("accounting_journal_lines", "ix_accounting_journal_lines_entry_id"):
        op.create_index("ix_accounting_journal_lines_entry_id", "accounting_journal_lines", ["entry_id"])
    if not _has_index("accounting_journal_lines", "ix_accounting_journal_lines_account_id"):
        op.create_index("ix_accounting_journal_lines_account_id", "accounting_journal_lines", ["account_id"])

    if not _has_table("accounting_vouchers"):
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
    if not _has_index("accounting_vouchers", "ix_accounting_vouchers_number"):
        op.create_index("ix_accounting_vouchers_number", "accounting_vouchers", ["number"], unique=True)
    if not _has_index("accounting_vouchers", "ix_accounting_vouchers_voucher_date"):
        op.create_index("ix_accounting_vouchers_voucher_date", "accounting_vouchers", ["voucher_date"])

    if "ledger_account_id" not in _columns("customers"):
        op.add_column("customers", sa.Column("ledger_account_id", sa.Integer(), nullable=True))
    if not _has_fk("customers", ["ledger_account_id"], "ledger_accounts"):
        op.create_foreign_key(
            "fk_customers_ledger_account_id", "customers", "ledger_accounts",
            ["ledger_account_id"], ["id"], ondelete="SET NULL",
        )
    if not _has_unique("customers", ["ledger_account_id"]):
        op.create_unique_constraint("uq_customers_ledger_account_id", "customers", ["ledger_account_id"])

    if "ledger_account_id" not in _columns("admins"):
        op.add_column("admins", sa.Column("ledger_account_id", sa.Integer(), nullable=True))
    if not _has_fk("admins", ["ledger_account_id"], "ledger_accounts"):
        op.create_foreign_key(
            "fk_admins_ledger_account_id", "admins", "ledger_accounts",
            ["ledger_account_id"], ["id"], ondelete="SET NULL",
        )
    if not _has_unique("admins", ["ledger_account_id"]):
        op.create_unique_constraint("uq_admins_ledger_account_id", "admins", ["ledger_account_id"])


def downgrade():
    if "ledger_account_id" in _columns("admins"):
        if _has_unique("admins", ["ledger_account_id"]):
            for item in _inspector().get_unique_constraints("admins"):
                if item.get("column_names") == ["ledger_account_id"]:
                    op.drop_constraint(item.get("name"), "admins", type_="unique")
                    break
        if _has_fk("admins", ["ledger_account_id"], "ledger_accounts"):
            for item in _inspector().get_foreign_keys("admins"):
                if item.get("constrained_columns") == ["ledger_account_id"] and item.get("referred_table") == "ledger_accounts":
                    op.drop_constraint(item.get("name"), "admins", type_="foreignkey")
                    break
        op.drop_column("admins", "ledger_account_id")
    if "ledger_account_id" in _columns("customers"):
        if _has_unique("customers", ["ledger_account_id"]):
            for item in _inspector().get_unique_constraints("customers"):
                if item.get("column_names") == ["ledger_account_id"]:
                    op.drop_constraint(item.get("name"), "customers", type_="unique")
                    break
        if _has_fk("customers", ["ledger_account_id"], "ledger_accounts"):
            for item in _inspector().get_foreign_keys("customers"):
                if item.get("constrained_columns") == ["ledger_account_id"] and item.get("referred_table") == "ledger_accounts":
                    op.drop_constraint(item.get("name"), "customers", type_="foreignkey")
                    break
        op.drop_column("customers", "ledger_account_id")

    for table, index in [
        ("accounting_vouchers", "ix_accounting_vouchers_voucher_date"),
        ("accounting_vouchers", "ix_accounting_vouchers_number"),
        ("accounting_journal_lines", "ix_accounting_journal_lines_account_id"),
        ("accounting_journal_lines", "ix_accounting_journal_lines_entry_id"),
        ("accounting_journal_entries", "ix_accounting_journal_entries_entry_date"),
        ("accounting_journal_entries", "ix_accounting_journal_entries_number"),
        ("ledger_accounts", "ix_ledger_accounts_code"),
    ]:
        if _has_index(table, index):
            op.drop_index(index, table_name=table)
    for table in ("accounting_vouchers", "accounting_journal_lines", "accounting_journal_entries", "ledger_accounts"):
        if _has_table(table):
            op.drop_table(table)
