import re
import unicodedata
from decimal import Decimal, InvalidOperation

from flask import redirect, render_template, request, session, url_for

from sqlalchemy import func

from ..extensions import db
from ..models import (
    AppSetting,
    AuditLog,
    Banner,
    Campaign,
    Conversation,
    Coupon,
    Customer,
    ExchangeRate,
    FeatureFlag,
    InventoryLocation,
    Order,
    PaymentMethod,
    PaymentTransaction,
    PricingGroup,
    PricingGroupCity,
    ProductDisplaySettings,
    ProductMedia,
    ProductVariant,
    Review,
    Role,
    ShippingMethod,
    ShippingPolicy,
    ReturnPolicy,
    WarrantyPolicy,
    Badge,
    Theme,
    Wallet,
)
from .context import build_admin_context
from ..modules.commerce.services import CommerceService
from ..modules.catalog.services import CatalogService, MediaService
from ..modules.support.services import SupportService


def _ctx():
    return build_admin_context()


_ARABIC_SLUG_MAP = str.maketrans({
    "ا": "a", "أ": "a", "إ": "i", "آ": "a", "ء": "a", "ؤ": "w", "ئ": "y",
    "ب": "b", "ت": "t", "ث": "th", "ج": "j", "ح": "h", "خ": "kh", "د": "d",
    "ذ": "dh", "ر": "r", "ز": "z", "س": "s", "ش": "sh", "ص": "s", "ض": "d",
    "ط": "t", "ظ": "z", "ع": "a", "غ": "gh", "ف": "f", "ق": "q", "ك": "k",
    "ل": "l", "م": "m", "ن": "n", "ه": "h", "و": "w", "ي": "y", "ى": "a", "ة": "h",
})


def _slugify(value, fallback="item"):
    value = (value or "").strip().lower().translate(_ARABIC_SLUG_MAP)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value[:180] or fallback


def _unique_slug(model, value, exclude_id=None, fallback="item"):
    base = _slugify(value, fallback=fallback)
    slug = base
    index = 2
    query = model.query.filter_by(slug=slug)
    if exclude_id is not None:
        query = query.filter(model.id != exclude_id)
    while query.first() is not None:
        slug = f"{base}-{index}"[:180]
        query = model.query.filter_by(slug=slug)
        if exclude_id is not None:
            query = query.filter(model.id != exclude_id)
        index += 1
    return slug


def _render(title, columns, rows, section=None, actions=None):
    return render_template(
        "admin/entity_list.html",
        title=title,
        columns=columns,
        rows=rows,
        section=section or "الإدارة",
        actions=actions or [],
        **_ctx(),
    )


