from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, Index
from .extensions import db


class TimestampMixin:
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    updated_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        server_default=db.func.now(),
        onupdate=db.func.now(),
    )


class ActiveMixin:
    is_active = db.Column(Boolean, nullable=False, default=True, server_default="true")


# ---------------------------------------------------------------------------
# Geography, currencies and customer pricing
# ---------------------------------------------------------------------------

class Country(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "countries"

    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(8), nullable=False, unique=True)
    name_ar = db.Column(String(120), nullable=False)
    name_en = db.Column(String(120))
    phone_code = db.Column(String(16))


class Region(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "regions"

    id = db.Column(Integer, primary_key=True)
    country_id = db.Column(ForeignKey("countries.id", ondelete="CASCADE"), nullable=False)
    code = db.Column(String(40), nullable=False)
    name = db.Column(String(160), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)
    __table_args__ = (
        UniqueConstraint("country_id", "code", name="uq_region_country_code"),
    )


class City(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "cities"

    id = db.Column(Integer, primary_key=True)
    region_id = db.Column(ForeignKey("regions.id", ondelete="CASCADE"), nullable=False)
    code = db.Column(String(40), nullable=False)
    name = db.Column(String(160), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)
    __table_args__ = (
        UniqueConstraint("region_id", "code", name="uq_city_region_code"),
        Index("ix_city_region_active", "region_id", "is_active"),
    )


class Currency(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "currencies"

    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(8), nullable=False, unique=True)
    symbol = db.Column(String(16))
    name_ar = db.Column(String(80), nullable=False)
    decimals = db.Column(Integer, nullable=False, default=2)
    is_base = db.Column(Boolean, nullable=False, default=False)


class ExchangeRate(TimestampMixin, db.Model):
    __tablename__ = "exchange_rates"

    id = db.Column(Integer, primary_key=True)
    base_currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    quote_currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    rate = db.Column(Numeric(24, 12), nullable=False)
    source = db.Column(String(80))
    valid_from = db.Column(db.DateTime(timezone=True), nullable=False)
    valid_to = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        Index(
            "ix_exchange_rate_lookup",
            "base_currency_id",
            "quote_currency_id",
            "valid_from",
        ),
    )


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
    __table_args__ = (
        UniqueConstraint("group_id", "currency_id", name="uq_pricing_rule_currency"),
    )


class PricingGroupCity(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "pricing_group_cities"

    id = db.Column(Integer, primary_key=True)
    city_id = db.Column(ForeignKey("cities.id", ondelete="CASCADE"))
    region_id = db.Column(ForeignKey("regions.id", ondelete="CASCADE"))
    pricing_group_id = db.Column(ForeignKey("pricing_groups.id", ondelete="CASCADE"), nullable=False)
    priority = db.Column(Integer, nullable=False, default=0)
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        CheckConstraint(
            "(city_id IS NOT NULL) OR (region_id IS NOT NULL)",
            name="ck_pricing_group_city_or_region",
        ),
        Index("ix_pricing_group_city_lookup", "city_id", "priority"),
        Index("ix_pricing_group_region_lookup", "region_id", "priority"),
    )


class Customer(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customers"

    id = db.Column(Integer, primary_key=True)
    phone_normalized = db.Column(String(32), nullable=False, unique=True)
    name = db.Column(String(160))
    email = db.Column(String(255))
    city_id = db.Column(ForeignKey("cities.id"))
    status = db.Column(String(40), nullable=False, default="active")
    created_via = db.Column(String(40), nullable=False, default="otp")
    __table_args__ = (Index("ix_customer_city_status", "city_id", "status"),)


class CustomerAddress(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customer_addresses"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    recipient_name = db.Column(String(160), nullable=False)
    phone = db.Column(String(32), nullable=False)
    country_id = db.Column(ForeignKey("countries.id"))
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
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        Index("ix_customer_pricing_assignment", "customer_id", "priority"),
    )


class CustomerDevice(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "customer_devices"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    device_id = db.Column(String(255), nullable=False)
    platform = db.Column(String(30))
    push_token = db.Column(String(500))
    last_seen = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        UniqueConstraint("customer_id", "device_id", name="uq_customer_device"),
    )


class OTPRequest(TimestampMixin, db.Model):
    __tablename__ = "otp_requests"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="SET NULL"))
    phone = db.Column(String(32), nullable=False)
    purpose = db.Column(String(40), nullable=False, default="login")
    code_hash = db.Column(String(255), nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)
    attempts = db.Column(Integer, nullable=False, default=0)
    status = db.Column(String(30), nullable=False, default="pending")


