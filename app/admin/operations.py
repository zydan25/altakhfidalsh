from decimal import Decimal, InvalidOperation

from flask import render_template, request

from ..extensions import db
from ..models import (
    Banner,
    Campaign,
    Currency,
    PricingGroup,
    PricingGroupRule,
    PricingGroupCity,
    CustomerPricingAssignment,
    Customer,
    Region,
    City,
    Hashtag,
    Category,
    Product,
    BannerTarget,
    MediaAsset,
    Badge,
    ShippingPolicy,
    ReturnPolicy,
    WarrantyPolicy,
)
from ..services.pricing import PricingRule, calculate_customer_price
from .context import build_admin_context
from ..modules.catalog.services import MediaService


def register_operation_routes(admin_bp):
    @admin_bp.route("/catalog/policies", methods=["GET", "POST"])
    def catalog_policies():
        error = None
        success = None
        if request.method == "POST":
            try:
                action = (request.form.get("action") or "").strip()
                if action.startswith("badge_"):
                    row = db.session.get(Badge, request.form.get("id", type=int))
                    if action == "badge_create":
                        name = (request.form.get("name") or "").strip(); code = (request.form.get("code") or "").strip().lower()
                        if not name or not code: raise ValueError("اسم الشارة والكود مطلوبان.")
                        if Badge.query.filter_by(code=code).first(): raise ValueError("كود الشارة مستخدم مسبقًا.")
                        icon_id = None; file = request.files.get("icon_file")
                        if file and file.filename:
                            assets = MediaService.save_generic_files([file], "badges"); icon_id = assets[0]["id"] if assets else None
                        db.session.add(Badge(name=name, code=code, icon_asset_id=icon_id, bg_color=request.form.get("bg_color") or None, text_color=request.form.get("text_color") or None, style=request.form.get("style") or "solid", priority=request.form.get("priority", 0, type=int)))
                        success = "تمت إضافة الشارة."
                    elif row is None: raise ValueError("الشارة غير موجودة.")
                    elif action == "badge_archive": row.is_active = False; success = "تمت أرشفة الشارة."
                    else:
                        name=(request.form.get("name") or "").strip(); code=(request.form.get("code") or "").strip().lower()
                        if not name or not code: raise ValueError("اسم الشارة والكود مطلوبان.")
                        if Badge.query.filter(Badge.id != row.id, Badge.code == code).first(): raise ValueError("كود الشارة مستخدم مسبقًا.")
                        row.name=name; row.code=code; row.bg_color=request.form.get("bg_color") or None; row.text_color=request.form.get("text_color") or None; row.style=request.form.get("style") or "solid"; row.priority=request.form.get("priority", 0, type=int); success="تم تحديث الشارة."
                else:
                    kind = action.split("_", 1)[0]
                    model = {"shipping": ShippingPolicy, "return": ReturnPolicy, "warranty": WarrantyPolicy}.get(kind)
                    if model is None: raise ValueError("إجراء السياسة غير معروف.")
                    row = db.session.get(model, request.form.get("id", type=int))
                    if action.endswith("_create"):
                        name=(request.form.get("name") or "").strip()
                        if not name: raise ValueError("اسم السياسة مطلوب.")
                        if kind == "shipping": row=ShippingPolicy(name=name, free_shipping_enabled=request.form.get("free_shipping_enabled")=="on", min_order_amount=request.form.get("min_order_amount") or None, promo_text=request.form.get("promo_text") or None, delivery_window=request.form.get("delivery_window") or None)
                        elif kind == "return": row=ReturnPolicy(name=name, return_window_days=request.form.get("return_window_days",0,type=int), conditions=request.form.get("conditions") or None, fee_rule=request.form.get("fee_rule") or None, refund_method=request.form.get("refund_method") or None)
                        else: row=WarrantyPolicy(name=name, duration_days=request.form.get("duration_days",0,type=int), coverage=request.form.get("coverage") or None, exclusions=request.form.get("exclusions") or None, claim_method=request.form.get("claim_method") or None)
                        db.session.add(row); success="تمت إضافة السياسة."
                    elif row is None: raise ValueError("السياسة غير موجودة.")
                    elif action.endswith("_archive"): row.is_active=False; success="تمت أرشفة السياسة."
                    else:
                        row.name=(request.form.get("name") or "").strip()
                        if not row.name: raise ValueError("اسم السياسة مطلوب.")
                        if kind == "shipping": row.free_shipping_enabled=request.form.get("free_shipping_enabled")=="on"; row.min_order_amount=request.form.get("min_order_amount") or None; row.promo_text=request.form.get("promo_text") or None; row.delivery_window=request.form.get("delivery_window") or None
                        elif kind == "return": row.return_window_days=request.form.get("return_window_days",0,type=int); row.conditions=request.form.get("conditions") or None; row.fee_rule=request.form.get("fee_rule") or None; row.refund_method=request.form.get("refund_method") or None
                        else: row.duration_days=request.form.get("duration_days",0,type=int); row.coverage=request.form.get("coverage") or None; row.exclusions=request.form.get("exclusions") or None; row.claim_method=request.form.get("claim_method") or None
                        success="تم تحديث السياسة."
                db.session.commit()
            except (ValueError, TypeError, OSError) as exc:
                db.session.rollback(); error=str(exc)
        return render_template("admin/catalog_policies.html", title="الشارات والسياسات", badges=Badge.query.filter_by(is_active=True).order_by(Badge.priority.desc(),Badge.name).all(), shipping_policies=ShippingPolicy.query.filter_by(is_active=True).order_by(ShippingPolicy.name).all(), return_policies=ReturnPolicy.query.filter_by(is_active=True).order_by(ReturnPolicy.name).all(), warranty_policies=WarrantyPolicy.query.filter_by(is_active=True).order_by(WarrantyPolicy.name).all(), success=success, error=error, **build_admin_context())

    @admin_bp.route("/pricing/preview", methods=["GET", "POST"])
    def pricing_preview_page():
        context = _ctx()
        result = None
        error = None
        if request.method == "POST":
            try:
                result = calculate_customer_price(
                    Decimal(request.form["base_price_sar"]),
                    Decimal(request.form["fx_rate"]),
                    PricingRule(
                        Decimal(request.form.get("percent_markup", "0")),
                        Decimal(request.form.get("fixed_markup", "0")),
                        int(request.form.get("decimals", "2")),
                        request.form.get("rounding_rule", "nearest"),
                    ),
                )
            except (KeyError, InvalidOperation, ValueError) as exc:
                error = str(exc)
        return render_template(
            "admin/pricing_preview.html",
            title="معاينة السعر",
            result=result,
            error=error,
            **context,
        )

    @admin_bp.route("/banners", methods=["GET", "POST"])
    def banners():
        context=_ctx(); error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create_banner").strip(); row=db.session.get(Banner,request.form.get("id",type=int))
                if action=="create_banner":
                    name=(request.form.get("name") or "").strip(); image=request.files.get("image_file"); mobile=request.files.get("mobile_image_file")
                    if not name or not image or not image.filename: raise ValueError("اسم البانر والصورة الأساسية مطلوبان.")
                    files=[image]+([mobile] if mobile and mobile.filename else []); assets=MediaService.save_generic_files(files,"banners")
                    db.session.add(Banner(name=name,image_asset_id=assets[0]["id"],mobile_asset_id=assets[1]["id"] if len(assets)>1 else None,size_spec=(request.form.get("size_spec") or "").strip() or None,overlay_text=(request.form.get("overlay_text") or "").strip() or None,position_text=(request.form.get("position_text") or "").strip() or None,duration=request.form.get("duration",type=int),status=(request.form.get("status") or "draft").strip())); success="تم إنشاء البانر."
                elif action=="add_target":
                    banner_id=request.form.get("banner_id",type=int); target_type=(request.form.get("target_type") or "").strip(); target_id=request.form.get("target_id",type=int); url=(request.form.get("target_url") or "").strip() or None
                    if db.session.get(Banner,banner_id) is None: raise ValueError("البانر غير موجود.")
                    models={"category":Category,"product":Product,"campaign":Campaign}
                    if target_type=="url": target_id=None; url=url or (_ for _ in ()).throw(ValueError("الرابط مطلوب."))
                    elif target_type not in models or db.session.get(models[target_type],target_id) is None: raise ValueError("هدف البانر غير صحيح.")
                    db.session.add(BannerTarget(banner_id=banner_id,target_type=target_type,target_id=target_id,url=url,priority=request.form.get("target_priority",0,type=int))); success="تم ربط الهدف."
                elif action=="update_banner":
                    if row is None:
                        raise ValueError("البانر غير موجود.")
                    name=(request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم البانر مطلوب.")
                    row.name=name
                    row.size_spec=(request.form.get("size_spec") or "").strip() or None
                    row.overlay_text=(request.form.get("overlay_text") or "").strip() or None
                    row.position_text=(request.form.get("position_text") or "").strip() or None
                    row.duration=request.form.get("duration",type=int)
                    row.status=(request.form.get("status") or row.status).strip()
                    image=request.files.get("image_file")
                    mobile=request.files.get("mobile_image_file")
                    if image and image.filename:
                        assets=MediaService.save_generic_files([image],"banners")
                        if assets: row.image_asset_id=assets[0]["id"]
                    if mobile and mobile.filename:
                        assets=MediaService.save_generic_files([mobile],"banners")
                        if assets: row.mobile_asset_id=assets[0]["id"]
                    success="تم تحديث البانر."
                elif action=="archive_banner":
                    if row is None: raise ValueError("البانر غير موجود.")
                    row.is_active=False; success="تمت أرشفة البانر."
                elif action=="delete_target":
                    target=db.session.get(BannerTarget,request.form.get("id",type=int))
                    if target is None: raise ValueError("هدف البانر غير موجود.")
                    db.session.delete(target); success="تم حذف هدف البانر."
                elif action=="update_target":
                    target=db.session.get(BannerTarget,request.form.get("target_id",type=int))
                    if target is None:
                        raise ValueError("هدف البانر غير موجود.")
                    target_type=(request.form.get("target_type") or target.target_type).strip()
                    if target_type not in {"category","product","campaign","url"}:
                        raise ValueError("نوع هدف البانر غير مدعوم.")
                    if target_type == "url":
                        url=(request.form.get("target_url") or "").strip()
                        if not url:
                            raise ValueError("الرابط مطلوب.")
                        target.target_id=None
                        target.url=url
                    else:
                        target_id=request.form.get("target_id_value",type=int)
                        model={"category":Category,"product":Product,"campaign":Campaign}[target_type]
                        if not target_id or db.session.get(model,target_id) is None:
                            raise ValueError("الهدف المختار غير موجود.")
                        target.target_id=target_id
                        target.url=None
                    target.target_type=target_type
                    target.priority=request.form.get("target_priority",0,type=int)
                    success="تم تحديث هدف البانر."
                else: raise ValueError("إجراء البانر غير معروف.")
                db.session.commit()
            except (ValueError,OSError,TypeError) as exc: db.session.rollback(); error=str(exc)
        banners=Banner.query.filter_by(is_active=True).order_by(Banner.id.desc()).limit(100).all()
        ids=[x.id for x in banners]; asset_ids=[]
        for x in banners: asset_ids += [x.image_asset_id] + ([x.mobile_asset_id] if x.mobile_asset_id else [])
        assets=MediaAsset.query.filter(MediaAsset.id.in_(asset_ids)).all() if asset_ids else []; asset_map={x.id:x for x in assets}
        targets=BannerTarget.query.filter(BannerTarget.banner_id.in_(ids)).order_by(BannerTarget.priority.desc(),BannerTarget.id.desc()).all() if ids else []
        categories=Category.query.filter_by(is_active=True).order_by(Category.sort_order,Category.name).limit(300).all(); products=Product.query.filter(Product.is_active.is_(True),Product.status!="archived").order_by(Product.id.desc()).limit(300).all(); campaigns=Campaign.query.filter_by(is_active=True).order_by(Campaign.display_priority.desc(),Campaign.name).limit(200).all()
        return render_template("admin/banners.html",title="البانرات",banners=banners,asset_map=asset_map,targets=targets,categories=categories,products=products,campaigns=campaigns,success=success,error=error,**context)

    @admin_bp.route("/campaigns", methods=["GET", "POST"])
    def campaigns():
        from .entity_views import _unique_slug
        context=_ctx(); error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Campaign,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip()
                    if not name: raise ValueError("اسم الحملة مطلوب.")
                    slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Campaign,name,fallback="campaign")
                    if Campaign.query.filter_by(slug=slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    db.session.add(Campaign(name=name,slug=slug,start_at=None,end_at=None,status=(request.form.get("status") or "draft").strip(),display_priority=request.form.get("display_priority",0,type=int))); success="تم إنشاء الحملة."
                elif row is None: raise ValueError("الحملة غير موجودة.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الحملة."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Campaign,name,exclude_id=row.id,fallback="campaign")
                    if not name: raise ValueError("اسم الحملة مطلوب.")
                    if Campaign.query.filter(Campaign.id!=row.id,Campaign.slug==slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    row.name=name; row.slug=slug; row.status=(request.form.get("status") or row.status).strip(); row.display_priority=request.form.get("display_priority",0,type=int); success="تم تحديث الحملة."
                else: raise ValueError("إجراء الحملة غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Campaign.query.filter_by(is_active=True).order_by(Campaign.id.desc()).limit(100).all()
        records=[{"id":x.id,"title":x.name,"badge":x.status,"edit_action":"update","archive_action":"archive","edit_fields":[{"name":"name","label":"اسم الحملة","required":True,"value":x.name},{"name":"slug","label":"Slug","dir":"ltr","value":x.slug},{"name":"status","label":"الحالة","type":"select","options":[{"value":"draft","label":"مسودة","selected":x.status=="draft"},{"value":"scheduled","label":"مجدولة","selected":x.status=="scheduled"},{"value":"active","label":"نشطة","selected":x.status=="active"}]},{"name":"display_priority","label":"الأولوية","type":"number","value":x.display_priority}],"fields":[{"label":"Slug","value":x.slug,"dir":"ltr"},{"label":"الأولوية","value":x.display_priority}]} for x in rows]
        return render_template("admin/manage.html",title="الحملات",section="المحتوى والمتجر",description="إضافة وتعديل وأرشفة الحملات، مع Slug تلقائي.",fields=[{"name":"name","label":"اسم الحملة","required":True},{"name":"slug","label":"Slug","dir":"ltr"},{"name":"status","label":"الحالة","type":"select","options":[{"value":"draft","label":"مسودة","selected":True},{"value":"scheduled","label":"مجدولة"},{"value":"active","label":"نشطة"}]},{"name":"display_priority","label":"الأولوية","type":"number","value":0}],records=records,modal_id="campaignAddModal",success=success,error=error,**context)


    @admin_bp.route("/hashtags", methods=["GET", "POST"])
    def hashtags():
        from .entity_views import _unique_slug
        context=_ctx(); error=None; success=None
        if request.method=="POST":
            try:
                action=(request.form.get("action") or "create").strip(); row=db.session.get(Hashtag,request.form.get("id",type=int))
                if action=="create":
                    name=(request.form.get("name") or "").strip(); display=(request.form.get("display_name") or "").strip() or name
                    if not name: raise ValueError("اسم الوسم مطلوب.")
                    slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Hashtag,display,fallback="tag")
                    if Hashtag.query.filter_by(slug=slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    db.session.add(Hashtag(name=name,slug=slug,display_name=display,sort_order=request.form.get("sort_order",0,type=int))); success="تم إنشاء الوسم."
                elif row is None: raise ValueError("الوسم غير موجود.")
                elif action=="archive": row.is_active=False; success="تمت أرشفة الوسم."
                elif action=="update":
                    name=(request.form.get("name") or "").strip(); display=(request.form.get("display_name") or "").strip() or name; slug=(request.form.get("slug") or "").strip().lower() or _unique_slug(Hashtag,display,exclude_id=row.id,fallback="tag")
                    if not name: raise ValueError("اسم الوسم مطلوب.")
                    if Hashtag.query.filter(Hashtag.id!=row.id,Hashtag.slug==slug).first(): raise ValueError("الـSlug مستخدم مسبقًا.")
                    row.name=name; row.display_name=display; row.slug=slug; row.sort_order=request.form.get("sort_order",0,type=int); success="تم تحديث الوسم."
                else: raise ValueError("إجراء الوسم غير معروف.")
                db.session.commit()
            except (ValueError,TypeError) as exc: db.session.rollback(); error=str(exc)
        rows=Hashtag.query.filter_by(is_active=True).order_by(Hashtag.sort_order,Hashtag.id.desc()).limit(300).all()
        records=[{"id":x.id,"title":x.display_name or x.name,"badge":f"#{x.id}","edit_action":"update","archive_action":"archive","edit_fields":[{"name":"name","label":"الاسم","required":True,"value":x.name},{"name":"slug","label":"Slug","dir":"ltr","value":x.slug},{"name":"display_name","label":"اسم العرض","value":x.display_name or x.name},{"name":"sort_order","label":"الترتيب","type":"number","value":x.sort_order}],"fields":[{"label":"Slug","value":x.slug,"dir":"ltr"},{"label":"الترتيب","value":x.sort_order}]} for x in rows]
        return render_template("admin/manage.html",title="الهاشتاجات",section="المحتوى والمتجر",description="إضافة وتعديل وأرشفة الهاشتاجات مع Slug تلقائي.",fields=[{"name":"name","label":"الاسم","required":True},{"name":"slug","label":"Slug","dir":"ltr"},{"name":"display_name","label":"اسم العرض"},{"name":"sort_order","label":"الترتيب","type":"number","value":0}],records=records,modal_id="hashtagAddModal",success=success,error=error,**context)



def _ctx():
    return build_admin_context()
