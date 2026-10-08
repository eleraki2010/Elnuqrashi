import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';

class InventoryCountScreen extends ConsumerStatefulWidget {
  const InventoryCountScreen({super.key});

  @override
  ConsumerState<InventoryCountScreen> createState() =>
      _InventoryCountScreenState();
}

class _InventoryCountScreenState extends ConsumerState<InventoryCountScreen> {
  final Map<String, TextEditingController> controllers = {};

  @override
  void dispose() {
    for (var controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('جرد المخزون'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
      ),
      body: MaxWidthContainer(
        child: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.DANGER_RED,
              ),
              const SizedBox(height: 16),
              Text('خطأ: $err'),
            ],
          ),
        ),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('لا توجد منتجات لجردها'),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.NEUTRAL_BG,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'جرد المخزون',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل الكمية الفعلية لكل منتج',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'عدد المنتجات: ${products.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
              ),

              // Products List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    controllers[product.id] ??= TextEditingController();
                    final controller = controllers[product.id]!;

                    final isOutOfStock = product.quantity == 0;
                    final isLowStock =
                        product.quantity <= product.minQuantityAlert;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Product Info
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOutOfStock
                                              ? AppColors.DANGER_RED
                                                  .withValues(alpha: 0.12)
                                              : isLowStock
                                                  ? AppColors.WARNING_AMBER
                                                      .withValues(alpha: 0.12)
                                                  : AppColors.SUCCESS_GREEN
                                                      .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'مسجّل: ${product.quantity} ${product.unit}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isOutOfStock
                                                ? AppColors.DANGER_RED
                                                : isLowStock
                                                    ? AppColors.WARNING_AMBER
                                                    : AppColors.SUCCESS_GREEN,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 12),

                            // Input Field
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: controller,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  hintText: 'الفعلي',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: AppColors.PRIMARY_BLUE,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: AppColors.PRIMARY_BLUE,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onChanged: (value) {
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Cancel Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Submit Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _submitCount(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.SUCCESS_GREEN,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('حفظ الجرد'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Future<void> _submitCount() async {
    try {
      int changesCount = 0;
      int addedQuantity = 0;
      int removedQuantity = 0;

      final stockMovementRepo = ref.read(stockMovementRepositoryProvider);
      final productRepo = ref.read(productRepositoryProvider);

      for (var productId in controllers.keys) {
        final actualText = controllers[productId]!.text.trim();

        if (actualText.isEmpty) continue;

        try {
          final actual = int.parse(actualText);
          final product = await productRepo.getProductById(productId);

          if (product != null) {
            final difference = actual - product.quantity;

            if (difference != 0) {
              // Create stock movement
              await stockMovementRepo.addMovement(
                productId: productId,
                type: 'count',
                quantityChange: difference,
                note: 'جرد كمية المخزون',
              );

              changesCount++;

              if (difference > 0) {
                addedQuantity += difference;
              } else {
                removedQuantity += difference.abs();
              }
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.WARNING_AMBER,
                content: Text('تحذير: خطأ في المنتج - $e'),
              ),
            );
          }
        }
      }

      // Refresh products
      ref.invalidate(productListProvider);

      if (!mounted) return;

      String message = '✓ تم حفظ الجرد ($changesCount تصحيح)';

      if (addedQuantity > 0 || removedQuantity > 0) {
        message += '\n(+$addedQuantity, -$removedQuantity)';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.SUCCESS_GREEN,
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }
}
