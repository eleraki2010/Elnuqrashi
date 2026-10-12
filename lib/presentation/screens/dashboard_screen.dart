import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../widgets/stat_card.dart';
import '../widgets/store_logo.dart';
import '../../providers/app_providers.dart';

class DashboardScreen extends ConsumerWidget {
  /// التنقل بالاسم (مقاوم لإعادة الترتيب وفلترة الصلاحيات).
  final Function(String targetRoute)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

   @override
   Widget build(BuildContext context, WidgetRef ref) {
     final statsAsync = ref.watch(dashboardStatsProvider);
     final recentSalesAsync = ref.watch(salesHistoryProvider);
     final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    // عامل تكبير متجاوب: يكبّر/يصغّر عناصر اللوحة بسلاسة حسب عرض المحتوى
    // المتاح فعلياً (باستثناء الشريط الجانبي)، فتبقى متناسقة على أي شاشة.
    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);
    final sectionGap = ResponsiveUtils.scaledSpacing(20.0, contentWidth);

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
            ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 3.0, contentWidth)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store Title & Header
            // على العرض الضيق (تابلت رأسي بشريط جانبي، أو هاتف) يُرصّ
            // الزر أسفل العنوان بدل صف واحد يفيض ويتداخل.
            _buildHeader(scale, contentWidth, dateFormat),
            SizedBox(height: ResponsiveUtils.scaledSpacing(24.0, contentWidth)),

            // Metrics Cards Grid
            statsAsync.when(
              data: (stats) {
                final statColumns = ResponsiveUtils.statGridColumns(
                  contentWidth,
                );
                final statSpacing = ResponsiveUtils.scaledSpacing(16.0, contentWidth);
                // عرض البطاقة المشتق من عرض المحتوى المتاح (يُخصم منه الهامش
                // الخارجي والمسافات بين الأعمدة)، ومنه يُشتق معامل
                // التناسب حتى تظل ارتفاع البطاقة عند القدر الذي يحتاجه
                // محتواها — فلا تفيض مع 4 أعمدة ضيقة.
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
                  childAspectRatio: (statCardWidth / statTargetHeight).clamp(
                    0.8,
                    2.2,
                  ),
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
                      subtitle: 'متوسط الفاتورة: ${AppStrings.money(stats.invoiceCount > 0 ? stats.totalSales / stats.invoiceCount : 0.0)}',
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
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Center(
                child: Text('خطأ في تحميل بيانات لوحة القيادة: $e'),
              ),
            ),
            SizedBox(height: sectionGap),

            // Recent Sales List
            Text(
              'المبيعات الأخيرة',
              style: TextStyle(
                fontSize: ResponsiveUtils.scaledFont(
                    AppTypography.HEADING_2, contentWidth),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveUtils.scaledSpacing(8.0, contentWidth)),
            recentSalesAsync.when(
              data: (sales) {
                if (sales.isEmpty) {
                  return Center(
                    child: Text(
                      'لا توجد مبيعات اليوم',
                      style: TextStyle(
                        fontSize:
                            ResponsiveUtils.scaledFont(
                                14.0, contentWidth),
                        color: AppColors.TEXT_SECONDARY),
                      ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sales.length > 5 ? 5 : sales.length,
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    return ListTile(
                      leading: Icon(Icons.attach_money, size: 24 * scale),
                      title: Text(
                        sale.customerName ?? 'عميل غير معروف',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(
                                  14.0, contentWidth),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${AppStrings.money(sale.total)} • ${sale.invoiceNumber}',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(
                                  12.0, contentWidth),
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16 * scale,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Center(
                child: Text('خطأ في تحميل المبيعات الأخيرة: $e'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Store Title & Header
  Widget _buildHeader(double scale, double contentWidth, DateFormat dateFormat) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: ResponsiveUtils.scaledSpacing(16.0, contentWidth)),
      child: Row(
        children: [
          StoreLogo(
            size: 60 * scale,
          ),
          SizedBox(width: ResponsiveUtils.scaledSpacing(12.0, contentWidth)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.APP_TITLE,
                  style: TextStyle(
                    fontSize: ResponsiveUtils.scaledFont(
                        20.0, contentWidth),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${AppStrings.STORE_NAME} • ${dateFormat.format(DateTime.now())}',
                  style: TextStyle(
                    fontSize:
                        ResponsiveUtils.scaledFont(
                            14.0, contentWidth),
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart, size: 26 * scale),
            tooltip: 'عربة التسوق',
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