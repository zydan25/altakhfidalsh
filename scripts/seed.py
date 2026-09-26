import os

from app import create_app
from app.extensions import db
from app.models import (
    AdminRole,
    Country,
    Currency,
    Permission,
    PricingGroup,
    PricingGroupRule,
    Region,
    Role,
    RolePermission,
)


def seed():
    app = create_app()
    with app.app_context():
        sar = Currency.query.filter_by(code="SAR").first()
        if sar is None:
            sar = Currency(
                code="SAR",
                symbol="ر.س",
                name_ar="الريال السعودي",
                decimals=2,
                is_base=True,
            )
            db.session.add(sar)

        for code, symbol, name_ar, decimals in (
            ("YER", "﷼", "الريال اليمني", 0),
            ("USD", "$", "الدولار الأمريكي", 2),
        ):
            if Currency.query.filter_by(code=code).first() is None:
                db.session.add(Currency(
                    code=code,
                    symbol=symbol,
                    name_ar=name_ar,
                    decimals=decimals,
                    is_base=False,
                ))

        db.session.flush()

        group = (
            PricingGroup.query
            .filter(PricingGroup.is_default.is_(True))
            .order_by(PricingGroup.priority.desc(), PricingGroup.id)
            .first()
        )
        if group is None:
            group = PricingGroup(
                name="المجموعة الافتراضية",
                description="مجموعة أسعار أساسية تبدأ بسعر SAR نفسه",
                default_currency_id=sar.id,
                priority=0,
                is_default=True,
            )
            db.session.add(group)
            db.session.flush()

        if PricingGroupRule.query.filter_by(group_id=group.id, currency_id=sar.id).first() is None:
            db.session.add(PricingGroupRule(
                group_id=group.id,
                currency_id=sar.id,
                percent_markup=0,
                fixed_markup=0,
                rounding_rule="nearest",
                decimals=2,
            ))

        country = Country.query.filter_by(code="YE").first()
        if country is None:
            country = Country(code="YE", name_ar="اليمن", name_en="Yemen", phone_code="+967")
            db.session.add(country)
            db.session.flush()

        for code, name in (("NORTH", "الشمال"), ("SOUTH", "الجنوب")):
            if Region.query.filter_by(country_id=country.id, code=code).first() is None:
                db.session.add(Region(country_id=country.id, code=code, name=name))

        permissions = [
            ("dashboard.view", "عرض لوحة التحكم"),
            ("product.view", "عرض المنتجات"),
            ("product.create", "إنشاء المنتجات"),
            ("product.edit", "تعديل المنتجات"),
            ("category.view", "عرض التصنيفات"),
            ("category.manage", "إدارة التصنيفات"),
            ("pricing.view", "عرض التسعير"),
            ("pricing.manage", "إدارة التسعير"),
            ("content.view", "عرض المحتوى"),
            ("banner.manage", "إدارة البانرات"),
            ("campaign.view", "عرض الحملات"),
            ("campaign.manage", "إدارة الحملات"),
            ("hashtag.view", "عرض الهاشتاجات"),
            ("hashtag.manage", "إدارة الهاشتاجات"),
            ("order.view", "عرض الطلبات"),
            ("order.manage", "إدارة الطلبات"),
            ("customer.view", "عرض العملاء"),
            ("customer.manage", "إدارة العملاء"),
            ("inventory.manage", "إدارة المخزون"),
            ("policy.manage", "إدارة السياسات"),
            ("content.manage", "إدارة محتوى المتجر"),
            ("payment.manage", "إدارة الدفعات"),
            ("shipping.manage", "إدارة الشحن"),
            ("refund.approve", "اعتماد الاسترداد"),
            ("promotion.manage", "إدارة الترويج"),
            ("wallet.adjust", "تعديل المحافظ"),
            ("campaign.manage", "إدارة الحملات"),
            ("system.manage", "إدارة النظام"),
            ("theme.manage", "إدارة الثيم"),
            ("geo.manage", "إدارة الجغرافيا"),
            ("report.view", "عرض التقارير"),
            ("product.publish", "نشر المنتجات"),
            ("side_category.view", "عرض الفئات الجانبية"),
            ("side_category.manage", "إدارة الفئات الجانبية"),
        ]
        permission_rows = []
        for code, name in permissions:
            row = Permission.query.filter_by(code=code).first()
            if row is None:
                row = Permission(code=code, name=name)
                db.session.add(row)
                db.session.flush()
            permission_rows.append(row)

        role = Role.query.filter_by(code="super_admin").first()
        if role is None:
            role = Role(name="مدير النظام", code="super_admin")
            db.session.add(role)
            db.session.flush()
        for permission in permission_rows:
            if RolePermission.query.filter_by(role_id=role.id, permission_id=permission.id).first() is None:
                db.session.add(RolePermission(role_id=role.id, permission_id=permission.id))

        admin_username = os.getenv("ADMIN_USERNAME")
        admin_password = os.getenv("ADMIN_PASSWORD")
        if admin_username and admin_password:
            from app.admin.auth import AdminAuthService
            admin = AdminAuthService.bootstrap(admin_username, admin_password)
            from app.services.phone import normalize_phone
            from app.models import Admin
            admin_row_model = db.session.get(Admin, admin["id"])
            admin_row_model.phone = normalize_phone(os.getenv("ADMIN_PHONE", "774952665"))
            admin_row = AdminRole.query.filter_by(admin_id=admin["id"], role_id=role.id).first()
            if admin_row is None:
                db.session.add(AdminRole(admin_id=admin["id"], role_id=role.id))

        db.session.commit()
        print("Seed completed.")


if __name__ == "__main__":
    seed()
