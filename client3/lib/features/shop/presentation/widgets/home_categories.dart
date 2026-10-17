import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';
import 'package:t_store/core/utils/constants/colors.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/core/utils/helpers/helper_functions.dart';
import 'package:t_store/features/shop/domain/entities/category_entity.dart';
import 'package:t_store/features/shop/presentation/cubit/categories_cubit.dart';
import 'package:t_store/features/shop/presentation/cubit/categories_state.dart';
import 'package:t_store/features/shop/presentation/views/category_products_view.dart';

class HomeCategories extends StatefulWidget {
  const HomeCategories({super.key});

  @override
  State<HomeCategories> createState() => _HomeCategoriesState();
}

class _HomeCategoriesState extends State<HomeCategories> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CategoriesCubit>().getCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: BlocBuilder<CategoriesCubit, CategoriesState>(
        builder: (context, state) {
          if (state is CategoriesLoading || state is CategoriesInitial) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (state is CategoriesError) {
            return Center(
              child: Text(
                'تعذر تحميل التصنيفات',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: TColors.white,
                    ),
              ),
            );
          }
          if (state is! CategoriesLoaded) return const SizedBox.shrink();

          final categories = state.categories
              .where((category) =>
                  category.isActive &&
                  (category.parentId == null || category.parentId!.isEmpty))
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          if (categories.isEmpty) {
            return Center(
              child: Text(
                'لا توجد تصنيفات متاحة',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: TColors.white,
                    ),
              ),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: TSizes.spaceBtwItems),
            itemBuilder: (context, index) =>
                _CategoryCircle(category: categories[index]),
          );
        },
      ),
    );
  }
}

class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({required this.category});

  final CategoryEntity category;

  @override
  Widget build(BuildContext context) {
    final dark = THelperFunctions.isDarkMode(context);
    return GestureDetector(
      onTap: () => THelperFunctions.navigateToScreen(
        context,
        CategoryProductsView(category: category),
      ),
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            Container(
              height: 56,
              width: 56,
              padding: const EdgeInsets.all(TSizes.sm),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? TColors.white : TColors.black,
              ),
              child: category.imageUrl != null &&
                      category.imageUrl!.trim().isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: category.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Icon(Iconsax.category),
                        errorWidget: (_, __, ___) =>
                            Icon(Iconsax.category, color: TColors.dark),
                      ),
                    )
                  : Icon(
                      Iconsax.category,
                      color: dark ? TColors.black : TColors.white,
                      size: 25,
                    ),
            ),
            const SizedBox(height: TSizes.spaceBtwItems / 2),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TColors.white,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
