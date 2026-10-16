import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../widgets/max_width_container.dart';

class InventoryCountScreen extends ConsumerStatefulWidget {
  const InventoryCountScreen({super.key});

  @override
  ConsumerState<InventoryCountScreen> createState() =>
      _InventoryCountScreenState();
}

class _InventoryCountScreenState extends ConsumerState<InventoryCountScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, modified, low_stock
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearAllInputs() {
    setState(() {
      for (var controller in _controllers.values) {
        controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);

    return Scaffold(
      backgroundColor: AppColors.NEUTRAL_BG,
      appBar: AppBar(
        title: const Text('جرد المخزون والتسوية المحاسبية'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث قائمة المنتجات',
            onPressed: () {
              ref.invalidate(productListProvider);
            },
          ),
        ],
      ),
      body: MaxWidthContainer(
        child: productsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.DANGER_RED,
                ),
                const SizedBox(height: 16),
                Text('حدث خطأ أثناء تحميل المنتجات: $err'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(productListProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
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
                    const Text('لا توجد منتجات مسجلة لجردها بالمخزن'),
                  ],
                ),
              );
            }

            // تصفية المنتجات حسب البحث والفلتر
            final filteredProducts = products.where((product) {
              // 1. بحث بالاسم أو الباركود
              if (_searchQuery.isNotEmpty) {
                final matchName = product.name
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase());
                final matchBarcode = product.barcode
                        ?.toLowerCase()
                        .contains(_searchQuery.toLowerCase()) ??
                    false;
                if (!matchName && !matchBarcode) return false;
              }

              // 2. فلترة سريعة
              if (_selectedFilter == 'modified') {
                final text = _controllers[product.id]?.text.trim() ?? '';
                if (text.isEmpty) return false;
                final actual = int.tryParse(text);
                return actual != null && actual != product.quantity;
              } else if (_selectedFilter == 'low_stock') {
                return product.quantity <= product.minQuantityAlert;
              }

              return true;
            }).toList();

            // حساب الإحصائيات الفورية للجرد المدخل
            int modifiedCount = 0;
            int shortageCount = 0;
            int surplusCount = 0;
            double totalShortageLoss = 0.0;
            double totalSurplusGain = 0.0;

            for (final p in products) {
              final text = _controllers[p.id]?.text.trim() ?? '';
              if (text.isEmpty) continue;
              final actual = int.tryParse(text);
              if (actual == null) continue;
              final diff = actual - p.quantity;
              if (diff < 0) {
                modifiedCount++;
                shortageCount++;
                totalShortageLoss += diff.abs() * p.purchasePrice;
              } else if (diff > 0) {
                modifiedCount++;
                surplusCount++;
                totalSurplusGain += diff * p.purchasePrice;
              }
            }

            return Column(
              children: [
                // 1. شريط الإحصائيات المحاسبية الفورية
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryMetric(
                              title: 'أصناف معدلة',
                              value: '$modifiedCount',
                              color: modifiedCount > 0
                                  ? AppColors.PRIMARY_BLUE
                                  : AppColors.TEXT_SECONDARY,
                              icon: Icons.edit_note,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryMetric(
                              title: 'عجز جرد (خسارة)',
                              value: totalShortageLoss > 0
                                  ? AppStrings.money(totalShortageLoss)
                                  : '0',
                              color: totalShortageLoss > 0
                                  ? AppColors.DANGER_RED
                                  : AppColors.TEXT_SECONDARY,
                              icon: Icons.trending_down,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryMetric(
                              title: 'فائض جرد (زيادة)',
                              value: totalSurplusGain > 0
                                  ? AppStrings.money(totalSurplusGain)
                                  : '0',
                              color: totalSurplusGain > 0
                                  ? AppColors.SUCCESS_GREEN
                                  : AppColors.TEXT_SECONDARY,
                              icon: Icons.trending_up,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // شريط البحث وفلاتر التصفية
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'بحث باسم المنتج أو الباركود...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              onChanged: (val) {
                                setState(() => _searchQuery = val.trim());
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // أزرار الفلترة
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('all', 'كافة المنتجات (${products.length})'),
                            const SizedBox(width: 6),
                            _buildFilterChip(
                              'modified',
                              'المعدلة فقط ($modifiedCount)',
                              highlight: modifiedCount > 0,
                            ),
                            const SizedBox(width: 6),
                            _buildFilterChip('low_stock', 'نواقص ومنتهية'),
                            if (modifiedCount > 0) ...[
                              const SizedBox(width: 12),
                              TextButton.icon(
                                onPressed: _clearAllInputs,
                                icon: const Icon(Icons.restart_alt, size: 16),
                                label: const Text('تفريغ الإدخالات', style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.DANGER_RED,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. قائمة المنتجات
                Expanded(
                  child: filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 48,
                                color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              const Text('لا توجد منتجات تطابق البحث أو الفلتر المحدد'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            _controllers[product.id] ??= TextEditingController();
                            final controller = _controllers[product.id]!;

                            final actualText = controller.text.trim();
                            final actual = int.tryParse(actualText);
                            final hasDiff = actual != null && actual != product.quantity;
                            final diff = hasDiff ? (actual - product.quantity) : 0;
                            final costDiff = diff.abs() * product.purchasePrice;

                            final isOutOfStock = product.quantity == 0;
                            final isLowStock =
                                product.quantity <= product.minQuantityAlert;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              elevation: hasDiff ? 1.5 : 0.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: hasDiff
                                      ? (diff < 0
                                          ? AppColors.DANGER_RED.withValues(alpha: 0.6)
                                          : AppColors.SUCCESS_GREEN.withValues(alpha: 0.6))
                                      : Colors.grey.shade200,
                                  width: hasDiff ? 1.5 : 1.0,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    // بيانات المنتج
                                    Expanded(
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
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isOutOfStock
                                                      ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                                      : isLowStock
                                                          ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                                                          : AppColors.PRIMARY_BLUE.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'المسجل: ${product.quantity} ${product.unit}',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: isOutOfStock
                                                        ? AppColors.DANGER_RED
                                                        : isLowStock
                                                            ? AppColors.WARNING_AMBER
                                                            : AppColors.PRIMARY_BLUE,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                'التكلفة: ${AppStrings.money(product.purchasePrice)}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.TEXT_SECONDARY,
                                                ),
                                              ),
                                              if (product.barcode?.isNotEmpty == true)
                                                Text(
                                                  '• باركود: ${product.barcode}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.TEXT_SECONDARY,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          // شارة الفارق المحاسبي الحي
                                          if (hasDiff) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: diff < 0
                                                    ? AppColors.DANGER_RED.withValues(alpha: 0.1)
                                                    : AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                diff < 0
                                                    ? 'عجز: ${diff.abs()} ${product.unit} (خسارة محاسبية: ${AppStrings.money(costDiff)})'
                                                    : 'فائض: +$diff ${product.unit} (قيمة الزيادة: ${AppStrings.money(costDiff)})',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: diff < 0
                                                      ? AppColors.DANGER_RED
                                                      : AppColors.SUCCESS_GREEN,
                                                ),
                                              ),
                                            ),
                                          ] else if (actual != null && actual == product.quantity) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              '✓ مطابق للمخزون المسجل',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.SUCCESS_GREEN,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    // حقل إدخال الكمية الفعلية
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        SizedBox(
                                          width: 105,
                                          height: 42,
                                          child: TextField(
                                            controller: controller,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'الفعلي',
                                              hintStyle: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.normal,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(
                                                vertical: 8,
                                                horizontal: 6,
                                              ),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // أزرار سريعة
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                controller.text = '${product.quantity}';
                                                setState(() {});
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'مطابق',
                                                  style: TextStyle(fontSize: 10),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () {
                                                controller.text = '0';
                                                setState(() {});
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'نفد (0)',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.DANGER_RED,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // 3. أزرار الإجراءات السفلية
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // زر الإلغاء / مسح التعديلات
                      Expanded(
                        flex: 1,
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  if (modifiedCount > 0) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('تأكيد الإلغاء'),
                                        content: const Text(
                                          'هل تريد تفريغ كل كميات الجرد المدخلة والتراجع عنها؟',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(),
                                            child: const Text('متابعة الجرد'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              Navigator.of(ctx).pop();
                                              _clearAllInputs();
                                              if (Navigator.canPop(context)) {
                                                Navigator.pop(context);
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.DANGER_RED,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('تفريغ الإدخالات'),
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context);
                                    } else {
                                      _clearAllInputs();
                                    }
                                  }
                                },
                          icon: const Icon(Icons.close),
                          label: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // زر حفظ الجرد والتسوية المحاسبية
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (_isSubmitting || modifiedCount == 0)
                              ? null
                              : () => _confirmAndSubmitCount(
                                    products: products,
                                    modifiedCount: modifiedCount,
                                    shortageCount: shortageCount,
                                    surplusCount: surplusCount,
                                    totalShortageLoss: totalShortageLoss,
                                    totalSurplusGain: totalSurplusGain,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.SUCCESS_GREEN,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 2,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            modifiedCount == 0
                                ? 'أدخل الكميات الفعلية لتسوية الجرد'
                                : 'حفظ وتسوية الجرد ($modifiedCount صنف)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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

  Widget _buildSummaryMetric({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, {bool highlight = false}) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = key),
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? Colors.white
            : (highlight ? AppColors.PRIMARY_BLUE : AppColors.TEXT_PRIMARY),
      ),
      selectedColor: AppColors.PRIMARY_BLUE,
      backgroundColor: highlight
          ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.1)
          : Colors.grey.shade100,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _confirmAndSubmitCount({
    required List<Product> products,
    required int modifiedCount,
    required int shortageCount,
    required int surplusCount,
    required double totalShortageLoss,
    required double totalSurplusGain,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory, color: AppColors.PRIMARY_BLUE),
            SizedBox(width: 8),
            Text('تأكيد تسوية جرد المخزون'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيتم تطبيق التسوية المحاسبية والمخزنية التالية:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('• عدد الأصناف التي سيتم تعديل رصيدها: $modifiedCount صنف'),
              if (shortageCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '• عجز جرد: $shortageCount أصناف بخسارة تقديرية ${AppStrings.money(totalShortageLoss)}',
                  style: const TextStyle(
                    color: AppColors.DANGER_RED,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '  (سيتم إثبات العجز تلقائياً كمصروف تشغيلي "عجز وفروقات جرد" لدقة الأرباح والميزانية)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY),
                ),
              ],
              if (surplusCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '• فائض جرد: $surplusCount أصناف بقيمة زيادة ${AppStrings.money(totalSurplusGain)}',
                  style: const TextStyle(
                    color: AppColors.SUCCESS_GREEN,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'هل تريد اعتماد الجرد وتحديث المخزون والدفاتر الآن؟',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.SUCCESS_GREEN,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد واعتماد التسوية'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final entries = <InventoryCountEntry>[];
      for (final p in products) {
        final text = _controllers[p.id]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final actual = int.tryParse(text);
        if (actual == null) continue;
        if (actual != p.quantity) {
          entries.add(
            InventoryCountEntry(
              productId: p.id,
              actualQuantity: actual,
            ),
          );
        }
      }

      if (entries.isEmpty) {
        setState(() => _isSubmitting = false);
        return;
      }

      final productRepo = ref.read(productRepositoryProvider);
      final userId = ref.read(authProvider).user?.id;

      final result = await productRepo.applyInventoryCount(
        entries: entries,
        recordShortageAsExpense: true,
        userId: userId,
      );

      // تحديث كل المزودات المرتبطة بالمخزون والمصروفات والأرباح فورياً
      refreshAfterProductChange(ref);
      refreshAfterExpense(ref);

      // تفريغ المدخلات بعد الحفظ الناجح
      _clearAllInputs();

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      // عرض نافذة نجاح مع الملخص المحاسبي
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.SUCCESS_GREEN),
              SizedBox(width: 8),
              Text('تم اعتماد الجرد بنجاح'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✓ تم تعديل أرصدة ${result.adjustedItemsCount} صنف بالمخزن.'),
                if (result.shortageItemsCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '✓ تم تسجيل عجز ${result.totalShortageQty} قطعة (بخسارة ${AppStrings.money(result.totalShortageValue)}) كمصروف تشغيلي "عجز وفروقات جرد".',
                    style: const TextStyle(color: AppColors.DANGER_RED),
                  ),
                ],
                if (result.surplusItemsCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '✓ تم تسجيل زيادة وفائض ${result.totalSurplusQty} قطعة (بقيمة ${AppStrings.money(result.totalSurplusValue)}).',
                    style: const TextStyle(color: AppColors.SUCCESS_GREEN),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'تم توثيق كافة الحركات في سجل الرقابة وتحديث رصيد المخزن الفعلي لحظياً.',
                  style: TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // فقط نغلق الشاشة إذا كانت مفتوحة بنافذة منبثقة مستقلة (Push)،
                // وإذا كانت تبويب مدمج رئيسي نبقى عليها لتجنب الشاشة السوداء نهائياً.
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              child: const Text('تم'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('حدث خطأ أثناء حفظ الجرد: $e'),
          ),
        );
      }
    }
  }
}
