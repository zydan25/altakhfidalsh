"""Customer onboarding, order shipping override and delivery feedback.
Revision ID: 20261003_0029
Revises: 20261003_0028
"""
from alembic import op
import sqlalchemy as sa

revision = "20261003_0029"
down_revision = "20261003_0028"
branch_labels = None
depends_on = None

def _add(bind, table, name, column):
    inspector = sa.inspect(bind)
    columns = {c["name"] for c in inspector.get_columns(table)}
    if name not in columns:
        op.add_column(table, column)

def upgrade():
    bind = op.get_bind()
    _add(bind, "customers", "gender", sa.Column("gender", sa.String(20), nullable=True))
    _add(bind, "customers", "password_hash", sa.Column("password_hash", sa.String(255), nullable=True))
    _add(bind, "customers", "privacy_accepted_at", sa.Column("privacy_accepted_at", sa.DateTime(timezone=True), nullable=True))
    _add(bind, "customers", "privacy_policy_version", sa.Column("privacy_policy_version", sa.String(40), nullable=True))
    _add(bind, "customers", "onboarding_completed", sa.Column("onboarding_completed", sa.Boolean(), nullable=False, server_default=sa.false()))
    _add(bind, "orders", "shipping_override", sa.Column("shipping_override", sa.Numeric(24, 4), nullable=True))
    _add(bind, "orders", "shipping_override_note", sa.Column("shipping_override_note", sa.Text(), nullable=True))
    _add(bind, "orders", "customer_feedback", sa.Column("customer_feedback", sa.Text(), nullable=True))
    _add(bind, "orders", "customer_rating", sa.Column("customer_rating", sa.Integer(), nullable=True))

def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for table, name in [
        ("orders", "customer_rating"), ("orders", "customer_feedback"),
        ("orders", "shipping_override_note"), ("orders", "shipping_override"),
        ("customers", "onboarding_completed"), ("customers", "privacy_policy_version"),
        ("customers", "privacy_accepted_at"), ("customers", "password_hash"), ("customers", "gender"),
    ]:
        columns = {c["name"] for c in inspector.get_columns(table)}
        if name in columns:
            op.drop_column(table, name)
