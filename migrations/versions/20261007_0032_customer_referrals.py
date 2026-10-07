"""Add/refine customer referral identity and referrer relation.

Revision ID: 20261007_0032
Revises: 20261007_0031
"""
import secrets

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


revision = "20261007_0032"
down_revision = "20261007_0031"
branch_labels = None
depends_on = None

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_REFERRER_INDEX = "ix_customers_referrer_0032"
_REFERRER_FK = "fk_customers_referrer_0032"
_REFERRAL_UNIQUE_INDEX = "uq_customers_invite_code_0032"


def _new_code(bind, used):
    while True:
        code = "".join(secrets.choice(_ALPHABET) for _ in range(8))
        if code in used:
            continue
        row = bind.execute(
            sa.text("SELECT id FROM customers WHERE invite_code = :code"),
            {"code": code},
        ).first()
        if row is None:
            used.add(code)
            return code


def _column(inspector, table_name, column_name):
    for row in inspector.get_columns(table_name):
        if row["name"] == column_name:
            return row
    return None


def _has_unique_invite_key(inspector):
    for row in inspector.get_indexes("customers"):
        if row.get("unique") and row.get("column_names") == ["invite_code"]:
            return True
    for row in inspector.get_unique_constraints("customers"):
        if row.get("column_names") == ["invite_code"]:
            return True
    return False


def _has_referrer_fk(inspector):
    for row in inspector.get_foreign_keys("customers"):
        if (
            row.get("referred_columns") == ["id"]
            and row.get("constrained_columns") == ["referred_by_customer_id"]
            and row.get("referred_table") == "customers"
        ):
            return True
    return False


def _has_referrer_index(inspector):
    for row in inspector.get_indexes("customers"):
        if row.get("column_names") == ["referred_by_customer_id"]:
            return True
    return False


def upgrade():
    bind = op.get_bind()
    inspector = inspect(bind)

    invite_column = _column(inspector, "customers", "invite_code")
    if invite_column is None:
        op.add_column(
            "customers",
            sa.Column("invite_code", sa.String(length=20), nullable=True),
        )
        invite_column = {"name": "invite_code", "nullable": True}
        inspector = inspect(bind)

    # Bootstrap migration 0001 derives the initial schema from SQLAlchemy's
    # current metadata. On a fresh database invite_code may therefore already
    # exist. On an older production database it may be missing. Handle both.
    if invite_column.get("nullable", True):
        rows = bind.execute(
            sa.text("SELECT id FROM customers WHERE invite_code IS NULL ORDER BY id")
        ).scalars().all()
        used = set()
        for customer_id in rows:
            bind.execute(
                sa.text(
                    "UPDATE customers SET invite_code = :code "
                    "WHERE id = :customer_id"
                ),
                {"code": _new_code(bind, used), "customer_id": customer_id},
            )
        op.alter_column("customers", "invite_code", nullable=False)

    inspector = inspect(bind)
    if not _has_unique_invite_key(inspector):
        op.create_index(
            _REFERRAL_UNIQUE_INDEX,
            "customers",
            ["invite_code"],
            unique=True,
        )

    inspector = inspect(bind)
    if _column(inspector, "customers", "referred_by_customer_id") is None:
        op.add_column(
            "customers",
            sa.Column("referred_by_customer_id", sa.Integer(), nullable=True),
        )

    inspector = inspect(bind)
    if not _has_referrer_index(inspector):
        op.create_index(
            _REFERRER_INDEX,
            "customers",
            ["referred_by_customer_id"],
            unique=False,
        )

    inspector = inspect(bind)
    if not _has_referrer_fk(inspector):
        op.create_foreign_key(
            _REFERRER_FK,
            "customers",
            "customers",
            ["referred_by_customer_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade():
    # The bootstrap migration builds current metadata directly. A downgrade
    # from this compatibility migration must never remove columns/indexes that
    # were already present before revision 0032.
    pass
