class CategoryModel {
  final int id;
  final int? parentId;
  final String name;
  final String? slug;
  final String? iconUrl;
  const CategoryModel({required this.id, this.parentId, required this.name, this.slug, this.iconUrl});
  factory CategoryModel.fromJson(Map<String,dynamic> j) => CategoryModel(
    id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
    parentId: j['parent_id'] == null ? null : int.tryParse(j['parent_id'].toString()),
    name: (j['name'] ?? '').toString(),
    slug: j['slug']?.toString(),
  );
}
class ProductModel {
  final int id;
  final String name;
  final String price;
  final String? oldPrice;
  final String? image;
  final int? variantId;
  const ProductModel({required this.id,required this.name,required this.price,this.oldPrice,this.image,this.variantId});
  factory ProductModel.fromJson(Map<String,dynamic> j) {
    final p=j['product'] is Map ? Map<String,dynamic>.from(j['product']) : j;
    return ProductModel(
      id:int.tryParse((p['id'] ?? j['product_id'] ?? 0).toString()) ?? 0,
      name:(p['name'] ?? j['name'] ?? '').toString(),
      price:(j['price'] ?? p['base_price_sar'] ?? p['price'] ?? '0').toString(),
      oldPrice:(j['compare_at_price'] ?? p['compare_at_price'])?.toString(),
      image:(j['image_url'] ?? p['image_url'])?.toString(),
      variantId:j['variant_id']==null ? null : int.tryParse(j['variant_id'].toString()),
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
