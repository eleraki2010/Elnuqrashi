import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../widgets/max_width_container.dart';
import '../widgets/product_search_dialog.dart';

/// شاشة خدمة المخزن: كشف حيّ بالبضاعة الحالية (الاسم، العدد، القيمة)
/// بعد خصم المبيعات. القيمة تُحسب بطريقتين: سعر الشراء (التكلفة)
/// وسعر البيع (القيمة المتوقعة)، مع الربح المتوقع.
class StockSummaryScreen extends ConsumerStatefulWidget {
  const StockSummaryScreen({super.key});

  @override
  ConsumerState<StockSummaryScreen> createState() =>
      _StockSummaryScreenState();
}

class _StockSummaryScreenState extends ConsumerState<StockSummaryScreen> {
  String _searchQuery = '';
  StockSort _sort = StockSort.valueDesc;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(stockSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('خدمة المخزن'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.DANGER_RED,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.broken_image_outlined, size: 18),
            label: const Text('تسجيل تالف / كسر', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _showRecordDamageDialog(context),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: MaxWidthContainer(
        child: Padding(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
          child: summaryAsync.when(
          data: (summary) {
            final items = _applySearchAndSort(summary);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كشف خدمة المخزن',
                      style: TextStyle(
                        fontSize: AppTypography.HEADING_2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.PRIMARY_BLUE_DARK,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'تفاصيل حديثة وحيّة للبضاعة الحالية بعد خصم المبيعات — العدد والقيمة لكل صنف',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Summary cards
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'أصناف المخزن',
                        value: '${summary.productsCount}',
                        subtitle:
                            'نافد: ${summary.outOfStockCount} • قطع: ${summary.totalQuantity}',
                        icon: Icons.inventory_2,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'قيمة البضاعة (شراء)',
                        value:
                            '${summary.totalCostValue.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                        subtitle: 'أموال المحل في المخزون',
                        icon: Icons.account_balance_wallet,
                        color: AppColors.WARNING_AMBER,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'القيمة المتوقعة (بيع)',
                        value:
                            '${summary.totalSaleValue.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                        subtitle:
                            'ربح متوقع: ${summary.expectedProfit.toStringAsFixed(0)}',
                        icon: Icons.trending_up,
                        color: AppColors.SUCCESS_GREEN,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Search + sort
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم الصنف أو الباركود...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<StockSort>(
                      value: _sort,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: StockSort.valueDesc,
                          child: Text('الأعلى قيمة'),
                        ),
                        DropdownMenuItem(
                          value: StockSort.valueAsc,
                          child: Text('الأقل قيمة'),
                        ),
                        DropdownMenuItem(
                          value: StockSort.qtyDesc,
                          child: Text('الأكثر عدداً'),
                        ),
                        DropdownMenuItem(
                          value: StockSort.nameAsc,
                          child: Text('الاسم'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _sort = val);
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'تحديث',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => ref.invalidate(stockSummaryProvider),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppLayout.BORDER_RADIUS),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'البضاعة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'العدد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'القيمة (شراء)',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'القيمة (بيع)',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Items list
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState(summary)
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.NEUTRAL_SURFACE,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(AppLayout.BORDER_RADIUS),
                            ),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom:
                                  Radius.circular(AppLayout.BORDER_RADIUS),
                            ),
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, thickness: 0.8),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final isOut = item.quantity <= 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      // 1. البضاعة
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              item.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.barcode != null &&
                                                      item.barcode!.isNotEmpty
                                                  ? item.barcode!
                                                  : '—',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.TEXT_SECONDARY,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 2. العدد
                                      Expanded(
                                        flex: 2,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isOut
                                                  ? AppColors.DANGER_RED
                                                      .withValues(alpha: 0.12)
                                                  : AppColors.SUCCESS_GREEN
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${item.quantity} ${item.unit}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isOut
                                                    ? AppColors.DANGER_RED
                                                    : AppColors.SUCCESS_GREEN,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // 3. القيمة (شراء)
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          item.stockValue.toStringAsFixed(0),
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.WARNING_AMBER,
                                          ),
                                        ),
                                      ),
                                      // 4. القيمة (بيع)
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          item.expectedSaleValue
                                              .toStringAsFixed(0),
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.PRIMARY_BLUE,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // Grand total row
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    border: Border.all(
                      color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 6,
                        child: Text(
                          'الإجمالي العام',
                          style: TextStyle(
                            fontSize: AppTypography.HEADING_3,
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${summary.totalCostValue.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: AppTypography.HEADING_3,
                            fontWeight: FontWeight.bold,
                            color: AppColors.WARNING_AMBER,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${summary.totalSaleValue.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: AppTypography.HEADING_3,
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('خطأ: $err')),
        ),
        ),
      ),
    );
  }

  List<StockSummaryItem> _applySearchAndSort(StockSummary summary) {
    var items = summary.items.where((i) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.name.toLowerCase().contains(q) ||
          (i.barcode ?? '').toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case StockSort.valueDesc:
        items.sort((a, b) => b.stockValue.compareTo(a.stockValue));
      case StockSort.valueAsc:
        items.sort((a, b) => a.stockValue.compareTo(b.stockValue));
      case StockSort.qtyDesc:
        items.sort((a, b) => b.quantity.compareTo(a.quantity));
      case StockSort.nameAsc:
        items.sort((a, b) => a.name.compareTo(b.name));
    }
    return items;
  }

  Widget _buildEmptyState(StockSummary summary) {
    final isEmpty = summary.productsCount == 0;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
            size: 64,
            color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            isEmpty ? 'لا توجد بضاعة في المخزن' : 'لا توجد أصناف مطابقة',
            style: const TextStyle(
              fontSize: AppTypography.HEADING_3,
              color: AppColors.TEXT_SECONDARY,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isEmpty
                ? 'أضف منتجات أو سجّل فاتورة شراء لتظهر البضاعة هنا'
                : 'جرّب كلمة بحث أخرى أو امسح الفلتر',
            style: const TextStyle(color: AppColors.TEXT_SECONDARY),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecordDamageDialog(BuildContext context) async {
    final products = ref.read(productListProvider).value ?? [];
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أصناف مسجلة بالمخزن')),
      );
      return;
    }

    Product? selectedProduct = products.firstWhere(
      (p) => p.quantity > 0,
      orElse: () => products.first,
    );
    int quantity = 1;
    final reasonController = TextEditingController(text: 'تالف وكسر مخزني');
    final qtyController = TextEditingController(text: '1');
    bool recordAsExpense = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final maxStock = selectedProduct?.quantity ?? 0;
          final totalLoss = (selectedProduct?.purchasePrice ?? 0.0) * quantity;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.broken_image_outlined, color: AppColors.DANGER_RED),
                SizedBox(width: 8),
                Text('تسجيل كسر وتوالف مخزون'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('اختر الصنف:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final p = await ProductSearchDialog.show(context);
                        if (p != null) {
                          setDialogState(() {
                            selectedProduct = p;
                            quantity = 1;
                            qtyController.text = '1';
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selectedProduct != null
                                ? AppColors.PRIMARY_BLUE
                                : Colors.grey.shade400,
                            width: selectedProduct != null ? 1.5 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          color: selectedProduct != null
                              ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.04)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedProduct != null
                                  ? Icons.inventory_2
                                  : Icons.search,
                              size: 20,
                              color: AppColors.PRIMARY_BLUE,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedProduct != null
                                    ? '${selectedProduct!.name} (المتاح: ${selectedProduct!.quantity} ${selectedProduct!.unit})'
                                    : 'اضغط للبحث عن الصنف بالاسم أو الباركود...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: selectedProduct != null
                                      ? AppColors.PRIMARY_BLUE_DARK
                                      : AppColors.TEXT_SECONDARY,
                                  fontWeight: selectedProduct != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('الكمية التالفة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: quantity > 1
                              ? () {
                                  setDialogState(() {
                                    quantity--;
                                    qtyController.text = '$quantity';
                                  });
                                }
                              : null,
                        ),
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              helperText: 'أقصى كمية متاحة: $maxStock',
                            ),
                            onChanged: (val) {
                              final q = int.tryParse(val) ?? 1;
                              setDialogState(() {
                                quantity = q.clamp(1, maxStock > 0 ? maxStock : 1);
                              });
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: quantity < maxStock
                              ? () {
                                  setDialogState(() {
                                    quantity++;
                                    qtyController.text = '$quantity';
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('سبب الكسر أو التلف:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        hintText: 'مثال: كسر أثناء النقل، انتهاء صلاحية...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: recordAsExpense,
                      title: const Text('تسجيل الخسارة كمصروف تشغيلي (توالف مخزون)'),
                      subtitle: const Text('لتخفيض صافي الأرباح تلقائياً في قائمة الدخل'),
                      onChanged: (v) => setDialogState(() => recordAsExpense = v ?? true),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.DANGER_RED.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.DANGER_RED.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('إجمالي الخسارة المحسوبة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            AppStrings.money(totalLoss),
                            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.DANGER_RED, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.DANGER_RED,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check),
                label: const Text('تأكيد وإسقاط التالف'),
                onPressed: (selectedProduct == null || maxStock <= 0)
                    ? null
                    : () async {
                        try {
                          await ref.read(productRepositoryProvider).recordStockDamage(
                                productId: selectedProduct!.id,
                                quantity: quantity,
                                reason: reasonController.text.trim().isEmpty
                                    ? 'تالف وكسر مخزني'
                                    : reasonController.text.trim(),
                                recordAsExpense: recordAsExpense,
                                userId: ref.read(authProvider).user?.id,
                              );
                          ref.invalidate(productListProvider);
                          ref.invalidate(stockSummaryProvider);
                          ref.invalidate(expensesListProvider);
                          ref.invalidate(shopBalanceProvider);

                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.SUCCESS_GREEN,
                                content: Text(
                                  '✓ تم إسقاط $quantity قطعة من "${selectedProduct!.name}" بنجاح (${AppStrings.money(totalLoss)})',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.DANGER_RED,
                                content: Text('خطأ: $e'),
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }
}

enum StockSort { valueDesc, valueAsc, qtyDesc, nameAsc }

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.TEXT_SECONDARY,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
