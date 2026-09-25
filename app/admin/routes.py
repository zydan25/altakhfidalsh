from decimal import Decimal, InvalidOperation

from flask import render_template, request
from sqlalchemy import func

from .context import build_admin_context
from ..modules.catalog.services import MediaService
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
    return build_admin_context()


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
    @admin_bp.route("/login", methods=["GET", "POST"])
    def login():
        from .auth import AdminAuthService
        error = None
        if request.method == "POST":
            try:
                AdminAuthService.login(
                    (request.form.get("username") or "").strip(),
                    request.form.get("password") or "",
                )
                return __import__("flask").redirect(request.form.get("next") or "/admin/")
            except ValueError as exc:
                error = str(exc)
        return render_template(
            "admin/login.html",
            error=error,
            next_path=request.args.get("next", "/admin/"),
        )

    @admin_bp.get("/logout")
    def logout():
        from .auth import AdminAuthService
        AdminAuthService.logout()
        return __import__("flask").redirect("/admin/login")

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
        success = None

        if request.method == "POST":
            action = (request.form.get("action") or "create").strip()
            try:
                name = (request.form.get("name") or "").strip()
                slug = (request.form.get("slug") or "").strip().lower()
                parent_id = request.form.get("parent_id", type=int)
                display_style = (request.form.get("display_style") or "circle").strip()

                if action == "create":
                    if not name or not slug:
                        raise ValueError("اسم الفئة وSlug مطلوبان.")
                    duplicate = Category.query.filter_by(parent_id=parent_id, slug=slug).first()
                    if duplicate:
                        raise ValueError("الـSlug مستخدم داخل هذا المستوى.")

                    icon_asset_id = None
                    icon_file = request.files.get("icon_file")
                    if icon_file and icon_file.filename:
                        assets = MediaService.save_generic_files([icon_file], "categories")
                        icon_asset_id = assets[0]["id"] if assets else None

                    category = Category(
                        name=name,
                        slug=slug,
                        parent_id=parent_id,
                        display_style=display_style,
                        sort_order=request.form.get("sort_order", 0, type=int),
                        is_featured=request.form.get("is_featured") == "on",
                        icon_asset_id=icon_asset_id,
                        badge_id=request.form.get("badge_id", type=int),
                    )
                    db.session.add(category)
                    db.session.commit()
                    success = "تم إنشاء الفئة."

                elif action == "update":
                    category_id = request.form.get("category_id", type=int)
                    category = db.session.get(Category, category_id)
                    if category is None:
                        raise ValueError("الفئة غير موجودة.")
                    if not name or not slug:
                        raise ValueError("اسم الفئة وSlug مطلوبان.")
                    if parent_id == category.id:
                        raise ValueError("لا يمكن أن تكون الفئة أبًا لنفسها.")

                    cursor = parent_id
                    seen = set()
                    while cursor is not None:
                        if cursor in seen:
                            raise ValueError("سلسلة الأب غير صالحة.")
                        seen.add(cursor)
                        if cursor == category.id:
                            raise ValueError("لا يمكن نقل الفئة إلى أحد فروعها.")
                        parent = db.session.get(Category, cursor)
                        cursor = parent.parent_id if parent else None

                    duplicate = (
                        Category.query
                        .filter(Category.id != category.id)
                        .filter(Category.parent_id == parent_id, Category.slug == slug)
                        .first()
                    )
                    if duplicate:
                        raise ValueError("الـSlug مستخدم داخل هذا المستوى.")

                    category.name = name
                    category.slug = slug
                    category.parent_id = parent_id
                    category.display_style = display_style
                    category.sort_order = request.form.get("sort_order", 0, type=int)
                    category.is_featured = request.form.get("is_featured") == "on"
                    category.badge_id = request.form.get("badge_id", type=int)
                    icon_file = request.files.get("icon_file")
                    if icon_file and icon_file.filename:
                        assets = MediaService.save_generic_files([icon_file], "categories")
                        category.icon_asset_id = assets[0]["id"] if assets else category.icon_asset_id
                    db.session.commit()
                    success = "تم تحديث الفئة."

                elif action == "delete":
                    category_id = request.form.get("category_id", type=int)
                    category = db.session.get(Category, category_id)
                    if category is None:
                        raise ValueError("الفئة غير موجودة.")
                    has_children = Category.query.filter_by(parent_id=category.id, is_active=True).first()
                    product_count = ProductCategory.query.filter_by(category_id=category.id).count()
                    if has_children:
                        raise ValueError("لا يمكن حذف فئة لها فروع. انقل الفروع أولًا.")
                    if product_count:
                        raise ValueError("لا يمكن حذف فئة مرتبطة بمنتجات. أزل الربط أولًا.")
                    category.is_active = False
                    db.session.commit()
                    success = "تم أرشفة الفئة."

                else:
                    raise ValueError("إجراء التصنيف غير معروف.")

            except (ValueError, OSError) as exc:
                db.session.rollback()
                error = str(exc)

        try:
            rows = _category_tree_rows()
            parents = Category.query.filter_by(is_active=True).order_by(Category.name).all()
            from ..models import Badge
            badges = Badge.query.filter_by(is_active=True).order_by(Badge.priority.desc(), Badge.name).all()
        except Exception:
            db.session.rollback()
            rows, parents, badges = [], [], []
            error = error or "قاعدة البيانات غير متاحة حاليًا."

        return render_template(
            "admin/categories.html",
            title="التصنيفات",
            rows=rows,
            parents=parents,
            badges=badges,
            success=success,
            error=error,
            **context,
        )

    @admin_bp.post("/categories/<int:category_id>")
    def category_update(category_id):
        request.form  # keep route explicit in the navigation and browser history
        context = _navigation_context()
        category = db.session.get(Category, category_id)
        if category is None:
            return render_template(
                "admin/module.html",
                title="الفئة غير موجودة",
                section="الكتالوج",
                requested_path=request.path,
                **context,
            ), 404
        form = request.form.to_dict(flat=True)
        form["action"] = form.get("action", "update")
        # Reuse the canonical categories handler by posting through a compact redirect-safe path.
        name = (form.get("name") or "").strip()
        slug = (form.get("slug") or "").strip().lower()
        parent_id = int(form["parent_id"]) if form.get("parent_id") else None
        category.name = name
        category.slug = slug
        category.parent_id = parent_id
        category.display_style = (form.get("display_style") or "circle").strip()
        category.sort_order = int(form.get("sort_order") or 0)
        category.is_featured = form.get("is_featured") == "on"
        category.badge_id = int(form["badge_id"]) if form.get("badge_id") else None
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            raise
        return __import__("flask").redirect("/admin/categories")

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
