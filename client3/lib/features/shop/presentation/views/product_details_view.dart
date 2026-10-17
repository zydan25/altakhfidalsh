import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';
import 'package:t_store/core/dependency_injection/service_locator.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/features/shop/domain/entities/product_entity.dart';
import 'package:t_store/features/shop/presentation/cubit/products_cubit.dart';
import 'package:t_store/features/shop/presentation/cubit/products_state.dart';

class ProductDetailsView extends StatelessWidget {
  const ProductDetailsView({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context) {
    final id = productId?.trim() ?? '';
    if (id.isEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تفاصيل المنتج')),
          body: const Center(child: Text('اختر منتجًا لعرض تفاصيله.')),
        ),
      );
    }
    return BlocProvider(
      create: (_) => sl<ProductsCubit>()..getProductById(id),
      child: _ProductDetailsBody(productId: id),
    );
  }
}

class _ProductDetailsBody extends StatelessWidget {
  const _ProductDetailsBody({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل المنتج')),
        body: SafeArea(
          child: BlocBuilder<ProductsCubit, ProductsState>(
            builder: (context, state) {
              if (state is ProductDetailLoading || state is ProductsInitial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ProductDetailError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(TSizes.defaultSpace),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message, textAlign: TextAlign.center),
                        const SizedBox(height: TSizes.spaceBtwItems),
                        ElevatedButton(
                          onPressed: () => context
                              .read<ProductsCubit>()
                              .getProductById(productId),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (state is ProductDetailLoaded) {
                return _ProductDetailsContent(product: state.product);
              }
              return const Center(child: Text('لا توجد تفاصيل لعرضها.'));
            },
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsContent extends StatelessWidget {
  const _ProductDetailsContent({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final images = product.images
        .where((image) => image.trim().isNotEmpty)
        .toList(growable: false);
    final symbol = product.currencySymbol ?? product.currencyCode ?? 'SAR';
    final rawBadges = product.attributes?['badges'];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 340,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: images.isEmpty
                ? const Center(child: Icon(Iconsax.gallery, size: 56))
                : PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(TSizes.defaultSpace),
                      child: Image.network(
                        images[index],
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Iconsax.gallery, size: 56),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(TSizes.defaultSpace),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rawBadges is List && rawBadges.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: rawBadges.whereType<Map>().map((raw) {
                      final badge = Map<String, dynamic>.from(raw);
                      final title = (badge['custom_text'] ??
                                  badge['name'] ??
                                  badge['code'])
                              ?.toString()
                              .trim() ??
                          '';
                      if (title.isEmpty) return const SizedBox.shrink();
                      return Chip(label: Text(title));
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: TSizes.spaceBtwItems),
                ],
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if ((product.brandName ?? '').isNotEmpty) ...[
                  const SizedBox(height: TSizes.spaceBtwItems / 2),
                  Text(
                    product.brandName!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: TSizes.spaceBtwItems),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: TSizes.spaceBtwItems,
                  runSpacing: 6,
                  children: [
                    if (product.hasDiscount)
                      Text(
                        '${product.price.toStringAsFixed(2)} $symbol',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    Text(
                      '${product.effectivePrice.toStringAsFixed(2)} $symbol',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: product.hasDiscount
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                    ),
                    if (product.hasDiscount)
                      Text(
                        '-${product.discountPercentage.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: TSizes.spaceBtwItems),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Icon(
                      product.isInStock
                          ? Iconsax.tick_circle
                          : Iconsax.close_circle,
                      size: 18,
                      color: product.isInStock
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
                    Text(
                      product.isInStock
                          ? 'متوفر (${product.stock})'
                          : 'غير متوفر حاليًا',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (product.rating > 0) ...[
                      const Icon(Iconsax.star1, size: 18, color: Colors.amber),
                      Text(product.rating.toStringAsFixed(1)),
                      if (product.reviewsCount > 0)
                        Text('(${product.reviewsCount} تقييم)'),
                    ],
                  ],
                ),
                if ((product.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: TSizes.spaceBtwSections),
                  Text(
                    'وصف المنتج',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: TSizes.spaceBtwItems),
                  Text(
                    product.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
