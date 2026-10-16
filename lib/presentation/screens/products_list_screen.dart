import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../providers/app_providers.dart';
import '../../widgets/product_card.dart';
import '../../widgets/max_width_container.dart';
import '../widgets/searchable_dropdown.dart';
import 'product_form_screen.dart';

class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() =>
      _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  String? _searchQuery;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final selectedCategory = ref.watch(selectedCategoryFilterProvider);

    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(
            ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 3.0, contentWidth)),
      child: MaxWidthContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'إدارة المنتجات والمخزون',
                  style: TextStyle(
                    fontSize: ResponsiveUtils.scaledFont(
                        AppTypography.HEADING_2, contentWidth),
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductFormScreen(),
                      ),
                    );
                  },
                  icon: Icon(Icons.add, size: 20 * scale),
                  label: Text(
                    AppStrings.BTN_ADD_PRODUCT,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.scaledFont(
                          14.0, contentWidth),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.import_export, size: 20 * scale),
                  tooltip: 'استيراد / تصدير Excel',
                  onSelected: (value) {
                    if (value == 'export') {
                      _exportToExcel(context, ref);
                    } else if (value == 'import') {
                      _importFromExcel(context, ref);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('تصدير إلى Excel')),
                    PopupMenuItem(
                      value: 'import',
                      child: Text('استيراد من Excel')),
                  ],
                ),
              ],
            ),
            SizedBox(
                height: ResponsiveUtils.scaledSpacing(16.0, contentWidth)),
            // Search and Filter Bar
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'ابحث عن منتج',
                      prefixIcon: Icon(Icons.search, size: 20 * scale),
                      border: const OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.scaledSpacing(
                            12.0, contentWidth),
                        vertical: ResponsiveUtils.scaledSpacing(
                            10.0, contentWidth),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim();
                      });
                    },
                  ),
                ),
                SizedBox(
                    width: ResponsiveUtils.scaledSpacing(8.0, contentWidth)),
                Expanded(
                  flex: 2,
                  child: categoriesAsync.when(
                    data: (categories) {
                      return SearchableDropdownFormField<String>(
                        value: selectedCategory,
                        labelText: 'تصنيف',
                        prefixIcon: Icon(Icons.category, size: 20 * scale),
                        searchHint: 'ابحث عن تصنيف...',
                        items: categories
                            .map(
                              (c) => SearchableDropdownItem<String>(
                                value: c.id,
                                label: c.name,
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          ref
                              .read(selectedCategoryFilterProvider.notifier)
                              .setCategory(value);
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (e, _) => Center(
                      child: Text('خطأ في تحميل التصنيفات: $e'),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
                height: ResponsiveUtils.scaledSpacing(16.0, contentWidth)),
            // Products Grid
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  final filteredProducts = products.where((product) {
                    final matchesSearch = _searchQuery == null ||
                        _searchQuery!.isEmpty ||
                        product.name
                            .toLowerCase()
                            .contains(_searchQuery!.toLowerCase());
                    final matchesCategory = selectedCategory == null ||
                        product.categoryId == selectedCategory;
                    return matchesSearch && matchesCategory;
                  }).toList();

                  if (filteredProducts.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد منتجات مطابقة للمعايير',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(
                                  14.0, contentWidth),
                          color: AppColors.TEXT_SECONDARY),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ResponsiveUtils.posGridColumns(
                          contentWidth),
                      crossAxisSpacing: ResponsiveUtils.scaledSpacing(
                          8.0, contentWidth),
                      mainAxisSpacing: ResponsiveUtils.scaledSpacing(
                          8.0, contentWidth),
                      childAspectRatio: 0.75,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      return ProductCard(
                        product: product,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductFormScreen(productToEdit: product),
                            ),
                          );
                        },
                        onEdit: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductFormScreen(productToEdit: product),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: Text('خطأ في تحميل المنتجات: $e'),
                ),
              ),
            ),
           ],
         ),
       ),
       ),
     );
  }

  // Placeholder methods for Excel import/export
  void _exportToExcel(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم تنفيذ تصدير Excel في الإصدار القادم'),
      ),
    );
  }

  void _importFromExcel(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم تنفيذ استيراد Excel في الإصدار القادم'),
      ),
    );
  }
}