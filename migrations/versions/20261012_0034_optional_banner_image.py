"""Allow removing the main banner image while keeping the banner as a draft.

Revision ID: 20261012_0034
Revises: 20261008_0033
"""
from alembic import op
import sqlalchemy as sa


revision = "20261012_0034"
down_revision = "20261008_0033"
branch_labels = None
depends_on = None


def _has_table(name):
    return sa.inspect(op.get_bind()).has_table(name)


def _columns(table):
    if not _has_table(table):
        return {}
    return {column["name"]: column for column in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade():
    columns = _columns("banners")
    if "image_asset_id" in columns and columns["image_asset_id"]["nullable"] is False:
        op.alter_column(
            "banners",
            "image_asset_id",
            existing_type=sa.Integer(),
            nullable=True,
        )


def downgrade():
    columns = _columns("banners")
    if "image_asset_id" in columns and columns["image_asset_id"]["nullable"]:
        # Refuse a lossy rollback if any banner has intentionally removed its image.
        missing = op.get_bind().execute(
            sa.text("SELECT COUNT(*) FROM banners WHERE image_asset_id IS NULL")
        ).scalar_one()
        if missing:
            raise RuntimeError(
                "Cannot make banners.image_asset_id NOT NULL while image-less drafts exist."
            )
        op.alter_column(
            "banners",
            "image_asset_id",
            existing_type=sa.Integer(),
            nullable=False,
        )
