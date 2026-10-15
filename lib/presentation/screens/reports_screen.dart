import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/shop_profile_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import '../widgets/report_pdf_generator.dart';
import '../widgets/stat_card.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Daily tab state
  DateTime _selectedDate = DateTime.now();
  PeriodReportSummary? _dailyReport;
  bool _dailyLoading = true;

  // Monthly tab state
  DateTime _selectedMonth = DateTime.now();
  PeriodReportSummary? _monthlyReport;
  bool _monthlyLoading = true;

  // Custom range tab state
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  PeriodReportSummary? _customReport;
  bool _customLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDailyReport();
    _loadMonthlyReport();
    _loadCustomReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDailyReport() async {
    setState(() => _dailyLoading = true);
    final repo = ref.read(reportRepositoryProvider);
    final report = await repo.getDailyReport(_selectedDate);
    if (mounted) {
      setState(() {
        _dailyReport = report;
        _dailyLoading = false;
      });
    }
  }

  Future<void> _loadMonthlyReport() async {
    setState(() => _monthlyLoading = true);
    final repo = ref.read(reportRepositoryProvider);
    final report = await repo.getMonthlyReport(_selectedMonth.year, _selectedMonth.month);
    if (mounted) {
      setState(() {
        _monthlyReport = report;
        _monthlyLoading = false;
      });
    }
  }

  Future<void> _loadCustomReport() async {
    setState(() => _customLoading = true);
    final repo = ref.read(reportRepositoryProvider);
    final report = await repo.getReportForRange(_startDate, _endDate);
    if (mounted) {
      setState(() {
        _customReport = report;
        _customLoading = false;
      });
    }
  }

  Widget _buildReportContent(PeriodReportSummary? report, bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (report == null) {
      return const Center(child: Text('لا توجد بيانات متاحة'));
    }

    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);
    final statCols = ResponsiveUtils.statGridColumns(contentWidth);
    final statSpacing = 16.0 * scale;
    final statCardWidth =
        (contentWidth - 32 - (statCols - 1) * statSpacing) / statCols;
    final statCardHeight =
        134.0 * ResponsiveUtils.scaleForWidth(statCardWidth);
    final statRatio = (statCardWidth / statCardHeight).clamp(1.2, 2.3);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // Metric Cards Grid
        GridView.count(
          crossAxisCount: statCols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: statSpacing,
          mainAxisSpacing: statSpacing,
          childAspectRatio: statRatio,
          children: [
            StatCard(
              title: 'صافي المبيعات',
              value: AppStrings.money(report.netSales),
              subtitle:
                  'الإجمالي ${report.totalSales.toStringAsFixed(0)} − المرتجعات ${report.totalReturns.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet_outlined,
              iconColor: AppColors.PRIMARY_BLUE_DARK,
            ),
            StatCard(
              title: 'صافي أرباح المبيعات',
              value: AppStrings.money(report.totalProfit),
              subtitle: 'سعر البيع - سعر الشراء',
              icon: Icons.trending_up,
              iconColor: AppColors.SUCCESS_GREEN,
            ),
            StatCard(
              title: 'الربح بعد المصروفات',
              value: AppStrings.money(report.netProfitAfterExpenses),
              subtitle:
                  'صافي الأرباح − المصروفات ${report.totalExpenses.toStringAsFixed(0)}',
              icon: Icons.savings,
              iconColor: report.netProfitAfterExpenses >= 0
                  ? AppColors.SUCCESS_GREEN
                  : AppColors.DANGER_RED,
            ),
            StatCard(
              title: 'إجمالي المشتريات والتوريد',
              value: AppStrings.money(report.totalPurchases),
              subtitle: 'فواتير شراء البضاعة',
              icon: Icons.shopping_bag_outlined,
              iconColor: AppColors.PRIMARY_BLUE,
            ),
            StatCard(
              title: 'عدد فواتير البيع',
              value: '${report.totalInvoices}',
              subtitle: 'عملية بيع مسجلة',
              icon: Icons.receipt_long,
              iconColor: AppColors.PRIMARY_BLUE_DARK,
            ),
            StatCard(
              title: 'إجمالي المرتجعات',
              value: AppStrings.money(report.totalReturns),
              subtitle: 'مبالغ مرتجعة للعملاء',
              icon: Icons.undo,
              iconColor: AppColors.WARNING_AMBER,
            ),
            StatCard(
              title: 'ضريبة القيمة المضافة',
              value: AppStrings.money(report.totalTax),
              subtitle: 'وعاء: ${AppStrings.money(report.salesBeforeTax)}',
              icon: Icons.account_balance,
              iconColor: Colors.deepPurple,
            ),
          ],
        ),
        if (report.totalTax > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_outlined, color: Colors.deepPurple.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إقرار ضريبة القيمة المضافة (14% VAT)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14 * scale,
                          color: Colors.deepPurple.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'إجمالي ضريبة المبيعات المحصلة خلال هذه الفترة: ${AppStrings.money(report.totalTax)} — مستحقة التوريد لمصلحة الضرائب على وعاء مبيعات قدره ${AppStrings.money(report.salesBeforeTax)}.',
                        style: TextStyle(
                          fontSize: 12.5 * scale,
                          color: Colors.deepPurple.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),

        // Top Selling Products Table
        Container(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
          decoration: BoxDecoration(
            color: AppColors.NEUTRAL_SURFACE,
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'أعلى المنتجات مبيعاً وأرباحاً خلال هذه الفترة',
                style: TextStyle(
                  fontSize: AppTypography.HEADING_3,
                  fontWeight: FontWeight.bold,
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              if (report.topSellingProducts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('لا توجد مبيعات مسجلة في هذه الفترة', style: TextStyle(color: AppColors.TEXT_SECONDARY)),
                  ),
                )
              else
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(4),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFF9FAFB)),
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('اسم المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(8), child: Text('الكمية المباعة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(8), child: Text('إجمالي المبيعات', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(8), child: Text('الربح المحقق', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                    ...report.topSellingProducts.map((p) {
                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(p.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${p.totalQuantity}', textAlign: TextAlign.center)),
                           Padding(padding: const EdgeInsets.all(8), child: Text(AppStrings.money(p.totalSales), textAlign: TextAlign.center)),
                           Padding(
                             padding: const EdgeInsets.all(8),
                             child: Text(
                               AppStrings.money(p.totalProfit),
                               textAlign: TextAlign.end,
                               style: const TextStyle(color: AppColors.SUCCESS_GREEN, fontWeight: FontWeight.bold),
                             ),
                           ),
                        ],
                      );
                    }),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // إعادة تحميل التقارير تلقائياً عند تسجيل أو تعديل أي مبيعات، مصروفات، مشتريات، أو دفعات
    ref.listen(salesHistoryProvider, (_, _) {
      _loadDailyReport();
      _loadMonthlyReport();
      _loadCustomReport();
    });
    ref.listen(expensesListProvider, (_, _) {
      _loadDailyReport();
      _loadMonthlyReport();
      _loadCustomReport();
    });
    ref.listen(purchasesListProvider, (_, _) {
      _loadDailyReport();
      _loadMonthlyReport();
      _loadCustomReport();
    });
    ref.listen(paymentsProvider, (_, _) {
      _loadDailyReport();
      _loadMonthlyReport();
      _loadCustomReport();
    });

    final dateFormat = DateFormat('yyyy/MM/dd');

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'التقارير المالية وحساب الأرباح',
                  style: TextStyle(
                    fontSize: AppTypography.HEADING_2,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  color: AppColors.PRIMARY_BLUE,
                  tooltip: 'تصدير كـ PDF',
                      onPressed: () {
                        final report = _getCurrentActiveReport();
                        if (report != null) {
                          _shareReportPdf(report);
                        } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('لا توجد بيانات للتصدير'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'تقارير يومية وشهرية وفترات مخصصة لمتابعة الإيرادات، المشتريات، وصافي الأرباح بدقة',
              style: TextStyle(fontSize: 13, color: AppColors.TEXT_SECONDARY),
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.NEUTRAL_SURFACE,
                borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.PRIMARY_BLUE,
                labelColor: AppColors.PRIMARY_BLUE,
                unselectedLabelColor: AppColors.TEXT_SECONDARY,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(icon: Icon(Icons.today), text: 'التقرير اليومي'),
                  Tab(icon: Icon(Icons.calendar_month), text: 'التقرير الشهري'),
                  Tab(icon: Icon(Icons.date_range), text: 'تقرير مخصص'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1. Daily Tab
                  Column(
                    children: [
                      Row(
                        children: [
                          const Text('اختر اليوم: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                                _loadDailyReport();
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(dateFormat.format(_selectedDate)),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadDailyReport,
                            tooltip: 'تحديث',
                          ),
                        ],
                      ),
                      Expanded(child: _buildReportContent(_dailyReport, _dailyLoading)),
                    ],
                  ),

                  // 2. Monthly Tab
                  Column(
                    children: [
                      Row(
                        children: [
                          const Text('الشهر المحدد: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedMonth,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _selectedMonth = picked);
                                _loadMonthlyReport();
                              }
                            },
                            icon: const Icon(Icons.calendar_month, size: 16),
                            label: Text(DateFormat('yyyy / MMMM', 'ar').format(_selectedMonth)),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadMonthlyReport,
                            tooltip: 'تحديث',
                          ),
                        ],
                      ),
                      Expanded(child: _buildReportContent(_monthlyReport, _monthlyLoading)),
                    ],
                  ),

                  // 3. Custom Range Tab
                  Column(
                    children: [
                      Row(
                        children: [
                          const Text('من تاريخ: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate: DateTime(2020),
                                lastDate: _endDate,
                              );
                              if (picked != null) {
                                setState(() => _startDate = picked);
                                _loadCustomReport();
                              }
                            },
                            child: Text(dateFormat.format(_startDate)),
                          ),
                          const SizedBox(width: 16),
                          const Text('إلى تاريخ: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _endDate,
                                firstDate: _startDate,
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _endDate = picked);
                                _loadCustomReport();
                              }
                            },
                            child: Text(dateFormat.format(_endDate)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _loadCustomReport,
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('عرض التقرير'),
                          ),
                        ],
                      ),
                      Expanded(child: _buildReportContent(_customReport, _customLoading)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ), // MaxWidthContainer
    ),
    );
  }

  PeriodReportSummary? _getCurrentActiveReport() {
    final index = _tabController.index;
    if (index == 0) return _dailyReport;
    if (index == 1) return _monthlyReport;
    return _customReport;
  }

  DateTime _getStartDateForActiveTab() {
    final index = _tabController.index;
    if (index == 0) return _selectedDate;
    if (index == 1) return DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    return _startDate;
  }

  DateTime _getEndDateForActiveTab() {
    final index = _tabController.index;
    if (index == 0) return _selectedDate;
    if (index == 1) {
      final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
      return DateTime(_selectedMonth.year, _selectedMonth.month, lastDay);
    }
    return _endDate;
  }

  /// تصدير التقرير كـ PDF مع اسم المحل والشعار (إن وُجد).
  Future<void> _shareReportPdf(PeriodReportSummary report) async {
    String? storeName;
    try {
      final prefs = await SharedPreferences.getInstance();
      storeName = prefs.getString('store_name');
    } catch (_) {}

    String? logoPath;
    try {
      logoPath = (await ShopProfileRepository().getProfile()).logoPath;
    } catch (_) {}

    await ReportPdfGenerator.generateAndShareReport(
      report: report,
      startDate: _getStartDateForActiveTab(),
      endDate: _getEndDateForActiveTab(),
      storeName: storeName,
      storeLogoPath: logoPath,
    );
  }
}