def register_entity_views(admin_bp):
    @admin_bp.get("/customers")
    def customers():
        rows = Customer.query.order_by(Customer.id.desc()).limit(200).all()
        return render_template(
            "admin/customers.html",
            title="العملاء",
            customers=rows,
            **build_admin_context(),
        )

    @admin_bp.route("/customers/<int:customer_id>", methods=["GET", "POST"])
    def customer_detail_page(customer_id):
        customer = db.session.get(Customer, customer_id)
        if customer is None:
            return render_template(
                "admin/module.html",
                title="العميل غير موجود",
                section="العملاء والتواصل",
                requested_path=request.path,
                **build_admin_context(),
            ), 404

        from ..models import (
            CustomerAddress, CustomerPricingAssignment, Order,
            Conversation, Wallet, CustomerNotification, Notification,
        )

        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "profile":
                    customer.name = (request.form.get("name") or "").strip() or None
                    customer.email = (request.form.get("email") or "").strip() or None
                    customer.status = (request.form.get("status") or customer.status).strip()
                    customer.city_id = request.form.get("city_id", type=int)
                    db.session.commit()
                    success = "تم حفظ بيانات العميل."
                elif action == "address":
                    address = CustomerAddress(
                        customer_id=customer.id,
                        recipient_name=(request.form.get("recipient_name") or "").strip(),
                        phone=(request.form.get("address_phone") or "").strip(),
                        city_id=request.form.get("address_city_id", type=int),
                        district=(request.form.get("district") or "").strip() or None,
                        street=(request.form.get("street") or "").strip() or None,
                        landmark=(request.form.get("landmark") or "").strip() or None,
                        is_default=request.form.get("is_default") == "on",
                    )
                    if not address.recipient_name or not address.phone:
                        raise ValueError("اسم المستلم ورقم الهاتف مطلوبان.")
                    if address.is_default:
                        CustomerAddress.query.filter_by(customer_id=customer.id, is_active=True).update(
                            {CustomerAddress.is_default: False}, synchronize_session=False
                        )
                    db.session.add(address)
                    db.session.commit()
                    success = "تمت إضافة العنوان."
                else:
                    raise ValueError("إجراء العميل غير معروف.")
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        orders = Order.query.filter_by(customer_id=customer.id).order_by(Order.id.desc()).limit(50).all()
        conversations = Conversation.query.filter_by(customer_id=customer.id).order_by(
            Conversation.last_message_at.desc(), Conversation.id.desc()
        ).limit(50).all()
        addresses = CustomerAddress.query.filter_by(
            customer_id=customer.id, is_active=True
        ).order_by(CustomerAddress.is_default.desc(), CustomerAddress.id).all()
        assignments = CustomerPricingAssignment.query.filter_by(
            customer_id=customer.id, is_active=True
        ).order_by(CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()).all()
        wallets = Wallet.query.filter_by(customer_id=customer.id, is_active=True).all()
        notifications = (
            db.session.query(CustomerNotification, Notification)
            .join(Notification, Notification.id == CustomerNotification.notification_id)
            .filter(CustomerNotification.customer_id == customer.id)
            .order_by(CustomerNotification.id.desc())
            .limit(50).all()
        )

        cities = []
        try:
            from ..models import City
            cities = City.query.filter_by(is_active=True).order_by(City.name).all()
        except Exception:
            db.session.rollback()

        return render_template(
            "admin/customer_detail.html",
            title=f"العميل · {customer.name or customer.phone_normalized}",
            customer=customer,
            orders=orders,
            conversations=conversations,
            addresses=addresses,
            pricing_assignments=assignments,
            wallets=wallets,
            notifications=notifications,
            cities=cities,
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.get("/orders")
    def orders():
        rows = Order.query.order_by(Order.id.desc()).limit(200).all()
        return render_template(
            "admin/orders.html",
            title="الطلبات",
            orders=rows,
            **build_admin_context(),
        )

    @admin_bp.route("/orders/<int:order_id>", methods=["GET", "POST"])
    def order_detail_page(order_id):
        order = db.session.get(Order, order_id)
        if order is None:
            return render_template(
                "admin/module.html",
                title="الطلب غير موجود",
                section="المبيعات والطلبات",
                requested_path=request.path,
                **build_admin_context(),
            ), 404

        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "status":
                    CommerceService.transition_order(
                        order.id,
                        str(request.form["status"]),
                        actor_type="admin",
                        actor_id=session.get("admin_id"),
                        note=(request.form.get("note") or "").strip() or None,
                    )
                    success = "تم تحديث حالة الطلب."
                elif action == "message":
                    conversation = Conversation.query.filter_by(order_id=order.id).order_by(Conversation.id.desc()).first()
                    if conversation is None:
                        conversation = Conversation(
                            customer_id=order.customer_id,
                            order_id=order.id,
                            type="order_support",
                            subject=f"الطلب {order.order_no}",
                            status="open",
                        )
                        db.session.add(conversation)
                        db.session.commit()
                    SupportService.send_message(
                        conversation.id,
                        "admin",
                        session.get("admin_id") or 0,
                        (request.form.get("body") or "").strip(),
                        "text",
                    )
                    success = "تم إرسال الرسالة للعميل."
                else:
                    raise ValueError("إجراء الطلب غير معروف.")
            except (KeyError, ValueError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

            order = db.session.get(Order, order_id)

        detail = CommerceService.serialize_order_detail(order)
        return render_template(
            "admin/order_detail.html",
            title=f"الطلب {order.order_no}",
            order=detail,
            status_choices=(
                "created", "awaiting_payment", "paid", "processing",
                "shipped", "delivered", "returned", "cancelled",
            ),
            error=error,
            success=success,
            **build_admin_context(),
        )

    @admin_bp.get("/chat")
    def chat():
        rows = Conversation.query.order_by(Conversation.last_message_at.desc(), Conversation.id.desc()).limit(200).all()
        return _render("المحادثات", ["ID", "العميل", "الطلب", "النوع", "الحالة"],
                       [[x.id, x.customer_id, x.order_id or "—", x.type, x.status] for x in rows],
                       "العملاء والتواصل")

    @admin_bp.route("/payments", methods=["GET", "POST"])
    def payments():
        from ..models import Currency, Order, PaymentMethod
        error=None; success=request.args.get("success")
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "").strip(); row=db.session.get(PaymentMethod,request.form.get("id",type=int))
                if action=="method":
                    name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip().lower()
                    if not name or not code: raise ValueError("اسم وطريقة الدفع والكود مطلوبان.")
                    from ..modules.commerce.payment_shipping import PaymentShippingService
                    PaymentShippingService.create_payment_method({"name":name,"code":code,"provider":request.form.get("provider"),"supports_proof":request.form.get("supports_proof")=="on"}); success="تم إنشاء طريقة الدفع."
                elif action=="method_update":
                    if row is None: raise ValueError("طريقة الدفع غير موجودة.")
                    name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip().lower()
                    if not name or not code: raise ValueError("اسم وكود طريقة الدفع مطلوبان.")
                    if PaymentMethod.query.filter(PaymentMethod.id!=row.id,PaymentMethod.code==code).first(): raise ValueError("كود طريقة الدفع مستخدم.")
                    row.name=name; row.code=code; row.provider=(request.form.get("provider") or "").strip() or None; row.supports_proof=request.form.get("supports_proof")=="on"; success="تم تحديث طريقة الدفع."
                elif action=="method_archive":
                    if row is None: raise ValueError("طريقة الدفع غير موجودة.")
                    row.is_active=False; success="تمت أرشفة طريقة الدفع."
                elif action=="transaction":
                    from ..modules.commerce.payment_shipping import PaymentShippingService
                    PaymentShippingService.record_payment({"order_id":request.form.get("order_id"),"method_id":request.form.get("method_id"),"currency_id":request.form.get("currency_id"),"amount":request.form.get("amount"),"provider_ref":request.form.get("provider_ref"),"status":request.form.get("status","pending")}); success="تم تسجيل عملية الدفع."
                else: raise ValueError("إجراء الدفع غير معروف.")
                db.session.commit()
            except (ValueError,TypeError,LookupError) as exc: db.session.rollback(); error=str(exc)
        transactions=PaymentTransaction.query.order_by(PaymentTransaction.id.desc()).limit(200).all()
        methods=PaymentMethod.query.filter_by(is_active=True).order_by(PaymentMethod.name).all()
        orders=Order.query.order_by(Order.id.desc()).limit(200).all(); currencies=Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        return render_template("admin/payments.html",title="الدفعات",transactions=transactions,methods=methods,orders=orders,currencies=currencies,success=success,error=error,**build_admin_context())


    @admin_bp.route("/shipping", methods=["GET", "POST"])
    def shipping():
        from ..models import Order, ShippingMethod, Shipment
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "").strip(); row=db.session.get(ShippingMethod,request.form.get("id",type=int))
                from ..modules.commerce.payment_shipping import PaymentShippingService
                if action=="method":
                    PaymentShippingService.create_shipping_method({"name":request.form.get("name"),"code":request.form.get("code"),"delivery_days_min":request.form.get("delivery_days_min",type=int),"delivery_days_max":request.form.get("delivery_days_max",type=int),"supports_cod":request.form.get("supports_cod")=="on"}); success="تم إنشاء طريقة الشحن."
                elif action=="method_update":
                    if row is None: raise ValueError("طريقة الشحن غير موجودة.")
                    name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip().lower()
                    if not name or not code: raise ValueError("اسم وكود طريقة الشحن مطلوبان.")
                    if ShippingMethod.query.filter(ShippingMethod.id!=row.id,ShippingMethod.code==code).first(): raise ValueError("كود طريقة الشحن مستخدم.")
                    lo=request.form.get("delivery_days_min",type=int); hi=request.form.get("delivery_days_max",type=int)
                    if lo is not None and hi is not None and hi<lo: raise ValueError("المدة القصوى يجب ألا تقل عن الدنيا.")
                    row.name=name; row.code=code; row.delivery_days_min=lo; row.delivery_days_max=hi; row.supports_cod=request.form.get("supports_cod")=="on"; success="تم تحديث طريقة الشحن."
                elif action=="method_archive":
                    if row is None: raise ValueError("طريقة الشحن غير موجودة.")
                    row.is_active=False; success="تمت أرشفة طريقة الشحن."
                elif action=="shipment":
                    PaymentShippingService.create_shipment({"order_id":request.form.get("order_id"),"shipping_method_id":request.form.get("shipping_method_id",type=int),"tracking_no":(request.form.get("tracking_no") or "").strip() or None,"status":request.form.get("status","pending"),"event":{"status":(request.form.get("event_status") or "").strip() or request.form.get("status","pending"),"location":(request.form.get("event_location") or "").strip() or None,"description":(request.form.get("event_description") or "").strip() or None}}); success="تم إنشاء الشحنة."
                elif action=="event":
                    PaymentShippingService.add_shipment_event(request.form.get("shipment_id",type=int),{"status":request.form.get("event_status"),"location":request.form.get("event_location"),"description":request.form.get("event_description")}); success="تم حفظ حدث التتبع."
                else: raise ValueError("إجراء الشحن غير معروف.")
                db.session.commit()
            except (ValueError,TypeError,LookupError) as exc: db.session.rollback(); error=str(exc)
        methods=ShippingMethod.query.filter_by(is_active=True).order_by(ShippingMethod.name).all(); orders=Order.query.order_by(Order.id.desc()).limit(200).all(); shipments=Shipment.query.order_by(Shipment.id.desc()).limit(200).all()
        return render_template("admin/shipping.html",title="الشحن والتتبع",methods=methods,orders=orders,shipments=shipments,success=success,error=error,**build_admin_context())


    def returns():
        from ..models import ReturnRequest, ReturnItem, Order, Currency
        error = None
        success = None
        if request.method == "POST":
            try:
                action = request.form.get("action")
                row = db.session.get(ReturnRequest, request.form.get("return_id", type=int))
                if row is None:
                    raise ValueError("طلب الإرجاع غير موجود.")
                if action in {"approve", "reject"}:
                    row.status = "approved" if action == "approve" else "rejected"
                    if action == "approve":
                        row.approved_at = __import__("datetime").datetime.now(__import__("datetime").timezone.utc)
                    db.session.commit()
                    success = "تم تحديث حالة الإرجاع."
                elif action == "refund":
                    from ..modules.after_sales.services import AfterSalesService
                    amount = (request.form.get("amount") or "").strip()
                    currency_id = request.form.get("currency_id", type=int)
                    if not amount or not currency_id:
                        raise ValueError("المبلغ والعملة مطلوبان.")
                    result = AfterSalesService.process_refund({
                        "order_id": row.order_id,
                        "return_request_id": row.id,
                        "amount": amount,
                        "currency_id": currency_id,
                        "method": (request.form.get("method") or "wallet").strip(),
                        "status": "processed",
                    })
                    success = f"تم إنشاء الاسترداد #{result['id']}."
                else:
                    raise ValueError("إجراء الإرجاع غير معروف.")
            except (ValueError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)
        rows = ReturnRequest.query.order_by(ReturnRequest.id.desc()).limit(200).all()
        currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        return render_template(
            "admin/returns.html",
            title="الإرجاع والاسترداد",
            returns=rows,
            currencies=currencies,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.route("/warranty", methods=["GET", "POST"])
    def warranty():
        from ..models import WarrantyClaim
        error = None
        success = None
        if request.method == "POST":
            try:
                row = db.session.get(WarrantyClaim, request.form.get("claim_id", type=int))
                if row is None:
                    raise ValueError("مطالبة الضمان غير موجودة.")
                row.status = (request.form.get("status") or row.status).strip()
                row.resolution = (request.form.get("resolution") or "").strip() or None
                db.session.commit()
                success = "تم تحديث مطالبة الضمان."
            except ValueError as exc:
                db.session.rollback()
                error = str(exc)
        rows = WarrantyClaim.query.order_by(WarrantyClaim.id.desc()).limit(200).all()
        return render_template(
            "admin/warranty.html",
            title="الضمان",
            claims=rows,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.route("/reviews", methods=["GET", "POST"])
    def reviews():
        error = None
        success = None
        if request.method == "POST":
            try:
                row = db.session.get(Review, request.form.get("review_id", type=int))
                if row is None:
                    raise ValueError("التقييم غير موجود.")
                action = (request.form.get("action") or "update").strip()
                if action == "archive":
                    row.is_active = False
                    row.status = "archived"
                    success = "تمت أرشفة التقييم."
                else:
                    row.status = (request.form.get("status") or row.status).strip()
                    success = "تم تحديث حالة التقييم."
                db.session.commit()
            except ValueError as exc:
                db.session.rollback()
                error = str(exc)
        rows = Review.query.filter_by(is_active=True).order_by(Review.id.desc()).limit(200).all()
        return render_template(
            "admin/reviews.html",
            title="التقييمات",
            reviews=rows,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.route("/promotions/coupons", methods=["GET", "POST"])
    def coupons():
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip()
                row=db.session.get(Coupon,request.form.get("id",type=int))
                code=(request.form.get("code") or "").strip().upper()
                ctype=(request.form.get("type") or "percent").strip()
                value=Decimal(request.form.get("value") or "0")
                if action=="create":
                    if not code or value<0: raise ValueError("الكود والقيمة مطلوبان.")
                    if Coupon.query.filter_by(code=code).first(): raise ValueError("الكود مستخدم مسبقًا.")
                    db.session.add(Coupon(code=code,type=ctype,value=value,min_order=Decimal(request.form.get("min_order") or "0"),max_discount=Decimal(request.form.get("max_discount") or "0") or None,usage_limit=request.form.get("usage_limit",type=int))); success="تم إنشاء الكوبون."
                elif row is None: raise ValueError("الكوبون غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الكوبون."
                elif action=="update":
                    if not code: raise ValueError("كود الكوبون مطلوب.")
                    if Coupon.query.filter(Coupon.id!=row.id,Coupon.code==code).first(): raise ValueError("الكود مستخدم مسبقًا.")
                    row.code=code; row.type=ctype; row.value=value; row.min_order=Decimal(request.form.get("min_order") or "0"); row.max_discount=Decimal(request.form.get("max_discount") or "0") or None; row.usage_limit=request.form.get("usage_limit",type=int); success="تم تحديث الكوبون."
                else: raise ValueError("إجراء الكوبون غير معروف.")
                db.session.commit()
            except (ValueError,InvalidOperation) as exc: db.session.rollback(); error=str(exc)
        rows=Coupon.query.filter_by(is_active=True).order_by(Coupon.id.desc()).limit(200).all()
        return render_template("admin/coupons.html",title="الكوبونات",coupons=rows,success=success,error=error,**build_admin_context())


    @admin_bp.route("/promotions/gifts", methods=["GET", "POST"])
    def gifts():
        from ..models import GiftCampaign
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(GiftCampaign,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip()
                    if not name: raise ValueError("اسم حملة الهدية مطلوب.")
                    db.session.add(GiftCampaign(name=name,gift_type=(request.form.get("gift_type") or "credit").strip(),value=Decimal(request.form.get("value") or "0"),expires_at=None)); success="تم إنشاء حملة الهدية."
                elif row is None: raise ValueError("حملة الهدية غير موجودة.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة حملة الهدية."
                elif action=="update":
                    name=(request.form.get("name") or "").strip()
                    if not name: raise ValueError("اسم حملة الهدية مطلوب.")
                    row.name=name; row.gift_type=(request.form.get("gift_type") or row.gift_type).strip(); row.value=Decimal(request.form.get("value") or "0"); success="تم تحديث حملة الهدية."
                else: raise ValueError("إجراء الهدايا غير معروف.")
                db.session.commit()
            except (ValueError,InvalidOperation) as exc: db.session.rollback(); error=str(exc)
        rows=GiftCampaign.query.filter_by(is_active=True).order_by(GiftCampaign.id.desc()).limit(200).all()
        customers=Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(200).all()
        return render_template("admin/gifts.html",title="الهدايا",campaigns=rows,customers=customers,success=success,error=error,**build_admin_context())


    def issue_gift_admin():
        from ..modules.promotions.services import PromotionService
        try:
            result = PromotionService.issue_gift(
                request.form.get("campaign_id", type=int),
                request.form.get("customer_id", type=int),
            )
            return __import__("flask").redirect("/admin/promotions/gifts")
        except (ValueError, LookupError):
            return {"error": "gift_issue_failed"}, 400

    @admin_bp.route("/finance/wallets", methods=["GET", "POST"])
    def wallets():
        error = None
        success = None
        if request.method == "POST":
            try:
                from ..modules.promotions.services import PromotionService
                PromotionService.adjust_wallet(
                    request.form.get("customer_id", type=int),
                    request.form.get("currency_id", type=int),
                    request.form.get("amount"),
                    request.form.get("type") or "adjustment",
                    "admin",
                    session.get("admin_id"),
                )
                success = "تم تعديل المحفظة."
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)
        rows = Wallet.query.order_by(Wallet.id.desc()).limit(200).all()
        customers = Customer.query.filter_by(is_active=True).order_by(Customer.id.desc()).limit(200).all()
        currencies = __import__("app.models", fromlist=["Currency"]).Currency.query.filter_by(is_active=True).order_by(__import__("app.models", fromlist=["Currency"]).Currency.code).all()
        return render_template("admin/wallets.html", title="محافظ العملاء", wallets=rows, customers=customers, currencies=currencies, success=success, error=error, **build_admin_context())

    @admin_bp.route("/system/admins", methods=["GET", "POST"])
    def admins():
        from ..models import Admin, AdminRole, Role
        from .auth import AdminAuthService
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Admin,request.form.get("id",type=int))
                if action=="create":
                    username=(request.form.get("username") or "").strip(); password=request.form.get("password") or ""
                    if not username or len(password)<8: raise ValueError("اسم المستخدم وكلمة المرور (8 أحرف على الأقل) مطلوبان.")
                    created=AdminAuthService.bootstrap(username,password); row=db.session.get(Admin,created["id"])
                    row.phone=(request.form.get("phone") or "").strip() or None; row.email=(request.form.get("email") or "").strip() or None
                    db.session.flush(); role_id=request.form.get("role_id",type=int)
                    if role_id: db.session.add(AdminRole(admin_id=row.id,role_id=role_id))
                    success="تم إنشاء حساب المدير."
                elif row is None: raise ValueError("حساب المدير غير موجود.")
                elif action=="archive": row.is_active=False; row.status="disabled"; success="تم تعطيل حساب المدير."
                elif action=="update":
                    row.phone=(request.form.get("phone") or "").strip() or None; row.email=(request.form.get("email") or "").strip() or None; row.status=(request.form.get("status") or row.status).strip(); row.is_active = row.status == "active"
                    password=request.form.get("password") or ""
                    if password:
                        if len(password) < 8: raise ValueError("كلمة المرور يجب ألا تقل عن 8 أحرف.")
                        from werkzeug.security import generate_password_hash
                        row.password_hash=generate_password_hash(password)
                    AdminRole.query.filter_by(admin_id=row.id).delete(); role_id=request.form.get("role_id",type=int)
                    if role_id: db.session.add(AdminRole(admin_id=row.id,role_id=role_id))
                    success="تم تحديث حساب المدير."
                else: raise ValueError("إجراء المستخدم غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Admin.query.order_by(Admin.username).all(); roles_rows=Role.query.filter_by(is_active=True).order_by(Role.name).all()
        admin_roles={row.id:(AdminRole.query.filter_by(admin_id=row.id).first().role_id if AdminRole.query.filter_by(admin_id=row.id).first() else None) for row in rows}
        return render_template("admin/admins.html",title="المستخدمون",admins=rows,roles=roles_rows,admin_roles=admin_roles,success=success,error=error,**build_admin_context())

    @admin_bp.route("/system/roles", methods=["GET", "POST"])
    def roles():
        from ..models import Permission, Role, RolePermission
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Role,request.form.get("id",type=int))
                if action=="create":
                    code=(request.form.get("code") or "").strip(); name=(request.form.get("name") or "").strip()
                    if not code or not name: raise ValueError("اسم الدور والكود مطلوبان.")
                    if Role.query.filter_by(code=code).first(): raise ValueError("كود الدور مستخدم مسبقًا.")
                    row=Role(name=name,code=code); db.session.add(row); db.session.flush()
                    for pid in request.form.getlist("permission_ids"): db.session.add(RolePermission(role_id=row.id,permission_id=int(pid)))
                    success="تم إنشاء الدور."
                elif row is None: raise ValueError("الدور غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الدور."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip()
                    if not name or not code: raise ValueError("اسم الدور والكود مطلوبان.")
                    if Role.query.filter(Role.id!=row.id,Role.code==code).first(): raise ValueError("كود الدور مستخدم مسبقًا.")
                    row.name=name; row.code=code; RolePermission.query.filter_by(role_id=row.id).delete()
                    for pid in request.form.getlist("permission_ids"): db.session.add(RolePermission(role_id=row.id,permission_id=int(pid)))
                    success="تم تحديث الدور."
                else: raise ValueError("إجراء الدور غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Role.query.filter_by(is_active=True).order_by(Role.name).all()
        permissions=Permission.query.filter_by(is_active=True).order_by(Permission.code).all()
        role_perms={row.id:{rp.permission_id for rp in RolePermission.query.filter_by(role_id=row.id).all()} for row in rows}
        return render_template("admin/roles.html",title="الأدوار والصلاحيات",roles=rows,permissions=permissions,role_perms=role_perms,success=success,error=error,**build_admin_context())

    @admin_bp.get("/system/audit")
    def audit():
        rows = AuditLog.query.order_by(AuditLog.id.desc()).limit(200).all()
        return _render("سجل التدقيق", ["ID", "العملية", "الكيان", "المعرف", "المدير"],
                       [[x.id, x.action, x.entity_type, x.entity_id or "—", x.admin_id or "—"] for x in rows],
                       "النظام")

    @admin_bp.route("/system/theme", methods=["GET", "POST"])
    def theme():
        from ..models import AppSetting
        error = None
        success = None
        if request.method == "POST":
            try:
                for key in ("accent", "accent_soft", "bg", "surface", "border", "text", "muted"):
                    value = (request.form.get(key) or "").strip()
                    if not value:
                        continue
                    row = AppSetting.query.filter_by(group_code="theme", key=key).first()
                    if row is None:
                        row = AppSetting(group_code="theme", key=key, value=value, value_type="css")
                        db.session.add(row)
                    else:
                        row.value = value
                db.session.commit()
                success = "تم حفظ ألوان الواجهة."
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)
        values = {row.key: row.value for row in AppSetting.query.filter_by(group_code="theme").all()}
        return render_template(
            "admin/system_theme.html",
            title="الثيم",
            values=values,
            error=error,
            success=success,
            **build_admin_context(),
        )



    @admin_bp.get("/tasks")
    def tasks():
        from ..models import PaymentProof, ReturnRequest, WarrantyClaim
        rows = []
        for x in PaymentProof.query.filter_by(status="pending").limit(50).all():
            rows.append(["دفع", x.id, x.order_id, x.status])
        for x in ReturnRequest.query.filter_by(status="requested").limit(50).all():
            rows.append(["إرجاع", x.id, x.order_id, x.status])
        for x in WarrantyClaim.query.filter_by(status="submitted").limit(50).all():
            rows.append(["ضمان", x.id, x.order_id, x.status])
        return _render("الأعمال المعلقة", ["النوع", "ID", "الطلب", "الحالة"], rows, "الرئيسية")

    @admin_bp.get("/notifications")
    def notifications():
        from ..models import Notification
        rows = Notification.query.order_by(Notification.id.desc()).limit(200).all()
        return _render("الإشعارات", ["ID", "العميل", "النوع", "العنوان", "الحالة"],
                       [[x.id, x.customer_id, x.type, x.title, x.status] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/products/drafts")
    def product_drafts():
        from ..models import Product
        rows = Product.query.filter_by(status="draft").order_by(Product.id.desc()).limit(200).all()
        return _render("مسودات المنتجات", ["ID", "SKU", "الاسم", "السعر", "الحالة"],
                       [[x.id, x.sku, x.name, x.base_price, x.status] for x in rows], "الكتالوج")

    @admin_bp.route("/brands", methods=["GET", "POST"])
    def brands():
        from ..models import Brand
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip()
                row=db.session.get(Brand,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip()
                    if not name: raise ValueError("اسم العلامة التجارية مطلوب.")
                    slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Brand,name,fallback="brand")
                    if Brand.query.filter_by(slug=slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    logo_id=None; f=request.files.get("logo_file")
                    if f and f.filename:
                        a=MediaService.save_generic_files([f],"brands"); logo_id=a[0]["id"] if a else None
                    db.session.add(Brand(name=name,slug=slug,logo_asset_id=logo_id)); success="تم إنشاء العلامة التجارية."
                elif row is None: raise ValueError("العلامة التجارية غير موجودة.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة العلامة التجارية."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Brand,name,exclude_id=row.id,fallback="brand")
                    if not name: raise ValueError("اسم العلامة التجارية مطلوب.")
                    if Brand.query.filter(Brand.id!=row.id,Brand.slug==slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    row.name=name; row.slug=slug
                    f=request.files.get("logo_file")
                    if f and f.filename:
                        a=MediaService.save_generic_files([f],"brands")
                        if a: row.logo_asset_id=a[0]["id"]
                    success="تم تحديث العلامة التجارية."
                else: raise ValueError("إجراء العلامة التجارية غير معروف.")
                db.session.commit()
            except (ValueError,OSError) as exc:
                db.session.rollback(); error=str(exc)
        rows=Brand.query.filter_by(is_active=True).order_by(Brand.name).all()
        records=[{"id":x.id,"title":x.name,"badge":f"#{x.id}","edit_action":"update","archive_action":"archive",
            "edit_fields":[{"name":"name","label":"اسم العلامة","required":True,"value":x.name},{"name":"slug","label":"Slug","dir":"ltr","value":x.slug},{"name":"logo_file","label":"استبدال الشعار","type":"file","accept":"image/*"}],
            "fields":[{"label":"Slug","value":x.slug,"dir":"ltr"},{"label":"الشعار","value":f"Asset #{x.logo_asset_id}" if x.logo_asset_id else "بدون شعار"}]} for x in rows]
        return render_template("admin/manage.html",title="العلامات التجارية",section="الكتالوج",description="إضافة وتعديل وأرشفة العلامات التجارية مع Slug تلقائي.",fields=[{"name":"name","label":"اسم العلامة","required":True},{"name":"slug","label":"Slug","dir":"ltr"},{"name":"logo_file","label":"الشعار","type":"file","accept":"image/*"}],records=records,modal_id="brandAddModal",success=success,error=error,**_ctx())


    @admin_bp.route("/options", methods=["GET", "POST"])
    def options():
        from ..models import Color, Size, ProductVariant
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "").strip()
                if action.startswith("color_"):
                    row = db.session.get(Color, request.form.get("id", type=int))
                    if action == "color_create":
                        name = (request.form.get("name") or "").strip()
                        if not name:
                            raise ValueError("اسم اللون مطلوب.")
                        if Color.query.filter(Color.name == name, Color.is_active.is_(True)).first():
                            raise ValueError("هذا اللون الفعال موجود مسبقًا.")
                        db.session.add(Color(
                            name=name,
                            hex_code=(request.form.get("hex_code") or "").strip() or None,
                            sort_order=request.form.get("sort_order", 0, type=int),
                            is_active=True,
                        ))
                        success = "تم إنشاء اللون وإتاحته للمنتجات."
                    elif row is None:
                        raise ValueError("اللون غير موجود.")
                    elif action == "color_archive":
                        if ProductVariant.query.filter_by(color_id=row.id, is_active=True).first():
                            raise ValueError("لا يمكن أرشفة لون مستخدم في متغير نشط.")
                        row.is_active = False
                        success = "تمت أرشفة اللون. ويمكن استعادته من الأرشيف."
                    elif action == "color_restore":
                        row.is_active = True
                        success = "تمت إعادة تفعيل اللون وأصبح متاحًا للمنتجات."
                    elif action == "color_update":
                        name = (request.form.get("name") or "").strip()
                        if not name:
                            raise ValueError("اسم اللون مطلوب.")
                        duplicate = Color.query.filter(
                            Color.id != row.id,
                            Color.name == name,
                            Color.is_active.is_(True),
                        ).first()
                        if duplicate:
                            raise ValueError("هذا اللون الفعال موجود مسبقًا.")
                        row.name = name
                        row.hex_code = (request.form.get("hex_code") or "").strip() or None
                        row.sort_order = request.form.get("sort_order", 0, type=int)
                        success = "تم تحديث اللون."
                    else:
                        raise ValueError("إجراء اللون غير معروف.")
                elif action.startswith("size_"):
                    row = db.session.get(Size, request.form.get("id", type=int))
                    if action == "size_create":
                        group = (request.form.get("group") or "").strip()
                        code = (request.form.get("code") or "").strip().upper()
                        label = (request.form.get("label") or "").strip()
                        if not group or not code or not label:
                            raise ValueError("المجموعة والكود والاسم الظاهر مطلوبة.")
                        if Size.query.filter_by(group=group, code=code).first():
                            raise ValueError("كود المقاس مستخدم داخل المجموعة، حتى لو كان مؤرشفًا. استعده بدل إنشاء نسخة جديدة.")
                        db.session.add(Size(group=group, code=code, label=label, sort_order=request.form.get("sort_order", 0, type=int), is_active=True))
                        success = "تم إنشاء المقاس وإتاحته للمنتجات."
                    elif row is None:
                        raise ValueError("المقاس غير موجود.")
                    elif action == "size_archive":
                        if ProductVariant.query.filter_by(size_id=row.id, is_active=True).first():
                            raise ValueError("لا يمكن أرشفة مقاس مستخدم في متغير نشط.")
                        row.is_active = False
                        success = "تمت أرشفة المقاس. ويمكن استعادته من الأرشيف."
                    elif action == "size_restore":
                        row.is_active = True
                        success = "تمت إعادة تفعيل المقاس وأصبح متاحًا للمنتجات."
                    elif action == "size_update":
                        group = (request.form.get("group") or "").strip()
                        code = (request.form.get("code") or "").strip().upper()
                        label = (request.form.get("label") or "").strip()
                        if not group or not code or not label:
                            raise ValueError("المجموعة والكود والاسم الظاهر مطلوبة.")
                        duplicate = Size.query.filter(
                            Size.id != row.id,
                            Size.group == group,
                            Size.code == code,
                        ).first()
                        if duplicate:
                            raise ValueError("كود المقاس مستخدم داخل المجموعة.")
                        row.group = group
                        row.code = code
                        row.label = label
                        row.sort_order = request.form.get("sort_order", 0, type=int)
                        success = "تم تحديث المقاس."
                    else:
                        raise ValueError("إجراء المقاس غير معروف.")
                else:
                    raise ValueError("إجراء الخيارات غير معروف.")
                db.session.commit()
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        colors = Color.query.filter_by(is_active=True).order_by(Color.sort_order, Color.name).limit(300).all()
        archived_colors = Color.query.filter_by(is_active=False).order_by(Color.sort_order, Color.name).limit(300).all()
        sizes = Size.query.filter_by(is_active=True).order_by(Size.group, Size.sort_order, Size.label).limit(300).all()
        archived_sizes = Size.query.filter_by(is_active=False).order_by(Size.group, Size.sort_order, Size.label).limit(300).all()
        return render_template(
            "admin/options.html",
            title="الألوان والمقاسات",
            colors=colors,
            archived_colors=archived_colors,
            sizes=sizes,
            archived_sizes=archived_sizes,
            success=success,
            error=error,
            **build_admin_context(),
        )

    @admin_bp.route("/category-strip", methods=["GET", "POST"])
    def category_strip():
        from ..models import CategoryNavigationItem, Category
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(CategoryNavigationItem,request.form.get("id",type=int))
                if action=="create":
                    category_id=request.form.get("category_id",type=int)
                    if db.session.get(Category,category_id) is None: raise ValueError("الفئة غير موجودة.")
                    db.session.add(CategoryNavigationItem(category_id=category_id,slot=(request.form.get("slot") or "top").strip(),visible=request.form.get("visible")=="on",sort_order=request.form.get("sort_order",0,type=int),label_override=(request.form.get("label_override") or "").strip() or None)); success="تمت إضافة عنصر الشريط."
                elif row is None: raise ValueError("عنصر الشريط غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة عنصر الشريط."
                elif action=="update":
                    category_id=request.form.get("category_id",type=int)
                    if db.session.get(Category,category_id) is None: raise ValueError("الفئة غير موجودة.")
                    row.category_id=category_id; row.slot=(request.form.get("slot") or row.slot).strip(); row.visible=request.form.get("visible")=="on"; row.sort_order=request.form.get("sort_order",0,type=int); row.label_override=(request.form.get("label_override") or "").strip() or None; success="تم تحديث عنصر الشريط."
                else: raise ValueError("إجراء شريط الأقسام غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=CategoryNavigationItem.query.filter_by(is_active=True).order_by(CategoryNavigationItem.sort_order,CategoryNavigationItem.id).limit(300).all()
        categories=Category.query.filter_by(is_active=True).order_by(Category.sort_order,Category.name).limit(300).all()
        return render_template("admin/category_strip.html",title="شريط الأقسام",rows=rows,categories=categories,success=success,error=error,**build_admin_context())

    @admin_bp.post("/storefront/sections/<int:section_id>/items")
    def storefront_section_item_create(section_id):
        from ..models import StorefrontSection, StorefrontSectionItem, Product, Category, Banner, Campaign, Hashtag, PromotionalStrip

        section = db.session.get(StorefrontSection, section_id)
        if section is None:
            return redirect(url_for("admin.storefront_pages"))
        try:
            item_type = (request.form.get("item_type") or "product").strip()
            item_id = request.form.get("item_id", type=int)
            models = {
                "product": Product,
                "category": Category,
                "banner": Banner,
                "campaign": Campaign,
                "hashtag": Hashtag,
                "promotional_strip": PromotionalStrip,
            }
            model = models.get(item_type)
            if model is None or item_id is None or db.session.get(model, item_id) is None:
                raise ValueError("نوع أو معرّف عنصر القسم غير صحيح.")
            db.session.add(StorefrontSectionItem(
                section_id=section.id,
                item_type=item_type,
                item_id=item_id,
                sort_order=request.form.get("sort_order", 0, type=int),
                custom_label=(request.form.get("custom_label") or "").strip() or None,
            ))
            db.session.commit()
        except (ValueError, TypeError):
            db.session.rollback()
        return redirect(url_for("admin.storefront_pages"))

    @admin_bp.route("/storefront/pages", methods=["GET", "POST"])
    def storefront_pages():
        from ..models import StorefrontPage, StorefrontSection, StorefrontSectionItem, Product, Category, Banner, Campaign, Hashtag, PromotionalStrip
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "").strip()
                if action.startswith("page_"):
                    row=db.session.get(StorefrontPage,request.form.get("id",type=int))
                    if action=="page_create":
                        code=(request.form.get("code") or "").strip().lower(); name=(request.form.get("name") or "").strip(); route=(request.form.get("route") or "").strip()
                        if not code or not name or not route: raise ValueError("Code والاسم وRoute مطلوبة.")
                        if StorefrontPage.query.filter((StorefrontPage.code==code)|(StorefrontPage.route==route)).first(): raise ValueError("Code أو Route مستخدم مسبقًا.")
                        db.session.add(StorefrontPage(code=code,name=name,route=route)); success="تم إنشاء الصفحة."
                    elif row is None: raise ValueError("الصفحة غير موجودة.")
                    elif action=="page_archive": row.is_active=False; success="تمت أرشفة الصفحة."
                    else:
                        code=(request.form.get("code") or "").strip().lower(); name=(request.form.get("name") or "").strip(); route=(request.form.get("route") or "").strip()
                        if not code or not name or not route: raise ValueError("Code والاسم وRoute مطلوبة.")
                        if StorefrontPage.query.filter(StorefrontPage.id!=row.id,((StorefrontPage.code==code)|(StorefrontPage.route==route))).first(): raise ValueError("Code أو Route مستخدم مسبقًا.")
                        row.code=code; row.name=name; row.route=route; success="تم تحديث الصفحة."
                elif action.startswith("section_"):
                    row=db.session.get(StorefrontSection,request.form.get("id",type=int))
                    if action=="section_create":
                        page_id=request.form.get("page_id",type=int); page=db.session.get(StorefrontPage,page_id)
                        if page is None: raise ValueError("الصفحة غير موجودة.")
                        db.session.add(StorefrontSection(page_id=page_id,section_type=(request.form.get("section_type") or "product_grid").strip(),title=(request.form.get("title") or "").strip() or None,sort_order=request.form.get("sort_order",0,type=int),settings={},visible_rules={})); success="تم إنشاء القسم."
                    elif row is None: raise ValueError("القسم غير موجود.")
                    elif action=="section_archive": db.session.delete(row); success="تم حذف القسم وأغراضه التابعة."
                    else:
                        row.section_type=(request.form.get("section_type") or row.section_type).strip(); row.title=(request.form.get("title") or "").strip() or None; row.sort_order=request.form.get("sort_order",0,type=int); success="تم تحديث القسم."
                elif action in {"item_create","item_update","item_delete"}:
                    row=db.session.get(StorefrontSectionItem,request.form.get("id",type=int))
                    if action=="item_delete":
                        if row is None: raise ValueError("عنصر القسم غير موجود.")
                        db.session.delete(row); success="تم حذف عنصر القسم."
                    else:
                        section_id=request.form.get("section_id",type=int) if action=="item_create" else (row.section_id if row else None)
                        section=db.session.get(StorefrontSection,section_id)
                        if section is None: raise ValueError("القسم غير موجود.")
                        item_type=(request.form.get("item_type") or "product").strip(); item_id=request.form.get("item_id",type=int)
                        models={"product":Product,"category":Category,"banner":Banner,"campaign":Campaign,"hashtag":Hashtag,"promotional_strip":PromotionalStrip}
                        model=models.get(item_type)
                        if model is None or db.session.get(model,item_id) is None: raise ValueError("نوع أو معرّف عنصر القسم غير صحيح.")
                        if action=="item_create": db.session.add(StorefrontSectionItem(section_id=section.id,item_type=item_type,item_id=item_id,sort_order=request.form.get("sort_order",0,type=int),custom_label=(request.form.get("custom_label") or "").strip() or None)); success="تمت إضافة عنصر القسم."
                        else: row.item_type=item_type; row.item_id=item_id; row.sort_order=request.form.get("sort_order",0,type=int); row.custom_label=(request.form.get("custom_label") or "").strip() or None; success="تم تحديث عنصر القسم."
                else: raise ValueError("إجراء صفحات المتجر غير معروف.")
                db.session.commit()
                return redirect(url_for("admin.storefront_pages", success=success))
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        pages=StorefrontPage.query.filter_by(is_active=True).order_by(StorefrontPage.id).all()
        sections=StorefrontSection.query.order_by(StorefrontSection.page_id,StorefrontSection.sort_order).limit(1000).all()
        section_ids=[x.id for x in sections]
        items=StorefrontSectionItem.query.filter(StorefrontSectionItem.section_id.in_(section_ids)).order_by(StorefrontSectionItem.section_id,StorefrontSectionItem.sort_order,StorefrontSectionItem.id).all() if section_ids else []
        items_by_section={}
        for item in items: items_by_section.setdefault(item.section_id,[]).append(item)
        products=Product.query.filter(Product.is_active.is_(True),Product.status!="archived").order_by(Product.id.desc()).limit(300).all()
        categories=Category.query.filter_by(is_active=True).order_by(Category.sort_order,Category.name).limit(300).all()
        banners=Banner.query.filter_by(is_active=True).order_by(Banner.id.desc()).limit(300).all()
        campaigns=Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(),Campaign.name).limit(200).all()
        hashtags=Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order,Hashtag.name).limit(200).all()
        strips=PromotionalStrip.query.filter_by(is_active=True).order_by(PromotionalStrip.id.desc()).limit(200).all()
        return render_template("admin/storefront_pages.html",title="صفحات المتجر",pages=pages,sections=sections,items_by_section=items_by_section,products=products,categories=categories,banners=banners,campaigns=campaigns,hashtags=hashtags,strips=strips,success=success,error=error,**build_admin_context())


    @admin_bp.get("/banner-targets")
    def banner_targets():
        from ..models import BannerTarget
        rows = BannerTarget.query.order_by(BannerTarget.banner_id, BannerTarget.priority.desc()).limit(500).all()
        return _render("أهداف البانرات", ["ID", "Banner", "النوع", "الهدف", "الرابط"],
                       [[x.id, x.banner_id, x.target_type, x.target_id or "—", x.url or "—"] for x in rows], "المحتوى والمتجر")

    @admin_bp.get("/category-circles")
    def category_circles():
        from ..models import Category
        rows = Category.query.filter(Category.is_active.is_(True), Category.display_style == "circle").order_by(Category.sort_order, Category.name).limit(200).all()
        return _render("دوائر الفئات", ["ID", "الفئة", "الأب", "الترتيب"],
                       [[x.id, x.name, x.parent_id or "—", x.sort_order] for x in rows], "المحتوى والمتجر")

    @admin_bp.route("/side-categories", methods=["GET", "POST"])
    def side_categories():
        from ..models import (
            Badge,
            Category,
            MediaAsset,
            SideCategory,
            SideCategoryCircle,
        )

        error = None
        success = None
        view = (request.args.get("view") or "groups").strip().lower()
        if view not in {"groups", "circles", "collections"}:
            view = "groups"

        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "save_circle_display_settings":
                    CatalogService.save_side_circle_display({
                        "grid_columns": request.form.get("grid_columns", 3, type=int),
                        "item_width": request.form.get("item_width", 88, type=int),
                        "item_height": request.form.get("item_height", 88, type=int),
                        "item_shape": request.form.get("item_shape") or "circle",
                        "item_corner_radius": request.form.get("item_corner_radius", 18, type=int),
                        "item_spacing": request.form.get("item_spacing", 8, type=int),
                        "item_label_font_size": request.form.get("item_label_font_size", 10, type=int),
                        "item_label_bold": request.form.get("item_label_bold") == "on",
                        "section_spacing": request.form.get("section_spacing", 14, type=int),
                        "title_font_size": request.form.get("title_font_size", 15, type=int),
                        "show_empty_state": request.form.get("show_empty_state") == "on",
                    })
                    success = "تم حفظ إعدادات دوائر الفئات."
                elif action == "create_circle_group":
                    CatalogService.create_side_circle_group({
                        "root_category_id": request.form.get("root_category_id", type=int),
                        "name": request.form.get("name"),
                        "slug": request.form.get("slug"),
                        "sort_order": request.form.get("sort_order", 0, type=int),
                        "show_view_all": request.form.get("show_view_all") == "on",
                        "circle_ids": request.form.getlist("circle_ids", type=int),
                    })
                    success = "تم إنشاء مجموعة الدوائر."
                elif action == "update_circle_group":
                    CatalogService.update_side_circle_group(
                        request.form.get("id", type=int),
                        {
                            "root_category_id": request.form.get("root_category_id", type=int),
                            "name": request.form.get("name"),
                            "slug": request.form.get("slug"),
                            "sort_order": request.form.get("sort_order", 0, type=int),
                            "show_view_all": request.form.get("show_view_all") == "on",
                            "circle_ids": request.form.getlist("circle_ids", type=int),
                        },
                    )
                    success = "تم تحديث مجموعة الدوائر."
                elif action == "archive_circle_group":
                    CatalogService.archive_side_circle_group(request.form.get("id", type=int))
                    success = "تمت أرشفة مجموعة الدوائر."
                elif action == "create_side_category":
                    CatalogService.create_side_category(request.form)
                    success = "تمت إضافة الفئة الجانبية."
                elif action == "update_side_category":
                    CatalogService.update_side_category(request.form.get("id", type=int), request.form)
                    success = "تم تحديث الفئة الجانبية."
                elif action == "archive_side_category":
                    CatalogService.archive_side_category(request.form.get("id", type=int))
                    success = "تمت أرشفة الفئة الجانبية مع دوائرها."
                elif action == "move_side_category":
                    CatalogService.reorder_side_category(
                        request.form.get("id", type=int),
                        request.form.get("direction"),
                    )
                    success = "تم تحديث ترتيب الفئات الجانبية."
                elif action == "create_circle":
                    side_id = request.form.get("side_category_id", type=int)
                    CatalogService.create_side_category_circle(
                        side_id,
                        request.form,
                        request.files.getlist("files"),
                    )
                    success = "تمت إضافة الدائرة."
                elif action == "update_circle":
                    circle_id = request.form.get("id", type=int)
                    CatalogService.update_side_category_circle(
                        circle_id,
                        request.form,
                        request.files.getlist("files"),
                    )
                    success = "تم تحديث الدائرة."
                elif action == "archive_circle":
                    CatalogService.archive_side_category_circle(request.form.get("id", type=int))
                    success = "تمت أرشفة الدائرة."
                elif action == "move_circle":
                    CatalogService.reorder_side_category_circle(
                        request.form.get("id", type=int),
                        request.form.get("direction"),
                    )
                    success = "تم تحديث ترتيب الدوائر."
                else:
                    raise ValueError("إجراء الفئات الجانبية غير معروف.")
            except (ValueError, TypeError, OSError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

        root_categories = (
            Category.query
            .filter(Category.is_active.is_(True), Category.parent_id.is_(None))
            .order_by(Category.sort_order, Category.name)
            .all()
        )
        badges = Badge.query.filter(Badge.is_active.is_(True)).order_by(Badge.priority.desc(), Badge.name).all()
        active_side_category_objects = (
            SideCategory.query
            .filter(SideCategory.is_active.is_(True))
            .order_by(SideCategory.sort_order, SideCategory.name, SideCategory.id)
            .all()
        )
        side_categories = [
            CatalogService._serialize_side_category(row)
            for row in active_side_category_objects
        ]
        archived_side_categories = (
            SideCategory.query
            .filter(SideCategory.is_active.is_(False))
            .order_by(SideCategory.id.desc())
            .limit(100)
            .all()
        )
        circles = (
            SideCategoryCircle.query
            .filter(SideCategoryCircle.is_active.is_(True))
            .order_by(
                SideCategoryCircle.side_category_id,
                SideCategoryCircle.sort_order,
                SideCategoryCircle.name,
            )
            .all()
        )
        archived_circles = (
            SideCategoryCircle.query
            .filter(SideCategoryCircle.is_active.is_(False))
            .order_by(SideCategoryCircle.id.desc())
            .limit(100)
            .all()
        )

        side_map = {row["id"]: row for row in side_categories}
        circle_assets = {
            row.id: db.session.get(MediaAsset, row.image_asset_id) if row.image_asset_id else None
            for row in circles
        }
        circle_display_settings = CatalogService.get_side_circle_display()
        circle_groups = CatalogService.list_side_circle_groups()

        return render_template(
            "admin/side_categories.html",
            title="الفئات الجانبية",
            section="المحتوى والمتجر",
            view=view,
            root_categories=root_categories,
            badges=badges,
            side_categories=side_categories,
            archived_side_categories=archived_side_categories,
            circles=circles,
            archived_circles=archived_circles,
            side_map=side_map,
            circle_assets=circle_assets,
            circle_display_settings=circle_display_settings,
            circle_groups=circle_groups,
            error=error,
            success=success,
            **_ctx(),
        )

    @admin_bp.post("/trends/settings")
    def trends_settings():
        import json

        defaults = CatalogService.trend_display_settings()
        color_re = re.compile(r"^#[0-9a-fA-F]{6}$")

        def number(name, default, low, high, integer=False):
            raw = request.form.get(name)
            try:
                value = float(raw) if raw not in (None, "") else float(default)
            except (TypeError, ValueError):
                raise ValueError(f"القيمة {name} غير صحيحة.")
            value = max(low, min(high, value))
            return int(round(value)) if integer else value

        def color(name, default):
            value = (request.form.get(name) or default).strip()
            if not color_re.fullmatch(value):
                raise ValueError(f"لون {name} غير صالح.")
            return value

        try:
            settings = dict(defaults)
            for name, low, high, integer in (
                ("hero_height", 180, 520, True),
                ("hero_card_top", 35, 180, True),
                ("hero_card_width", 220, 520, True),
                ("hero_card_height", 120, 360, True),
                ("hero_card_radius", 0, 40, True),
                ("hero_card_border_width", 0, 5, False),
                ("hero_background_overlay_opacity", 0, 1, False),
                ("hero_card_overlay_opacity", 0, 1, False),
                ("content_padding", 0, 30, True),
                ("title_font_size", 10, 34, False),
                ("title_font_weight", 400, 900, True),
                ("title_spacing", 0, 20, True),
                ("title_arrow_font_size", 9, 28, False),
                ("title_arrow_gap", 0, 20, True),
                ("promo_font_size", 7, 18, False),
                ("promo_font_weight", 400, 900, True),
                ("promo_max_lines", 1, 3, True),
                ("product_width", 0, 180, False),
                ("product_height", 0, 320, True),
                ("product_top_spacing", 8, 120, True),
                ("product_gap", 0, 20, True),
                ("product_radius", 0, 20, True),
                ("hero_product_radius", 0, 20, True),
                ("hero_product_info_height", 16, 55, True),
                ("hero_product_name_font_size", 6, 14, False),
                ("hero_product_price_font_size", 7, 15, False),
                ("hero_product_name_font_weight", 400, 900, True),
                ("hero_product_price_font_weight", 400, 900, True),
                ("hero_product_name_max_lines", 1, 3, True),
                ("product_info_height", 16, 55, True),
                ("product_name_font_size", 6, 14, False),
                ("product_price_font_size", 7, 15, False),
                ("product_name_font_weight", 400, 900, True),
                ("product_price_font_weight", 400, 900, True),
                ("product_name_max_lines", 1, 3, True),
                ("badge_font_size", 7, 16, False),
                ("badge_radius", 0, 16, True),
                ("counter_font_size", 7, 18, True),
                ("counter_bottom", 0, 30, True),
                ("timer_font_size", 7, 16, False),
                ("timer_radius", 0, 16, True),
                ("logo_font_size", 14, 40, True),
                ("logo_letter_spacing", -4, 2, False),
                ("tabs_indicator_width", 40, 180, True),
                ("tabs_font_size", 10, 28, False),
                ("hashtag_font_size", 8, 18, False),
                ("hashtag_radius", 0, 20, True),
                ("pull_font_size", 8, 20, False),
                ("pull_height", 28, 100, True),
                ("pull_distance", 30, 130, True),
                ("content_top_radius", 0, 40, True),
                ("header_collapse_offset", 0, 140, False),
                ("compact_header_height", 44, 96, True),
                ("search_width_ratio", 0.45, 0.9, False),
                ("search_height", 32, 58, True),
                ("search_radius", 0, 30, True),
                ("search_horizontal_padding", 4, 24, True),
                ("search_icon_size", 14, 30, True),
                ("search_font_size", 9, 20, False),
                ("search_divider_width", 0, 4, False),
                ("trend_store_card_height", 220, 520, True),
                ("trend_store_image_height", 140, 430, True),
                ("trend_store_content_height", 50, 140, True),
                ("trend_store_radius", 0, 30, True),
                ("trend_store_content_padding", 4, 24, True),
                ("trend_store_title_offset", -30, 30, True),
                ("trend_store_title_arrow_font_size", 9, 28, False),
                ("trend_store_title_arrow_gap", 0, 20, True),
                ("trend_store_title_spacing", 0, 30, True),
                ("trend_store_title_font_size", 9, 28, False),
                ("trend_store_title_font_weight", 400, 900, True),
                ("trend_store_promo_offset", -30, 30, True),
                ("trend_store_promo_font_size", 8, 20, False),
                ("trend_store_promo_font_weight", 400, 900, True),
                ("picks_card_extent", 280, 520, True),
                ("picks_image_height", 190, 390, True),
                ("picks_content_height", 60, 150, True),
                ("picks_title_font_size", 8, 18, False),
            ):
                settings[name] = number(name, defaults[name], low, high, integer)

            for name in (
                "hero_card_border_color",
                "hero_background_overlay_color",
                "hero_card_overlay_color",
                "title_color",
                "promo_color",
                "badge_background_color",
                "badge_text_color",
                "counter_color",
                "timer_background_color",
                "timer_text_color",
                "top_icon_color",
                "logo_color",
                "tabs_active_color",
                "tabs_inactive_color",
                "tabs_indicator_color",
                "hashtag_text_color",
                "hashtag_active_text_color",
                "hashtag_background_color",
                "hashtag_active_background_color",
                "pull_background_color",
                "pull_indicator_color",
                "pull_text_color",
                "page_background_color",
                "search_background_color",
                "search_text_color",
                "search_icon_color",
                "search_divider_color",
                "trend_store_content_background",
                "trend_store_title_color",
                "trend_store_title_arrow_color",
                "trend_store_promo_color",
                "hero_product_name_color",
                "hero_product_price_color",
                "hero_product_text_color",
                "hero_product_info_background_color",
                "product_text_color",
                "product_name_color",
                "product_price_color",
                "product_info_background_color",
                "title_hash_color",
                "title_arrow_color",
            ):
                settings[name] = color(name, str(defaults[name]))

            for name in ("logo_text", "pull_text", "pull_release_text", "badge_text"):
                settings[name] = (request.form.get(name) or defaults[name]).strip()[:120]
            settings["title_hash_text"] = (request.form.get("title_hash_text") or defaults["title_hash_text"]).strip()[:3] or "#"
            settings["search_hint"] = (request.form.get("search_hint") or defaults["search_hint"]).strip()[:80]

            settings["show_counter"] = request.form.get("show_counter") == "on"
            settings["show_timer"] = request.form.get("show_timer") == "on"
            settings["pull_enabled"] = request.form.get("pull_enabled") == "on"
            settings["header_collapse_enabled"] = request.form.get("header_collapse_enabled") == "on"
            settings["show_title"] = request.form.get("show_title") == "on"
            settings["show_description"] = request.form.get("show_description") == "on"
            settings["show_product_name"] = request.form.get("show_product_name") == "on"
            settings["show_product_price"] = request.form.get("show_product_price") == "on"
            settings["hero_show_product_name"] = request.form.get("hero_show_product_name") == "on"
            settings["hero_show_product_price"] = request.form.get("hero_show_product_price") == "on"
            settings["trend_store_show_title"] = request.form.get("trend_store_show_title") == "on"
            settings["trend_store_show_description"] = request.form.get("trend_store_show_description") == "on"
            settings["title_show_arrow"] = request.form.get("title_show_arrow") == "on"
            settings["show_title_hash"] = request.form.get("show_title_hash") == "on"
            settings["trend_store_title_show_arrow"] = request.form.get("trend_store_title_show_arrow") == "on"
            settings["hero_product_image_fit"] = (
                request.form.get("hero_product_image_fit") or defaults["hero_product_image_fit"]
            )
            if settings["hero_product_image_fit"] not in {"cover", "contain", "fill"}:
                settings["hero_product_image_fit"] = "cover"
            settings["product_image_fit"] = (
                request.form.get("product_image_fit") or defaults["product_image_fit"]
            )
            if settings["product_image_fit"] not in {"cover", "contain", "fill"}:
                settings["product_image_fit"] = "cover"
            settings["timer_position"] = request.form.get("timer_position") or defaults["timer_position"]
            settings["badge_position"] = request.form.get("badge_position") or defaults["badge_position"]
            for name in (
                "product_name_align",
                "product_price_align",
                "hero_product_name_align",
                "hero_product_price_align",
                "title_align",
                "description_align",
                "trend_store_title_align",
                "trend_store_promo_align",
            ):
                settings[name] = (request.form.get(name) or defaults[name]).strip().lower()
                if settings[name] not in {"left", "center", "right"}:
                    settings[name] = defaults[name]
            settings["title_arrow"] = request.form.get("title_arrow") or defaults["title_arrow"]
            if settings["title_arrow"] not in {">", "<"}:
                settings["title_arrow"] = defaults["title_arrow"]
            settings["trend_store_title_arrow"] = request.form.get("trend_store_title_arrow") or defaults["trend_store_title_arrow"]
            if settings["trend_store_title_arrow"] not in {">", "<"}:
                settings["trend_store_title_arrow"] = defaults["trend_store_title_arrow"]
            if settings["timer_position"] not in {"top_left", "top_right"}:
                settings["timer_position"] = "top_left"
            if settings["badge_position"] not in {"top_left", "top_right"}:
                settings["badge_position"] = "top_right"

            row = AppSetting.query.filter_by(
                group_code="trends",
                key="display_settings",
            ).first()
            payload = json.dumps(settings, ensure_ascii=False, separators=(",", ":"))
            if row is None:
                db.session.add(
                    AppSetting(
                        group_code="trends",
                        key="display_settings",
                        value=payload,
                        value_type="json",
                    )
                )
            else:
                row.value = payload
                row.value_type = "json"
            db.session.commit()
            return redirect(url_for("admin.trends", trend_settings="saved"))
        except (ValueError, TypeError) as exc:
            db.session.rollback()
            return redirect(url_for("admin.trends", trend_settings_error=str(exc)))

    @admin_bp.route("/trends/display-settings", methods=["GET", "POST"])
    def trends_display_settings():
        import json

        # The old /trends/settings endpoint remains untouched for backward
        # compatibility. This page is a clearer editor for the same settings.
        trend_groups = [
            {
                "title": "الهيكل والمساحة",
                "hint": "حجم مساحة الترند والبطاقة والصورة الخلفية.",
                "fields": [
                    ("hero_height", "ارتفاع مساحة الترند", "number", 180, 520, 1, True),
                    ("hero_card_top", "موضع البطاقة من الأعلى", "number", 35, 180, 1, True),
                    ("hero_card_width", "عرض بطاقة الترند", "number", 220, 520, 1, True),
                    ("hero_card_height", "ارتفاع بطاقة الترند", "number", 120, 360, 1, True),
                    ("hero_card_radius", "تدوير بطاقة الترند", "number", 0, 40, 1, True),
                    ("hero_card_border_width", "سُمك إطار البطاقة", "number", 0, 5, .1, False),
                    ("hero_background_overlay_opacity", "تغميق الخلفية", "number", 0, 1, .01, False),
                    ("hero_card_overlay_opacity", "تغميق بطاقة الترند", "number", 0, 1, .01, False),
                    ("content_padding", "مسافة المحتوى الداخلي", "number", 0, 30, 1, True),
                ],
            },
            {
                "title": "العنوان والوصف",
                "hint": "التحكم في اسم الترند والوصف والرموز.",
                "fields": [
                    ("show_title", "إظهار عنوان الترند", "checkbox"),
                    ("show_description", "إظهار وصف الترند", "checkbox"),
                    ("title_align", "محاذاة العنوان", "select", ["right", "center", "left"]),
                    ("description_align", "محاذاة الوصف", "select", ["right", "center", "left"]),
                    ("title_show_arrow", "إظهار السهم", "checkbox"),
                    ("title_arrow", "السهم", "select", [">", "<"]),
                    ("title_arrow_font_size", "حجم السهم", "number", 9, 28, .5, False),
                    ("title_arrow_gap", "المسافة بين العنوان والسهم", "number", 0, 20, 1, True),
                    ("show_title_hash", "إظهار # قبل العنوان", "checkbox"),
                    ("title_hash_text", "رمز قبل العنوان", "text", 3),
                    ("title_font_size", "حجم العنوان", "number", 10, 34, .5, False),
                    ("title_font_weight", "وزن العنوان", "number", 400, 900, 100, True),
                    ("title_spacing", "المسافة تحت العنوان", "number", 0, 20, 1, True),
                    ("promo_font_size", "حجم الوصف الترويجي", "number", 7, 18, .5, False),
                    ("promo_font_weight", "وزن الوصف الترويجي", "number", 400, 900, 100, True),
                    ("promo_max_lines", "عدد أسطر الوصف", "number", 1, 3, 1, True),
                ],
            },
            {
                "title": "المنتجات داخل الترند",
                "hint": "البطاقات الثلاث التي تظهر داخل مستطيل الترند.",
                "fields": [
                    ("product_width", "عرض المنتج", "number", 0, 180, .5, False),
                    ("product_height", "ارتفاع المنتجات", "number", 0, 320, 1, True),
                    ("product_top_spacing", "المسافة قبل المنتجات", "number", 8, 120, 1, True),
                    ("product_gap", "المسافة بين المنتجات", "number", 0, 20, 1, True),
                    ("product_radius", "تدوير المنتجات", "number", 0, 20, 1, True),
                    ("product_info_height", "ارتفاع معلومات المنتج", "number", 16, 55, 1, True),
                    ("show_product_name", "إظهار اسم المنتج", "checkbox"),
                    ("show_product_price", "إظهار سعر المنتج", "checkbox"),
                    ("product_name_font_size", "حجم اسم المنتج", "number", 6, 14, .5, False),
                    ("product_price_font_size", "حجم السعر", "number", 7, 15, .5, False),
                    ("product_name_font_weight", "وزن اسم المنتج", "number", 400, 900, 100, True),
                    ("product_price_font_weight", "وزن السعر", "number", 400, 900, 100, True),
                    ("product_name_max_lines", "أقصى أسطر الاسم", "number", 1, 3, 1, True),
                    ("product_name_align", "محاذاة اسم المنتج", "select", ["right", "center", "left"]),
                    ("product_price_align", "محاذاة السعر", "select", ["right", "center", "left"]),
                    ("product_image_fit", "طريقة ملء الصورة", "select", ["cover", "contain", "fill"]),
                ],
            },
            {
                "title": "الشارة والمؤقت والعداد",
                "hint": "المظهر العلوي لبطاقة الترند.",
                "fields": [
                    ("badge_text", "نص الشارة", "text", 120),
                    ("badge_position", "مكان الشارة", "select", ["top_right", "top_left"]),
                    ("badge_font_size", "حجم خط الشارة", "number", 7, 16, .5, False),
                    ("badge_radius", "تدوير الشارة", "number", 0, 16, 1, True),
                    ("show_timer", "إظهار المؤقت", "checkbox"),
                    ("timer_position", "مكان المؤقت", "select", ["top_left", "top_right"]),
                    ("timer_font_size", "حجم خط المؤقت", "number", 7, 16, .5, False),
                    ("timer_radius", "تدوير المؤقت", "number", 0, 16, 1, True),
                    ("show_counter", "إظهار العداد", "checkbox"),
                    ("counter_font_size", "حجم العداد", "number", 7, 18, 1, True),
                    ("counter_bottom", "موضع العداد من الأسفل", "number", 0, 30, 1, True),
                    ("counter_align", "محاذاة العداد", "select", ["right", "center", "left"]),
                ],
            },
            {
                "title": "شريط البحث والرأس",
                "hint": "إعدادات رأس صفحة الترندات وشريط البحث.",
                "fields": [
                    ("logo_text", "النص العلوي", "text", 60),
                    ("logo_font_size", "حجم النص العلوي", "number", 14, 40, 1, True),
                    ("logo_letter_spacing", "تباعد حروف النص العلوي", "number", -4, 2, .1, False),
                    ("header_collapse_enabled", "تفعيل انكماش الرأس", "checkbox"),
                    ("header_collapse_offset", "مسافة بدء الانكماش", "number", 0, 140, 1, False),
                    ("compact_header_height", "ارتفاع الرأس المضغوط", "number", 44, 96, 1, True),
                    ("search_width_ratio", "نسبة عرض البحث", "number", .45, .9, .01, False),
                    ("search_height", "ارتفاع البحث", "number", 32, 58, 1, True),
                    ("search_radius", "تدوير البحث", "number", 0, 30, 1, True),
                    ("search_horizontal_padding", "حشو البحث الأفقي", "number", 4, 24, 1, True),
                    ("search_icon_size", "حجم أيقونة البحث", "number", 14, 30, 1, True),
                    ("search_font_size", "حجم خط البحث", "number", 9, 20, .5, False),
                    ("search_hint", "نص البحث التجريبي", "text", 80),
                ],
            },
            {
                "title": "شريط الهاشتاج والسحب",
                "hint": "أزرار الهاشتاج وتعليمات السحب والتحديث.",
                "fields": [
                    ("hashtag_font_size", "حجم الهاشتاج", "number", 8, 18, .5, False),
                    ("hashtag_height", "ارتفاع زر الهاشتاج", "number", 24, 48, 1, True),
                    ("hashtag_horizontal_padding", "الحشو الأفقي لزر الهاشتاج", "number", 4, 28, 1, True),
                    ("hashtag_radius", "تدوير الهاشتاج", "number", 0, 20, 1, True),
                    ("pull_enabled", "تفعيل السحب للتحديث", "checkbox"),
                    ("pull_text", "نص السحب", "text", 120),
                    ("pull_release_text", "نص التحرير", "text", 120),
                    ("pull_font_size", "حجم خط السحب", "number", 8, 20, .5, False),
                    ("pull_height", "ارتفاع منطقة السحب", "number", 28, 100, 1, True),
                    ("pull_distance", "مسافة تفعيل التحديث", "number", 30, 130, 1, True),
                    ("content_top_radius", "تدوير أعلى المحتوى", "number", 0, 40, 1, True),
                ],
            },
            {
                "title": "متجر الترندات واختياراتنا",
                "hint": "البطاقات التي تظهر في أقسام الترندات داخل المتجر.",
                "fields": [
                    ("trend_store_card_height", "ارتفاع بطاقة ترند المتجر", "number", 220, 520, 1, True),
                    ("trend_store_image_height", "ارتفاع صورة بطاقة الترند", "number", 140, 430, 1, True),
                    ("trend_store_content_height", "ارتفاع محتوى بطاقة الترند", "number", 50, 140, 1, True),
                    ("trend_store_radius", "تدوير بطاقة الترند", "number", 0, 30, 1, True),
                    ("trend_store_content_padding", "حشو محتوى بطاقة الترند", "number", 4, 24, 1, True),
                    ("trend_store_show_title", "إظهار عنوان بطاقة الترند", "checkbox"),
                    ("trend_store_show_description", "إظهار وصف بطاقة الترند", "checkbox"),
                    ("trend_store_title_offset", "إزاحة عنوان البطاقة", "number", -30, 30, 1, True),
                    ("trend_store_title_align", "محاذاة عنوان البطاقة", "select", ["right", "center", "left"]),
                    ("trend_store_title_show_arrow", "إظهار سهم عنوان البطاقة", "checkbox"),
                    ("trend_store_title_arrow", "سهم عنوان البطاقة", "select", [">", "<"]),
                    ("trend_store_title_arrow_font_size", "حجم سهم عنوان البطاقة", "number", 9, 28, .5, False),
                    ("trend_store_title_arrow_gap", "مسافة السهم", "number", 0, 20, 1, True),
                    ("trend_store_title_spacing", "المسافة تحت العنوان", "number", 0, 30, 1, True),
                    ("trend_store_title_font_size", "حجم عنوان البطاقة", "number", 9, 28, .5, False),
                    ("trend_store_title_font_weight", "وزن عنوان البطاقة", "number", 400, 900, 100, True),
                    ("trend_store_promo_offset", "إزاحة وصف البطاقة", "number", -30, 30, 1, True),
                    ("trend_store_promo_align", "محاذاة الوصف", "select", ["right", "center", "left"]),
                    ("trend_store_promo_font_size", "حجم وصف البطاقة", "number", 8, 20, .5, False),
                    ("trend_store_promo_font_weight", "وزن وصف البطاقة", "number", 400, 900, 100, True),
                    ("picks_card_extent", "ارتفاع بطاقة اختياراتنا", "number", 280, 520, 1, True),
                    ("picks_image_height", "ارتفاع صورة اختياراتنا", "number", 190, 390, 1, True),
                    ("picks_content_height", "ارتفاع محتوى اختياراتنا", "number", 60, 150, 1, True),
                    ("picks_title_font_size", "حجم عنوان اختياراتنا", "number", 8, 18, .5, False),
                ],
            },
        ]

        trend_color_fields = [
            ("hero_card_border_color", "لون إطار بطاقة الترند"),
            ("hero_background_overlay_color", "لون تغميق الخلفية"),
            ("hero_card_overlay_color", "لون تغميق البطاقة"),
            ("title_color", "لون العنوان"),
            ("title_arrow_color", "لون السهم"),
            ("title_hash_color", "لون #"),
            ("promo_color", "لون الوصف"),
            ("badge_background_color", "خلفية الشارة"),
            ("badge_text_color", "لون نص الشارة"),
            ("counter_color", "لون العداد"),
            ("timer_background_color", "خلفية المؤقت"),
            ("timer_text_color", "لون نص المؤقت"),
            ("top_icon_color", "لون أيقونات الرأس"),
            ("logo_color", "لون النص العلوي"),
            ("tabs_active_color", "لون التبويب النشط"),
            ("tabs_inactive_color", "لون التبويب غير النشط"),
            ("tabs_indicator_color", "لون مؤشر التبويب"),
            ("hashtag_text_color", "لون الهاشتاج"),
            ("hashtag_active_text_color", "لون الهاشتاج النشط"),
            ("hashtag_background_color", "خلفية الهاشتاج"),
            ("hashtag_active_background_color", "خلفية الهاشتاج النشط"),
            ("picks_section_background_color", "خلفية منطقة منتجات الترند"),
            ("pull_background_color", "خلفية السحب"),
            ("pull_indicator_color", "لون مؤشر السحب"),
            ("pull_text_color", "لون نص السحب"),
            ("page_background_color", "خلفية الصفحة"),
            ("search_background_color", "خلفية البحث"),
            ("search_text_color", "لون نص البحث"),
            ("search_icon_color", "لون أيقونة البحث"),
            ("search_divider_color", "لون فاصل البحث"),
            ("trend_store_content_background", "خلفية محتوى بطاقة الترند"),
            ("trend_store_title_color", "لون عنوان بطاقة الترند"),
            ("trend_store_title_arrow_color", "لون سهم بطاقة الترند"),
            ("trend_store_promo_color", "لون وصف بطاقة الترند"),
            ("hero_product_name_color", "لون اسم المنتج داخل الترند"),
            ("hero_product_price_color", "لون سعر المنتج داخل الترند"),
            ("hero_product_text_color", "لون نص المنتج داخل الترند"),
            ("hero_product_info_background_color", "خلفية معلومات المنتج داخل الترند"),
            ("product_text_color", "لون نص المنتج"),
            ("product_name_color", "لون اسم المنتج"),
            ("product_price_color", "لون سعر المنتج"),
            ("product_info_background_color", "خلفية معلومات المنتج"),
        ]

        product_card_groups = [
            {
                "title": "الخلفية والهوية الأساسية",
                "hint": "تحكم في خلفية البطاقة واسم المنتج والوصف القصير وتناسق النصوص.",
                "fields": [
                    ("card_radius", "تدوير البطاقة", "number", 0, 30, 1, True),
                    ("card_background_opacity", "شفافية خلفية البطاقة", "number", 0, 1, .05, False),
                    ("show_name", "إظهار اسم المنتج", "checkbox"),
                    ("name_font_size", "حجم اسم المنتج", "number", 7, 24, .5, False),
                    ("name_font_weight", "وزن اسم المنتج", "number", 300, 900, 100, True),
                    ("name_max_lines", "أقصى أسطر للاسم", "number", 1, 3, 1, True),
                    ("name_background_opacity", "شفافية خلفية الاسم", "number", 0, 1, .05, False),
                    ("show_short_description", "إظهار الوصف القصير", "checkbox"),
                    ("short_description_font_size", "حجم الوصف القصير", "number", 7, 18, .5, False),
                    ("short_description_font_weight", "وزن الوصف القصير", "number", 300, 900, 100, True),
                    ("short_description_max_lines", "أقصى أسطر للوصف", "number", 1, 3, 1, True),
                    ("short_description_background_opacity", "شفافية خلفية الوصف", "number", 0, 1, .05, False),
                ],
            },
            {
                "title": "السعر والعملة",
                "hint": "تحكم مستقل في السعر الحالي والسعر قبل الخصم ورمز العملة، مع شفافية الخلفيات.",
                "fields": [
                    ("show_price", "إظهار السعر الحالي", "checkbox"),
                    ("price_font_size", "حجم السعر الحالي", "number", 9, 28, .5, False),
                    ("price_font_weight", "وزن السعر الحالي", "number", 300, 900, 100, True),
                    ("price_background_opacity", "شفافية خلفية السعر", "number", 0, 1, .05, False),
                    ("show_compare_price", "إظهار السعر قبل الخصم", "checkbox"),
                    ("compare_price_font_size", "حجم السعر قبل الخصم", "number", 7, 20, .5, False),
                    ("compare_price_font_weight", "وزن السعر قبل الخصم", "number", 300, 900, 100, True),
                    ("compare_price_text_decoration", "خط السعر قبل الخصم", "select", ["line_through", "none"]),
                    ("compare_price_background_opacity", "شفافية خلفية السعر السابق", "number", 0, 1, .05, False),
                    ("show_currency", "إظهار رمز العملة", "checkbox"),
                    ("currency_font_size", "حجم رمز العملة", "number", 7, 20, .5, False),
                    ("currency_font_weight", "وزن رمز العملة", "number", 300, 900, 100, True),
                    ("currency_background_opacity", "شفافية خلفية العملة", "number", 0, 1, .05, False),
                ],
            },
            {
                "title": "المقاس والهوامش الصغيرة",
                "hint": "اختياري لإظهار المقاس أو المعلومة المختصرة على بطاقة المنتج.",
                "fields": [
                    ("show_size", "إظهار المقاس", "checkbox"),
                    ("size_font_size", "حجم المقاس", "number", 7, 18, .5, False),
                    ("size_font_weight", "وزن المقاس", "number", 300, 900, 100, True),
                    ("meta_font_size", "حجم المعلومة العلوية", "number", 6, 18, .5, False),
                    ("meta_radius", "تدوير المعلومة العلوية", "number", 0, 16, 1, True),
                    ("meta_padding_horizontal", "حشو المعلومة أفقيًا", "number", 0, 12, 1, True),
                    ("meta_padding_vertical", "حشو المعلومة رأسيًا", "number", 0, 8, 1, True),
                ],
            },
            {
                "title": "الترند والهاشتاج فوق اسم المنتج",
                "hint": "هذه العناصر تظهر قبل اسم المنتج في البطاقة الرئيسية.",
                "fields": [
                    ("show_trend_badge", "إظهار شارة الترند", "checkbox"),
                    ("trend_badge_text", "اسم شارة الترند", "text", 40),
                    ("trend_badge_font_size", "حجم شارة الترند", "number", 6, 18, .5, False),
                    ("trend_badge_radius", "تدوير شارة الترند", "number", 0, 16, 1, True),
                    ("show_trend_hashtag", "إظهار هاشتاج الترند", "checkbox"),
                    ("trend_hashtag_font_size", "حجم الهاشتاج", "number", 6, 18, .5, False),
                    ("trend_hashtag_font_weight", "وزن الهاشتاج", "number", 400, 900, 100, True),
                    ("trend_hashtag_use_background", "إظهار خلفية الهاشتاج", "checkbox"),
                    ("trend_ribbon_gap", "المسافة بين الترند والهاشتاج", "number", 0, 12, 1, True),
                    ("trend_show_arrow", "إظهار سهم الهاشتاج", "checkbox"),
                    ("trend_arrow_text", "رمز السهم", "text", 3),
                ],
            },
            {
                "title": "الألوان داخل صورة المنتج",
                "hint": "مكان وشكل ألوان المنتج. الافتراضي الآن رأسي ومناسب لبطاقة شي إن.",
                "fields": [
                    ("colors_show", "إظهار ألوان المنتج", "checkbox"),
                    ("colors_position", "مكان الألوان", "select", ["bottom_right", "bottom_left", "top_right", "top_left"]),
                    ("colors_direction", "اتجاه الألوان", "select", ["vertical", "horizontal"]),
                    ("colors_size", "حجم دائرة اللون", "number", 8, 24, 1, True),
                    ("colors_container_size", "حجم حاوية اللون", "number", 10, 28, 1, True),
                    ("colors_gap", "المسافة بين الألوان", "number", 0, 10, 1, True),
                    ("colors_max", "أقصى عدد ألوان", "number", 1, 8, 1, True),
                    ("colors_border_width", "سُمك حدود دائرة اللون", "number", 0, 3, .5, False),
                ],
            },
            {
                "title": "الهوية والشارات والمعلومة العلوية",
                "hint": "العلامة التجارية وشارات المنتج والمقاس/العمر.",
                "fields": [
                    ("show_brand", "إظهار العلامة التجارية", "checkbox"),
                    ("brand_position", "مكان العلامة التجارية", "select", ["top_left", "top_right", "bottom_left", "bottom_right"]),
                    ("brand_font_size", "حجم العلامة التجارية", "number", 6, 18, .5, False),
                    ("brand_radius", "تدوير العلامة التجارية", "number", 0, 16, 1, True),
                    ("show_product_badges", "إظهار شارات المنتج", "checkbox"),
                    ("product_badge_position", "مكان شارات المنتج", "select", ["top_left", "top_right", "bottom_left", "bottom_right"]),
                    ("product_badge_font_size", "حجم شارة المنتج", "number", 6, 18, .5, False),
                    ("product_badge_radius", "تدوير شارة المنتج", "number", 0, 16, 1, True),
                    ("product_badge_max", "عدد الشارات المعروضة", "number", 1, 4, 1, True),
                    ("meta_show", "إظهار المقاس/العمر", "checkbox"),
                    ("meta_position", "مكان المقاس/العمر", "select", ["top_right", "top_left", "bottom_right", "bottom_left"]),
                    ("meta_font_size", "حجم المقاس/العمر", "number", 6, 18, .5, False),
                    ("meta_radius", "تدوير المقاس/العمر", "number", 0, 16, 1, True),
                    ("meta_padding_horizontal", "حشو المقاس أفقيًا", "number", 0, 12, 1, True),
                    ("meta_padding_vertical", "حشو المقاس رأسيًا", "number", 0, 8, 1, True),
                ],
            },
        ]

        product_card_color_fields = [
            ("card_background_color", "خلفية البطاقة"),
            ("name_color", "لون اسم المنتج"),
            ("name_background_color", "خلفية اسم المنتج"),
            ("short_description_color", "لون الوصف القصير"),
            ("short_description_background_color", "خلفية الوصف القصير"),
            ("price_color", "لون السعر الحالي"),
            ("price_background_color", "خلفية السعر الحالي"),
            ("compare_price_color", "لون السعر قبل الخصم"),
            ("compare_price_background_color", "خلفية السعر قبل الخصم"),
            ("currency_color", "لون رمز العملة"),
            ("currency_background_color", "خلفية رمز العملة"),
            ("size_color", "لون المقاس"),
            ("size_background_color", "خلفية المقاس"),
            ("brand_background_color", "خلفية العلامة التجارية"),
            ("brand_text_color", "لون نص العلامة"),
            ("trend_badge_background_color", "خلفية شارة الترند"),
            ("trend_badge_text_color", "لون نص شارة الترند"),
            ("trend_hashtag_text_color", "لون نص الهاشتاج"),
            ("trend_hashtag_background_color", "خلفية الهاشتاج"),
            ("trend_arrow_color", "لون السهم"),
            ("meta_background_color", "خلفية المقاس/العمر"),
            ("meta_text_color", "لون نص المقاس/العمر"),
        ]

        trend_number_names = {
            field[0]: field for group in trend_groups for field in group["fields"]
            if field[2] == "number"
        }
        trend_select_names = {
            field[0]: field[3] for group in trend_groups for field in group["fields"]
            if field[2] == "select"
        }
        product_number_names = {
            field[0]: field for group in product_card_groups for field in group["fields"]
            if field[2] == "number"
        }
        product_select_names = {
            field[0]: field[3] for group in product_card_groups for field in group["fields"]
            if field[2] == "select"
        }

        error = None
        success = None
        if request.method == "POST":
            action = (request.form.get("action") or "").strip()
            try:
                if action == "save_trends":
                    settings = dict(CatalogService.trend_display_settings())
                    color_re = re.compile(r"^#[0-9a-fA-F]{6}$")

                    for group in trend_groups:
                        for field in group["fields"]:
                            key, _label, kind = field[:3]
                            if kind == "checkbox":
                                settings[key] = request.form.get(key) == "on"
                            elif kind == "number":
                                _value, _ = field[3], field[4]
                                raw = request.form.get(key)
                                value = float(raw) if raw not in (None, "") else float(settings[key])
                                value = max(float(_value), min(float(field[4]), value))
                                settings[key] = int(round(value)) if field[6] else value
                            elif kind == "text":
                                max_len = int(field[3])
                                settings[key] = (request.form.get(key) or settings.get(key) or "").strip()[:max_len]
                            elif kind == "select":
                                allowed = field[3]
                                value = (request.form.get(key) or settings.get(key) or "").strip()
                                if value not in allowed:
                                    raise ValueError(f"القيمة {key} غير صالحة.")
                                settings[key] = value

                    for key, _label in trend_color_fields:
                        value = (request.form.get(key) or settings.get(key) or "").strip()
                        if not color_re.fullmatch(value):
                            raise ValueError(f"لون {_label} غير صالح. استخدم صيغة مثل #7c3aed.")
                        settings[key] = value

                    # Keep both the detailed and legacy hero product keys in sync.
                    for new_name, old_name in {
                        "hero_product_radius": "product_radius",
                        "hero_product_info_height": "product_info_height",
                        "hero_show_product_name": "show_product_name",
                        "hero_show_product_price": "show_product_price",
                        "hero_product_name_font_size": "product_name_font_size",
                        "hero_product_price_font_size": "product_price_font_size",
                        "hero_product_name_font_weight": "product_name_font_weight",
                        "hero_product_price_font_weight": "product_price_font_weight",
                        "hero_product_name_max_lines": "product_name_max_lines",
                        "hero_product_name_align": "product_name_align",
                        "hero_product_price_align": "product_price_align",
                        "hero_product_name_color": "product_name_color",
                        "hero_product_price_color": "product_price_color",
                        "hero_product_text_color": "product_text_color",
                        "hero_product_info_background_color": "product_info_background_color",
                        "hero_product_image_fit": "product_image_fit",
                    }.items():
                        if new_name not in settings or settings[new_name] is None:
                            settings[new_name] = settings.get(old_name)

                    row = AppSetting.query.filter_by(group_code="trends", key="display_settings").first()
                    payload = json.dumps(settings, ensure_ascii=False, separators=(",", ":"))
                    if row is None:
                        row = AppSetting(
                            group_code="trends",
                            key="display_settings",
                            value=payload,
                            value_type="json",
                        )
                        db.session.add(row)
                    else:
                        row.value = payload
                        row.value_type = "json"
                    db.session.commit()
                    success = "تم حفظ إعدادات الترندات."

                elif action == "save_product_card":
                    settings = dict(CatalogService.product_card_display_settings())
                    color_re = re.compile(r"^#[0-9a-fA-F]{6}$")

                    for group in product_card_groups:
                        for field in group["fields"]:
                            key, _label, kind = field[:3]
                            if kind == "checkbox":
                                settings[key] = request.form.get(key) == "on"
                            elif kind == "number":
                                raw = request.form.get(key)
                                value = float(raw) if raw not in (None, "") else float(settings[key])
                                value = max(float(field[3]), min(float(field[4]), value))
                                settings[key] = int(round(value)) if field[6] else value
                            elif kind == "text":
                                max_len = int(field[3])
                                settings[key] = (request.form.get(key) or settings.get(key) or "").strip()[:max_len]
                            elif kind == "select":
                                allowed = field[3]
                                value = (request.form.get(key) or settings.get(key) or "").strip()
                                if value not in allowed:
                                    raise ValueError(f"القيمة {key} غير صالحة.")
                                settings[key] = value

                    for key, _label in product_card_color_fields:
                        value = (request.form.get(key) or settings.get(key) or "").strip()
                        if not color_re.fullmatch(value):
                            raise ValueError(f"لون {_label} غير صالح. استخدم صيغة مثل #7c3aed.")
                        settings[key] = value

                    row = AppSetting.query.filter_by(
                        group_code="storefront",
                        key="product_card_settings",
                    ).first()
                    payload = json.dumps(settings, ensure_ascii=False, separators=(",", ":"))
                    if row is None:
                        row = AppSetting(
                            group_code="storefront",
                            key="product_card_settings",
                            value=payload,
                            value_type="json",
                        )
                        db.session.add(row)
                    else:
                        row.value = payload
                        row.value_type = "json"
                    db.session.commit()
                    success = "تم حفظ إعدادات بطاقة المنتج."

                else:
                    raise ValueError("إجراء الإعدادات غير معروف.")
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        return render_template(
            "admin/trend_product_display_settings.html",
            title="إعدادات الترندات وبطاقات المنتجات",
            section="المحتوى والمتجر",
            trend_display_settings=CatalogService.trend_display_settings(),
            trend_groups=trend_groups,
            trend_color_fields=trend_color_fields,
            product_card_settings=CatalogService.product_card_display_settings(),
            product_card_groups=product_card_groups,
            product_card_color_fields=product_card_color_fields,
            error=error,
            success=success,
            **_ctx(),
        )

    @admin_bp.route("/trends", methods=["GET", "POST"])
    def trends():
        from ..models import (
            Hashtag,
            MediaAsset,
            Product,
            ProductHashtag,
            Trend,
            TrendProduct,
            ProductMedia,
        )
        error = request.args.get("trend_settings_error") or None
        success = "تم حفظ التنسيق العام للترندات." if request.args.get("trend_settings") == "saved" else None

        if request.method == "POST":
            action = (request.form.get("action") or "create").strip()
            try:
                trend_id = request.form.get("id", type=int)
                hashtag_id = request.form.get("hashtag_id", type=int)
                promo_text = (request.form.get("promo_text") or "").strip()
                duration_days = request.form.get("duration_days", type=int) or 8
                sort_order = request.form.get("sort_order", type=int) or 0
                status = (request.form.get("status") or "draft").strip().lower()
                product_ids = request.form.getlist("product_ids", type=int)
                timer_enabled = request.form.get("timer_enabled") == "on"
                timer_value = request.form.get("timer_value", type=int)
                timer_unit = (request.form.get("timer_unit") or "seconds").strip().lower()
                overlay_text = (request.form.get("overlay_text") or "").strip() or None
                overlay_text_color = (request.form.get("overlay_text_color") or "#ffffff").strip()
                overlay_background_color = (request.form.get("overlay_background_color") or "#111827").strip()
                product_image_asset_ids = request.form.getlist("product_image_asset_ids", type=int)

                import re
                color_re = re.compile(r"^#[0-9a-fA-F]{6}$")
                if not color_re.fullmatch(overlay_text_color) or not color_re.fullmatch(overlay_background_color):
                    raise ValueError("ألوان النص والخلفية يجب أن تكون بصيغة HEX مثل #7c3aed.")
                if timer_enabled:
                    if timer_value is None or timer_value < 1:
                        raise ValueError("قيمة المؤقت يجب أن تكون رقمًا أكبر من صفر.")
                    if timer_unit not in {"seconds", "minutes"}:
                        raise ValueError("وحدة المؤقت يجب أن تكون ثوانٍ أو دقائق.")
                else:
                    timer_value = None
                    timer_unit = "seconds"

                if len(product_ids) != 3:
                    raise ValueError("يجب اختيار 3 منتجات بالضبط للترند.")
                if len(product_image_asset_ids) not in {0, 3}:
                    raise ValueError("صور منتجات الترند يجب أن تكون 3 صور أو تُترك تلقائية.")

                if action in {"create", "update"}:
                    if not hashtag_id:
                        raise ValueError("الهاشتاج الرئيسي مطلوب.")
                    if not promo_text:
                        raise ValueError("النص الترويجي مطلوب.")
                    if duration_days < 1:
                        raise ValueError("مدة العرض يجب أن تكون يومًا واحدًا على الأقل.")
                    if status not in {"draft", "active"}:
                        raise ValueError("حالة الترند غير صحيحة.")

                    product_ids = CatalogService.validate_trend_product_selection(
                        hashtag_id,
                        product_ids,
                    )
                    if len(product_image_asset_ids) == 3:
                        for slot, product_id in enumerate(product_ids):
                            asset_id = product_image_asset_ids[slot]
                            if asset_id <= 0:
                                continue
                            valid_media = (
                                db.session.query(ProductMedia)
                                .filter(
                                    ProductMedia.product_id == product_id,
                                    ProductMedia.asset_id == asset_id,
                                )
                                .first()
                            )
                            if valid_media is None:
                                raise ValueError("صورة أحد منتجات الترند لا تنتمي إلى المنتج المختار.")

                    trend = db.session.get(Trend, trend_id) if action == "update" else None
                    if action == "update" and trend is None:
                        raise ValueError("الترند غير موجود.")

                    image_file = request.files.get("background_image_file")
                    if image_file and image_file.filename:
                        assets = MediaService.save_generic_files([image_file], "trends")
                        if not assets:
                            raise ValueError("تعذر حفظ صورة خلفية الترند.")
                        background_asset_id = assets[0]["id"]
                    elif action == "create":
                        raise ValueError("صورة الخلفية مطلوبة.")
                    else:
                        background_asset_id = trend.background_asset_id

                    if action == "create":
                        trend = Trend(
                            hashtag_id=hashtag_id,
                            promo_text=promo_text,
                            duration_days=duration_days,
                            background_asset_id=background_asset_id,
                            status=status,
                            sort_order=sort_order,
                            timer_value=timer_value,
                            timer_unit=timer_unit,
                            timer_started_at=(db.func.now() if timer_enabled and status == "active" else None),
                            overlay_text=overlay_text,
                            overlay_text_color=overlay_text_color,
                            overlay_background_color=overlay_background_color,
                            is_active=True,
                        )
                        db.session.add(trend)
                        db.session.flush()
                        message = "تم إنشاء الترند المستطيل."
                    else:
                        trend.hashtag_id = hashtag_id
                        trend.promo_text = promo_text
                        trend.duration_days = duration_days
                        trend.background_asset_id = background_asset_id
                        trend.status = status
                        trend.sort_order = sort_order
                        trend.timer_value = timer_value
                        trend.timer_unit = timer_unit
                        trend.timer_started_at = db.func.now() if timer_enabled and status == "active" else None
                        trend.overlay_text = overlay_text
                        trend.overlay_text_color = overlay_text_color
                        trend.overlay_background_color = overlay_background_color
                        trend.is_active = True
                        message = "تم تحديث الترند المستطيل."

                    TrendProduct.query.filter_by(trend_id=trend.id).delete()
                    db.session.add_all([
                        TrendProduct(
                            trend_id=trend.id,
                            product_id=product_id,
                            slot=slot,
                            image_asset_id=(
                                product_image_asset_ids[slot]
                                if len(product_image_asset_ids) == 3
                                else None
                            ),
                            settings_json={},
                        )
                        for slot, product_id in enumerate(product_ids)
                    ])
                    db.session.commit()
                    success = message

                elif action == "archive":
                    trend = db.session.get(Trend, trend_id)
                    if trend is None:
                        raise ValueError("الترند غير موجود.")
                    trend.is_active = False
                    db.session.commit()
                    success = "تمت أرشفة الترند."

                elif action == "restore":
                    trend = db.session.get(Trend, trend_id)
                    if trend is None:
                        raise ValueError("الترند غير موجود.")
                    trend.is_active = True
                    trend.status = "draft"
                    db.session.commit()
                    success = "تمت إعادة الترند كمسودة."

                elif action == "hashtag_create":
                    name = (request.form.get("name") or "").strip()
                    display_name = (request.form.get("display_name") or "").strip() or None
                    slug = (
                        (request.form.get("slug") or "").strip().lower()
                        or _unique_slug(Hashtag, display_name or name, fallback="tag")
                    )
                    if not name:
                        raise ValueError("اسم الهاشتاج مطلوب.")
                    if Hashtag.query.filter_by(slug=slug).first():
                        raise ValueError("الـSlug مستخدم مسبقًا.")
                    db.session.add(Hashtag(
                        name=name,
                        slug=slug,
                        display_name=display_name,
                        sort_order=request.form.get("hashtag_sort_order", 0, type=int),
                    ))
                    db.session.commit()
                    success = "تمت إضافة الهاشتاج."

                else:
                    raise ValueError("إجراء الترند غير معروف.")
            except (ValueError, TypeError, OSError) as exc:
                db.session.rollback()
                error = str(exc)

        hashtags = (
            Hashtag.query
            .filter(Hashtag.is_active.is_(True))
            .order_by(Hashtag.sort_order, Hashtag.name)
            .limit(500)
            .all()
        )
        hashtag_map = {
            int(hashtag.id): (hashtag.display_name or f"#{hashtag.name}")
            for hashtag in hashtags
        }

        hashtag_products_count = {
            int(hashtag.id): ProductHashtag.query
            .join(Product, Product.id == ProductHashtag.product_id)
            .filter(
                ProductHashtag.hashtag_id == hashtag.id,
                Product.is_active.is_(True),
                Product.status == "published",
            )
            .count()
            for hashtag in hashtags
        }

        active_trends = (
            Trend.query
            .filter(Trend.is_active.is_(True))
            .order_by(Trend.sort_order, Trend.id.desc())
            .limit(100)
            .all()
        )
        archived_trends = (
            Trend.query
            .filter(Trend.is_active.is_(False))
            .order_by(Trend.id.desc())
            .limit(100)
            .all()
        )

        trend_seeds = []
        for trend in active_trends:
            background = db.session.get(MediaAsset, trend.background_asset_id)
            selected_products = []
            for assignment in (
                TrendProduct.query
                .filter_by(trend_id=trend.id)
                .order_by(TrendProduct.slot, TrendProduct.id)
                .all()
            ):
                product = db.session.get(Product, assignment.product_id)
                if product is None:
                    continue
                selected_product_payload = CatalogService._serialize_trend_product(product)
                selected_products.append({
                    "slot": assignment.slot,
                    "image_asset_id": assignment.image_asset_id,
                    "settings": assignment.settings_json if isinstance(assignment.settings_json, dict) else {},
                    "product": selected_product_payload,
                })
            public_reasons = []
            if trend.status != "active":
                public_reasons.append("الحالة ليست نشطة")
            if not background:
                public_reasons.append("لا توجد صورة خلفية")
            if not selected_products or len(selected_products) != 3:
                public_reasons.append("يجب توفر 3 منتجات منشورة")
            if CatalogService.is_trend_timer_expired(trend):
                public_reasons.append("المؤقت منتهي")
            trend_seeds.append({
                "id": trend.id,
                "public_ready": not public_reasons,
                "public_reason": "جاهز للعميل" if not public_reasons else "غير ظاهر: " + " • ".join(public_reasons),
                "hashtag_id": trend.hashtag_id,
                "promo_text": trend.promo_text,
                "duration_days": trend.duration_days,
                "sort_order": trend.sort_order,
                "status": trend.status,
                "is_active": bool(trend.is_active),
                "timer_enabled": bool(trend.timer_value),
                "timer_value": trend.timer_value,
                "timer_unit": trend.timer_unit,
                "timer_started_at": trend.timer_started_at.isoformat() if trend.timer_started_at else None,
                "overlay_text": trend.overlay_text or "",
                "overlay_text_color": trend.overlay_text_color or "#ffffff",
                "overlay_background_color": trend.overlay_background_color or "#111827",
                "settings": trend.settings_json if isinstance(trend.settings_json, dict) else {},
                "background_url": background.url if background else "",
                "products": selected_products,
            })

        return render_template(
            "admin/trends.html",
            title="الترندات والهاشتاجات",
            section="المحتوى والمتجر",
            hashtags=hashtags,
            hashtag_map=hashtag_map,
            hashtag_products_count=hashtag_products_count,
            active_trends=active_trends,
            archived_trends=archived_trends,
            trend_seeds=trend_seeds,
            trend_display_settings=CatalogService.trend_display_settings(),
            hashtag_seeds=[
                {
                    "id": hashtag.id,
                    "name": hashtag.name,
                    "display_name": hashtag.display_name or f"#{hashtag.name}",
                    "slug": hashtag.slug,
                }
                for hashtag in hashtags
            ],
            error=error,
            success=success,
            **_ctx(),
        )

    @admin_bp.route("/storefront/collections", methods=["GET", "POST"])
    def storefront_collections():
        from ..models import PromotionalStrip
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(PromotionalStrip,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip(); text_body=(request.form.get("text_body") or "").strip()
                    if not name or not text_body: raise ValueError("اسم الشريط ونصه مطلوبان.")
                    db.session.add(PromotionalStrip(name=name,text_prefix=(request.form.get("text_prefix") or "").strip() or None,text_body=text_body,background_color=(request.form.get("background_color") or "").strip() or None,text_color=(request.form.get("text_color") or "").strip() or None)); success="تمت إضافة شريط العرض."
                elif row is None: raise ValueError("شريط العرض غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة شريط العرض."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); text_body=(request.form.get("text_body") or "").strip()
                    if not name or not text_body: raise ValueError("اسم الشريط ونصه مطلوبان.")
                    row.name=name; row.text_prefix=(request.form.get("text_prefix") or "").strip() or None; row.text_body=text_body; row.background_color=(request.form.get("background_color") or "").strip() or None; row.text_color=(request.form.get("text_color") or "").strip() or None; success="تم تحديث شريط العرض."
                else: raise ValueError("إجراء شريط العرض غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=PromotionalStrip.query.filter_by(is_active=True).order_by(PromotionalStrip.id.desc()).limit(200).all()
        records=[{"id":x.id,"title":x.name,"badge":f"#{x.id}","color":x.background_color,"edit_action":"update","archive_action":"archive","edit_fields":[{"name":"name","label":"الاسم","required":True,"value":x.name},{"name":"text_prefix","label":"مقدمة قصيرة","value":x.text_prefix},{"name":"text_body","label":"نص العرض","required":True,"type":"textarea","value":x.text_body},{"name":"background_color","label":"لون الخلفية","type":"color","value":x.background_color or "#111827"},{"name":"text_color","label":"لون النص","type":"color","value":x.text_color or "#ffffff"}],"fields":[{"label":"النص","value":x.text_body},{"label":"الخلفية","value":x.background_color or "—","dir":"ltr"},{"label":"لون النص","value":x.text_color or "—","dir":"ltr"}]} for x in rows]
        return render_template("admin/manage.html",title="جديدنا والعروض",section="المحتوى والمتجر",description="إضافة وتعديل وأرشفة شرائط العروض.",fields=[{"name":"name","label":"الاسم","required":True},{"name":"text_prefix","label":"مقدمة قصيرة"},{"name":"text_body","label":"نص العرض","required":True,"type":"textarea"},{"name":"background_color","label":"لون الخلفية","type":"color","value":"#111827"},{"name":"text_color","label":"لون النص","type":"color","value":"#ffffff"}],records=records,modal_id="promoStripAddModal",success=success,error=error,**_ctx())

    @admin_bp.get("/payments/proofs")
    def payment_proofs():
        from ..models import PaymentProof
        rows = PaymentProof.query.order_by(PaymentProof.id.desc()).limit(200).all()
        return _render("إثباتات الدفع", ["ID", "الطلب", "المعاملة", "Asset", "الحالة"],
                       [[x.id, x.order_id, x.transaction_id or "—", x.asset_id, x.status] for x in rows], "المبيعات والطلبات")

    @admin_bp.get("/customers/addresses")
    def customer_addresses():
        from ..models import CustomerAddress
        rows = CustomerAddress.query.order_by(CustomerAddress.id.desc()).limit(300).all()
        return _render("عناوين العملاء", ["ID", "العميل", "المستلم", "الهاتف", "المدينة"],
                       [[x.id, x.customer_id, x.recipient_name, x.phone, x.city_id or "—"] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/attachments")
    def attachments():
        from ..models import MessageAttachment
        rows = MessageAttachment.query.order_by(MessageAttachment.id.desc()).limit(300).all()
        return _render("مرفقات المحادثات", ["ID", "الرسالة", "Asset", "النوع"],
                       [[x.id, x.message_id, x.asset_id, x.mime_type] for x in rows], "العملاء والتواصل")

    @admin_bp.get("/finance/wallet-ledger")
    def wallet_ledger():
        from ..models import WalletTransaction
        rows = WalletTransaction.query.order_by(WalletTransaction.id.desc()).limit(300).all()
        return _render("دفتر حركات المحافظ", ["ID", "المحفظة", "النوع", "المبلغ", "بعد الحركة"],
                       [[x.id, x.wallet_id, x.type, x.amount, x.balance_after] for x in rows], "الترويج والمالية")

    @admin_bp.get("/reports")
    def reports():
        from ..models import Order, Product, ProductVariant, StockInventory
        orders_total = db.session.query(func.coalesce(func.sum(Order.total), 0)).filter(Order.status != "cancelled").scalar()
        products_count = db.session.query(func.count(Product.id)).scalar() or 0
        variants_count = db.session.query(func.count(ProductVariant.id)).scalar() or 0
        available_stock = db.session.query(func.coalesce(func.sum(StockInventory.available), 0)).scalar() or 0
        rows = [
            ["مبيعات", "إجمالي الطلبات غير الملغاة", orders_total],
            ["كتالوج", "المنتجات", products_count],
            ["كتالوج", "المتغيرات", variants_count],
            ["مخزون", "المتاح", available_stock],
        ]
        return _render("التقارير", ["المجال", "المؤشر", "القيمة"], rows, "الترويج والمالية")


    @admin_bp.route("/system/settings", methods=["GET", "POST"])
    def settings():
        from ..models import AppSetting
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "save").strip(); row=db.session.get(AppSetting,request.form.get("id",type=int))
                if action=="create":
                    group=(request.form.get("group_code") or "").strip(); key=(request.form.get("key") or "").strip()
                    if not group or not key: raise ValueError("المجموعة والمفتاح مطلوبان.")
                    if AppSetting.query.filter_by(group_code=group,key=key).first(): raise ValueError("هذا الإعداد موجود مسبقًا.")
                    db.session.add(AppSetting(group_code=group,key=key,value=(request.form.get("value") or "").strip() or None,value_type=(request.form.get("value_type") or "text").strip())); success="تم إنشاء الإعداد."
                elif row is None: raise ValueError("الإعداد غير موجود.")
                elif action=="delete": db.session.delete(row); success="تم حذف الإعداد."
                elif action=="update":
                    group=(request.form.get("group_code") or "").strip(); key=(request.form.get("key") or "").strip()
                    if not group or not key: raise ValueError("المجموعة والمفتاح مطلوبان.")
                    if AppSetting.query.filter(AppSetting.id!=row.id,AppSetting.group_code==group,AppSetting.key==key).first(): raise ValueError("هذا الإعداد موجود مسبقًا.")
                    row.group_code=group; row.key=key; row.value=(request.form.get("value") or "").strip() or None; row.value_type=(request.form.get("value_type") or row.value_type).strip(); success="تم تحديث الإعداد."
                else: raise ValueError("إجراء الإعداد غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=AppSetting.query.order_by(AppSetting.group_code,AppSetting.key).limit(500).all()
        return render_template("admin/settings.html",title="الإعدادات",settings=rows,success=success,error=error,**build_admin_context())


    @admin_bp.route("/system/features", methods=["GET", "POST"])
    def features():
        import json
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(FeatureFlag,request.form.get("id",type=int))
                if action=="create":
                    key=(request.form.get("key") or "").strip(); raw=(request.form.get("conditions") or "{}").strip()
                    if not key: raise ValueError("مفتاح الميزة مطلوب.")
                    if FeatureFlag.query.filter_by(key=key).first(): raise ValueError("مفتاح الميزة مستخدم مسبقًا.")
                    db.session.add(FeatureFlag(key=key,enabled=request.form.get("enabled")=="on",conditions=json.loads(raw or "{}"))); success="تم إنشاء الميزة."
                elif row is None: raise ValueError("الميزة غير موجودة.")
                elif action=="archive": row.is_active=False; success="تم تعطيل الميزة."
                elif action=="update":
                    key=(request.form.get("key") or "").strip(); raw=(request.form.get("conditions") or "{}").strip()
                    if not key: raise ValueError("مفتاح الميزة مطلوب.")
                    if FeatureFlag.query.filter(FeatureFlag.id!=row.id,FeatureFlag.key==key).first(): raise ValueError("مفتاح الميزة مستخدم مسبقًا.")
                    row.key=key; row.enabled=request.form.get("enabled")=="on"; row.conditions=json.loads(raw or "{}"); success="تم تحديث الميزة."
                else: raise ValueError("إجراء الميزة غير معروف.")
                db.session.commit()
            except (ValueError,TypeError,json.JSONDecodeError) as exc: db.session.rollback(); error=str(exc)
        rows=FeatureFlag.query.filter_by(is_active=True).order_by(FeatureFlag.key).all()
        return render_template("admin/features.html",title="المزايا",flags=rows,success=success,error=error,**build_admin_context())

    @admin_bp.route("/pricing/currencies", methods=["GET", "POST"])
    def currencies():
        from ..models import Currency
        error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip()
                row=db.session.get(Currency,request.form.get("id",type=int))
                if action=="create":
                    code=(request.form.get("code") or "").strip().upper()
                    name=(request.form.get("name_ar") or "").strip()
                    if not code or not name: raise ValueError("كود العملة واسمها مطلوبان.")
                    if Currency.query.filter_by(code=code).first(): raise ValueError("كود العملة مستخدم مسبقًا.")
                    is_base=request.form.get("is_base")=="on"
                    if is_base and Currency.query.filter_by(is_base=True).first(): raise ValueError("توجد عملة أساسية بالفعل.")
                    db.session.add(Currency(code=code,symbol=(request.form.get("symbol") or "").strip() or None,name_ar=name,decimals=max(0,min(6,request.form.get("decimals",2,type=int))),is_base=is_base))
                    success="تم إنشاء العملة."
                elif row is None:
                    raise ValueError("العملة غير موجودة.")
                elif action=="archive":
                    if row.is_base: raise ValueError("لا يمكن أرشفة العملة الأساسية.")
                    row.is_active=False
                    success="تمت أرشفة العملة."
                elif action=="update":
                    code=(request.form.get("code") or "").strip().upper()
                    name=(request.form.get("name_ar") or "").strip()
                    if not code or not name: raise ValueError("كود العملة واسمها مطلوبان.")
                    if Currency.query.filter(Currency.id!=row.id,Currency.code==code).first(): raise ValueError("كود العملة مستخدم مسبقًا.")
                    is_base=request.form.get("is_base")=="on"
                    if is_base and Currency.query.filter(Currency.id!=row.id,Currency.is_base.is_(True),Currency.is_active.is_(True)).first():
                        raise ValueError("توجد عملة أساسية فعالة بالفعل.")
                    row.code=code; row.name_ar=name; row.symbol=(request.form.get("symbol") or "").strip() or None
                    row.decimals=max(0,min(6,request.form.get("decimals",2,type=int))); row.is_base=is_base; row.is_active=True
                    success="تم تحديث العملة."
                else:
                    raise ValueError("إجراء العملة غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc:
                db.session.rollback(); error=str(exc)
        rows=Currency.query.order_by(Currency.code).all()
        records=[]
        for row in rows:
            records.append({
                "id":row.id,
                "title":f"{row.code} · {row.name_ar}",
                "badge":"أساسية" if row.is_base else "فعال" if row.is_active else "معطل",
                "edit_action":"update",
                "archive_action":None if row.is_base else "archive",
                "edit_fields":[
                    {"name":"code","label":"Code","required":True,"value":row.code,"dir":"ltr"},
                    {"name":"name_ar","label":"الاسم","required":True,"value":row.name_ar},
                    {"name":"symbol","label":"الرمز","value":row.symbol or "","dir":"ltr"},
                    {"name":"decimals","label":"الكسور","type":"number","value":row.decimals,"min":0},
                    {"name":"is_base","label":"العملة الأساسية","type":"select","options":[
                        {"value":"","label":"لا","selected":not row.is_base},
                        {"value":"on","label":"نعم","selected":row.is_base}
                    ]}
                ],
                "fields":[
                    {"label":"الكود","value":row.code,"dir":"ltr"},
                    {"label":"الرمز","value":row.symbol or "—","dir":"ltr"},
                    {"label":"الكسور","value":row.decimals},
                    {"label":"الحالة","value":"نشطة" if row.is_active else "معطلة"}
                ]
            })
        return render_template("admin/manage.html",title="العملات",section="التسعير",description="إضافة وتعديل وأرشفة العملات. العملة الأساسية لا تُؤرشف.",fields=[
            {"name":"code","label":"Code","required":True,"dir":"ltr"},
            {"name":"name_ar","label":"الاسم","required":True},
            {"name":"symbol","label":"الرمز","dir":"ltr"},
            {"name":"decimals","label":"الكسور","type":"number","value":2,"min":0},
            {"name":"is_base","label":"العملة الأساسية","type":"select","options":[
                {"value":"","label":"لا","selected":True},
                {"value":"on","label":"نعم"}
            ]}
        ],records=records,modal_id="currencyAddModal",success=success,error=error,**_ctx())


    @admin_bp.route("/pricing/rates", methods=["GET", "POST"])
    def rates():
        from datetime import datetime, timezone
        from ..models import ExchangeRate, Currency
        error=None; success=None
        def parse_dt(raw):
            value=(raw or "").strip()
            if not value: return datetime.now(timezone.utc)
            dt=datetime.fromisoformat(value.replace("Z","+00:00"))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip()
                row=db.session.get(ExchangeRate,request.form.get("id",type=int))
                if action=="create":
                    base=request.form.get("base_currency_id",type=int); quote=request.form.get("quote_currency_id",type=int); rate=Decimal(request.form.get("rate") or "0")
                    if not base or not quote or base==quote or rate<=0: raise ValueError("اختر عملتين مختلفتين وسعرًا أكبر من صفر.")
                    if db.session.get(Currency,base) is None or db.session.get(Currency,quote) is None: raise ValueError("العملة المختارة غير موجودة.")
                    db.session.add(ExchangeRate(base_currency_id=base,quote_currency_id=quote,rate=rate,source=(request.form.get("source") or "").strip() or None,valid_from=parse_dt(request.form.get("valid_from")),valid_to=parse_dt(request.form.get("valid_to")) if request.form.get("valid_to") else None))
                    success="تم إنشاء سعر الصرف."
                elif row is None:
                    raise ValueError("سعر الصرف غير موجود.")
                elif action=="delete":
                    db.session.delete(row); success="تم حذف سعر الصرف."
                elif action=="update":
                    base=request.form.get("base_currency_id",type=int); quote=request.form.get("quote_currency_id",type=int); rate=Decimal(request.form.get("rate") or "0")
                    if not base or not quote or base==quote or rate<=0: raise ValueError("اختر عملتين مختلفتين وسعرًا أكبر من صفر.")
                    if db.session.get(Currency,base) is None or db.session.get(Currency,quote) is None: raise ValueError("العملة المختارة غير موجودة.")
                    row.base_currency_id=base; row.quote_currency_id=quote; row.rate=rate; row.source=(request.form.get("source") or "").strip() or None; row.valid_from=parse_dt(request.form.get("valid_from")); row.valid_to=parse_dt(request.form.get("valid_to")) if request.form.get("valid_to") else None
                    success="تم تحديث سعر الصرف."
                else:
                    raise ValueError("إجراء سعر الصرف غير معروف.")
                db.session.commit()
            except (ValueError,InvalidOperation) as exc:
                db.session.rollback(); error=str(exc)
        currencies=Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
        cmap={x.id:x for x in currencies}
        rows=ExchangeRate.query.order_by(ExchangeRate.valid_from.desc(),ExchangeRate.id.desc()).limit(300).all()
        records=[]
        for row in rows:
            records.append({
                "id":row.id,
                "title":f"{cmap.get(row.base_currency_id).code if cmap.get(row.base_currency_id) else row.base_currency_id} → {cmap.get(row.quote_currency_id).code if cmap.get(row.quote_currency_id) else row.quote_currency_id}",
                "badge":str(row.rate),
                "delete_action":"delete",
                "edit_action":"update",
                "edit_fields":[
                    {"name":"base_currency_id","label":"من","type":"select","options":[{"value":x.id,"label":x.code,"selected":x.id==row.base_currency_id} for x in currencies]},
                    {"name":"quote_currency_id","label":"إلى","type":"select","options":[{"value":x.id,"label":x.code,"selected":x.id==row.quote_currency_id} for x in currencies]},
                    {"name":"rate","label":"السعر","type":"number","value":row.rate,"step":0.000000000001,"min":0},
                    {"name":"source","label":"المصدر","value":row.source or ""},
                    {"name":"valid_from","label":"يبدأ","value":row.valid_from.isoformat(timespec="minutes") if row.valid_from else ""},
                    {"name":"valid_to","label":"ينتهي","value":row.valid_to.isoformat(timespec="minutes") if row.valid_to else ""}
                ],
                "fields":[
                    {"label":"السعر","value":row.rate,"dir":"ltr"},
                    {"label":"المصدر","value":row.source or "—"},
                    {"label":"من","value":cmap.get(row.base_currency_id).code if cmap.get(row.base_currency_id) else row.base_currency_id,"dir":"ltr"},
                    {"label":"إلى","value":cmap.get(row.quote_currency_id).code if cmap.get(row.quote_currency_id) else row.quote_currency_id,"dir":"ltr"}
                ]
            })
        return render_template("admin/manage.html",title="أسعار الصرف",section="التسعير",description="إضافة وتعديل وحذف أسعار الصرف. تحافظ الطلبات على السعر الذي استُخدم وقت الشراء.",fields=[
            {"name":"base_currency_id","label":"من","type":"select","options":[{"value":x.id,"label":x.code} for x in currencies]},
            {"name":"quote_currency_id","label":"إلى","type":"select","options":[{"value":x.id,"label":x.code} for x in currencies]},
            {"name":"rate","label":"السعر","type":"number","step":0.000000000001,"min":0,"required":True},
            {"name":"source","label":"المصدر"},
            {"name":"valid_from","label":"يبدأ","placeholder":"2026-09-25T00:00"},
            {"name":"valid_to","label":"ينتهي","placeholder":"اختياري"}
        ],records=records,modal_id="rateAddModal",success=success,error=error,**_ctx())


    @admin_bp.get("/pricing/city-assignments")
    def city_assignments():
        rows = PricingGroupCity.query.order_by(PricingGroupCity.priority.desc(), PricingGroupCity.id.desc()).limit(200).all()
        return _render("ربط المدن بالمجموعات", ["ID", "المدينة", "المنطقة", "المجموعة", "الأولوية"],
                       [[x.id, x.city_id or "—", x.region_id or "—", x.pricing_group_id, x.priority] for x in rows],
                       "التسعير")

    @admin_bp.get("/pricing/customer-assignments")
    def customer_assignments():
        from ..models import CustomerPricingAssignment
        rows = CustomerPricingAssignment.query.order_by(CustomerPricingAssignment.priority.desc(), CustomerPricingAssignment.id.desc()).limit(200).all()
        return _render("تعيينات العملاء", ["ID", "العميل", "المجموعة", "% override", "ثابت"],
                       [[x.id, x.customer_id, x.pricing_group_id, x.percent_override or 0, x.fixed_override or 0] for x in rows],
                       "التسعير")

    @admin_bp.get("/inventory")
    def inventory():
        rows = ProductVariant.query.order_by(ProductVariant.id.desc()).limit(200).all()
        return _render("المتغيرات والمخزون", ["ID", "المنتج", "SKU", "اللون", "المقاس"],
                       [[x.id, x.product_id, x.sku, x.color_id or "—", x.size_id or "—"] for x in rows],
                       "الكتالوج")

    @admin_bp.get("/media")
    def media():
        rows = ProductMedia.query.order_by(ProductMedia.id.desc()).limit(200).all()
        return _render("مكتبة الوسائط", ["ID", "المنتج", "Asset", "الدور"],
                       [[x.id, x.product_id, x.asset_id, x.role] for x in rows],
                       "الكتالوج")

    @admin_bp.get("/product-settings")
    def product_settings():
        rows = ProductDisplaySettings.query.order_by(ProductDisplaySettings.product_id).limit(200).all()
        return _render("إعدادات المنتج", ["المنتج", "التقييم", "تم البيع", "الشحن", "الإرجاع"],
                       [[x.product_id, x.show_rating, x.show_sold_badge, x.show_shipping_banner, x.show_return] for x in rows],
                       "الكتالوج")
