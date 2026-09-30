"""Use white as the default banner pull/header color.

The header pull color was introduced in revision 20260930_0019 with
#111827 as the initial/default value. Existing rows created by that
migration therefore carry the old default even when no custom color
was intentionally configured.
"""
from alembic import op
import sqlalchemy as sa

revision = "20260930_0020"
down_revision = "20260930_0019"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return

    columns = {column["name"] for column in inspector.get_columns("banners")}
    if "header_top_background_color" not in columns:
        return

    op.execute(
        sa.text(
            """
            UPDATE banners
            SET header_top_background_color = '#ffffff'
            WHERE header_top_background_color IS NULL
               OR trim(header_top_background_color) = ''
               OR lower(header_top_background_color) = '#111827'
            """
        )
    )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("banners"):
        return

    columns = {column["name"] for column in inspector.get_columns("banners")}
    if "header_top_background_color" not in columns:
        return

    op.execute(
        sa.text(
            """
            UPDATE banners
            SET header_top_background_color = '#111827'
            WHERE lower(header_top_background_color) = '#ffffff'
            """
        )
    )
