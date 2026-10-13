import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/product.dart';
import '../../providers/app_providers.dart';
import '../screens/product_form_screen.dart';

/// نافذة بحث وتصفح ذكية للمنتجات:
/// تتيح البحث الفوري بالاسم، الباركود، أو التصنيف مع عرض الرصيد الحالي وسعر الشراء والبيع،
/// وتتيح إضافة منتج جديد على الفور إذا لم يكن مسجلاً.
class ProductSearchDialog extends ConsumerStatefulWidget {
  final String? initialQuery;

  const ProductSearchDialog({super.key, this.initialQuery});

  static Future<Product?> show(BuildContext context, {String? initialQuery}) {
    return showDialog<Product>(
      context: context,
      builder: (_) => ProductSearchDialog(initialQuery: initialQuery),
    );
  }

  @override
  ConsumerState<ProductSearchDialog> createState() =>
      _ProductSearchDialogState();
}

class _ProductSearchDialogState extends ConsumerState<ProductSearchDialog> {
  late final TextEditingController _searchController;
  String _query = '';
  String? _selectedCategoryFilter;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
    _searchController = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 700,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: AppColors.PRIMARY_BLUE,
                        size: 26,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'البحث عن صنف / منتج',
                        style: TextStyle(
                          fontSize: AppTypography.HEADING_3,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE_DARK,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.PRIMARY_BLUE,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: () async {
                          final newProduct = await Navigator.of(context).push<Product>(
                            MaterialPageRoute(
                              builder: (_) => const ProductFormScreen(),
                            ),
                          );
                          if (newProduct != null && context.mounted) {
                            Navigator.of(context).pop(newProduct);
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('صنف جديد', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'إغلاق',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) {
                  setState(() {
                    _query = val.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المنتج، كود الصنف، أو الباركود...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 10),

              // Category filter chips
              categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) return const SizedBox.shrink();
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: _selectedCategoryFilter == null,
                          onSelected: (_) {
                            setState(() {
                              _selectedCategoryFilter = null;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        for (final cat in categories) ...[
                          ChoiceChip(
                            label: Text(cat.name),
                            selected: _selectedCategoryFilter == cat.id,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategoryFilter =
                                    selected ? cat.id : null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),

              // Results List
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    final q = _query.toLowerCase();
                    final filtered = products.where((p) {
                      final matchesCat = _selectedCategoryFilter == null ||
                          p.categoryId == _selectedCategoryFilter;
                      if (!matchesCat) return false;

                      if (q.isEmpty) return true;
                      final nameMatch = p.name.toLowerCase().contains(q);
                      final barcodeMatch =
                          p.barcode != null && p.barcode!.toLowerCase().contains(q);
                      return nameMatch || barcodeMatch;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: AppColors.TEXT_SECONDARY.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _query.isEmpty
                                  ? 'لا توجد أصناف في هذا التصنيف'
                                  : 'لا توجد نتائج مطابقة لـ "$_query"',
                              style: const TextStyle(
                                color: AppColors.TEXT_SECONDARY,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final newProduct =
                                    await Navigator.of(context).push<Product>(
                                  MaterialPageRoute(
                                    builder: (_) => const ProductFormScreen(),
                                  ),
                                );
                                if (newProduct != null && context.mounted) {
                                  Navigator.of(context).pop(newProduct);
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة هذا الصنف للمخزن الآن'),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, thickness: 0.6),
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: p.isOutOfStock
                                ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                : p.isLowStock
                                    ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                                    : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.inventory_2,
                              size: 20,
                              color: p.isOutOfStock
                                  ? AppColors.DANGER_RED
                                  : p.isLowStock
                                      ? AppColors.WARNING_AMBER
                                      : AppColors.PRIMARY_BLUE,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (p.barcode != null && p.barcode!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    p.barcode!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Text(
                                  'المتاح بالمخزن: ${p.quantity} ${p.unit}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: p.isOutOfStock
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: p.isOutOfStock
                                        ? AppColors.DANGER_RED
                                        : AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'سعر الشراء: ${AppStrings.money(p.purchasePrice)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.PRIMARY_BLUE_DARK,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'سعر البيع: ${AppStrings.money(p.salePrice)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.SUCCESS_GREEN,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: AppColors.TEXT_SECONDARY,
                          ),
                          onTap: () {
                            Navigator.of(context).pop(p);
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, _) => Center(
                    child: Text('حدث خطأ في تحميل الأصناف: $err'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
