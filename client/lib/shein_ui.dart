    required this.onSearch,
    required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 2, 6, 2),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            textDirection: TextDirection.ltr,
            children: [
              const SizedBox(width: 42),
              SxCircleIcon(icon: Icons.favorite_border, onTap: onWishlist),
              const SizedBox(width: 2),
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'تغيير طريقة العرض',
                  onPressed: onViewMode,
                  icon: Icon(
                    viewMode == _SxResultsState._viewList
                        ? Icons.view_list_outlined
                        : Icons.grid_view_outlined,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 39,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFCFCFCF), width: .8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Container(
                        width: 39,
                        height: double.infinity,
                        color: Colors.black,
                        child: const Icon(Icons.search, color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              title.isEmpty ? 'ابحث عن المنتجات' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7),
                        child: Icon(Icons.camera_alt_outlined, size: 17),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              const SizedBox(width: 6),
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'رجوع',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ResultsCategoryRail extends StatelessWidget {
  final List<CategoryModel> categories;