class AuthSession(TimestampMixin, db.Model):
    __tablename__ = "auth_sessions"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    refresh_token_hash = db.Column(String(255), nullable=False, unique=True)
    device_id = db.Column(String(255))
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)
    revoked_at = db.Column(db.DateTime(timezone=True))


class CustomerPreference(TimestampMixin, db.Model):
    __tablename__ = "customer_preferences"

    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), primary_key=True)
    locale = db.Column(String(16), nullable=False, default="ar")
    preferred_currency_id = db.Column(ForeignKey("currencies.id"))
    notifications_enabled = db.Column(Boolean, nullable=False, default=True)
    theme_mode = db.Column(String(20), nullable=False, default="system")


# ---------------------------------------------------------------------------
# Media, catalog and product variants
# ---------------------------------------------------------------------------

class MediaAsset(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "media_assets"

    id = db.Column(Integer, primary_key=True)
    storage_key = db.Column(String(500), nullable=False, unique=True)
    url = db.Column(String(1000), nullable=False)
    mime_type = db.Column(String(120), nullable=False)
    width = db.Column(Integer)
    height = db.Column(Integer)
    checksum = db.Column(String(128))
    size_bytes = db.Column(db.BigInteger)
    metadata_json = db.Column(db.JSON)


class Category(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "categories"

    id = db.Column(Integer, primary_key=True)
    parent_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"))
    name = db.Column(String(160), nullable=False)
    slug = db.Column(String(180), nullable=False)
    icon_asset_id = db.Column(ForeignKey("media_assets.id"))
    badge_id = db.Column(ForeignKey("badges.id"))
    sort_order = db.Column(Integer, nullable=False, default=0)
    display_style = db.Column(String(30), nullable=False, default="circle")
    is_featured = db.Column(Boolean, nullable=False, default=False)
    __table_args__ = (
        UniqueConstraint("parent_id", "slug", name="uq_category_parent_slug"),
        Index("ix_category_tree", "parent_id", "sort_order", "is_active"),
    )


class CategoryNavigationItem(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "category_navigation_items"

    id = db.Column(Integer, primary_key=True)
    category_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"), nullable=False)
    slot = db.Column(String(60), nullable=False, default="top")
    visible = db.Column(Boolean, nullable=False, default=True)
    sort_order = db.Column(Integer, nullable=False, default=0)
    label_override = db.Column(String(160))


class CategoryFilterDefinition(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "category_filter_definitions"

    id = db.Column(Integer, primary_key=True)
    category_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"), nullable=False)
    name = db.Column(String(120), nullable=False)
    filter_type = db.Column(String(40), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)


class CategoryFilterValue(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "category_filter_values"

    id = db.Column(Integer, primary_key=True)
    filter_id = db.Column(ForeignKey("category_filter_definitions.id", ondelete="CASCADE"), nullable=False)
    label = db.Column(String(120), nullable=False)
    slug = db.Column(String(160), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)


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
    __table_args__ = (
        UniqueConstraint("group", "code", name="uq_size_group_code"),
    )


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
    product_type = db.Column(String(80))
    published_at = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        Index("ix_product_status_sort", "status", "is_active"),
    )


class ProductCategory(TimestampMixin, db.Model):
    __tablename__ = "product_categories"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    category_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"), nullable=False)
    is_primary = db.Column(Boolean, nullable=False, default=False)
    __table_args__ = (
        UniqueConstraint("product_id", "category_id", name="uq_product_category"),
    )


class ProductMedia(TimestampMixin, db.Model):
    __tablename__ = "product_media"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="CASCADE"), nullable=False)
    role = db.Column(String(40), nullable=False, default="gallery")
    sort_order = db.Column(Integer, nullable=False, default=0)
    alt_text = db.Column(String(300))


class ProductVideo(TimestampMixin, db.Model):
    __tablename__ = "product_videos"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="SET NULL"))
    external_url = db.Column(String(1000))
    poster_asset_id = db.Column(ForeignKey("media_assets.id", ondelete="SET NULL"))
    duration = db.Column(Integer)
    sort_order = db.Column(Integer, nullable=False, default=0)


