class CategoryModel {
  final int id;
  final int? parentId;
  final String name;
  final String? slug;
  final String? iconUrl;
  final int sortOrder;
  const CategoryModel({required this.id, this.parentId, required this.name, this.slug, this.iconUrl, this.sortOrder = 0});
  factory CategoryModel.fromJson(Map<String,dynamic> j) => CategoryModel(
    id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    parentId: j['parent_id'] == null ? null : int.tryParse(j['parent_id'].toString()),
    name: (j['name'] ?? '').toString(),
    slug: j['slug']?.toString(),
    iconUrl: j['icon_url']?.toString(),
    sortOrder: int.tryParse((j['sort_order'] ?? 0).toString()) ?? 0,
  );
}
class ProductModel {
  final int id;
  final String name;
  final String shortDescription;
  final String price;
  final String? oldPrice;
  final String? image;
  final List<String> images;
  final List<Map<String, dynamic>> badges;
  final List<int> categoryIds;
  final List<int> rootCategoryIds;
  final double? imageAspectRatio;
  final String? cardAspectRatio;
  final int? variantId;
  final double? rating;
  final int reviewCount;
  final int soldQty;
  final String? brandName;
  final List<Map<String, dynamic>> colors;
  final bool isTrend;
  final Map<String, dynamic>? trendCard;
  final List<Map<String, dynamic>> hashtags;
  final Map<String, dynamic>? cardMeta;

  const ProductModel({
    required this.id,
    required this.name,
    this.shortDescription = '',
    required this.price,
    this.oldPrice,
    this.image,
    this.images=const[],
    this.badges=const[],
    this.categoryIds=const[],
    this.rootCategoryIds=const[],
    this.imageAspectRatio,
    this.cardAspectRatio,
    this.variantId,
    this.rating,
    this.reviewCount = 0,
    this.soldQty = 0,
    this.brandName,
    this.colors = const [],
    this.isTrend = false,
    this.trendCard,
    this.hashtags = const [],
    this.cardMeta,
  });

  factory ProductModel.fromJson(Map<String,dynamic> j) {
    final p=j['product'] is Map ? Map<String,dynamic>.from(j['product']) : j;
    final primary=(j['image_url'] ?? p['image_url'])?.toString();
    final rawImages=(j['images'] as List?)?.whereType<String>().where((x)=>x.isNotEmpty).toList() ?? <String>[];
    final merged=<String>[if(primary!=null && primary.isNotEmpty) primary, ...rawImages];
    final unique=merged.toSet().toList();
    final rawBrand = j['brand'];
    final brandName = rawBrand is Map ? rawBrand['name']?.toString() : null;
    final rawColors = j['colors'];
    final colors = rawColors is List
        ? rawColors.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
        : <Map<String, dynamic>>[];
    final isTrend = j['is_trend'] == true;
    final trendCard = j['trend_card'] is Map
        ? Map<String, dynamic>.from(j['trend_card'] as Map)
        : null;
    final rawHashtags = j['hashtags'];
    final hashtags = rawHashtags is List
        ? rawHashtags.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
        : <Map<String, dynamic>>[];
    final cardMeta = j['card_meta'] is Map
        ? Map<String, dynamic>.from(j['card_meta'] as Map)
        : null;

    final rawBadges=j['badges'];
    final badges=rawBadges is List
        ? rawBadges.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList()
        : <Map<String,dynamic>>[];
    final rawCategoryIds=j['category_ids'];
    final categoryIds=rawCategoryIds is List
        ? rawCategoryIds.map((x)=>int.tryParse(x.toString())).whereType<int>().toList()
        : <int>[];
    final rawRootCategoryIds=j['root_category_ids'];
    final rootCategoryIds=rawRootCategoryIds is List
        ? rawRootCategoryIds.map((x)=>int.tryParse(x.toString())).whereType<int>().toList()
        : <int>[];
    final rawAspect=double.tryParse((j['image_aspect_ratio'] ?? '').toString());
    final rawRating = double.tryParse((j['rating'] ?? '').toString());
    final reviewCount = int.tryParse((j['review_count'] ?? 0).toString()) ?? 0;
    final soldQty = int.tryParse((j['sold_qty'] ?? 0).toString()) ?? 0;
    return ProductModel(
      id:int.tryParse((p['id'] ?? j['product_id'] ?? 0).toString()) ?? 0,
      name:(p['name'] ?? j['name'] ?? '').toString(),
      shortDescription:(j['short_description'] ?? p['short_description'] ?? p['description'] ?? '').toString(),
      price:(j['price'] ?? p['base_price_sar'] ?? p['price'] ?? '0').toString(),
      oldPrice:(j['compare_at_price'] ?? p['compare_at_price'])?.toString(),
      image:unique.isNotEmpty ? unique.first : primary,
      images:unique,
      badges:badges,
      categoryIds:categoryIds,
      rootCategoryIds:rootCategoryIds,
      imageAspectRatio: rawAspect != null && rawAspect > 0 ? rawAspect : null,
      cardAspectRatio: j['card_aspect_ratio']?.toString(),
      variantId:j['variant_id']==null ? null : int.tryParse(j['variant_id'].toString()),
      rating: rawRating != null && rawRating > 0 ? rawRating : null,
      reviewCount: reviewCount,
      soldQty: soldQty,
      brandName: brandName,
      colors: colors,
      isTrend: isTrend,
      trendCard: trendCard,
      hashtags: hashtags,
      cardMeta: cardMeta,
    );
  }
}
class BannerModel {
  final int id;
  final String? title;
  final String? image;
  final String? mobileImage;
  final List<Map<String,dynamic>> targets;
  const BannerModel({required this.id,this.title,this.image,this.mobileImage,this.targets=const[]});
  factory BannerModel.fromJson(Map<String,dynamic> j)=>BannerModel(
    id:int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    title:j['title']?.toString(),
    image:j['image_url']?.toString(),
    mobileImage:j['mobile_image_url']?.toString(),
    targets:((j['targets'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList(),
  );
}
