import re

from app.admin.context import (
    ORDER_STATUS_LABELS,
    PAYMENT_STATUS_LABELS,
    SHIPPING_STATUS_LABELS,
)
from app.modules.commerce.services import ORDER_STATUSES


def test_order_status_flow_contains_customer_tracking_states_in_order():
    expected = [
        "created",
        "awaiting_payment",
        "paid",
        "processing",
        "shipped",
        "in_transit",
        "delivered",
        "returned",
        "cancelled",
    ]
    assert ORDER_STATUSES == tuple(expected)
    assert ORDER_STATUSES.index("shipped") < ORDER_STATUSES.index("in_transit")
    assert ORDER_STATUSES.index("in_transit") < ORDER_STATUSES.index("delivered")


def test_every_order_status_has_an_arabic_admin_label():
    assert set(ORDER_STATUSES).issubset(ORDER_STATUS_LABELS)
    for status in ORDER_STATUSES:
        label = ORDER_STATUS_LABELS[status]
        assert label.strip()
        assert re.search(r"[A-Za-z]", label) is None, (status, label)


def test_payment_and_shipping_states_have_arabic_labels():
    for status in ("unpaid", "pending", "pending_proof", "paid", "failed"):
        assert status in PAYMENT_STATUS_LABELS
        assert re.search(r"[A-Za-z]", PAYMENT_STATUS_LABELS[status]) is None

    for status in (
        "pending", "shipped", "picked_up", "in_transit",
        "out_for_delivery", "delivered", "cancelled",
    ):
        assert status in SHIPPING_STATUS_LABELS
        assert re.search(r"[A-Za-z]", SHIPPING_STATUS_LABELS[status]) is None
