import 'package:t_store/core/network/api_config.dart';
import 'package:t_store/features/shop/domain/entities/category_entity.dart';

class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.name,
    super.description,
    super.imageUrl,
    super.parentId,
    super.sortOrder,
    super.isActive,
    super.createdAt,
    super.updatedAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    final rawImage = json['image_url'] ?? json['icon_url'];
    String? imageUrl;
    if (rawImage != null && rawImage.toString().trim().isNotEmpty) {
      try {
        imageUrl = ApiConfig.resolveMediaUrl(rawImage.toString());
      } on FormatException {
        imageUrl = rawImage.toString();
      }
    }

    return CategoryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      imageUrl: imageUrl,
      parentId: json['parent_id']?.toString(),
      sortOrder: _toInt(json['sort_order']),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'parent_id': parentId,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  factory CategoryModel.fromEntity(CategoryEntity entity) {
    return CategoryModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      imageUrl: entity.imageUrl,
      parentId: entity.parentId,
      sortOrder: entity.sortOrder,
      isActive: entity.isActive,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
