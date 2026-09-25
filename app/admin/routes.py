from decimal import Decimal, InvalidOperation

from flask import render_template, request
from sqlalchemy import func

from .navigation import NAVIGATION
from ..extensions import db
from ..models import (
    Category,
    Conversation,
    Currency,
    Customer,
    Order,
    Product,
    ProductCategory,
)


def _safe_count(model):
    try:
        return db.session.query(func.count(model.id)).scalar() or 0
    except Exception:
        db.session.rollback()
        return 0


def _navigation_context():
    current_path = request.path
    page_item_map = []
    for section in NAVIGATION:
        section.active = any(
            current_path == child.route or current_path.startswith(child.route + "/")
            for child in section.children
        )
        for child in section.children:
            page_item_map.append(
                {
                    "label": child.label,
                    "route": child.route,
                    "section": section.label,
                }
            )
    return {
        "navigation": NAVIGATION,
        "current_path": current_path,
        "page_item_map": page_item_map,
    }


def _category_tree_rows():
    categories = (
        Category.query
        .filter(Category.is_active.is_(True))
        .order_by(Category.parent_id, Category.sort_order, Category.name)
        .all()
    )
    by_parent = {}
    for category in categories:
        by_parent.setdefault(category.parent_id, []).append(category)

    rows = []

    def walk(parent_id, depth=0):
        for category in by_parent.get(parent_id, []):
            rows.append((category, depth))
            walk(category.id, depth + 1)

    walk(None)
    return rows


def register_admin_routes(admin_bp):
    @admin_bp.get("/")
    def dashboard():
        context = _navigation_context()
        metrics = {
            "products": _safe_count(Product),
            "categories": _safe_count(Category),
            "orders": _safe_count(Order),
            "customers": _safe_count(Customer),
            "conversations": _safe_count(Conversation),
        }
        return render_template(
            "admin/dashboard.html",
            title="لوحة الإدارة",
            metrics=metrics,
            **context,
        )

    @admin_bp.route("/categories", methods=["GET", "POST"])
    def categories():
        context = _navigation_context()
        error = None
        if request.method == "POST":
            name = (request.form.get("name") or "").strip()
            slug = (request.form.get("slug") or "").strip().lower()
            parent_id = request.form.get("parent_id", type=int)
            display_style = (request.form.get("display_style") or "circle").strip()

            if not name or not slug:
                error = "اسم الفئة وSlug مطلوبان."
            else:
                duplicate = Category.query.filter_by(parent_id=parent_id, slug=slug).first()
                if duplicate:
                    error = "الـSlug مستخدم داخل هذا المستوى."
                else:
                    category = Category(
                        name=name,
                        slug=slug,
                        parent_id=parent_id,
                        display_style=display_style,
                    )
                    db.session.add(category)
                    db.session.commit()
                    return (
                        render_template(
                            "admin/categories.html",
                            title="التصنيفات",
                            rows=_category_tree_rows(),
                            parents=Category.query.filter_by(is_active=True).order_by(Category.name).all(),
                            success="تم إنشاء الفئة بنجاح.",
                            error=None,
                            **context,
                        )
                    )

        try:
            rows = _category_tree_rows()
            parents = Category.query.filter_by(is_active=True).order_by(Category.name).all()
        except Exception:
            db.session.rollback()
            rows = []
            parents = []
            error = error or "قاعدة البيانات غير متاحة حاليًا."

        return render_template(
            "admin/categories.html",
            title="التصنيفات",
            rows=rows,
            parents=parents,
            success=None,
            error=error,
            **context,
        )

    @admin_bp.get("/products")
    def products():
        context = _navigation_context()
        try:
            items = (
                Product.query
                .filter(Product.is_active.is_(True))
                .order_by(Product.id.desc())
                .limit(100)
                .all()
            )
            error = None
        except Exception:
            db.session.rollback()
            items = []
            error = "قاعدة البيانات غير متاحة حاليًا."
        return render_template(
            "admin/products.html",
            title="المنتجات",
            products=items,
            error=error,
            **context,
        )

    @admin_bp.route("/products/new", methods=["GET", "POST"])
    def product_new():
        context = _navigation_context()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        categories = Category.query.filter_by(is_active=True).order_by(Category.name).all()
        error = None

        if request.method == "POST":
            sku = (request.form.get("sku") or "").strip().upper()
            name = (request.form.get("name") or "").strip()
            description = (request.form.get("description") or "").strip()
            base_price_raw = (request.form.get("base_price") or "").strip()
            base_currency_id = request.form.get("base_currency_id", type=int)
            category_id = request.form.get("category_id", type=int)

            if not sku or not name or not base_price_raw or not base_currency_id:
                error = "SKU واسم المنتج والسعر والعملة الأساسية حقول مطلوبة."
            else:
                try:
                    base_price = Decimal(base_price_raw)
                except (InvalidOperation, ValueError):
                    error = "السعر الأساسي غير صحيح."
                if error is None and base_price < 0:
                    error = "السعر الأساسي لا يمكن أن يكون سالبًا."

            if error is None:
                if Product.query.filter_by(sku=sku).first():
                    error = "SKU مستخدم مسبقًا."

            if error is None:
                product = Product(
                    sku=sku,
                    name=name,
                    description=description or None,
                    base_currency_id=base_currency_id,
                    base_price=base_price,
                    status="draft",
                )
                db.session.add(product)
                db.session.flush()
                if category_id:
                    db.session.add(
                        ProductCategory(
                            product_id=product.id,
                            category_id=category_id,
                            is_primary=True,
                        )
                    )
                db.session.commit()
                return render_template(
                    "admin/product_wizard.html",
                    title="إعداد المنتج",
                    product_id=product.id,
                    product=product,
                    categories=categories,
                    **context,
                )

        return render_template(
            "admin/product_form.html",
            title="إضافة منتج",
            currencies=currencies,
            categories=categories,
            error=error,
            success=None,
            **context,
        )

    @admin_bp.get("/products/<int:product_id>/edit")
    def product_edit(product_id):
        context = _navigation_context()
        product = db.session.get(Product, product_id)
        if product is None:
            return render_template(
                "admin/module.html",
                title="المنتج غير موجود",
                section="الكتالوج",
                requested_path=request.path,
                **context,
            ), 404
        categories = Category.query.filter_by(is_active=True).order_by(Category.name).all()
        return render_template(
            "admin/product_wizard.html",
            title=f"إعداد المنتج · {product.name}",
            product_id=product.id,
            product=product,
            categories=categories,
            **context,
        )

    @admin_bp.get("/<path:subpath>")
    def module_shell(subpath):
        context = _navigation_context()
        requested = "/" + subpath.rstrip("/")
        title = "وحدة الإدارة"
        section = "النظام"
        for item in context["page_item_map"]:
            if requested == item["route"]:
                title = item["label"]
                section = item["section"]
                break
        return render_template(
            "admin/module.html",
            title=title,
            section=section,
            requested_path=requested,
            **context,
        )
