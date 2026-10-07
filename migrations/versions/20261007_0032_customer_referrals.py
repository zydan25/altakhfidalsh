"""Add customer referral identity and referrer relation.

Revision ID: 20261007_0032
Revises: 20261007_0031
"""
import secrets

from alembic import op
import sqlalchemy as sa

revision = "20261007_0032"
down_revision = "20261007_0031"
branch_labels = None
depends_on = None

_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


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


def upgrade():
    op.add_column(
        "customers",
        sa.Column("invite_code", sa.String(length=20), nullable=True),
    )
    op.add_column(
        "customers",
        sa.Column("referred_by_customer_id", sa.Integer(), nullable=True),
    )

    op.create_foreign_key(
        "fk_customers_referred_by_customer_id",
        "customers",
        "customers",
        ["referred_by_customer_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_customers_referred_by_customer_id",
        "customers",
        ["referred_by_customer_id"],
        unique=False,
    )
    op.create_index(
        "uq_customers_invite_code",
        "customers",
        ["invite_code"],
        unique=True,
    )

    bind = op.get_bind()
    used = set()
    customer_ids = bind.execute(
        sa.text("SELECT id FROM customers WHERE invite_code IS NULL ORDER BY id")
    ).scalars().all()
    for customer_id in customer_ids:
        bind.execute(
            sa.text(
                "UPDATE customers SET invite_code = :code WHERE id = :customer_id"
            ),
            {"code": _new_code(bind, used), "customer_id": customer_id},
        )

    op.alter_column("customers", "invite_code", nullable=False)


def downgrade():
    op.drop_index("uq_customers_invite_code", table_name="customers")
    op.drop_index("ix_customers_referred_by_customer_id", table_name="customers")
    op.drop_constraint(
        "fk_customers_referred_by_customer_id",
        "customers",
        type_="foreignkey",
    )
    op.drop_column("customers", "referred_by_customer_id")
    op.drop_column("customers", "invite_code")
