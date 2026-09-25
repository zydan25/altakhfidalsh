from ..app.extensions import db
from sqlalchemy import Boolean, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint

class TimestampMixin:
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now(), onupdate=db.func.now())

class ActiveMixin:
    is_active = db.Column(Boolean, nullable=False, default=True, server_default="true")

class Currency(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "currencies"
    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(8), nullable=False, unique=True)
    symbol = db.Column(String(16))
    name_ar = db.Column(String(80), nullable=False)
    decimals = db.Column(Integer, nullable=False, default=2)
    is_base = db.Column(Boolean, nullable=False, default=False)

class Region(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "regions"
    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(40), nullable=False)
    name = db.Column(String(160), nullable=False)
    country_code = db.Column(String(8), nullable=False, default="YE")
    sort_order = db.Column(Integer, nullable=False, default=0)

class City(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "cities"
    id = db.Column(Integer, primary_key=True)
    region_id = db.Column(ForeignKey("regions.id", ondelete="CASCADE"), nullable=False)
    code = db.Column(String(40), nullable=False)
    name = db.Column(String(160), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)

class ExchangeRate(TimestampMixin, db.Model):
    __tablename__ = "exchange_rates"
    id = db.Column(Integer, primary_key=True)
    base_currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    quote_currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    rate = db.Column(Numeric(24, 12), nullable=False)
    source = db.Column(String(80))
    valid_from = db.Column(db.DateTime(timezone=True), nullable=False)
    valid_to = db.Column(db.DateTime(timezone=True))

class PricingGroup(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "pricing_groups"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    description = db.Column(Text)
    default_currency_id = db.Column(ForeignKey("currencies.id"))
    priority = db.Column(Integer, nullable=False, default=0)
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    is_default = db.Column(Boolean, nullable=False, default=False)

class PricingGroupRule(TimestampMixin, db.Model):
    __tablename__ = "pricing_group_rules"
    id = db.Column(Integer, primary_key=True)
    group_id = db.Column(ForeignKey("pricing_groups.id", ondelete="CASCADE"), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    percent_markup = db.Column(Numeric(12, 4), nullable=False, default=0)
    fixed_markup = db.Column(Numeric(24, 4), nullable=False, default=0)
    rounding_rule = db.Column(String(40), nullable=False, default="nearest")
    decimals = db.Column(Integer, nullable=False, default=2)

class PricingGroupCity(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "pricing_group_cities"
    id = db.Column(Integer, primary_key=True)
    city_id = db.Column(ForeignKey("cities.id", ondelete="CASCADE"))
    region_id = db.Column(ForeignKey("regions.id", ondelete="CASCADE"))
    pricing_group_id = db.Column(ForeignKey("pricing_groups.id", ondelete="CASCADE"), nullable=False)
    priority = db.Column(Integer, nullable=False, default=0)

class Customer(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customers"
    id = db.Column(Integer, primary_key=True)
    phone_normalized = db.Column(String(32), nullable=False, unique=True)
    name = db.Column(String(160))
    email = db.Column(String(255))
    city_id = db.Column(ForeignKey("cities.id"))
    status = db.Column(String(40), nullable=False, default="active")

class CustomerAddress(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customer_addresses"
    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    recipient_name = db.Column(String(160), nullable=False)
    phone = db.Column(String(32), nullable=False)
    city_id = db.Column(ForeignKey("cities.id"))
    district = db.Column(String(160))
    street = db.Column(String(200))
    landmark = db.Column(String(200))
    lat = db.Column(Numeric(10, 7))
    lng = db.Column(Numeric(10, 7))
    is_default = db.Column(Boolean, nullable=False, default=False)

class CustomerPricingAssignment(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customer_pricing_assignments"
    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    pricing_group_id = db.Column(ForeignKey("pricing_groups.id", ondelete="CASCADE"), nullable=False)
    percent_override = db.Column(Numeric(12, 4))
    fixed_override = db.Column(Numeric(24, 4))
    priority = db.Column(Integer, nullable=False, default=0)

class MediaAsset(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "media_assets"
    id = db.Column(Integer, primary_key=True)
    storage_key = db.Column(String(500), nullable=False, unique=True)
    url = db.Column(String(1000), nullable=False)
    mime_type = db.Column(String(120), nullable=False)
    width = db.Column(Integer)
    height = db.Column(Integer)
    checksum = db.Column(String(128))
    metadata_json = db.Column(db.JSON)

class Category(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "categories"
    id = db.Column(Integer, primary_key=True)
    parent_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"))
    name = db.Column(String(160), nullable=False)
    slug = db.Column(String(180), nullable=False)
    icon_asset_id = db.Column(ForeignKey("media_assets.id"))
    sort_order = db.Column(Integer, nullable=False, default=0)
    display_style = db.Column(String(30), nullable=False, default="circle")
    __table_args__ = (UniqueConstraint("parent_id", "slug", name="uq_category_parent_slug"),)

class Brand(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "brands"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    slug = db.Column(String(180), nullable=False, unique=True)
    logo_asset_id = db.Column(ForeignKey("media_assets.id"))

class Color(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "colors"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(80), nullable=False)
    hex_code = db.Column(String(20))
    swatch_asset_id = db.Column(ForeignKey("media_assets.id"))
    sort_order = db.Column(Integer, nullable=False, default=0)

class Size(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "sizes"
    id = db.Column(Integer, primary_key=True)
    group = db.Column(String(80), nullable=False)
    code = db.Column(String(40), nullable=False)
    label = db.Column(String(80), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)

class Product(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "products"
    id = db.Column(Integer, primary_key=True)
    sku = db.Column(String(120), nullable=False, unique=True)
    name = db.Column(String(260), nullable=False)
    description = db.Column(Text)
    brand_id = db.Column(ForeignKey("brands.id"))
    base_currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    base_price = db.Column(Numeric(24, 4), nullable=False)
    compare_at_price = db.Column(Numeric(24, 4))
    status = db.Column(String(40), nullable=False, default="draft")
    material = db.Column(String(200))
    care_instructions = db.Column(Text)

class ProductCategory(TimestampMixin, db.Model):
    __tablename__ = "product_categories"
    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    category_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"), nullable=False)
    is_primary = db.Column(Boolean, nullable=False, default=False)
    __table_args__ = (UniqueConstraint("product_id", "category_id", name="uq_product_category"),)

class ProductVariant(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "product_variants"
    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    sku = db.Column(String(120), nullable=False, unique=True)
    color_id = db.Column(ForeignKey("colors.id"))
    size_id = db.Column(ForeignKey("sizes.id"))
    barcode = db.Column(String(120), unique=True)
    weight = db.Column(Numeric(16, 4))
    status = db.Column(String(40), nullable=False, default="active")

class InventoryLocation(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "inventory_locations"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    code = db.Column(String(80), nullable=False, unique=True)
    city_id = db.Column(ForeignKey("cities.id"))

class StockInventory(TimestampMixin, db.Model):
    __tablename__ = "stock_inventory"
    id = db.Column(Integer, primary_key=True)
    location_id = db.Column(ForeignKey("inventory_locations.id", ondelete="CASCADE"), nullable=False)
    variant_id = db.Column(ForeignKey("product_variants.id", ondelete="CASCADE"), nullable=False)
    on_hand = db.Column(Integer, nullable=False, default=0)
    reserved = db.Column(Integer, nullable=False, default=0)
    available = db.Column(Integer, nullable=False, default=0)
    reorder_level = db.Column(Integer, nullable=False, default=0)
    __table_args__ = (UniqueConstraint("location_id", "variant_id", name="uq_stock_location_variant"),)

class ShippingPolicy(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "shipping_policies"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    free_shipping_enabled = db.Column(Boolean, nullable=False, default=False)
    min_order_amount = db.Column(Numeric(24, 4))
    promo_text = db.Column(String(500))
    delivery_window = db.Column(String(120))

class Order(TimestampMixin, db.Model):
    __tablename__ = "orders"
    id = db.Column(Integer, primary_key=True)
    order_no = db.Column(String(60), nullable=False, unique=True)
    customer_id = db.Column(ForeignKey("customers.id"), nullable=False)
    address_snapshot = db.Column(db.JSON, nullable=False)
    city_id = db.Column(ForeignKey("cities.id"))
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    pricing_group_id = db.Column(ForeignKey("pricing_groups.id"))
    fx_rate = db.Column(Numeric(24, 12), nullable=False)
    subtotal = db.Column(Numeric(24, 4), nullable=False)
    discount = db.Column(Numeric(24, 4), nullable=False, default=0)
    shipping = db.Column(Numeric(24, 4), nullable=False, default=0)
    total = db.Column(Numeric(24, 4), nullable=False)
    status = db.Column(String(40), nullable=False, default="created")

class OrderItem(TimestampMixin, db.Model):
    __tablename__ = "order_items"
    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(ForeignKey("products.id"))
    variant_id = db.Column(ForeignKey("product_variants.id"))
    sku_snapshot = db.Column(String(120), nullable=False)
    name_snapshot = db.Column(String(260), nullable=False)
    base_price_sar = db.Column(Numeric(24, 4), nullable=False)
    fx_rate = db.Column(Numeric(24, 12), nullable=False)
    markup_percent = db.Column(Numeric(12, 4), nullable=False, default=0)
    markup_fixed = db.Column(Numeric(24, 4), nullable=False, default=0)
    sale_price_display = db.Column(Numeric(24, 4), nullable=False)
    qty = db.Column(Integer, nullable=False)
    total = db.Column(Numeric(24, 4), nullable=False)

class StorefrontPage(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "storefront_pages"
    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(80), nullable=False, unique=True)
    name = db.Column(String(160), nullable=False)
    route = db.Column(String(240), nullable=False, unique=True)

class StorefrontSection(TimestampMixin, db.Model):
    __tablename__ = "storefront_sections"
    id = db.Column(Integer, primary_key=True)
    page_id = db.Column(ForeignKey("storefront_pages.id", ondelete="CASCADE"), nullable=False)
    section_type = db.Column(String(60), nullable=False)
    title = db.Column(String(200))
    settings = db.Column(db.JSON, nullable=False, default=dict)
    sort_order = db.Column(Integer, nullable=False, default=0)
    visible_rules = db.Column(db.JSON, nullable=False, default=dict)

class StorefrontSectionItem(TimestampMixin, db.Model):
    __tablename__ = "storefront_section_items"
    id = db.Column(Integer, primary_key=True)
    section_id = db.Column(ForeignKey("storefront_sections.id", ondelete="CASCADE"), nullable=False)
    item_type = db.Column(String(40), nullable=False)
    item_id = db.Column(Integer, nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)
    custom_label = db.Column(String(160))

class Banner(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "banners"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(200), nullable=False)
    image_asset_id = db.Column(ForeignKey("media_assets.id"), nullable=False)
    mobile_asset_id = db.Column(ForeignKey("media_assets.id"))
    size_spec = db.Column(String(60))
    overlay_text = db.Column(Text)
    position_text = db.Column(String(40))
    duration = db.Column(Integer)
    status = db.Column(String(40), nullable=False, default="draft")

class BannerTarget(TimestampMixin, db.Model):
    __tablename__ = "banner_targets"
    id = db.Column(Integer, primary_key=True)
    banner_id = db.Column(ForeignKey("banners.id", ondelete="CASCADE"), nullable=False)
    target_type = db.Column(String(40), nullable=False)
    target_id = db.Column(Integer)
    url = db.Column(String(1000))
    priority = db.Column(Integer, nullable=False, default=0)

class Badge(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "badges"
    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False)
    code = db.Column(String(80), nullable=False, unique=True)
    icon_asset_id = db.Column(ForeignKey("media_assets.id"))
    bg_color = db.Column(String(20))
    text_color = db.Column(String(20))
    style = db.Column(String(40))
    priority = db.Column(Integer, nullable=False, default=0)

class Coupon(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "coupons"
    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(120), nullable=False, unique=True)
    type = db.Column(String(30), nullable=False)
    value = db.Column(Numeric(24, 4), nullable=False)
    min_order = db.Column(Numeric(24, 4))
    max_discount = db.Column(Numeric(24, 4))
    usage_limit = db.Column(Integer)
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    conditions = db.Column(db.JSON, nullable=False, default=dict)

class Wallet(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "wallets"
    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    balance = db.Column(Numeric(24, 4), nullable=False, default=0)
    status = db.Column(String(30), nullable=False, default="active")

class WalletTransaction(TimestampMixin, db.Model):
    __tablename__ = "wallet_transactions"
    id = db.Column(Integer, primary_key=True)
    wallet_id = db.Column(ForeignKey("wallets.id", ondelete="CASCADE"), nullable=False)
    type = db.Column(String(40), nullable=False)
    amount = db.Column(Numeric(24, 4), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    reference_type = db.Column(String(60))
    reference_id = db.Column(Integer)
    balance_after = db.Column(Numeric(24, 4), nullable=False)
