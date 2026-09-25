from ...extensions import db
from ...models import (
    Order,
    OrderItem,
    ReturnItem,
    ReturnRequest,
    Review,
    WarrantyClaim,
)


class AfterSalesService:
    @staticmethod
    def create_return(payload):
        order_id = int(payload["order_id"])
        customer_id = int(payload["customer_id"])
        order = db.session.get(Order, order_id)
        if order is None or order.customer_id != customer_id:
            raise ValueError("order does not belong to customer")
        if order.status not in {"delivered", "returned"}:
            raise ValueError("order is not eligible for return")
        items = payload.get("items") or []
        if not items:
            raise ValueError("return must contain items")

        request_row = ReturnRequest(
            order_id=order_id,
            customer_id=customer_id,
            reason=str(payload["reason"]).strip(),
            description=(payload.get("description") or "").strip() or None,
            status="requested",
        )
        db.session.add(request_row)
        db.session.flush()

        for raw in items:
            order_item = db.session.get(OrderItem, int(raw["order_item_id"]))
            qty = int(raw.get("qty", 1))
            if order_item is None or order_item.order_id != order_id or qty <= 0 or qty > order_item.qty:
                raise ValueError("invalid return item")
            db.session.add(ReturnItem(
                return_request_id=request_row.id,
                order_item_id=order_item.id,
                qty=qty,
                condition=(raw.get("condition") or "").strip() or None,
            ))

        db.session.commit()
        return {
            "id": request_row.id,
            "order_id": request_row.order_id,
            "customer_id": request_row.customer_id,
            "reason": request_row.reason,
            "status": request_row.status,
        }

    @staticmethod
    def create_warranty_claim(payload):
        order = db.session.get(Order, int(payload["order_id"]))
        item = db.session.get(OrderItem, int(payload["order_item_id"]))
        if order is None or item is None or item.order_id != order.id:
            raise ValueError("invalid order item")
        if order.customer_id != int(payload["customer_id"]):
            raise ValueError("order does not belong to customer")
        row = WarrantyClaim(
            customer_id=order.customer_id,
            order_id=order.id,
            order_item_id=item.id,
            issue=str(payload["issue"]).strip(),
            description=(payload.get("description") or "").strip() or None,
            status="submitted",
        )
        db.session.add(row)
        db.session.commit()
        return {
            "id": row.id,
            "order_id": row.order_id,
            "order_item_id": row.order_item_id,
            "status": row.status,
        }

    @staticmethod
    def create_review(payload):
        product_id = int(payload["product_id"])
        customer_id = int(payload["customer_id"])
        order_item_id = payload.get("order_item_id")
        if order_item_id:
            item = db.session.get(OrderItem, int(order_item_id))
            if item is None or item.product_id != product_id:
                raise ValueError("invalid order item")
            if db.session.get(Order, item.order_id).customer_id != customer_id:
                raise ValueError("order item does not belong to customer")
        rating = int(payload["rating"])
        if rating < 1 or rating > 5:
            raise ValueError("rating must be between 1 and 5")
        row = Review(
            product_id=product_id,
            customer_id=customer_id,
            order_item_id=int(order_item_id) if order_item_id else None,
            rating=rating,
            title=(payload.get("title") or "").strip() or None,
            body=(payload.get("body") or "").strip() or None,
            status="pending",
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "status": row.status}
