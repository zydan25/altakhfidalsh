from app import create_app
from app.extensions import db


def test_schema_has_full_domain_table_set():
    create_app()
    names = set(db.metadata.tables)
    assert len(names) >= 100
    for required in {
        'countries', 'regions', 'cities', 'currencies', 'exchange_rates',
        'pricing_groups', 'pricing_group_rules', 'pricing_group_cities',
        'customer_pricing_assignments', 'customers', 'customer_addresses',
        'products', 'product_categories', 'product_variants', 'stock_inventory',
        'banners', 'banner_targets', 'campaigns', 'hashtags',
        'carts', 'orders', 'order_items', 'payment_transactions',
        'conversations', 'messages', 'message_attachments',
        'return_requests', 'refunds', 'warranty_claims', 'reviews',
        'coupons', 'gift_campaigns', 'wallets', 'wallet_transactions',
        'admins', 'roles', 'permissions', 'role_permissions', 'audit_logs',
        'themes', 'theme_tokens', 'feature_flags', 'app_settings',
    }:
        assert required in names