import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:t_store/core/network/flask_api_client.dart';
import 'package:t_store/core/utils/exceptions/exceptions.dart';
import 'package:t_store/features/shop/data/models/product_model.dart';

abstract class ShopRemoteDataSource {
  Future<Either<TExceptions, List<ProductModel>>> getProductsList({
    int page = 0,
    int limit = 10,
  });

  Future<Either<TExceptions, ProductModel>> getProductById({
    required int productId,
  });

  Future<Either<TExceptions, List<ProductModel>>> getProductsByCategory({
    required String categoryName,
  });

  Future<Either<TExceptions, List<ProductModel>>> getProductsBySearch({
    String? search = '',
  });

  Future<Either<TExceptions, List<ProductModel>>> getSortedProducts({
    required String sortBy,
    required String sortType,
  });
}

/// Compatibility adapter for the older ShopCubit. It now reads the same Flask
/// customer feed as the newer Clean Architecture repository, never DummyJSON.
class ShopRemoteDataSourceImpl implements ShopRemoteDataSource {
  ShopRemoteDataSourceImpl({required Dio dio, FlaskApiClient? api})
      : _api = api ?? FlaskApiClient(dio: dio);

  final FlaskApiClient _api;

  @override
  Future<Either<TExceptions, ProductModel>> getProductById({
    required int productId,
  }) async {
    try {
      final response = await _api.get('catalog/products/$productId');
      final root = _toMap(response);
      final item = _toMap(root['item'] ?? root);
      final nested = item['product'];
      final json = nested is Map
          ? <String, dynamic>{
              ...item,
              ...Map<String, dynamic>.from(nested),
            }
          : item;
      try {
        final feed = await _fetchFeed({'limit': 100, 'sort': 'recommended'});
        final matching = feed.where((product) => product.id == '$productId');
        if (matching.isNotEmpty) return Right(matching.first);
      } catch (_) {
        // Fall back to the detailed snapshot if the feed cannot be loaded.
      }
      return Right(ProductModel.fromFlaskJson(json));
    } catch (error) {
      return Left(_asException(error));
    }
  }

  @override
  Future<Either<TExceptions, List<ProductModel>>> getProductsList({
    int page = 0,
    int limit = 10,
  }) async {
    try {
      final safeLimit = limit.clamp(1, 100).toInt();
      final requestedLimit = ((page + 1) * safeLimit).clamp(1, 100).toInt();
      final products = await _fetchFeed({
        'limit': requestedLimit,
        'sort': 'recommended',
      });
      final start = page * safeLimit;
      if (start >= products.length) return const Right(<ProductModel>[]);
      final end = (start + safeLimit).clamp(0, products.length).toInt();
      return Right(products.sublist(start, end));
    } catch (error) {
      return Left(_asException(error));
    }
  }

  @override
  Future<Either<TExceptions, List<ProductModel>>> getProductsByCategory({
    required String categoryName,
  }) async {
    try {
      final response = await _api.get('catalog/categories');
      final root = _toMap(response);
      final rows = root['items'];
      if (rows is! List) {
        throw const FormatException('لم تُرجع واجهة التصنيفات قائمة صحيحة.');
      }
      final needle = categoryName.trim().toLowerCase();
      Map<String, dynamic>? match;
      for (final raw in rows.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final name = row['name']?.toString().trim().toLowerCase() ?? '';
        final slug = row['slug']?.toString().trim().toLowerCase() ?? '';
        if (name == needle || slug == needle) {
          match = row;
          break;
        }
      }
      if (match == null) return const Right(<ProductModel>[]);
      final categoryId = int.tryParse(match['id']?.toString() ?? '');
      if (categoryId == null || categoryId <= 0) {
        return const Right(<ProductModel>[]);
      }
      return Right(await _fetchFeed({
        'category_id': categoryId,
        'limit': 80,
        'sort': 'recommended',
      }));
    } catch (error) {
      return Left(_asException(error));
    }
  }

  @override
  Future<Either<TExceptions, List<ProductModel>>> getProductsBySearch({
    String? search,
  }) async {
    final query = search?.trim() ?? '';
    if (query.isEmpty) return const Right(<ProductModel>[]);
    try {
      return Right(await _fetchFeed({
        'q': query,
        'limit': 80,
        'sort': 'recommended',
      }));
    } catch (error) {
      return Left(_asException(error));
    }
  }

  @override
  Future<Either<TExceptions, List<ProductModel>>> getSortedProducts({
    required String sortBy,
    required String sortType,
  }) async {
    try {
      return Right(await _fetchFeed({
        'limit': 80,
        'sort': _sortKey(sortBy, sortType),
      }));
    } catch (error) {
      return Left(_asException(error));
    }
  }

  Future<List<ProductModel>> _fetchFeed(Map<String, dynamic> query) async {
    final response = await _api.get(
      'catalog/products/feed',
      queryParameters: query,
    );
    final root = _toMap(response);
    final items = root['items'];
    if (items is! List) {
      throw const FormatException('لم تُرجع واجهة المنتجات قائمة صحيحة.');
    }
    return items
        .whereType<Map>()
        .map((row) => ProductModel.fromFlaskJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  static String _sortKey(String sortBy, String sortType) {
    final ascending = sortType.toLowerCase() == 'asc' ||
        sortType.toLowerCase() == 'ascending';
    switch (sortBy.toLowerCase()) {
      case 'price':
        return ascending ? 'price_asc' : 'price_desc';
      case 'rating':
      case 'review_count':
        return ascending ? 'recommended' : 'highest_rated';
      case 'date':
      case 'created_at':
      case 'id':
        return 'newest';
      case 'stock':
      case 'popular':
        return 'popular';
      default:
        return 'recommended';
    }
  }

  static Map<String, dynamic> _toMap(dynamic value) {
    if (value is! Map) {
      throw const FormatException('صيغة بيانات الخادم غير صحيحة.');
    }
    return Map<String, dynamic>.from(value);
  }

  static TExceptions _asException(Object error) {
    if (error is FlaskApiException) return TExceptions(error.message);
    return TExceptions(error.toString());
  }
}
