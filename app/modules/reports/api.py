from sqlalchemy import func

from . import api_bp
from ...security import admin_api_required
from ...extensions import db
from ...models import Customer, Order, Product, ProductVariant, StockInventory


@api_bp.get("/sales")
@admin_api_required("report.view")
def sales_report():
    row = db.session.query(
        func.count(Order.id),
        func.coalesce(func.sum(Order.subtotal), 0),
        func.coalesce(func.sum(Order.discount), 0),
        func.coalesce(func.sum(Order.shipping), 0),
        func.coalesce(func.sum(Order.total), 0),
    ).filter(Order.status.notin_(["cancelled", "returned"])).one()
    return {
        "orders_count": int(row[0] or 0),
        "subtotal": str(row[1] or 0),
        "discount": str(row[2] or 0),
        "shipping": str(row[3] or 0),
        "total": str(row[4] or 0),
    }


@api_bp.get("/orders/status")
@admin_api_required("report.view")
def orders_by_status():
    rows = db.session.query(Order.status, func.count(Order.id)).group_by(Order.status).order_by(func.count(Order.id).desc()).all()
    return {"items": [{"status": status, "count": int(count)} for status, count in rows]}


@api_bp.get("/customers")
@admin_api_required("report.view")
def customers_report():
    row = db.session.query(func.count(Customer.id)).one()
    active = db.session.query(func.count(Customer.id)).filter(Customer.is_active.is_(True)).scalar() or 0
    return {"total": int(row[0] or 0), "active": int(active)}


@api_bp.get("/inventory")
@admin_api_required("report.view")
def inventory_report():
    row = db.session.query(
        func.count(ProductVariant.id),
        func.coalesce(func.sum(StockInventory.on_hand), 0),
        func.coalesce(func.sum(StockInventory.reserved), 0),
        func.coalesce(func.sum(StockInventory.available), 0),
    ).outerjoin(StockInventory, StockInventory.variant_id == ProductVariant.id).one()
    return {
        "variants": int(row[0] or 0),
        "on_hand": int(row[1] or 0),
        "reserved": int(row[2] or 0),
        "available": int(row[3] or 0),
    }


@api_bp.get("/catalog")
@admin_api_required("report.view")
def catalog_report():
    return {
        "products": int(db.session.query(func.count(Product.id)).scalar() or 0),
        "variants": int(db.session.query(func.count(ProductVariant.id)).scalar() or 0),
    }
