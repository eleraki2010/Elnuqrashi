import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/product.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';
import 'product_form_screen.dart';

class InventoryAlertsScreen extends ConsumerStatefulWidget {
  const InventoryAlertsScreen({super.key});

  @override
  ConsumerState<InventoryAlertsScreen> createState() =>
      _InventoryAlertsScreenState();
}

class _InventoryAlertsScreenState extends ConsumerState<InventoryAlertsScreen> {
  String _filter = 'all'; // 'all', 'out_of_stock', 'low_stock'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(stockAlertsProvider);
    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);
    final isCompact = contentWidth < 680;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(
            ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 2.5, contentWidth),
          ),
          child: MaxWidthContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Title, Subtitle, Refresh
                _buildHeader(scale, contentWidth),
                const SizedBox(height: 16),

                // Search & Filter Toolbar
                _buildSearchAndFilters(scale, isCompact),
                const SizedBox(height: 16),

                // Main Content List
                Expanded(
                  child: alertsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (err, _) => Center(
                      child: Text(
                        'حدث خطأ في تحميل النواقص: $err',
                        style: const TextStyle(color: AppColors.DANGER_RED),
                      ),
                    ),
                    data: (products) {
                      if (products.isEmpty) {
                        return _buildEmptyState(
                          title: 'المخزون في حالة ممتازة!',
                          subtitle:
                              'لا توجد منتجات وصلت إلى الحد الأدنى أو نفدت من المخزن حالياً.',
                          icon: Icons.check_circle_outline,
                          iconColor: AppColors.SUCCESS_GREEN,
                        );
                      }

                      // Apply search and filter
                      final filteredList = products.where((p) {
                        final matchesFilter = switch (_filter) {
                          'out_of_stock' => p.isOutOfStock,
                          'low_stock' => p.isLowStock,
                          _ => true,
                        };
                        if (!matchesFilter) return false;

                        if (_searchQuery.isEmpty) return true;
                        final q = _searchQuery.toLowerCase();
                        final nameMatches = p.name.toLowerCase().contains(q);
                        final barcodeMatches =
                            p.barcode?.toLowerCase().contains(q) ?? false;
                        return nameMatches || barcodeMatches;
                      }).toList();

                      if (filteredList.isEmpty) {
                        return _buildEmptyState(
                          title: 'لم يتم العثور على نتائج',
                          subtitle:
                              'لا توجد نواقص تطابق بحثك "$_searchQuery".',
                          icon: Icons.search_off_outlined,
                          iconColor: AppColors.TEXT_SECONDARY,
                        );
                      }

                      // Responsive grid: 1 column on phones, 2 columns on tablets/desktops
                      final crossAxisCount = isCompact ? 1 : 2;

                      if (crossAxisCount == 1) {
                        return ListView.separated(
                          itemCount: filteredList.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildShortageCard(
                              filteredList[index],
                              scale,
                              isCompact,
                            );
                          },
                        );
                      }

                      return GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 168,
                        ),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          return _buildShortageCard(
                            filteredList[index],
                            scale,
                            isCompact,
                          );
                        },
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

  Widget _buildHeader(double scale, double contentWidth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'النواقص وتنبيهات المخزون',
                style: TextStyle(
                  fontSize: ResponsiveUtils.scaledFont(
                    AppTypography.HEADING_2,
                    contentWidth,
                  ),
                  fontWeight: FontWeight.bold,
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'متابعة فورية للمنتجات المنتهية أو التي قاربت على النفاد لتوريدها في الوقت المناسب',
                style: TextStyle(
                  fontSize: 12.5 * scale,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () {
            ref.invalidate(stockAlertsProvider);
            ref.invalidate(lowStockCountProvider);
          },
          tooltip: 'تحديث البيانات',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters(double scale, bool isCompact) {
    return Column(
      children: [
        Row(
          children: [
            // Search field
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'ابحث عن صنف بالاسم أو الباركود...',
                    hintStyle: TextStyle(
                      fontSize: 13 * scale,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    filled: true,
                    fillColor: AppColors.NEUTRAL_SURFACE,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Filter Pills
        ref.watch(stockAlertsProvider).when(
              data: (products) {
                final outOfStockCount =
                    products.where((p) => p.isOutOfStock).length;
                final lowStockCount =
                    products.where((p) => p.isLowStock).length;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        id: 'all',
                        label: 'الكل (${products.length})',
                        icon: Icons.list_alt,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        id: 'out_of_stock',
                        label: 'نفد من المخزن ($outOfStockCount)',
                        icon: Icons.cancel_outlined,
                        color: AppColors.DANGER_RED,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        id: 'low_stock',
                        label: 'قارب على النفاد ($lowStockCount)',
                        icon: Icons.warning_amber_outlined,
                        color: AppColors.WARNING_AMBER,
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
      ],
    );
  }

  Widget _filterChip({
    required String id,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _filter == id;
    return InkWell(
      onTap: () {
        setState(() {
          _filter = id;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortageCard(Product p, double scale, bool isCompact) {
    final isZero = p.isOutOfStock;
    final statusColor = isZero ? AppColors.DANGER_RED : AppColors.WARNING_AMBER;
    final statusText = isZero ? 'نفد بالكامل' : 'قارب على النفاد';
    final shortageCount = (p.minQuantityAlert - p.quantity).clamp(0, 999999);

    // Stock ratio
    final ratio = p.minQuantityAlert > 0
        ? (p.quantity / p.minQuantityAlert).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Row: Product Name + Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14 * scale,
                        color: AppColors.TEXT_PRIMARY,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p.barcode != null && p.barcode!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'باركود: ${p.barcode}',
                          style: TextStyle(
                            fontSize: 11 * scale,
                            color: AppColors.TEXT_SECONDARY,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isZero ? Icons.cancel : Icons.warning_amber_rounded,
                      size: 13,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.5 * scale,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Middle: Metrics summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.NEUTRAL_BG,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricColumn(
                  label: 'المخزون الحالي',
                  value: '${p.quantity} ${p.unit}',
                  valueColor: statusColor,
                  scale: scale,
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.2),
                ),
                _metricColumn(
                  label: 'الحد الأدنى',
                  value: '${p.minQuantityAlert} ${p.unit}',
                  valueColor: AppColors.TEXT_PRIMARY,
                  scale: scale,
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.2),
                ),
                _metricColumn(
                  label: 'العجز المطلوب',
                  value: '$shortageCount ${p.unit}',
                  valueColor: AppColors.DANGER_RED,
                  scale: scale,
                ),
              ],
            ),
          ),

          // Bottom: Progress bar and action button
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(productToEdit: p),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 32),
                  side: BorderSide(
                    color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit_note, size: 16),
                label: Text(
                  'تحديث الصنف',
                  style: TextStyle(
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricColumn({
    required String label,
    required String value,
    required Color valueColor,
    required double scale,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10 * scale,
            color: AppColors.TEXT_SECONDARY,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12 * scale,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: AppTypography.HEADING_2,
              fontWeight: FontWeight.bold,
              color: AppColors.TEXT_PRIMARY,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.TEXT_SECONDARY),
            ),
          ),
        ],
      ),
    );
  }
}
