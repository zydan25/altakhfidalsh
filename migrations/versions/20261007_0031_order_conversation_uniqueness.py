"""Keep one support conversation per order.

Revision ID: 20261007_0031
Revises: 20261006_0030
"""
from alembic import op
import sqlalchemy as sa

revision = "20261007_0031"
down_revision = "20261006_0030"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()

    # Collapse historical duplicate order threads into the oldest thread.
    duplicate_orders = bind.execute(
        sa.text(
            """
            SELECT order_id
            FROM conversations
            WHERE order_id IS NOT NULL
            GROUP BY order_id
            HAVING COUNT(*) > 1
            ORDER BY order_id
            """
        )
    ).scalars().all()

    conversation_table = sa.table(
        "conversations",
        sa.column("id", sa.Integer),
        sa.column("customer_id", sa.Integer),
        sa.column("order_id", sa.Integer),
        sa.column("type", sa.String),
        sa.column("subject", sa.String),
        sa.column("status", sa.String),
    )
    notification_table = sa.table(
        "notifications",
        sa.column("id", sa.Integer),
        sa.column("data", sa.JSON),
    )

    duplicate_map = {}

    for order_id in duplicate_orders:
        ids = bind.execute(
            sa.text(
                """
                SELECT id
                FROM conversations
                WHERE order_id = :order_id
                ORDER BY id
                """
            ),
            {"order_id": order_id},
        ).scalars().all()
        if len(ids) < 2:
            continue

        keep_id = ids[0]
        duplicate_map.update({int(old_id): int(keep_id) for old_id in ids[1:]})

        bind.execute(
            sa.update(conversation_table)
            .where(conversation_table.c.id == keep_id)
            .values(type="order_support", status="open")
        )

    # Move all messages and participants first, so deleting duplicate threads
    # does not discard the actual conversation history.
    for old_id, keep_id in duplicate_map.items():
        bind.execute(
            sa.text(
                "UPDATE messages SET conversation_id = :keep_id "
                "WHERE conversation_id = :old_id"
            ),
            {"keep_id": keep_id, "old_id": old_id},
        )
        bind.execute(
            sa.text(
                "UPDATE conversation_participants SET conversation_id = :keep_id "
                "WHERE conversation_id = :old_id"
            ),
            {"keep_id": keep_id, "old_id": old_id},
        )

    # Notifications that open a conversation must now point to the canonical
    # order thread as well.
    if duplicate_map:
        notifications = bind.execute(
            sa.select(notification_table.c.id, notification_table.c.data)
        ).mappings().all()
        for row in notifications:
            data = row["data"]
            if not isinstance(data, dict):
                continue
            old_id = data.get("conversation_id")
            if data.get("target") != "conversation" or old_id not in duplicate_map:
                continue
            data = dict(data)
            data["conversation_id"] = duplicate_map[int(old_id)]
            bind.execute(
                sa.update(notification_table)
                .where(notification_table.c.id == row["id"])
                .values(data=data)
            )

    for old_id in duplicate_map:
        bind.execute(
            sa.text("DELETE FROM conversations WHERE id = :old_id"),
            {"old_id": old_id},
        )

    # An order can only have one order-specific support conversation.
    op.create_index(
        "uq_conversations_order_id",
        "conversations",
        ["order_id"],
        unique=True,
        postgresql_where=sa.text("order_id IS NOT NULL"),
    )


def downgrade():
    op.drop_index(
        "uq_conversations_order_id",
        table_name="conversations",
    )
