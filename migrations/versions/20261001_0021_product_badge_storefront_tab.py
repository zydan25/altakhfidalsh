"""Add storefront discovery grouping to product badges.

Badges can now explicitly belong to the storefront "new" or "offers"
discovery tab. Existing badges remain ungrouped unless their code clearly
matches a known storefront group.
"""
from alembic import op
import sqlalchemy as sa

revision = "20261001_0021"
down_revision = "20260930_0020"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("badges"):
        return

    columns = {column["name"] for column in inspector.get_columns("badges")}
    if "storefront_tab" not in columns:
        op.add_column(
            "badges",
            sa.Column(
                "storefront_tab",
                sa.String(length=30),
                nullable=False,
                server_default="none",
            ),
        )

    op.execute(
        sa.text(
            """
            UPDATE badges
            SET storefront_tab = CASE
                WHEN lower(code) IN ('new', 'new_in', 'new-arrivals', 'new_arrivals')
                    THEN 'new'
                WHEN lower(code) IN ('offer', 'offers', 'sale', 'sales', 'deal', 'deals', 'discount')
                    THEN 'offers'
                ELSE COALESCE(storefront_tab, 'none')
            END
            """
        )
    )

    op.alter_column(
        "badges",
        "storefront_tab",
        server_default=None,
        existing_type=sa.String(length=30),
        existing_nullable=False,
    )

    # Seed the two primary storefront badges when their codes are unused.
    op.execute(
        sa.text(
            """
            INSERT INTO badges
                (name, code, bg_color, text_color, style, storefront_tab, priority, is_active, created_at, updated_at)
            VALUES
                ('جديد', 'new', '#16a34a', '#ffffff', 'solid', 'new', 100, true, now(), now())
            ON CONFLICT (code) DO NOTHING
            """
        )
    )
    op.execute(
        sa.text(
            """
            INSERT INTO badges
                (name, code, bg_color, text_color, style, storefront_tab, priority, is_active, created_at, updated_at)
            VALUES
                ('عرض', 'offer', '#dc2626', '#ffffff', 'solid', 'offers', 90, true, now(), now())
            ON CONFLICT (code) DO NOTHING
            """
        )
    )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("badges"):
        return

    columns = {column["name"] for column in inspector.get_columns("badges")}
    if "storefront_tab" in columns:
        op.drop_column("badges", "storefront_tab")
