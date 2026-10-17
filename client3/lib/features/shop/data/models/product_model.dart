import 'package:t_store/core/network/api_config.dart';
import 'package:t_store/features/shop/domain/entities/product_entity.dart';

class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.name,
    super.description,
    required super.price,
    super.salePrice,
    required super.categoryId,
    super.brandId,
    required super.stock,
    required super.images,
    super.thumbnail,
    super.rating,
    super.reviewsCount,
    super.isFeatured,
    super.isActive,
    super.attributes,
    super.createdAt,
    super.updatedAt,
    super.categoryName,
    super.brandName,
    super.currencyCode,
    super.currencySymbol,
  });

  /// Legacy shape parser kept tolerant while old features are migrated.
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final images = _imageUrls(json['images']);
    final thumbnail = _resolveImage(
      json['thumbnail'] ?? json['image_url'] ??
          (images.isNotEmpty ? images.first : null),
    );
    final rawPrice = _number(json['price']);
    final rawSale = json['sale_price'] ?? json['salePrice'];
    final category = json['category_id'] ??
        json['categoryId'] ??
        _firstId(json['category_ids']) ??
        _firstId(json['root_category_ids']) ??
        '0';
    final brand = json['brand'];
    final brandMap = brand is Map ? Map<String, dynamic>.from(brand) : null;

    return ProductModel(
      id: _string(json['id']),
      name: _string(json['name']).isEmpty ? 'منتج' : _string(json['name']),
      description: _nullableString(json['description']),
      price: rawPrice,
      salePrice: rawSale == null ? null : _number(rawSale),
      categoryId: _string(category),
      brandId: _nullableString(json['brand_id'] ?? brandMap?['id']),
      stock: _integer(json['stock'] ?? json['available_qty']),
      images: images.isEmpty && thumbnail != null ? [thumbnail] : images,
      thumbnail: thumbnail,
      rating: _number(json['rating']),
      reviewsCount: _integer(json['reviews_count'] ?? json['review_count']),
      isFeatured: json['is_featured'] == true || json['is_trend'] == true,
      isActive: json['is_active'] as bool? ??
          (_string(json['status']).isEmpty ||
              _string(json['status']) == 'published'),
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : null,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      categoryName: _nullableString(
        json['category_name'] ??
            (json['categories'] is Map ? json['categories']['name'] : null),
      ),
      brandName: _nullableString(
        json['brand_name'] ?? brandMap?['name'] ??
            (json['brands'] is Map ? json['brands']['name'] : null),
      ),
      currencyCode: _nullableString(json['currency_code']),
      currencySymbol: _nullableString(json['currency_symbol']),
    );
  }

  /// Adapter for the public Flask storefront feed, which supplies the final
  /// customer price and compare-at price using strings to preserve Decimal data.
  factory ProductModel.fromFlaskJson(Map<String, dynamic> json) {
    final finalPrice = _number(json['price'] ?? json['base_price_sar']);
    final compareAt = json['compare_at_price'] == null
        ? null
        : _number(json['compare_at_price']);
    final hasValidCompareAt = compareAt != null && compareAt > finalPrice;
    final regularPrice = hasValidCompareAt ? compareAt! : finalPrice;
    final images = _imageUrls(json['images']);
    final imageUrl = _resolveImage(
      json['image_url'] ?? json['thumbnail'] ??
          (images.isNotEmpty ? images.first : null),
    );
    final resolvedImages = images
        .map(_resolveImage)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final allImages = resolvedImages.isNotEmpty
        ? resolvedImages
        : (imageUrl == null ? <String>[] : <String>[imageUrl]);
    final rawBrand = json['brand'];
    final brand = rawBrand is Map
        ? Map<String, dynamic>.from(rawBrand)
        : null;
    final categories = json['category_ids'];
    final rootCategories = json['root_category_ids'];
    final categoryId = _firstId(categories) ??
        _firstId(rootCategories) ??
        json['category_id'] ??
        '0';
    final currencyCode = _nullableString(json['currency_code']);

    return ProductModel(
      id: _string(json['id']),
      name: _string(json['name']).isEmpty ? 'منتج' : _string(json['name']),
      description: _nullableString(json['description']),
      price: regularPrice,
      salePrice: hasValidCompareAt ? finalPrice : null,
      categoryId: _string(categoryId),
      brandId: _nullableString(json['brand_id'] ?? brand?['id']),
      stock: _integer(json['available_qty'] ?? json['stock']),
      images: allImages,
      thumbnail: imageUrl ?? (allImages.isNotEmpty ? allImages.first : null),
      rating: _number(json['rating']),
      reviewsCount: _integer(json['review_count'] ?? json['reviews_count']),
      isFeatured: json['is_trend'] == true,
      isActive: _string(json['status']).isEmpty ||
          _string(json['status']) == 'published',
      attributes: <String, dynamic>{
        if (json['card_settings'] is Map) 'card_settings': json['card_settings'],
        if (json['badges'] is List) 'badges': json['badges'],
        if (json['colors'] is List) 'colors': json['colors'],
        if (json['variant_id'] != null) 'variant_id': json['variant_id'],
        if (json['in_stock'] != null) 'in_stock': json['in_stock'],
      },
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      categoryName: _nullableString(json['category_name']),
      brandName: _nullableString(brand?['name'] ?? json['brand_name']),
      currencyCode: currencyCode,
      currencySymbol: _nullableString(
        json['currency_symbol'] ?? json['currency_code'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'sale_price': salePrice,
      'category_id': categoryId,
      'brand_id': brandId,
      'stock': stock,
      'images': images,
      'thumbnail': thumbnail,
      'rating': rating,
      'reviews_count': reviewsCount,
      'is_featured': isFeatured,
      'is_active': isActive,
      'attributes': attributes,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
    };
  }

  factory ProductModel.fromEntity(ProductEntity entity) {
    return ProductModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      price: entity.price,
      salePrice: entity.salePrice,
      categoryId: entity.categoryId,
      brandId: entity.brandId,
      stock: entity.stock,
      images: entity.images,
      thumbnail: entity.thumbnail,
      rating: entity.rating,
      reviewsCount: entity.reviewsCount,
      isFeatured: entity.isFeatured,
      isActive: entity.isActive,
      attributes: entity.attributes,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      categoryName: entity.categoryName,
      brandName: entity.brandName,
      currencyCode: entity.currencyCode,
      currencySymbol: entity.currencySymbol,
    );
  }

  static List<String> _imageUrls(dynamic raw) {
    if (raw is! List) return <String>[];
    return raw.map((item) {
      if (item is Map) return _string(item['url'] ?? item['image_url']);
      return _string(item);
    }).where((value) => value.isNotEmpty).toList(growable: false);
  }

  static String? _resolveImage(dynamic raw) {
    final value = _nullableString(raw);
    if (value == null) return null;
    try {
      return ApiConfig.resolveMediaUrl(value);
    } on FormatException {
      return value;
    }
  }

  static dynamic _firstId(dynamic values) {
    if (values is List && values.isNotEmpty) return values.first;
    return null;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static String? _nullableString(dynamic value) {
    final result = _string(value);
    return result.isEmpty ? null : result;
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