class ProductOption(TimestampMixin, db.Model):
    __tablename__ = "product_options"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    name = db.Column(String(120), nullable=False)
    option_type = db.Column(String(30), nullable=False, default="custom")
    required = db.Column(Boolean, nullable=False, default=False)
    sort_order = db.Column(Integer, nullable=False, default=0)


class ProductOptionValue(TimestampMixin, db.Model):
    __tablename__ = "product_option_values"

    id = db.Column(Integer, primary_key=True)
    option_id = db.Column(ForeignKey("product_options.id", ondelete="CASCADE"), nullable=False)
    label = db.Column(String(120), nullable=False)
    color_id = db.Column(ForeignKey("colors.id"))
    size_id = db.Column(ForeignKey("sizes.id"))
    sort_order = db.Column(Integer, nullable=False, default=0)


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


class VariantOptionValue(TimestampMixin, db.Model):
    __tablename__ = "variant_option_values"

    id = db.Column(Integer, primary_key=True)
    variant_id = db.Column(ForeignKey("product_variants.id", ondelete="CASCADE"), nullable=False)
    option_value_id = db.Column(ForeignKey("product_option_values.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (
        UniqueConstraint("variant_id", "option_value_id", name="uq_variant_option_value"),
    )


class VariantMedia(TimestampMixin, db.Model):
    __tablename__ = "variant_media"

    id = db.Column(Integer, primary_key=True)
    variant_id = db.Column(ForeignKey("product_variants.id", ondelete="CASCADE"), nullable=False)
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="CASCADE"), nullable=False)
    role = db.Column(String(40), nullable=False, default="gallery")
    sort_order = db.Column(Integer, nullable=False, default=0)


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
    __table_args__ = (
        UniqueConstraint("location_id", "variant_id", name="uq_stock_location_variant"),
    )


class ProductDisplaySettings(TimestampMixin, db.Model):
    __tablename__ = "product_display_settings"

    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    show_rating = db.Column(Boolean, nullable=False, default=True)
    show_sold_badge = db.Column(Boolean, nullable=False, default=True)
    show_shipping_banner = db.Column(Boolean, nullable=False, default=True)
    show_return = db.Column(Boolean, nullable=False, default=True)
    show_review_count = db.Column(Boolean, nullable=False, default=True)
    card_aspect_ratio = db.Column(String(20), nullable=False, default="3:4")
    card_radius = db.Column(Integer, nullable=False, default=16)


