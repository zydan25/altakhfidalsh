"""Add configurable home header search/category gap."""

from alembic import op
import sqlalchemy as sa

revision = "20261002_0023"
down_revision = "20261001_0022"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    if not sa.inspect(bind).has_table("app_settings"):
        return

    op.execute(
        sa.text(
            """
            INSERT INTO app_settings (group_code, key, value, value_type)
            SELECT :group_code, :key, :value, :value_type
            WHERE NOT EXISTS (
                SELECT 1
                FROM app_settings
                WHERE group_code = :group_code
                  AND key = :key
            )
            """
        ).bindparams(
            group_code="storefront",
            key="home_header_category_gap",
            value="3",
            value_type="number",
        )
    )


def downgrade():
    bind = op.get_bind()
    if not sa.inspect(bind).has_table("app_settings"):
        return

    op.execute(
        sa.text(
            "DELETE FROM app_settings "
            "WHERE group_code = :group_code AND key = :key"
        ).bindparams(
            group_code="storefront",
            key="home_header_category_gap",
        )
    )
