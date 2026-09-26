# قاموس نطاقات قاعدة البيانات

هذا الملف يوضح نطاقات البيانات بدل النظر إلى قاعدة البيانات كجدول products ضخم.

| النطاق | أمثلة |
|---|---|
| geo | countries, regions, cities |
| pricing | currencies, exchange_rates, pricing_groups, pricing_group_rules, pricing_group_cities, customer_pricing_assignments |
| customer_auth | customers, customer_addresses, customer_devices, otp_requests, auth_sessions, customer_preferences |
| media | media_assets |
| catalog | ... product_filter_values | categories, brands, colors, sizes, products, product_categories, product_media, product_videos, product_options, product_option_values, product_variants, variant_option_values, variant_media |
| inventory | inventory_locations, stock_inventory |
| product_policies | shipping_policies, return_policies, warranty_policies, product_policy_assignments |
| merchandising | badges, product_badges, promotional_strips, hashtags, product_hashtags, campaigns, campaign_products, campaign_categories, campaign_hashtags |
| storefront | storefront_pages, storefront_sections, storefront_section_items, banners, banner_targets, navigation_actions |
| commerce | shipping_methods, shipping_rates, carts, cart_items, wishlists, wishlist_items, recently_viewed |
| orders | orders, order_items, order_item_options, order_status_history, shipments, shipment_events |
| payments | payment_methods, payment_transactions, payment_proofs |
| support | conversations, conversation_participants, messages, message_attachments |
| returns_warranty | return_requests, return_items, refunds, warranty_claims |
| reviews | reviews, review_media |
| promotions | coupons, coupon_redemptions, gift_campaigns, gift_issuances |
| wallet | wallets, wallet_transactions |
| notifications | notification_templates, notifications, customer_notifications |
| admin | admins, roles, permissions, role_permissions, admin_roles, audit_logs |
| appearance | themes, theme_tokens, component_theme_settings, feature_flags, app_settings |
| search | search_synonyms |

## علاقات مهمة

- categories.parent_id → categories.id
- products ↔ categories عبر product_categories
- product_variants → products
- stock_inventory → variant + inventory_location
- pricing_group_cities يطبق على city أو region
- customer_pricing_assignments يملك override اختياري
- order_items يحتفظ بنسخة اسم المنتج وSKU والسعر والسعر المحول والزيادة
- banner_targets تربط البانر بكيان الهدف
- storefront_section_items تربط section بكيانات المحتوى مع ترتيب
- conversations يمكن ربطها بطلب
- message_attachments تشير إلى media_assets
- wallet_transactions هي دفتر الحركة
- audit_logs يحتفظ before/after للعمليات الحساسة

العلاقات المرنة مثل storefront_section_items وbanner_targets مقصودة، ويجب أن تمنع طبقة service أي target غير صالح قبل الحفظ أو النشر.

## الفئات الجانبية

- `side_categories.root_category_id` يشير إلى Category من المستوى الأعلى فقط.
- `side_category_circles` منفصلة عن `categories` لتوفير Merchandising مستقل للواجهة.
- `product_side_category_circles` تربط المنتجات بالدوائر الجانبية وتسمح بتعدد الروابط.
- حذف/أرشفة القسم الجانبي يؤرشف دوائره، بينما أرشفة الدائرة لا تحذف المنتج.
