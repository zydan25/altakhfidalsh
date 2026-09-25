"""Initial bootstrap schema for the admin-first foundation.

This first production migration creates the complete SQLAlchemy metadata as one
versioned bootstrap. Subsequent schema changes must use normal Alembic revisions.
"""

from alembic import op
import sqlalchemy as sa


revision = "20260925_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    from app.models import db
    db.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade():
    from app.models import db
    db.metadata.drop_all(bind=op.get_bind())
