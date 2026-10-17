import 'package:dartz/dartz.dart';
import 'package:t_store/core/network/flask_api_client.dart';
import 'package:t_store/features/shop/data/models/product_model.dart';
import 'package:t_store/features/shop/domain/entities/product_entity.dart';
import 'package:t_store/features/shop/domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({required FlaskApiClient apiClient})
      : _apiClient = apiClient;

  final FlaskApiClient _apiClient;

  @override
  Future<Either<String, List<ProductEntity>>> getProducts({
    int page = 0,
    int limit = 20,
    String? categoryId,
    String? brandId,
    bool? isFeatured,
    String? sortBy,
    bool ascending = true,
  }) async {
    try {
      final requestedLimit = ((page + 1) * limit).clamp(1, 100).toInt();
      final query = <String, dynamic>{
        'limit': requestedLimit,
        'sort': _sortKey(sortBy, ascending),
      };
      final parsedCategoryId = int.tryParse(categoryId ?? '');
      if (parsedCategoryId != null && parsedCategoryId > 0) {
        query['category_id'] = parsedCategoryId;
      }
      final parsedBrandId = int.tryParse(brandId ?? '');
      if (parsedBrandId != null && parsedBrandId > 0) {
        // The Flask feed exposes standard brand filter values as negative IDs.
        query['filter_value_ids'] = -3000000 - parsedBrandId;
      }

      // The current customer feed does not expose a generic is_featured flag.
      // Don't invent one; use the requested server-side ordering instead.
      final products = await _feed(query);
      final start = page * limit;
      if (start >= products.length) return const Right(<ProductEntity>[]);
      final end = (start + limit).clamp(0, products.length).toInt();
      return Right(products.sublist(start, end));
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, ProductEntity>> getProductById(String id) async {
    try {
      final productId = int.tryParse(id);
      if (productId == null || productId <= 0) {
        return const Left('معرّف المنتج غير صحيح.');
      }
      final response = await _apiClient.get('catalog/products/$productId');
      final root = _map(response);
      final item = _map(root['item'] ?? root);
      final nestedProduct = item['product'];
      final json = nestedProduct is Map
          ? <String, dynamic>{
              ...Map<String, dynamic>.from(item),
              ...Map<String, dynamic>.from(nestedProduct),
            }
          : item;
      // Prefer the same customer-priced feed when it contains this product;
      // use the detailed snapshot if the product is outside the current feed.
      try {
        final feed = await _feed({'limit': 100, 'sort': 'recommended'});
        final matching = feed.where((product) => product.id == id).toList();
        if (matching.isNotEmpty) return Right(matching.first);
      } catch (_) {
        // A valid detail snapshot is still useful when feed is unavailable.
      }
      return Right(ProductModel.fromFlaskJson(json));
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<ProductEntity>>> searchProducts(String query) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const Right(<ProductEntity>[]);
      return Right(await _feed({
        'q': trimmed,
        'limit': 80,
        'sort': 'recommended',
      }));
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<ProductEntity>>> getProductsByCategory(
    String categoryId,
  ) async {
    final id = int.tryParse(categoryId);
    if (id == null || id <= 0) {
      return const Left('معرّف التصنيف غير صحيح.');
    }
    try {
      return Right(await _feed({
        'category_id': id,
        'limit': 80,
        'sort': 'recommended',
      }));
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<ProductEntity>>> getProductsByBrand(
    String brandId,
  ) async {
    final id = int.tryParse(brandId);
    if (id == null || id <= 0) {
      return const Left('معرّف العلامة التجارية غير صحيح.');
    }
    try {
      return Right(await _feed({
        'filter_value_ids': -3000000 - id,
        'limit': 80,
        'sort': 'recommended',
      }));
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<ProductEntity>>> getFeaturedProducts() async {
    // No active public route exposes the legacy is_featured field; use the
    // real customer feed rather than a locally fabricated featured collection.
    try {
      return Right(await _feed({'limit': 20, 'sort': 'highest_rated'}));
    } catch (error) {
      return Left(_message(error));
    }
  }

  Future<List<ProductEntity>> _feed(Map<String, dynamic> query) async {
    final response = await _apiClient.get(
      'catalog/products/feed',
      queryParameters: query,
    );
    final root = _map(response);
    final rows = root['items'];
    if (rows is! List) {
      throw const FormatException('لم تُرجع واجهة المنتجات قائمة صحيحة.');
    }
    return rows
        .whereType<Map>()
        .map((row) => ProductModel.fromFlaskJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  static String _sortKey(String? sortBy, bool ascending) {
    switch ((sortBy ?? '').toLowerCase()) {
      case 'rating':
      case 'review_count':
        return ascending ? 'recommended' : 'highest_rated';
      case 'price':
        return ascending ? 'price_asc' : 'price_desc';
      case 'created_at':
      case 'date':
      case 'newest':
      case 'id':
        return 'newest';
      case 'popular':
      case 'sold_qty':
        return 'popular';
      default:
        return 'recommended';
    }
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) {
      throw const FormatException('صيغة بيانات المنتجات غير صحيحة.');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _message(Object error) {
    if (error is FlaskApiException) return error.message;
    return error.toString();
  }
}
