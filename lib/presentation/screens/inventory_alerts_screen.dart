import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';
import 'product_form_screen.dart';

class InventoryAlertsScreen extends ConsumerWidget {
  const InventoryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(stockAlertsProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تنبيهات المخزون والحد الأدنى',
                      style: TextStyle(
                        fontSize: AppTypography.HEADING_2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.PRIMARY_BLUE_DARK,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'متابعة فورية للمنتجات المنتهية أو التي قاربت على النفاد لطلبها في الوقت المناسب',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  onPressed: () {
                    ref.invalidate(stockAlertsProvider);
                    ref.invalidate(lowStockCountProvider);
                  },
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: alertsAsync.when(
                data: (products) {
                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.SUCCESS_GREEN.withValues(
                                alpha: 0.1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color: AppColors.SUCCESS_GREEN,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'المخزون في حالة ممتازة!',
                            style: TextStyle(
                              fontSize: AppTypography.HEADING_2,
                              fontWeight: FontWeight.bold,
                              color: AppColors.TEXT_PRIMARY,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'لا توجد منتجات وصلت إلى الحد الأدنى أو نفدت من المخزن',
                            style: TextStyle(color: AppColors.TEXT_SECONDARY),
                          ),
                        ],
                      ),
                    );
                  }

                  final outOfStockList = products
                      .where((p) => p.isOutOfStock)
                      .toList();
                  final lowStockList = products
                      .where((p) => p.isLowStock)
                      .toList();

                  return ListView(
                    children: [
                      // Summary Chips
                      Row(
                        children: [
                          if (outOfStockList.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.DANGER_RED.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.DANGER_RED.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: AppColors.DANGER_RED,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${outOfStockList.length} ${AppStrings.ALERT_OUT_OF_STOCK}',
                                    style: const TextStyle(
                                      color: AppColors.DANGER_RED,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 12),
                          if (lowStockList.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.WARNING_AMBER.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.WARNING_AMBER.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_outlined,
                                    color: AppColors.WARNING_AMBER,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${lowStockList.length} ${AppStrings.ALERT_LOW_STOCK}',
                                    style: const TextStyle(
                                      color: AppColors.WARNING_AMBER,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // List Container
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.NEUTRAL_SURFACE,
                          borderRadius: BorderRadius.circular(
                            AppLayout.BORDER_RADIUS,
                          ),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: products.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.8),
                          itemBuilder: (context, index) {
                            final p = products[index];
                            final isZero = p.isOutOfStock;
                            final badgeColor = isZero
                                ? AppColors.DANGER_RED
                                : AppColors.WARNING_AMBER;
                            final alertTitle = isZero
                                ? AppStrings.ALERT_OUT_OF_STOCK
                                : AppStrings.ALERT_LOW_STOCK;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: badgeColor.withValues(
                                  alpha: 0.15,
                                ),
                                child: Icon(
                                  isZero
                                      ? Icons.cancel_outlined
                                      : Icons.warning_amber,
                                  color: badgeColor,
                                ),
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      'المخزون الحالي: ${p.quantity} ${p.unit}',
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      'الحد الأدنى: ${p.minQuantityAlert} ${p.unit}',
                                      style: const TextStyle(
                                        color: AppColors.TEXT_SECONDARY,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      alertTitle,
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ProductFormScreen(
                                            productToEdit: p,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text(
                                      'تحديث الكمية',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('حدث خطأ: $err')),
              ),
            ),
          ],
        ),
      ), // MaxWidthContainer
      ),
    );
  }
}
