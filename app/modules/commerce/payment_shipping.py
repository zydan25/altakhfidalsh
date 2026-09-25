from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from ...extensions import db
from ...models import (
    Order,
    PaymentMethod,
    PaymentProof,
    PaymentTransaction,
    Shipment,
    ShipmentEvent,
    ShippingMethod,
)
from .services import CommerceService


class PaymentShippingService:
    @staticmethod
    def create_payment_method(payload):
        name = str(payload["name"]).strip()
        code = str(payload["code"]).strip().lower()
        if PaymentMethod.query.filter_by(code=code).first():
            raise ValueError("payment method code already exists")
        row = PaymentMethod(
            name=name,
            code=code,
            provider=payload.get("provider"),
            supports_proof=bool(payload.get("supports_proof", False)),
        )
        db.session.add(row)
        db.session.commit()
        return {"id": row.id, "name": row.name, "code": row.code, "supports_proof": row.supports_proof}

    @staticmethod
    def record_payment(payload):
        order = db.session.get(Order, int(payload["order_id"]))
        method = db.session.get(PaymentMethod, int(payload["method_id"]))
        if order is None or method is None:
            raise LookupError("order or payment method not found")
        amount = Decimal(str(payload["amount"]))
        if amount <= 0:
            raise ValueError("payment amount must be positive")
        transaction = PaymentTransaction(
            order_id=order.id,
            method_id=method.id,
            amount=amount,
            currency_id=int(payload["currency_id"]),
            provider_ref=payload.get("provider_ref") or "MANUAL-" + uuid4().hex[:10].upper(),
            status=str(payload.get("status", "pending")),
            paid_at=datetime.now(timezone.utc) if payload.get("status") == "paid" else None,
        )
        db.session.add(transaction)
        db.session.flush()
        if transaction.status == "paid":
            order.payment_status = "paid"
            if order.status in {"created", "awaiting_payment"}:
                order.status = "paid"
        db.session.commit()
        return {
            "id": transaction.id,
            "order_id": transaction.order_id,
            "amount": str(transaction.amount),
            "status": transaction.status,
            "provider_ref": transaction.provider_ref,
        }

    @staticmethod
    def attach_payment_proof(payload):
        order = db.session.get(Order, int(payload["order_id"]))
        if order is None:
            raise LookupError("order not found")
        if not payload.get("asset_id"):
            raise ValueError("asset_id is required")
        proof = PaymentProof(
            order_id=order.id,
            transaction_id=payload.get("transaction_id"),
            asset_id=int(payload["asset_id"]),
            submitted_by=payload.get("submitted_by"),
            status="pending",
        )
        db.session.add(proof)
        db.session.commit()
        return {"id": proof.id, "order_id": proof.order_id, "asset_id": proof.asset_id, "status": proof.status}

    @staticmethod
    def create_shipping_method(payload):
        row = ShippingMethod(
            name=str(payload["name"]).strip(),
            code=str(payload["code"]).strip().lower(),
            delivery_days_min=payload.get("delivery_days_min"),
            delivery_days_max=payload.get("delivery_days_max"),
            supports_cod=bool(payload.get("supports_cod", False)),
        )
        if ShippingMethod.query.filter_by(code=row.code).first():
            raise ValueError("shipping method code already exists")
        db.session.add(row)
        db.session.commit()
        return {
            "id": row.id,
            "name": row.name,
            "code": row.code,
            "delivery_days_min": row.delivery_days_min,
            "delivery_days_max": row.delivery_days_max,
            "supports_cod": row.supports_cod,
        }

    @staticmethod
    def create_shipment(payload):
        order = db.session.get(Order, int(payload["order_id"]))
        if order is None:
            raise LookupError("order not found")
        shipment = Shipment(
            order_id=order.id,
            shipping_method_id=payload.get("shipping_method_id"),
            tracking_no=payload.get("tracking_no"),
            status=str(payload.get("status", "pending")),
            shipped_at=datetime.now(timezone.utc) if payload.get("status") == "shipped" else None,
        )
        db.session.add(shipment)
        order.shipping_status = shipment.status
        if shipment.status == "shipped":
            order.status = "shipped"
        db.session.flush()
        if payload.get("event"):
            event = payload["event"]
            db.session.add(ShipmentEvent(
                shipment_id=shipment.id,
                status=str(event.get("status", shipment.status)),
                location=event.get("location"),
                description=event.get("description"),
                occurred_at=datetime.now(timezone.utc),
            ))
        db.session.commit()
        return {
            "id": shipment.id,
            "order_id": shipment.order_id,
            "shipping_method_id": shipment.shipping_method_id,
            "tracking_no": shipment.tracking_no,
            "status": shipment.status,
        }

    @staticmethod
    def add_shipment_event(shipment_id, payload):
        shipment = db.session.get(Shipment, shipment_id)
        if shipment is None:
            raise LookupError("shipment not found")
        event = ShipmentEvent(
            shipment_id=shipment.id,
            status=str(payload["status"]),
            location=payload.get("location"),
            description=payload.get("description"),
            occurred_at=datetime.now(timezone.utc),
        )
        shipment.status = event.status
        order = db.session.get(Order, shipment.order_id)
        if order:
            order.shipping_status = event.status
            if event.status == "delivered":
                order.status = "delivered"
                shipment.delivered_at = datetime.now(timezone.utc)
        db.session.add(event)
        db.session.commit()
        return {"id": event.id, "shipment_id": event.shipment_id, "status": event.status}
