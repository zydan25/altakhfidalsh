from app import create_app
from app.extensions import db
from app.models import Country, Currency, PricingGroup, PricingGroupRule, Region


def seed():
    app = create_app()
    with app.app_context():
        sar = Currency.query.filter_by(code="SAR").first()
        if sar is None:
            sar = Currency(code="SAR", symbol="ر.س", name_ar="الريال السعودي", decimals=2, is_base=True)
            db.session.add(sar)

        yer = Currency.query.filter_by(code="YER").first()
        if yer is None:
            yer = Currency(code="YER", symbol="﷼", name_ar="الريال اليمني", decimals=0, is_base=False)
            db.session.add(yer)

        usd = Currency.query.filter_by(code="USD").first()
        if usd is None:
            usd = Currency(code="USD", symbol="$", name_ar="الدولار الأمريكي", decimals=2, is_base=False)
            db.session.add(usd)

        db.session.flush()

        group = PricingGroup.query.filter_by(code="default").first() if hasattr(PricingGroup, "code") else None
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

        db.session.commit()
        print("Seed completed: SAR/YER/USD, default pricing group, Yemen North/South regions.")


if __name__ == "__main__":
    seed()
