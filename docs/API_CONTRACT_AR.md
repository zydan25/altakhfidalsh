# عقد API الإصدار الأول

Base URL:

    /api/v1/

## Catalog

- GET /catalog/categories
- GET /catalog/products
- POST /catalog/products/drafts
- GET /catalog/products/{id}
- PATCH /catalog/products/{id}
- POST /catalog/products/{id}/categories
- POST /catalog/products/{id}/options
- POST /catalog/products/{id}/variants
- POST /catalog/products/{id}/inventory
- POST /catalog/products/{id}/media multipart
- GET /catalog/products/{id}/wizard
- POST /catalog/products/{id}/publish
- GET /catalog/categories/{id}/filters
- POST /catalog/categories/{id}/filters
- POST /catalog/filters/{id}/values
- POST /catalog/products/{id}/filter-values
- GET /catalog/reference/options
- GET /catalog/reference/policies
- GET /catalog/inventory-locations
- POST /catalog/inventory-locations
- POST /catalog/size-guides
- GET /catalog/size-guides
- POST /catalog/products/{id}/garment-size-settings
- POST /catalog/policies/shipping
- POST /catalog/policies/return
- POST /catalog/policies/warranty
- POST /catalog/badges

## Pricing

- GET /pricing/context
- POST /pricing/quote
- GET /pricing/currencies
- POST /pricing/currencies
- GET /pricing/groups
- POST /pricing/groups
- POST /pricing/exchange-rates
- POST /pricing/location-assignments
- POST /pricing/customer-assignments

السعر الأساسي SAR. الحساب المركزي:
base × FX → نسبة الزيادة → الزيادة الثابتة → rounding.

## Storefront

- GET /storefront/pages
- POST /storefront/pages
- GET /storefront/pages/{code}
- POST /storefront/pages/{id}/sections
- POST /storefront/sections/{id}/items
- GET /storefront/banners
- POST /storefront/banners
- POST /storefront/banners/{id}/targets
- GET /storefront/navigation-actions
- POST /storefront/navigation-actions
- GET /storefront/category-navigation
- POST /storefront/category-navigation

## Customer/Auth

- POST /customer/auth/request-otp
- POST /customer/auth/verify-otp
- POST /customer/auth/refresh
- POST /customer/auth/logout
- GET /customer/me
- PATCH /customer/me
- GET /customer/me/addresses
- POST /customer/me/addresses
- GET /customer/me/wishlist
- POST /customer/me/wishlist/{product_id}
- POST /customer/me/views/{product_id}

المسارات المحمية تستخدم:
    Authorization: Bearer <access_token>

## Commerce

- GET /commerce/cart/{customer_id}
- POST /commerce/cart/items
- DELETE /commerce/cart/{customer_id}/items/{item_id}
- DELETE /commerce/cart/{customer_id}
- GET /commerce/orders
- GET /commerce/orders/{id}
- POST /commerce/orders
- POST /commerce/orders/{id}/status
- GET /commerce/payment-methods
- POST /commerce/payment-methods
- POST /commerce/payments
- POST /commerce/payments/proofs
- GET /commerce/shipping-methods
- POST /commerce/shipping-methods
- POST /commerce/shipments
- POST /commerce/shipments/{id}/events

## Support

- POST /support/conversations
- GET /support/conversations
- GET /support/conversations/{id}/messages
- POST /support/conversations/{id}/messages
- POST /support/conversations/{id}/attachments multipart

## Promotions

- GET /promotions/campaigns
- GET /promotions/coupons
- POST /promotions/coupons/redeem
- GET /promotions/gifts
- POST /promotions/gifts/issue
- POST /promotions/wallet/adjust
- POST /promotions/campaigns/{id}/products/{product_id}
- POST /promotions/campaigns/{id}/categories/{category_id}
- POST /promotions/campaigns/{id}/hashtags/{hashtag_id}

## Geo

- GET/POST /geo/countries
- GET/POST /geo/regions
- GET/POST /geo/cities

## After Sales

- POST /after_sales/returns
- POST /after_sales/warranty/claims
- GET /after_sales/warranty/claims/{id}
- POST /after_sales/reviews
- GET /after_sales/reviews/product/{product_id}
- POST /after_sales/reviews/{id}/media multipart
- POST /after_sales/refunds

## Notifications

- GET /notifications/notifications/{customer_id}
- POST /notifications/notifications/{customer_id}/{notification_id}/read

## Reports

- GET /reports/sales
- GET /reports/orders/status
- GET /reports/customers
- GET /reports/inventory
- GET /reports/catalog

## Search

- GET /search/products?q=&category_id=&filter_value_id=
- GET /search/synonyms
- POST /search/synonyms

## System

- GET /system/health
- GET/POST /system/permissions
- GET/POST /system/roles
- POST /system/admins/{admin_id}/roles/{role_id}
- GET /system/admins
- GET /system/audit-logs
- GET/PATCH /system/features
- GET/POST /system/theme/{code}/tokens

## قواعد API

- الأخطاء ترجع JSON بالشكل error/detail.
- القيم المالية تُرسل كسلاسل Decimal عند الحاجة لمنع خسارة الدقة.
- التواريخ ISO 8601.
- الطلبات تحفظ snapshots تاريخية.
- الملفات multipart/form-data.
- لا يعتمد العميل على أسماء الجداول؛ يعتمد على العقد.

## ملاحظة أمنية

الـAPI الحالية تحتوي مسارات public ومسارات إدارية. لا تعتبر مسارات الإدارة الإنتاجية مكتملة أمنيًا حتى تُطبّق طبقة admin API permission على كل endpoint الإداري، وليس على صفحات HTML فقط.
