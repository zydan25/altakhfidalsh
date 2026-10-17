import 'package:dartz/dartz.dart';
import 'package:t_store/core/network/flask_api_client.dart';
import 'package:t_store/features/shop/data/models/category_model.dart';
import 'package:t_store/features/shop/domain/entities/category_entity.dart';
import 'package:t_store/features/shop/domain/repositories/category_repository.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl({required FlaskApiClient apiClient})
      : _apiClient = apiClient;

  final FlaskApiClient _apiClient;

  @override
  Future<Either<String, List<CategoryEntity>>> getCategories() async {
    try {
      final categories = await _fetchCategories();
      return Right(categories);
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, CategoryEntity>> getCategoryById(String id) async {
    try {
      final categories = await _fetchCategories();
      final matches = categories.where((category) => category.id == id);
      if (matches.isEmpty) return const Left('التصنيف غير موجود.');
      return Right(matches.first);
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<CategoryEntity>>> getParentCategories() async {
    try {
      final categories = await _fetchCategories();
      return Right(categories.where((category) => category.parentId == null || category.parentId!.isEmpty).toList());
    } catch (error) {
      return Left(_message(error));
    }
  }

  @override
  Future<Either<String, List<CategoryEntity>>> getSubCategories(
    String parentId,
  ) async {
    try {
      final categories = await _fetchCategories();
      return Right(
        categories.where((category) => category.parentId == parentId).toList(),
      );
    } catch (error) {
      return Left(_message(error));
    }
  }

  Future<List<CategoryEntity>> _fetchCategories() async {
    final response = await _apiClient.get('catalog/categories');
    if (response is! Map || response['items'] is! List) {
      throw const FormatException('لم تُرجع واجهة التصنيفات قائمة صحيحة.');
    }
    return (response['items'] as List)
        .whereType<Map>()
        .map((row) => CategoryModel.fromJson(Map<String, dynamic>.from(row)))
        .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
        .toList(growable: false);
  }

  static String _message(Object error) {
    if (error is FlaskApiException) return error.message;
    return error.toString();
  }
}
