import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:t_store/core/common/widgets/vertical_product_card.dart';
import 'package:t_store/core/dependency_injection/service_locator.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/features/shop/domain/entities/category_entity.dart';
import 'package:t_store/features/shop/presentation/cubit/products_cubit.dart';
import 'package:t_store/features/shop/presentation/cubit/products_state.dart';

class CategoryProductsView extends StatelessWidget {
  const CategoryProductsView({super.key, required this.category});

  final CategoryEntity category;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ProductsCubit>()
        ..getProducts(categoryId: category.id, refresh: true),
      child: _CategoryProductsBody(category: category),
    );
  }
}

class _CategoryProductsBody extends StatelessWidget {
  const _CategoryProductsBody({required this.category});

  final CategoryEntity category;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(category.name)),
        body: SafeArea(
          child: BlocBuilder<ProductsCubit, ProductsState>(
            builder: (context, state) {
              if (state is ProductsLoading || state is ProductsInitial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ProductsError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(TSizes.defaultSpace),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message, textAlign: TextAlign.center),
                        const SizedBox(height: TSizes.spaceBtwItems),
                        ElevatedButton(
                          onPressed: () =>
                              context.read<ProductsCubit>().getProducts(
                                    categoryId: category.id,
                                    refresh: true,
                                  ),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (state is ProductsLoaded) {
                if (state.products.isEmpty) {
                  return const Center(
                    child: Text('لا توجد منتجات في هذا التصنيف.'),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(TSizes.defaultSpace),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: TSizes.gridViewSpacing,
                    crossAxisSpacing: TSizes.gridViewSpacing,
                    mainAxisExtent: 288,
                  ),
                  itemCount: state.products.length,
                  itemBuilder: (context, index) =>
                      VerticalProductCard(product: state.products[index]),
                );
              }
              return const Center(child: Text('لا توجد منتجات لعرضها.'));
            },
          ),
        ),
      ),
    );
  }
}