class SizeGuide(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "size_guides"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    guide_type = db.Column(String(40), nullable=False, default="product")
    fit_type = db.Column(String(40))
    intro_text = db.Column(Text)


class SizeGuideRow(TimestampMixin, db.Model):
    __tablename__ = "size_guide_rows"

    id = db.Column(Integer, primary_key=True)
    guide_id = db.Column(ForeignKey("size_guides.id", ondelete="CASCADE"), nullable=False)
    size_id = db.Column(ForeignKey("sizes.id"), nullable=False)
    product_measurements = db.Column(db.JSON)
    body_measurements = db.Column(db.JSON)


class GarmentSizeSetting(TimestampMixin, db.Model):
    __tablename__ = "garment_size_settings"

    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    model_asset_id = db.Column(ForeignKey("media_assets.id"))
    displayed_sizes = db.Column(db.JSON, nullable=False, default=list)
    measurements_mode = db.Column(String(40), nullable=False, default="body")
    image_zoom = db.Column(Numeric(8, 4), nullable=False, default=1)


# ---------------------------------------------------------------------------
# Shipping, policies, badges, trends and storefront content
# ---------------------------------------------------------------------------

class ShippingPolicy(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "shipping_policies"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    free_shipping_enabled = db.Column(Boolean, nullable=False, default=False)
    min_order_amount = db.Column(Numeric(24, 4))
    promo_text = db.Column(String(500))
    delivery_window = db.Column(String(120))


class ReturnPolicy(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "return_policies"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    return_window_days = db.Column(Integer, nullable=False, default=0)
    conditions = db.Column(Text)
    fee_rule = db.Column(String(120))
    refund_method = db.Column(String(80))


class WarrantyPolicy(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "warranty_policies"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    duration_days = db.Column(Integer, nullable=False, default=0)
    coverage = db.Column(Text)
    exclusions = db.Column(Text)
    claim_method = db.Column(String(120))


class ProductPolicyAssignment(TimestampMixin, db.Model):
    __tablename__ = "product_policy_assignments"

    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    shipping_policy_id = db.Column(ForeignKey("shipping_policies.id"))
    return_policy_id = db.Column(ForeignKey("return_policies.id"))
    warranty_policy_id = db.Column(ForeignKey("warranty_policies.id"))


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


class ProductBadge(TimestampMixin, db.Model):
    __tablename__ = "product_badges"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    badge_id = db.Column(ForeignKey("badges.id", ondelete="CASCADE"), nullable=False)
    starts_at = db.Column(db.DateTime(timezone=True))
    ends_at = db.Column(db.DateTime(timezone=True))
    position = db.Column(String(30))
    custom_text = db.Column(String(120))
    __table_args__ = (
        UniqueConstraint("product_id", "badge_id", name="uq_product_badge"),
    )


class PromotionalStrip(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "promotional_strips"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    text_prefix = db.Column(String(80))
    text_body = db.Column(String(300), nullable=False)
    background_color = db.Column(String(20))
    text_color = db.Column(String(20))


class Hashtag(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "hashtags"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False)
    slug = db.Column(String(160), nullable=False, unique=True)
    display_name = db.Column(String(160))
    sort_order = db.Column(Integer, nullable=False, default=0)


class ProductHashtag(TimestampMixin, db.Model):
    __tablename__ = "product_hashtags"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    hashtag_id = db.Column(ForeignKey("hashtags.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (
        UniqueConstraint("product_id", "hashtag_id", name="uq_product_hashtag"),
    )


class Campaign(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "campaigns"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(200), nullable=False)
    slug = db.Column(String(200), nullable=False, unique=True)
    badge_id = db.Column(ForeignKey("badges.id"))
    start_at = db.Column(db.DateTime(timezone=True))
    end_at = db.Column(db.DateTime(timezone=True))
    status = db.Column(String(40), nullable=False, default="draft")
    display_priority = db.Column(Integer, nullable=False, default=0)


class CampaignProduct(TimestampMixin, db.Model):
    __tablename__ = "campaign_products"

    id = db.Column(Integer, primary_key=True)
    campaign_id = db.Column(ForeignKey("campaigns.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)
    __table_args__ = (
        UniqueConstraint("campaign_id", "product_id", name="uq_campaign_product"),
    )


class CampaignCategory(TimestampMixin, db.Model):
    __tablename__ = "campaign_categories"

    id = db.Column(Integer, primary_key=True)
    campaign_id = db.Column(ForeignKey("campaigns.id", ondelete="CASCADE"), nullable=False)
    category_id = db.Column(ForeignKey("categories.id", ondelete="CASCADE"), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)
    __table_args__ = (
        UniqueConstraint("campaign_id", "category_id", name="uq_campaign_category"),
    )


class CampaignHashtag(TimestampMixin, db.Model):
    __tablename__ = "campaign_hashtags"

    id = db.Column(Integer, primary_key=True)
    campaign_id = db.Column(ForeignKey("campaigns.id", ondelete="CASCADE"), nullable=False)
    hashtag_id = db.Column(ForeignKey("hashtags.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (
        UniqueConstraint("campaign_id", "hashtag_id", name="uq_campaign_hashtag"),
    )


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


class NavigationAction(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "navigation_actions"

    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(80), nullable=False, unique=True)
    label = db.Column(String(120), nullable=False)
    icon = db.Column(String(80))
    route = db.Column(String(240))
    sort_order = db.Column(Integer, nullable=False, default=0)
    visibility_rule = db.Column(db.JSON, nullable=False, default=dict)


# ---------------------------------------------------------------------------
# Cart, orders, payment, shipping, support, returns and reviews
# ---------------------------------------------------------------------------

class ShippingMethod(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "shipping_methods"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False)
    code = db.Column(String(60), nullable=False, unique=True)
    delivery_days_min = db.Column(Integer)
    delivery_days_max = db.Column(Integer)
    supports_cod = db.Column(Boolean, nullable=False, default=False)


class ShippingRate(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "shipping_rates"

    id = db.Column(Integer, primary_key=True)
    method_id = db.Column(ForeignKey("shipping_methods.id", ondelete="CASCADE"), nullable=False)
    city_id = db.Column(ForeignKey("cities.id", ondelete="CASCADE"))
    region_id = db.Column(ForeignKey("regions.id", ondelete="CASCADE"))
    min_order = db.Column(Numeric(24, 4))
    max_order = db.Column(Numeric(24, 4))
    price = db.Column(Numeric(24, 4), nullable=False)
    free_over = db.Column(Numeric(24, 4))


class Cart(TimestampMixin, db.Model):
    __tablename__ = "carts"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, unique=True)
    currency_id = db.Column(ForeignKey("currencies.id"))
    pricing_group_id = db.Column(ForeignKey("pricing_groups.id"))
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now(), onupdate=db.func.now())


class CartItem(TimestampMixin, db.Model):
    __tablename__ = "cart_items"

    id = db.Column(Integer, primary_key=True)
    cart_id = db.Column(ForeignKey("carts.id", ondelete="CASCADE"), nullable=False)
    variant_id = db.Column(ForeignKey("product_variants.id", ondelete="RESTRICT"), nullable=False)
    qty = db.Column(Integer, nullable=False)
    unit_price_snapshot = db.Column(Numeric(24, 4))
    selected_options = db.Column(db.JSON, nullable=False, default=dict)


class Wishlist(TimestampMixin, db.Model):
    __tablename__ = "wishlists"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, unique=True)


class WishlistItem(TimestampMixin, db.Model):
    __tablename__ = "wishlist_items"

    id = db.Column(Integer, primary_key=True)
    wishlist_id = db.Column(ForeignKey("wishlists.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    added_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    __table_args__ = (
        UniqueConstraint("wishlist_id", "product_id", name="uq_wishlist_product"),
    )


class RecentlyViewed(TimestampMixin, db.Model):
    __tablename__ = "recently_viewed"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    viewed_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())


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
    markup_percent = db.Column(Numeric(12, 4), nullable=False, default=0)
    markup_fixed = db.Column(Numeric(24, 4), nullable=False, default=0)
    subtotal = db.Column(Numeric(24, 4), nullable=False)
    discount = db.Column(Numeric(24, 4), nullable=False, default=0)
    shipping = db.Column(Numeric(24, 4), nullable=False, default=0)
    total = db.Column(Numeric(24, 4), nullable=False)
    status = db.Column(String(40), nullable=False, default="created")
    payment_status = db.Column(String(40), nullable=False, default="unpaid")
    shipping_status = db.Column(String(40), nullable=False, default="pending")


class OrderItem(TimestampMixin, db.Model):
    __tablename__ = "order_items"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    product_id = db.Column(ForeignKey("products.id", ondelete="SET NULL"))
    variant_id = db.Column(ForeignKey("product_variants.id", ondelete="SET NULL"))
    sku_snapshot = db.Column(String(120), nullable=False)
    name_snapshot = db.Column(String(260), nullable=False)
    base_price_sar = db.Column(Numeric(24, 4), nullable=False)
    fx_rate = db.Column(Numeric(24, 12), nullable=False)
    markup_percent = db.Column(Numeric(12, 4), nullable=False, default=0)
    markup_fixed = db.Column(Numeric(24, 4), nullable=False, default=0)
    sale_price_display = db.Column(Numeric(24, 4), nullable=False)
    qty = db.Column(Integer, nullable=False)
    total = db.Column(Numeric(24, 4), nullable=False)


class OrderItemOption(TimestampMixin, db.Model):
    __tablename__ = "order_item_options"

    id = db.Column(Integer, primary_key=True)
    order_item_id = db.Column(ForeignKey("order_items.id", ondelete="CASCADE"), nullable=False)
    option_name = db.Column(String(120), nullable=False)
    option_value = db.Column(String(160), nullable=False)


class OrderStatusHistory(TimestampMixin, db.Model):
    __tablename__ = "order_status_history"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    from_status = db.Column(String(40))
    to_status = db.Column(String(40), nullable=False)
    actor_type = db.Column(String(30), nullable=False)
    actor_id = db.Column(Integer)
    note = db.Column(Text)


class Shipment(TimestampMixin, db.Model):
    __tablename__ = "shipments"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    shipping_method_id = db.Column(ForeignKey("shipping_methods.id"))
    tracking_no = db.Column(String(160))
    status = db.Column(String(40), nullable=False, default="pending")
    shipped_at = db.Column(db.DateTime(timezone=True))
    delivered_at = db.Column(db.DateTime(timezone=True))


class ShipmentEvent(TimestampMixin, db.Model):
    __tablename__ = "shipment_events"

    id = db.Column(Integer, primary_key=True)
    shipment_id = db.Column(ForeignKey("shipments.id", ondelete="CASCADE"), nullable=False)
    status = db.Column(String(40), nullable=False)
    location = db.Column(String(180))
    description = db.Column(Text)
    occurred_at = db.Column(db.DateTime(timezone=True), nullable=False)


class PaymentMethod(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "payment_methods"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False)
    code = db.Column(String(60), nullable=False, unique=True)
    provider = db.Column(String(80))
    supports_proof = db.Column(Boolean, nullable=False, default=False)


class PaymentTransaction(TimestampMixin, db.Model):
    __tablename__ = "payment_transactions"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    method_id = db.Column(ForeignKey("payment_methods.id"), nullable=False)
    amount = db.Column(Numeric(24, 4), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    provider_ref = db.Column(String(180))
    status = db.Column(String(40), nullable=False, default="pending")
    paid_at = db.Column(db.DateTime(timezone=True))


class PaymentProof(TimestampMixin, db.Model):
    __tablename__ = "payment_proofs"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    transaction_id = db.Column(ForeignKey("payment_transactions.id", ondelete="SET NULL"))
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="RESTRICT"), nullable=False)
    submitted_by = db.Column(ForeignKey("customers.id", ondelete="SET NULL"))
    status = db.Column(String(40), nullable=False, default="pending")
    reviewed_by = db.Column(ForeignKey("admins.id", ondelete="SET NULL"))
    reviewed_at = db.Column(db.DateTime(timezone=True))


class Conversation(TimestampMixin, db.Model):
    __tablename__ = "conversations"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    order_id = db.Column(ForeignKey("orders.id", ondelete="SET NULL"))
    type = db.Column(String(40), nullable=False)
    subject = db.Column(String(200))
    status = db.Column(String(30), nullable=False, default="open")
    last_message_at = db.Column(db.DateTime(timezone=True))


class ConversationParticipant(TimestampMixin, db.Model):
    __tablename__ = "conversation_participants"

    id = db.Column(Integer, primary_key=True)
    conversation_id = db.Column(ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False)
    actor_type = db.Column(String(30), nullable=False)
    actor_id = db.Column(Integer, nullable=False)
    joined_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    last_read_at = db.Column(db.DateTime(timezone=True))


class Message(TimestampMixin, db.Model):
    __tablename__ = "messages"

    id = db.Column(Integer, primary_key=True)
    conversation_id = db.Column(ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False)
    sender_type = db.Column(String(30), nullable=False)
    sender_id = db.Column(Integer, nullable=False)
    message_type = db.Column(String(30), nullable=False, default="text")
    body = db.Column(Text)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    read_at = db.Column(db.DateTime(timezone=True), nullable=True)
    __table_args__ = (
        Index("ix_message_conversation_created", "conversation_id", "created_at"),
    )


class MessageAttachment(TimestampMixin, db.Model):
    __tablename__ = "message_attachments"

    id = db.Column(Integer, primary_key=True)
    message_id = db.Column(ForeignKey("messages.id", ondelete="CASCADE"), nullable=False)
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="RESTRICT"), nullable=False)
    mime_type = db.Column(String(120), nullable=False)
    sort_order = db.Column(Integer, nullable=False, default=0)


class ReturnRequest(TimestampMixin, db.Model):
    __tablename__ = "return_requests"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    reason = db.Column(String(160), nullable=False)
    description = db.Column(Text)
    status = db.Column(String(40), nullable=False, default="requested")
    requested_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    approved_at = db.Column(db.DateTime(timezone=True))


class ReturnItem(TimestampMixin, db.Model):
    __tablename__ = "return_items"

    id = db.Column(Integer, primary_key=True)
    return_request_id = db.Column(ForeignKey("return_requests.id", ondelete="CASCADE"), nullable=False)
    order_item_id = db.Column(ForeignKey("order_items.id", ondelete="RESTRICT"), nullable=False)
    qty = db.Column(Integer, nullable=False)
    condition = db.Column(String(80))


class Refund(TimestampMixin, db.Model):
    __tablename__ = "refunds"

    id = db.Column(Integer, primary_key=True)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    return_request_id = db.Column(ForeignKey("return_requests.id", ondelete="SET NULL"))
    amount = db.Column(Numeric(24, 4), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    method = db.Column(String(80), nullable=False)
    status = db.Column(String(40), nullable=False, default="pending")
    processed_at = db.Column(db.DateTime(timezone=True))


class WarrantyClaim(TimestampMixin, db.Model):
    __tablename__ = "warranty_claims"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    order_id = db.Column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    order_item_id = db.Column(ForeignKey("order_items.id", ondelete="CASCADE"), nullable=False)
    issue = db.Column(String(200), nullable=False)
    description = db.Column(Text)
    status = db.Column(String(40), nullable=False, default="submitted")
    resolution = db.Column(Text)


class Review(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "reviews"

    id = db.Column(Integer, primary_key=True)
    product_id = db.Column(ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    order_item_id = db.Column(ForeignKey("order_items.id", ondelete="SET NULL"))
    rating = db.Column(Integer, nullable=False)
    title = db.Column(String(200))
    body = db.Column(Text)
    status = db.Column(String(30), nullable=False, default="pending")
    __table_args__ = (
        Index("ix_reviews_product_status", "product_id", "status"),
    )


class ReviewMedia(TimestampMixin, db.Model):
    __tablename__ = "review_media"

    id = db.Column(Integer, primary_key=True)
    review_id = db.Column(ForeignKey("reviews.id", ondelete="CASCADE"), nullable=False)
    asset_id = db.Column(ForeignKey("media_assets.id", ondelete="RESTRICT"), nullable=False)


# ---------------------------------------------------------------------------
# Promotions, wallet, notifications, administration and themes
# ---------------------------------------------------------------------------

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


class CouponRedemption(TimestampMixin, db.Model):
    __tablename__ = "coupon_redemptions"

    id = db.Column(Integer, primary_key=True)
    coupon_id = db.Column(ForeignKey("coupons.id", ondelete="CASCADE"), nullable=False)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    order_id = db.Column(ForeignKey("orders.id", ondelete="SET NULL"))
    discount_amount = db.Column(Numeric(24, 4), nullable=False)
    redeemed_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())


class GiftCampaign(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "gift_campaigns"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(160), nullable=False)
    gift_type = db.Column(String(40), nullable=False)
    value = db.Column(Numeric(24, 4))
    eligibility_rule = db.Column(db.JSON, nullable=False, default=dict)
    auto_issue_rule = db.Column(db.JSON, nullable=False, default=dict)
    expires_at = db.Column(db.DateTime(timezone=True))


class GiftIssuance(TimestampMixin, db.Model):
    __tablename__ = "gift_issuances"

    id = db.Column(Integer, primary_key=True)
    campaign_id = db.Column(ForeignKey("gift_campaigns.id", ondelete="CASCADE"), nullable=False)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    gift_code = db.Column(String(120), unique=True)
    amount = db.Column(Numeric(24, 4))
    currency_id = db.Column(ForeignKey("currencies.id"))
    issued_at = db.Column(db.DateTime(timezone=True), nullable=False, server_default=db.func.now())
    expires_at = db.Column(db.DateTime(timezone=True))
    redeemed_at = db.Column(db.DateTime(timezone=True))


class Wallet(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "wallets"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    currency_id = db.Column(ForeignKey("currencies.id"), nullable=False)
    balance = db.Column(Numeric(24, 4), nullable=False, default=0)
    status = db.Column(String(30), nullable=False, default="active")
    __table_args__ = (
        UniqueConstraint("customer_id", "currency_id", name="uq_wallet_customer_currency"),
    )


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


class NotificationTemplate(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "notification_templates"

    id = db.Column(Integer, primary_key=True)
    event_code = db.Column(String(80), nullable=False, unique=True)
    title_template = db.Column(String(240), nullable=False)
    body_template = db.Column(Text, nullable=False)
    channels = db.Column(db.JSON, nullable=False, default=list)


class Notification(TimestampMixin, db.Model):
    __tablename__ = "notifications"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    type = db.Column(String(60), nullable=False)
    title = db.Column(String(240), nullable=False)
    body = db.Column(Text, nullable=False)
    data = db.Column(db.JSON, nullable=False, default=dict)
    status = db.Column(String(30), nullable=False, default="queued")
    sent_at = db.Column(db.DateTime(timezone=True))


class CustomerNotification(TimestampMixin, db.Model):
    __tablename__ = "customer_notifications"

    id = db.Column(Integer, primary_key=True)
    customer_id = db.Column(ForeignKey("customers.id", ondelete="CASCADE"), nullable=False)
    notification_id = db.Column(ForeignKey("notifications.id", ondelete="CASCADE"), nullable=False)
    read_at = db.Column(db.DateTime(timezone=True))
    __table_args__ = (
        UniqueConstraint("customer_id", "notification_id", name="uq_customer_notification"),
    )


class Admin(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "admins"

    id = db.Column(Integer, primary_key=True)
    username = db.Column(String(120), nullable=False, unique=True)
    phone = db.Column(String(32))
    email = db.Column(String(255))
    password_hash = db.Column(String(255))
    status = db.Column(String(30), nullable=False, default="active")
    last_login = db.Column(db.DateTime(timezone=True))


class Role(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "roles"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False, unique=True)
    code = db.Column(String(80), nullable=False, unique=True)


class Permission(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "permissions"

    id = db.Column(Integer, primary_key=True)
    code = db.Column(String(120), nullable=False, unique=True)
    name = db.Column(String(160), nullable=False)


class RolePermission(TimestampMixin, db.Model):
    __tablename__ = "role_permissions"

    id = db.Column(Integer, primary_key=True)
    role_id = db.Column(ForeignKey("roles.id", ondelete="CASCADE"), nullable=False)
    permission_id = db.Column(ForeignKey("permissions.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (
        UniqueConstraint("role_id", "permission_id", name="uq_role_permission"),
    )


class AdminRole(TimestampMixin, db.Model):
    __tablename__ = "admin_roles"

    id = db.Column(Integer, primary_key=True)
    admin_id = db.Column(ForeignKey("admins.id", ondelete="CASCADE"), nullable=False)
    role_id = db.Column(ForeignKey("roles.id", ondelete="CASCADE"), nullable=False)
    __table_args__ = (
        UniqueConstraint("admin_id", "role_id", name="uq_admin_role"),
    )


class AuditLog(TimestampMixin, db.Model):
    __tablename__ = "audit_logs"

    id = db.Column(Integer, primary_key=True)
    admin_id = db.Column(ForeignKey("admins.id", ondelete="SET NULL"))
    action = db.Column(String(120), nullable=False)
    entity_type = db.Column(String(120), nullable=False)
    entity_id = db.Column(Integer)
    before_json = db.Column(db.JSON)
    after_json = db.Column(db.JSON)
    request_id = db.Column(String(120))
    ip_address = db.Column(String(64))


class Theme(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "themes"

    id = db.Column(Integer, primary_key=True)
    name = db.Column(String(120), nullable=False)
    code = db.Column(String(80), nullable=False, unique=True)


class ThemeToken(TimestampMixin, db.Model):
    __tablename__ = "theme_tokens"

    id = db.Column(Integer, primary_key=True)
    theme_id = db.Column(ForeignKey("themes.id", ondelete="CASCADE"), nullable=False)
    token_name = db.Column(String(120), nullable=False)
    value = db.Column(String(255), nullable=False)
    value_type = db.Column(String(30), nullable=False, default="text")
    __table_args__ = (
        UniqueConstraint("theme_id", "token_name", name="uq_theme_token"),
    )


class ComponentThemeSetting(TimestampMixin, db.Model):
    __tablename__ = "component_theme_settings"

    id = db.Column(Integer, primary_key=True)
    theme_id = db.Column(ForeignKey("themes.id", ondelete="CASCADE"), nullable=False)
    component = db.Column(String(80), nullable=False)
    property = db.Column(String(80), nullable=False)
    value = db.Column(String(255), nullable=False)
    __table_args__ = (
        UniqueConstraint("theme_id", "component", "property", name="uq_theme_component_property"),
    )


class FeatureFlag(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "feature_flags"

    id = db.Column(Integer, primary_key=True)
    key = db.Column(String(120), nullable=False, unique=True)
    enabled = db.Column(Boolean, nullable=False, default=False)
    conditions = db.Column(db.JSON, nullable=False, default=dict)


class AppSetting(TimestampMixin, db.Model):
    __tablename__ = "app_settings"

    id = db.Column(Integer, primary_key=True)
    group_code = db.Column(String(80), nullable=False)
    key = db.Column(String(120), nullable=False)
    value = db.Column(Text)
    value_type = db.Column(String(30), nullable=False, default="text")
    __table_args__ = (
        UniqueConstraint("group_code", "key", name="uq_app_setting_group_key"),
    )


class SearchSynonym(TimestampMixin, ActiveMixin, db.Model):
    __tablename__ = "search_synonyms"

    id = db.Column(Integer, primary_key=True)
    term = db.Column(String(160), nullable=False)
    synonym = db.Column(String(160), nullable=False)
    locale = db.Column(String(16), nullable=False, default="ar")
    __table_args__ = (
        UniqueConstraint("term", "synonym", "locale", name="uq_search_synonym"),
    )
