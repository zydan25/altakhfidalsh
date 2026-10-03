from sqlalchemy import delete

from ..extensions import db
from ..models import (
    AuthSession,
    Cart,
    CartItem,
    Conversation,
    CouponRedemption,
    Customer,
    CustomerAddress,
    CustomerDevice,
    CustomerNotification,
    CustomerPreference,
    CustomerPricingAssignment,
    GiftIssuance,
    Notification,
    OTPRequest,
    Order,
    OrderItem,
    OrderItemOption,
    OrderStatusHistory,
    PaymentProof,
    PaymentTransaction,
    Refund,
    ReturnItem,
    ReturnRequest,
    Review,
    RecentlyViewed,
    Shipment,
    ShipmentEvent,
    ShippingRate,
    WarrantyClaim,
    Wallet,
    WalletTransaction,
    Wishlist,
    WishlistItem,
    StockInventory,
)


RESERVING_ORDER_STATUSES = {"created", "awaiting_payment", "paid", "processing"}


def _release_order_reservations(order_items):
    for item in order_items:
        if item.variant_id is None or item.stock_location_id is None:
            continue

        stock = (
            StockInventory.query
            .filter_by(
                variant_id=item.variant_id,
                location_id=item.stock_location_id,
            )
            .with_for_update()
            .first()
        )
        if stock is None:
            continue

        reserved = max(0, int(stock.reserved or 0))
        qty = max(0, int(item.qty or 0))
        released = min(reserved, qty)
        if released:
            stock.reserved = reserved - released
            stock.available = max(
                0,
                int(stock.on_hand or 0) - int(stock.reserved or 0),
            )


def delete_customer_permanently(customer_id):
    """Permanently remove a customer and all customer/order-owned records."""
    customer = db.session.get(Customer, int(customer_id))
    if customer is None:
        raise LookupError("customer not found")

    order_rows = (
        Order.query
        .filter(Order.customer_id == customer.id)
        .order_by(Order.id)
        .all()
    )
    order_ids = [row.id for row in order_rows]

    if order_ids:
        item_rows = (
            OrderItem.query
            .filter(OrderItem.order_id.in_(order_ids))
            .order_by(OrderItem.id)
            .all()
        )
        item_ids = [row.id for row in item_rows]

        reserving_orders = [
            row for row in order_rows if row.status in RESERVING_ORDER_STATUSES
        ]
        if reserving_orders:
            reserving_ids = {row.id for row in reserving_orders}
            _release_order_reservations(
                row for row in item_rows if row.order_id in reserving_ids
            )

        shipment_ids = [
            row.id
            for row in Shipment.query.filter(Shipment.order_id.in_(order_ids)).all()
        ]

        if item_ids:
            db.session.execute(
                delete(ReturnItem).where(ReturnItem.order_item_id.in_(item_ids))
            )
            db.session.execute(
                delete(OrderItemOption).where(OrderItemOption.order_item_id.in_(item_ids))
            )

        if shipment_ids:
            db.session.execute(
                delete(ShipmentEvent).where(ShipmentEvent.shipment_id.in_(shipment_ids))
            )

        # Delete order-owned records explicitly so this stays deterministic even
        # on databases where ORM/database cascade behavior differs.
        db.session.execute(delete(WarrantyClaim).where(WarrantyClaim.order_id.in_(order_ids)))
        db.session.execute(delete(PaymentProof).where(PaymentProof.order_id.in_(order_ids)))
        db.session.execute(
            delete(PaymentTransaction).where(PaymentTransaction.order_id.in_(order_ids))
        )
        db.session.execute(delete(Refund).where(Refund.order_id.in_(order_ids)))
        db.session.execute(
            delete(ReturnRequest).where(ReturnRequest.order_id.in_(order_ids))
        )
        db.session.execute(
            delete(OrderStatusHistory).where(OrderStatusHistory.order_id.in_(order_ids))
        )
        if shipment_ids:
            db.session.execute(delete(Shipment).where(Shipment.id.in_(shipment_ids)))
        if item_ids:
            db.session.execute(delete(OrderItem).where(OrderItem.id.in_(item_ids)))
        db.session.execute(delete(Order).where(Order.id.in_(order_ids)))

    # Customer-owned records outside orders.
    cart_ids = [
        row.id for row in Cart.query.filter(Cart.customer_id == customer.id).all()
    ]
    if cart_ids:
        db.session.execute(delete(CartItem).where(CartItem.cart_id.in_(cart_ids)))
        db.session.execute(delete(Cart).where(Cart.id.in_(cart_ids)))

    wishlist_ids = [
        row.id
        for row in Wishlist.query.filter(Wishlist.customer_id == customer.id).all()
    ]
    if wishlist_ids:
        db.session.execute(
            delete(WishlistItem).where(WishlistItem.wishlist_id.in_(wishlist_ids))
        )
        db.session.execute(delete(Wishlist).where(Wishlist.id.in_(wishlist_ids)))

    wallet_ids = [
        row.id for row in Wallet.query.filter(Wallet.customer_id == customer.id).all()
    ]
    if wallet_ids:
        db.session.execute(
            delete(WalletTransaction).where(WalletTransaction.wallet_id.in_(wallet_ids))
        )
        db.session.execute(delete(Wallet).where(Wallet.id.in_(wallet_ids)))

    db.session.execute(
        delete(CustomerNotification).where(
            CustomerNotification.customer_id == customer.id
        )
    )
    db.session.execute(
        delete(Notification).where(Notification.customer_id == customer.id)
    )
    db.session.execute(
        delete(CouponRedemption).where(CouponRedemption.customer_id == customer.id)
    )
    db.session.execute(delete(GiftIssuance).where(GiftIssuance.customer_id == customer.id))
    db.session.execute(delete(Review).where(Review.customer_id == customer.id))
    db.session.execute(
        delete(WarrantyClaim).where(WarrantyClaim.customer_id == customer.id)
    )
    db.session.execute(
        delete(ReturnRequest).where(ReturnRequest.customer_id == customer.id)
    )
    db.session.execute(
        delete(Conversation).where(Conversation.customer_id == customer.id)
    )
    db.session.execute(
        delete(ShippingRate).where(ShippingRate.customer_id == customer.id)
    )
    db.session.execute(
        delete(RecentlyViewed).where(RecentlyViewed.customer_id == customer.id)
    )
    db.session.execute(
        delete(CustomerAddress).where(CustomerAddress.customer_id == customer.id)
    )
    db.session.execute(
        delete(CustomerPricingAssignment).where(
            CustomerPricingAssignment.customer_id == customer.id
        )
    )
    db.session.execute(
        delete(CustomerDevice).where(CustomerDevice.customer_id == customer.id)
    )
    db.session.execute(
        delete(AuthSession).where(AuthSession.customer_id == customer.id)
    )
    db.session.execute(
        delete(CustomerPreference).where(CustomerPreference.customer_id == customer.id)
    )
    db.session.execute(
        delete(OTPRequest).where(OTPRequest.customer_id == customer.id)
    )

    db.session.delete(customer)
    db.session.flush()
    return customer.id
