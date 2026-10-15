import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/customer.dart';
import '../../data/models/product.dart';
import '../../data/models/sale_invoice.dart';
import '../../data/repositories/sale_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/stat_card.dart';
import '../widgets/store_logo.dart';
import 'customer_detail_screen.dart';
import 'product_form_screen.dart';

class DashboardScreen extends ConsumerWidget {
  /// التنقل بالاسم (مقاوم لإعادة الترتيب وفلترة الصلاحيات).
  final Function(String targetRoute)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  void _showInvoiceDetails(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice invoice,
  ) async {
    final repo = ref.read(saleRepositoryProvider);
    final fullInvoice = await repo.getSaleInvoiceWithItems(invoice.id);
    if (fullInvoice != null && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => ReceiptDialog(invoice: fullInvoice),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final recentSalesAsync = ref.watch(salesHistoryProvider);
    final topSellingAsync = ref.watch(topSellingProductsProvider);
    final nearingDueAsync = ref.watch(customersNearingDueDateProvider);
    final stockAlertsAsync = ref.watch(stockAlertsProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);
    final sectionGap = ResponsiveUtils.scaledSpacing(20.0, contentWidth);
    final isCompact = contentWidth < 800;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 3.0, contentWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store Title & Header
            _buildHeader(scale, contentWidth, dateFormat),
            SizedBox(height: ResponsiveUtils.scaledSpacing(24.0, contentWidth)),

            // Metrics Cards Grid
            statsAsync.when(
              data: (stats) {
                final statColumns = ResponsiveUtils.statGridColumns(contentWidth);
                final statSpacing = ResponsiveUtils.scaledSpacing(16.0, contentWidth);
                final statCardWidth =
                    (contentWidth -
                        ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 6.0, contentWidth) -
                        (statColumns - 1) * statSpacing) /
                    statColumns;
                final statTargetHeight =
                    132 * ResponsiveUtils.scaleForWidth(statCardWidth);
                return GridView.count(
                  crossAxisCount: statColumns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: statSpacing,
                  mainAxisSpacing: statSpacing,
                  childAspectRatio: (statCardWidth / statTargetHeight).clamp(0.8, 2.2),
                  children: [
                    StatCard(
                      title: 'إجمالي مبيعات اليوم',
                      value: AppStrings.money(stats.totalSales),
                      subtitle:
                          'كاش: ${AppStrings.money(stats.cashSales)} • آجل: ${AppStrings.money(stats.creditSales)}',
                      icon: Icons.payments,
                      iconColor: AppColors.SUCCESS_GREEN,
                    ),
                    StatCard(
                      title: 'إجمالي المبيعات الآجلة',
                      value: AppStrings.money(stats.creditSales),
                      subtitle:
                          'متوسط الفاتورة: ${AppStrings.money(stats.invoiceCount > 0 ? stats.totalSales / stats.invoiceCount : 0.0)}',
                      icon: Icons.credit_card,
                      iconColor: AppColors.PRIMARY_BLUE,
                    ),
                    StatCard(
                      title: 'المبيعات النقدية',
                      value: AppStrings.money(stats.cashSales),
                      subtitle: 'عدد الفواتير: ${stats.invoiceCount}',
                      icon: Icons.attach_money,
                      iconColor: AppColors.SUCCESS_GREEN,
                    ),
                    StatCard(
                      title: 'الصافي اليومي',
                      value: AppStrings.money(stats.netSales),
                      subtitle: 'المرتجعات: ${AppStrings.money(stats.todayReturns)}',
                      icon: Icons.receipt_long,
                      iconColor: AppColors.WARNING_AMBER,
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ في تحميل بيانات لوحة القيادة: $e')),
            ),
            SizedBox(height: sectionGap),

            // Responsive Layout of the 4 Dashboard Cards:
            // 1. المبيعات الأخيرة (Recent Sales)
            // 2. أفضل المنتجات مبيعاً (Top Selling Products)
            // 3. عملاء قاربوا موعد السداد (Customers Nearing Due Date)
            // 4. منتجات قاربت على الانتهاء (Low Stock Products)
            if (isCompact) ...[
              _buildRecentSalesCard(context, ref, recentSalesAsync, scale, contentWidth),
              const SizedBox(height: 16),
              _buildTopSellingCard(context, ref, topSellingAsync, scale, contentWidth),
              const SizedBox(height: 16),
              _buildCustomersNearingDueCard(context, ref, nearingDueAsync, scale, contentWidth),
              const SizedBox(height: 16),
              _buildLowStockCard(context, ref, stockAlertsAsync, scale, contentWidth),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildRecentSalesCard(
                      context,
                      ref,
                      recentSalesAsync,
                      scale,
                      contentWidth,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTopSellingCard(
                      context,
                      ref,
                      topSellingAsync,
                      scale,
                      contentWidth,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildCustomersNearingDueCard(
                      context,
                      ref,
                      nearingDueAsync,
                      scale,
                      contentWidth,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildLowStockCard(
                      context,
                      ref,
                      stockAlertsAsync,
                      scale,
                      contentWidth,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 1. كارت المبيعات الأخيرة (Recent Sales - 5 invoices with customer name & click to view details)
  Widget _buildRecentSalesCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SaleInvoice>> recentSalesAsync,
    double scale,
    double contentWidth,
  ) {
    return _dashboardSectionCard(
      title: 'المبيعات الأخيرة',
      icon: Icons.receipt_outlined,
      iconColor: AppColors.PRIMARY_BLUE,
      onShowMore: () => _showAllRecentSalesDialog(context, ref),
      child: recentSalesAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('خطأ في تحميل المبيعات الأخيرة: $e', style: const TextStyle(color: AppColors.DANGER_RED)),
        ),
        data: (sales) {
          if (sales.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('لا توجد مبيعات مسجلة حتى الآن', style: TextStyle(color: AppColors.TEXT_SECONDARY)),
              ),
            );
          }
          final last5 = sales.take(5).toList();
          final timeFormat = DateFormat('yyyy/MM/dd hh:mm a');

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: last5.length,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.6),
            itemBuilder: (context, index) {
              final sale = last5[index];
              final customerName = (sale.customerName != null && sale.customerName!.trim().isNotEmpty)
                  ? sale.customerName!
                  : 'عميل نقدي';

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                onTap: () => _showInvoiceDetails(context, ref, sale),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.PRIMARY_BLUE.withValues(alpha: 0.1),
                  child: const Icon(Icons.receipt, color: AppColors.PRIMARY_BLUE, size: 18),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.money(sale.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.SUCCESS_GREEN,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    Text(
                      'فاتورة #${sale.invoiceNumber}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY),
                    ),
                    const Text(' • ', style: TextStyle(color: AppColors.TEXT_SECONDARY)),
                    Expanded(
                      child: Text(
                        timeFormat.format(sale.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.TEXT_SECONDARY),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.TEXT_SECONDARY),
              );
            },
          );
        },
      ),
    );
  }

  // 2. كارت أفضل المنتجات مبيعاً (Top Selling Products - 5 items)
  Widget _buildTopSellingCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<TopSellingProduct>> topSellingAsync,
    double scale,
    double contentWidth,
  ) {
    return _dashboardSectionCard(
      title: 'أفضل المنتجات مبيعاً',
      icon: Icons.trending_up,
      iconColor: AppColors.SUCCESS_GREEN,
      onShowMore: () => _showAllTopSellingDialog(context, ref),
      child: topSellingAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('خطأ في تحميل أفضل المنتجات: $e', style: const TextStyle(color: AppColors.DANGER_RED)),
        ),
        data: (topProducts) {
          if (topProducts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('لا توجد مبيعات مكتملة بعد لحساب الأكثر مبيعاً', style: TextStyle(color: AppColors.TEXT_SECONDARY)),
              ),
            );
          }
          final top5 = topProducts.take(5).toList();

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: top5.length,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.6),
            itemBuilder: (context, index) {
              final prod = top5[index];
              final rank = index + 1;
              final rankColor = switch (rank) {
                1 => const Color(0xFFEAB308), // Gold
                2 => const Color(0xFF94A3B8), // Silver
                3 => const Color(0xFFCD7F32), // Bronze
                _ => AppColors.PRIMARY_BLUE,
              };

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: rankColor.withValues(alpha: 0.15),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: rankColor,
                    ),
                  ),
                ),
                title: Text(
                  prod.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'إجمالي المبيعات: ${AppStrings.money(prod.totalRevenue)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${prod.totalQuantity.toStringAsFixed(0)} قطعة',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.SUCCESS_GREEN,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 3. كارت عملاء قاربوا موعد السداد (Customers Nearing Due Date - 5 customers)
  Widget _buildCustomersNearingDueCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Customer>> nearingDueAsync,
    double scale,
    double contentWidth,
  ) {
    return _dashboardSectionCard(
      title: 'عملاء قاربوا موعد السداد',
      icon: Icons.event_repeat,
      iconColor: AppColors.WARNING_AMBER,
      onShowMore: () => _showAllCustomersNearingDueDialog(context, ref),
      child: nearingDueAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('خطأ في تحميل بيانات العملاء: $e', style: const TextStyle(color: AppColors.DANGER_RED)),
        ),
        data: (customers) {
          if (customers.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('لا يوجد عملاء عليهم مديونيات مستحقة حالياً', style: TextStyle(color: AppColors.TEXT_SECONDARY)),
              ),
            );
          }
          final top5 = customers.take(5).toList();
          final dateFormat = DateFormat('yyyy/MM/dd');

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: top5.length,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.6),
            itemBuilder: (context, index) {
              final c = top5[index];
              final isOverdue = c.isOverdue;
              final dueDateStr = c.paymentDueDate != null
                  ? dateFormat.format(c.paymentDueDate!)
                  : 'بدون موعد محدد';

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CustomerDetailScreen(customerId: c.id),
                    ),
                  );
                },
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: (isOverdue ? AppColors.DANGER_RED : AppColors.WARNING_AMBER).withValues(alpha: 0.12),
                  child: Icon(
                    isOverdue ? Icons.warning_rounded : Icons.person_outline,
                    color: isOverdue ? AppColors.DANGER_RED : AppColors.WARNING_AMBER,
                    size: 18,
                  ),
                ),
                title: Text(
                  c.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    if (isOverdue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: AppColors.DANGER_RED.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'متأخر',
                          style: TextStyle(fontSize: 10, color: AppColors.DANGER_RED, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Text(
                      'موعد: $dueDateStr',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? AppColors.DANGER_RED : AppColors.TEXT_SECONDARY,
                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                trailing: Text(
                  AppStrings.money(c.balanceDue),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isOverdue ? AppColors.DANGER_RED : AppColors.TEXT_PRIMARY,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 4. كارت منتجات قاربت على الانتهاء (Products Nearing Stockout - 5 items)
  Widget _buildLowStockCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Product>> stockAlertsAsync,
    double scale,
    double contentWidth,
  ) {
    return _dashboardSectionCard(
      title: 'منتجات قاربت على الانتهاء',
      icon: Icons.inventory_2_outlined,
      iconColor: AppColors.DANGER_RED,
      onShowMore: () {
        if (onNavigate != null) {
          onNavigate!('alerts');
        } else {
          _showAllLowStockDialog(context, ref);
        }
      },
      child: stockAlertsAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('خطأ في تحميل النواقص: $e', style: const TextStyle(color: AppColors.DANGER_RED)),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('المخزون مكتمل ولا توجد نواقص حالياً', style: TextStyle(color: AppColors.SUCCESS_GREEN, fontWeight: FontWeight.bold)),
              ),
            );
          }
          final top5 = alerts.take(5).toList();

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: top5.length,
            separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0.6),
            itemBuilder: (context, index) {
              final p = top5[index];
              final isZero = p.isOutOfStock;
              final badgeColor = isZero ? AppColors.DANGER_RED : AppColors.WARNING_AMBER;

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(productToEdit: p),
                    ),
                  );
                },
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: badgeColor.withValues(alpha: 0.12),
                  child: Icon(
                    isZero ? Icons.cancel_outlined : Icons.warning_amber_rounded,
                    color: badgeColor,
                    size: 16,
                  ),
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'المخزون: ${p.quantity} ${p.unit} • الحد الأدنى: ${p.minQuantityAlert} ${p.unit}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: badgeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isZero ? 'نفد تماماً' : 'قارب النفاد',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Common wrapper for each Dashboard Card with a Header & "إظهار المزيد" button
  Widget _dashboardSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onShowMore,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
        children: [
          // Header Row with Title, Icon and "إظهار المزيد"
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onShowMore,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.PRIMARY_BLUE,
                  ),
                  icon: const Text(
                    'المزيد',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  label: const Icon(Icons.arrow_forward_ios, size: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.8),
          child,
        ],
      ),
    );
  }

  // Dialog: All Recent Sales
  void _showAllRecentSalesDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: AppColors.PRIMARY_BLUE),
            const SizedBox(width: 8),
            const Text('كافة المبيعات الأخيرة', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Consumer(
            builder: (context, ref, _) {
              final salesAsync = ref.watch(salesHistoryProvider);
              return salesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (sales) {
                  if (sales.isEmpty) {
                    return const Center(child: Text('لا توجد مبيعات'));
                  }
                  final dateFormat = DateFormat('yyyy/MM/dd hh:mm a');
                  return ListView.separated(
                    itemCount: sales.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sale = sales[index];
                      final customerName = (sale.customerName != null && sale.customerName!.trim().isNotEmpty)
                          ? sale.customerName!
                          : 'عميل نقدي';
                      return ListTile(
                        dense: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showInvoiceDetails(context, ref, sale);
                        },
                        title: Text(
                          '$customerName • #${sale.invoiceNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(dateFormat.format(sale.createdAt)),
                        trailing: Text(
                          AppStrings.money(sale.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.SUCCESS_GREEN,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          if (onNavigate != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onNavigate!('history');
              },
              child: const Text('فتح سجل المبيعات الكامل'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Dialog: All Top Selling Products
  void _showAllTopSellingDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.trending_up, color: AppColors.SUCCESS_GREEN),
            const SizedBox(width: 8),
            const Text('قائمة المنتجات الأكثر مبيعاً', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Consumer(
            builder: (context, ref, _) {
              final topAsync = ref.watch(allTopSellingProductsProvider);
              return topAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (products) {
                  if (products.isEmpty) {
                    return const Center(child: Text('لا توجد مبيعات مكتملة بعد'));
                  }
                  return ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final prod = products[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(prod.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('إجمالي القيمة: ${AppStrings.money(prod.totalRevenue)}'),
                        trailing: Text(
                          '${prod.totalQuantity.toStringAsFixed(0)} قطعة',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.SUCCESS_GREEN),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Dialog: All Customers Nearing Due Date
  void _showAllCustomersNearingDueDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.event_repeat, color: AppColors.WARNING_AMBER),
            const SizedBox(width: 8),
            const Text('كافة العملاء المستحقة ديونهم', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Consumer(
            builder: (context, ref, _) {
              final customersAsync = ref.watch(allCustomersNearingDueDateProvider);
              return customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (customers) {
                  if (customers.isEmpty) {
                    return const Center(child: Text('لا توجد ديون مستحقة'));
                  }
                  final dateFormat = DateFormat('yyyy/MM/dd');
                  return ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = customers[index];
                      final isOverdue = c.isOverdue;
                      final dueDateStr = c.paymentDueDate != null
                          ? dateFormat.format(c.paymentDueDate!)
                          : 'بدون موعد';
                      return ListTile(
                        dense: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailScreen(customerId: c.id),
                            ),
                          );
                        },
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'موعد السداد: $dueDateStr ${c.phone != null ? "• ${c.phone}" : ""}',
                          style: TextStyle(color: isOverdue ? AppColors.DANGER_RED : AppColors.TEXT_SECONDARY),
                        ),
                        trailing: Text(
                          AppStrings.money(c.balanceDue),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isOverdue ? AppColors.DANGER_RED : AppColors.TEXT_PRIMARY,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Dialog: All Low Stock Products
  void _showAllLowStockDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.DANGER_RED),
            const SizedBox(width: 8),
            const Text('كافة النواقص وتنبيهات المخزون', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Consumer(
            builder: (context, ref, _) {
              final alertsAsync = ref.watch(stockAlertsProvider);
              return alertsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (products) {
                  if (products.isEmpty) {
                    return const Center(child: Text('المخزون مكتمل'));
                  }
                  return ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      final isZero = p.isOutOfStock;
                      return ListTile(
                        dense: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductFormScreen(productToEdit: p),
                            ),
                          );
                        },
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('المخزون الحالي: ${p.quantity} ${p.unit} • الحد الأدنى: ${p.minQuantityAlert}'),
                        trailing: Text(
                          isZero ? 'نفد تماماً' : 'قارب النفاد',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isZero ? AppColors.DANGER_RED : AppColors.WARNING_AMBER,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          if (onNavigate != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onNavigate!('alerts');
              },
              child: const Text('فتح صفحة النواقص'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Store Title & Header
  Widget _buildHeader(double scale, double contentWidth, DateFormat dateFormat) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.scaledSpacing(16.0, contentWidth),
      ),
      child: Row(
        children: [
          StoreLogo(size: 56 * scale),
          SizedBox(width: ResponsiveUtils.scaledSpacing(12.0, contentWidth)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.APP_TITLE,
                  style: TextStyle(
                    fontSize: ResponsiveUtils.scaledFont(20.0, contentWidth),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${AppStrings.STORE_NAME} • ${dateFormat.format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: ResponsiveUtils.scaledFont(13.5, contentWidth),
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart, size: 26 * scale),
            tooltip: 'نقطة البيع',
            onPressed: () {
              if (onNavigate != null) {
                onNavigate!('pos');
              }
            },
          ),
        ],
      ),
    );
  }
}