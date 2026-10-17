import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';
import 'package:t_store/core/common/widgets/vertical_product_card.dart';
import 'package:t_store/core/dependency_injection/service_locator.dart';
import 'package:t_store/core/utils/constants/sizes.dart';
import 'package:t_store/features/shop/presentation/cubit/products_cubit.dart';
import 'package:t_store/features/shop/presentation/cubit/products_state.dart';

class ProductSearchView extends StatelessWidget {
  const ProductSearchView({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => sl<ProductsCubit>(),
        child: const _ProductSearchBody(),
      );
}

class _ProductSearchBody extends StatefulWidget {
  const _ProductSearchBody();

  @override
  State<_ProductSearchBody> createState() => _ProductSearchBodyState();
}

class _ProductSearchBodyState extends State<_ProductSearchBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      context.read<ProductsCubit>().resetProducts();
    } else {
      context.read<ProductsCubit>().searchProducts(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('البحث عن المنتجات')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TSizes.defaultSpace),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Iconsax.search_normal),
                    suffixIcon: IconButton(
                      tooltip: 'بحث',
                      onPressed: _search,
                      icon: const Icon(Iconsax.arrow_left_2),
                    ),
                    labelText: 'اسم المنتج أو وصفه',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TSizes.cardRadiusLg),
                    ),
                  ),
                ),
                const SizedBox(height: TSizes.spaceBtwSections),
                Expanded(
                  child: BlocBuilder<ProductsCubit, ProductsState>(
                    builder: (context, state) {
                      if (state is ProductsSearching ||
                          state is ProductsLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state is ProductsError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(state.message, textAlign: TextAlign.center),
                              const SizedBox(height: TSizes.spaceBtwItems),
                              ElevatedButton(
                                onPressed: _search,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (state is ProductsSearchResult) {
                        if (state.products.isEmpty) {
                          return const Center(
                            child: Text('لا توجد منتجات مطابقة لبحثك.'),
                          );
                        }
                        return GridView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: TSizes.gridViewSpacing,
                            crossAxisSpacing: TSizes.gridViewSpacing,
                            mainAxisExtent: 288,
                          ),
                          itemCount: state.products.length,
                          itemBuilder: (context, index) => VerticalProductCard(
                            product: state.products[index],
                          ),
                        );
                      }
                      return const Center(
                        child: Text('اكتب اسم المنتج ثم اضغط بحث.'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
