/// Canonical customer-facing Flask API paths.
///
/// Keep paths relative to ApiConfig.baseUrl, which already ends in /api/v1/.
/// These are sourced from the registered Flask blueprints, not from older
/// planning documents or unregistered legacy route files.
abstract final class FlaskEndpoints {
  // Storefront and catalog.
  static const storefrontHome = 'storefront/home';
  static const storefrontPages = 'storefront/pages';
  static String storefrontPage(String code) =>
      'storefront/pages/${Uri.encodeComponent(code)}';
  static const banners = 'storefront/banners';
  static const categories = 'catalog/categories';
  static const sideCategories = 'catalog/side-categories';
  static const sideCircleGroups = 'catalog/side-circle-groups';
  static const sideCircleDisplay = 'catalog/side-circle-display';
  static const productFeed = 'catalog/products/feed';
  static String productDetail(int productId) =>
      'catalog/products/$productId';
  static String sideCircleProducts(int circleId) =>
      'catalog/side-category-circles/$circleId/products';

  // Search endpoint returns a smaller record than the storefront feed.
  static const searchProducts = 'search/products';

  // Customer pricing. Prices shown to customers should come from productFeed
  // or productDetail; do not re-calculate them in the Flutter client.
  static const pricingContext = 'pricing/context';
  static const currencies = 'pricing/currencies';

  // OTP/session and profile. These routes require the token after sign-in,
  // except requestOtp and verifyOtp.
  static const requestOtp = 'customer/auth/request-otp';
  static const verifyOtp = 'customer/auth/verify-otp';
  static const refreshSession = 'customer/auth/refresh';
  static const logout = 'customer/auth/logout';
  static const customerMe = 'customer/me';
  static const customerAddresses = 'customer/me/addresses';
  static const customerWishlist = 'customer/me/wishlist';
  static String customerWishlistProduct(int productId) =>
      'customer/me/wishlist/$productId';

  // Customer-scoped commerce avoids passing a customer ID supplied by UI.
  static const customerCart = 'commerce/me/cart';
  static const customerCartItems = 'commerce/me/cart/items';
  static String customerCartItem(int itemId) =>
      'commerce/me/cart/items/$itemId';
  static const customerOrders = 'commerce/me/orders';
  static String customerOrder(int orderId) =>
      'commerce/me/orders/$orderId';
  static String customerOrderDetail(int orderId) =>
      'commerce/me/orders/$orderId/detail';
  static const shippingMethods = 'commerce/shipping-methods';
  static const paymentMethods = 'commerce/payment-methods';

  // Reviews are public to read; creating a review requires a customer session.
  static String productReviews(int productId) =>
      'after_sales/reviews/product/$productId';
}
