import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import 'audit_log_screen.dart';
import 'customers_list_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'inventory_alerts_screen.dart';
import 'inventory_count_screen.dart';
import 'payments_screen.dart';
import 'pos_screen.dart';
import 'products_list_screen.dart';
import 'purchases_history_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'sales_history_screen.dart';
import 'settings_screen.dart';
import 'shop_balance_screen.dart';
import '../widgets/store_logo.dart';
import 'stock_summary_screen.dart';
import 'suppliers_list_screen.dart';
import '../dialogs/about_app_dialog.dart';

class MainLayoutScreen extends ConsumerStatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  ConsumerState<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends ConsumerState<MainLayoutScreen> {
  int _currentIndex = 0;

  /// هل الشريط الجانبي مطوي (أيقونات فقط)؟ null = قرار تلقائي حسب العرض.
  /// على الشاشات الأضيق من 1000dp (تابلت رأسي) يبدأ مطوياً ليترك مساحة
  /// أكبر للمحتوى، ويوسّعه المستخدم متى شاء.
  bool? _isSidebarCollapsed;

  void _onSelectTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  /// التنقل بالاسم (مقاوم لإعادة الترتيب وفلترة الصلاحيات).
  /// يُحسب الفهرس من نفس قائمة entries المستخدمة في build لضمان التطابق.
  void _navigateTo(String route) {
    final isOwner = ref.read(isOwnerProvider);
    final entries =
        _buildEntries().where((e) => !e.ownerOnly || isOwner).toList();
    final index = entries.indexWhere((e) => e.route == route);
    if (index == -1) return;
    _onSelectTab(index);
  }

  // مصدر واحد لكل وجهات التنقل (موبايل + ديسكتوب) لمنع التباعد بينهما.
  // مصدر واحد لكل وجهات التنقل (موبايل + ديسكتوب) بالترتيب المطلوب بدقة.
  List<({IconData icon, IconData selectedIcon, String label, String route, bool ownerOnly, Widget screen})>
      _buildEntries() {
    return [
      (
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'الرئيسية',
        route: 'dashboard',
        ownerOnly: false,
        screen: DashboardScreen(onNavigate: _navigateTo),
      ),
      (
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale,
        label: 'نقطة البيع',
        route: 'pos',
        ownerOnly: false,
        screen: const POSScreen(),
      ),
      (
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: 'المبيعات',
        route: 'sales',
        ownerOnly: false,
        screen: const SalesHistoryScreen(),
      ),
      (
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        label: 'العملاء',
        route: 'customers',
        ownerOnly: false,
        screen: const CustomersListScreen(),
      ),
      (
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: 'المنتجات',
        route: 'products',
        ownerOnly: false,
        screen: const ProductsListScreen(),
      ),
      (
        icon: Icons.warning_amber_outlined,
        selectedIcon: Icons.warning_amber,
        label: 'النواقص',
        route: 'alerts',
        ownerOnly: false,
        screen: const InventoryAlertsScreen(),
      ),
      (
        icon: Icons.warehouse_outlined,
        selectedIcon: Icons.warehouse,
        label: 'المخزن',
        route: 'warehouse',
        ownerOnly: false,
        screen: const StockSummaryScreen(),
      ),
      (
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        label: 'الموردين',
        route: 'suppliers',
        ownerOnly: false,
        screen: const SuppliersListScreen(),
      ),
      (
        icon: Icons.shopping_bag_outlined,
        selectedIcon: Icons.shopping_bag,
        label: 'المشتريات',
        route: 'purchases',
        ownerOnly: true,
        screen: const PurchasesHistoryScreen(),
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet,
        label: 'المدفوعات',
        route: 'payments',
        ownerOnly: false,
        screen: const PaymentsScreen(),
      ),
      (
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: 'المصروفات',
        route: 'expenses',
        ownerOnly: true,
        screen: const ExpensesScreen(),
      ),
      (
        icon: Icons.undo_outlined,
        selectedIcon: Icons.undo,
        label: 'المرتجعات',
        route: 'returns',
        ownerOnly: false,
        screen: const ReturnsScreen(),
      ),
      (
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics,
        label: 'التقارير',
        route: 'reports',
        ownerOnly: true,
        screen: const ReportsScreen(),
      ),
      (
        icon: Icons.checklist_outlined,
        selectedIcon: Icons.checklist,
        label: 'الجرد',
        route: 'count',
        ownerOnly: false,
        screen: const InventoryCountScreen(),
      ),
      (
        icon: Icons.history_edu_outlined,
        selectedIcon: Icons.history_edu,
        label: 'سجل العمليات',
        route: 'audit',
        ownerOnly: true,
        screen: const AuditLogScreen(),
      ),
      (
        icon: Icons.account_balance_outlined,
        selectedIcon: Icons.account_balance,
        label: 'رصيد المحل',
        route: 'balance',
        ownerOnly: true,
        screen: const ShopBalanceScreen(),
      ),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'الإعدادات',
        route: 'settings',
        ownerOnly: true,
        screen: const SettingsScreen(),
      ),
      (
        icon: Icons.apps_outlined,
        selectedIcon: Icons.apps,
        label: 'المزيد',
        route: 'more',
        ownerOnly: false,
        screen: _MoreShortcutsScreen(onNavigate: _navigateTo),
      ),
    ];
  }

  /// الوجهات الأساسية التي تظهر دائماً في شريط التنقّل السفلي للجوال.
  /// باقي الوجهات (النواقص، الجرد، المخزن، المدفوعات، المرتجعات، العملاء،
  /// الموردين، التقارير، المصروفات، الرصيد، سجل العمليات، الإعدادات)
  /// تُفتح من ورقة "المزيد" — لا يمكن حشر 18 وجهة في شريط سفلي واحد.
  static const List<String> _primaryCompactRoutes = [
    'dashboard',
    'pos',
    'sales',
    'customers',
  ];

  /// فهرس الزر النشط في شريط الجوال: الوجهة الأساسية إن كانت مفتوحة،
  /// وإلا فالزر "المزيد" (الذي يظل مضيئاً طالما نحن على شاشة ثانوية).
  int _compactNavIndex(
    List<({IconData icon, IconData selectedIcon, String label, String route, bool ownerOnly, Widget screen})> entries,
    int currentIndex,
  ) {
    if (currentIndex < 0 || currentIndex >= entries.length) return 0;
    final currentRoute = entries[currentIndex].route;
    final primaryIndex = _primaryCompactRoutes.indexOf(currentRoute);
    return primaryIndex == -1 ? _primaryCompactRoutes.length : primaryIndex;
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من الحساب؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCountAsync = ref.watch(lowStockCountProvider);
    final lowStockCount = lowStockCountAsync.value ?? 0;
    final isOwner = ref.watch(isOwnerProvider);
    final currentUser = ref.watch(authProvider).user;
    final isDesktop = ResponsiveUtils.showSidebar(
      MediaQuery.of(context).size.width,
    );
    final screenWidth = MediaQuery.of(context).size.width;
    // الشريط الجانبي مطوي تلقائياً تحت 1000dp (تابلت رأسي وشاشات صغيرة).
    final isSidebarCollapsed = _isSidebarCollapsed ?? (screenWidth < 1000);

    final entries =
        _buildEntries().where((e) => !e.ownerOnly || isOwner).toList();
    final screens = entries.map((e) => e.screen).toList();

    final int clampedIndex = _currentIndex.clamp(0, entries.length - 1);

    if (!isDesktop) {
      // شريط سفلي مختصر: 4 وجهات أساسية + "المزيد" للباقي.
      final navDestinations = <NavigationDestination>[
        for (final route in _primaryCompactRoutes)
          () {
            final e = entries.firstWhere((e) => e.route == route);
            return NavigationDestination(
              icon: Icon(e.icon),
              selectedIcon:
                  Icon(e.selectedIcon, color: AppColors.PRIMARY_BLUE),
              label: e.label,
            );
          }(),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_outlined),
          selectedIcon:
              const Icon(Icons.more_horiz, color: AppColors.PRIMARY_BLUE),
          label: 'المزيد',
        ),
      ];

      final storeName = ref.watch(storeNameProvider);

      return Scaffold(
        appBar: AppBar(
          title: Text(storeName.isNotEmpty ? storeName : AppStrings.APP_NAME),
          actions: [
            if (lowStockCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Badge(
                  label: Text('$lowStockCount'),
                  backgroundColor: AppColors.DANGER_RED,
                  child: IconButton(
                    icon: const Icon(Icons.warning_amber_outlined),
                    tooltip: 'تنبيهات نقص المخزون',
                    onPressed: () => _navigateTo('alerts'),
                  ),
                ),
              ),
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    '${currentUser.name} (${currentUser.isOwner ? "مالك" : "كاشير"})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'تسجيل الخروج',
              onPressed: _logout,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => ResponsiveScope(
            contentWidth: constraints.maxWidth,
            child: IndexedStack(
              index: clampedIndex,
              children: screens,
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _compactNavIndex(entries, clampedIndex),
          onDestinationSelected: (index) {
            if (index < _primaryCompactRoutes.length) {
              final route = _primaryCompactRoutes[index];
              final entryIndex =
                  entries.indexWhere((e) => e.route == route);
              if (entryIndex != -1) _onSelectTab(entryIndex);
            } else {
              _navigateTo('more');
            }
          },
          destinations: navDestinations,
        ),
      );
    }

    final sidebarEntries = entries.where((e) => e.route != 'more').toList();
    final sidebarSelected = sidebarEntries.indexWhere(
      (e) => e.route == entries[clampedIndex].route,
    );

    return Scaffold(
      body: Row(
        children: [
          // شريط جانبي قابل للطي والتمرير (يدعم كافة الوجهات دون فيضان).
          _CollapsibleSidebar(
            entries: sidebarEntries,
            selectedIndex: sidebarSelected != -1 ? sidebarSelected : 0,
            onSelect: (idx) {
              if (idx >= 0 && idx < sidebarEntries.length) {
                _navigateTo(sidebarEntries[idx].route);
              }
            },
            lowStockCount: lowStockCount,
            currentUser: currentUser,
            onLogout: _logout,
            isCollapsed: isSidebarCollapsed,
            onToggleCollapsed: () => setState(
              () => _isSidebarCollapsed = !isSidebarCollapsed,
            ),
          ),

          const VerticalDivider(thickness: 1, width: 1),

          // Main View
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => ResponsiveScope(
                contentWidth: constraints.maxWidth,
                child: IndexedStack(
                  index: clampedIndex,
                  children: screens,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط تنقل جانبي قابل للطي مع تمرير عمودي — يحل فيضان NavigationRail
/// عند كثرة الوجهات (18+) على شاشات التابلت، ويعرض الأيقونات فقط عند الطي.
class _CollapsibleSidebar extends ConsumerWidget {
  final List<({IconData icon, IconData selectedIcon, String label, String route, bool ownerOnly, Widget screen})> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final int lowStockCount;
  final dynamic currentUser;
  final VoidCallback onLogout;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  const _CollapsibleSidebar({
    required this.entries,
    required this.selectedIndex,
    required this.onSelect,
    required this.lowStockCount,
    required this.currentUser,
    required this.onLogout,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = ref.watch(storeNameProvider);
    final width = isCollapsed
        ? AppLayout.SIDEBAR_COLLAPSED_WIDTH
        : AppLayout.SIDEBAR_EXPANDED_WIDTH;
    // عامل التكبير يُحسب من عرض الشاشة (لا من عرض الشريط الثابت الضيق):
    // حتى تكون أيقونات التابلت ونصوصه واضحة ومريحة — نفس مقاس المحتوى.
    final scale =
        ResponsiveUtils.scaleForWidth(MediaQuery.sizeOf(context).width);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: width,
      color: AppColors.NEUTRAL_SURFACE,
        child: Column(
          children: [
            // الترويسة: الشعار + اسم المحل + زر الطي.
            // عند الطي تُرصّ عمودياً (الشعار فوق زر التوسيع) لتناسب
            // العرض الضيق 72dp دون أي فيضان.
            if (isCollapsed)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StoreLogo(size: 44 * scale),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_double_arrow_left,
                        size: 20 * scale,
                      ),
                      tooltip: 'توسيع القائمة',
                      onPressed: onToggleCollapsed,
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 8, 8),
                child: Row(
                  children: [
                    StoreLogo(size: 44 * scale),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            storeName.isNotEmpty ? storeName : AppStrings.DEFAULT_STORE_NAME,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5 * scale,
                              color: AppColors.PRIMARY_BLUE_DARK,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            AppStrings.APP_NAME,
                            style: TextStyle(
                              fontSize: 11 * scale,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_double_arrow_right,
                        size: 20 * scale,
                      ),
                      tooltip: 'طي القائمة',
                      onPressed: onToggleCollapsed,
                    ),
                  ],
                ),
              ),
          const Divider(height: 1, thickness: 0.5),

          // قائمة الوجهات — قابلة للتمرير عمودياً (الإصلاح الجوهري للفيضان).
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                final isSelected = index == selectedIndex;
                final isAlerts = e.icon == Icons.warning_amber_outlined;

                return _SidebarTile(
                  icon: isSelected ? e.selectedIcon : e.icon,
                  label: e.label,
                  isSelected: isSelected,
                  isCollapsed: isCollapsed,
                  showBadge: isAlerts && lowStockCount > 0,
                  badgeCount: lowStockCount,
                  scale: scale,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          const Divider(height: 1, thickness: 0.5),

          // التذييل: المستخدم + تسجيل الخروج
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            child: isCollapsed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (currentUser != null)
                        Tooltip(
                          message:
                              '${currentUser.name} (${currentUser.isOwner ? "مالك" : "كاشير"})',
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                            child: Text(
                              currentUser.name.isNotEmpty
                                  ? currentUser.name[0]
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.PRIMARY_BLUE,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      IconButton(
                        icon: Icon(Icons.info_outline_rounded, size: 18 * scale, color: AppColors.PRIMARY_BLUE),
                        tooltip: 'عن نظام ${AppStrings.APP_NAME}',
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const AboutAppDialog(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        icon: Icon(Icons.logout, size: 18 * scale),
                        tooltip: 'تسجيل الخروج',
                        onPressed: onLogout,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (currentUser != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                              '${currentUser.name} (${currentUser.isOwner ? "مالك" : "كاشير"})',
                            style: TextStyle(
                              fontSize: 13 * scale,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: onLogout,
                        icon: Icon(Icons.logout, size: 16 * scale),
                        label: Text(
                          'تسجيل الخروج',
                          style: TextStyle(fontSize: 13 * scale),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // زر عن النظام وهوية المطور
                      InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => const AboutAppDialog(),
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 13, color: AppColors.PRIMARY_BLUE),
                              const SizedBox(width: 6),
                              Text(
                                '${AppStrings.APP_NAME} • v1.0',
                                style: TextStyle(
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.PRIMARY_BLUE_DARK,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// عنصر وجهة واحد في الشريط الجانبي — أيقونة + شارة + تسمية (تُخفى عند الطي).
class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final bool showBadge;
  final int badgeCount;
  final double scale;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.showBadge,
    required this.badgeCount,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      // أيقونة أوضح على التابلت (24× العامل المتجاوب ≈ 30px على شاشة 10").
      size: 24 * scale,
      color: isSelected ? AppColors.PRIMARY_BLUE : AppColors.TEXT_SECONDARY,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // صفوف مدمجة: فوق حد اللمس الأدنى (40dp) وبأقل قدر من
          // التباعد حتى تحوي القائمة وجهات أكثر على شاشة التابلت.
          constraints: const BoxConstraints(minHeight: 42),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: isCollapsed
              ? Tooltip(
                  message: label,
                  child: _badgeWrapper(iconWidget),
                )
                  : Row(
                      children: [
                        _badgeWrapper(iconWidget),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14 * scale,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.PRIMARY_BLUE
                              : AppColors.TEXT_PRIMARY,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// يلف الأيقونة بشارة عدّاد التنبيهات عند الحاجة.
  Widget _badgeWrapper(Widget child) {
    if (!showBadge) return child;
    return Badge(
      label: Text('$badgeCount'),
      backgroundColor: AppColors.DANGER_RED,
      child: child,
    );
  }
}

/// شاشة تفتح باقي الاختصارات في نفس الشاشة بسلاسة وتصميم أنيق عند الضغط على "المزيد"
class _MoreShortcutsScreen extends ConsumerWidget {
  final Function(String route) onNavigate;

  const _MoreShortcutsScreen({required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final lowStockCount = ref.watch(lowStockCountProvider).value ?? 0;
    final isOwner = ref.watch(isOwnerProvider);

    final shortcuts = [
      (
        icon: Icons.inventory_2_outlined,
        color: AppColors.PRIMARY_BLUE,
        title: 'المنتجات',
        subtitle: 'إدارة الأصناف، الأسعار، الباركود والمخزون',
        route: 'products',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.warning_amber_outlined,
        color: AppColors.DANGER_RED,
        title: 'النواقص',
        subtitle: 'تنبيهات الأصناف الحرجة التي قاربت على النفاد',
        route: 'alerts',
        ownerOnly: false,
        badge: lowStockCount,
      ),
      (
        icon: Icons.warehouse_outlined,
        color: AppColors.PRIMARY_BLUE_DARK,
        title: 'المخزن',
        subtitle: 'جرد وتقييم البضاعة وتتبع حركة المخزون',
        route: 'warehouse',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.local_shipping_outlined,
        color: AppColors.SUCCESS_GREEN,
        title: 'الموردين',
        subtitle: 'بيانات الشركات والموردين ومتابعة الحسابات',
        route: 'suppliers',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.shopping_bag_outlined,
        color: AppColors.PRIMARY_BLUE,
        title: 'المشتريات',
        subtitle: 'تسجيل فواتير الشراء والتوريد وتحديث الأسعار',
        route: 'purchases',
        ownerOnly: true,
        badge: 0,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.SUCCESS_GREEN,
        title: 'المدفوعات',
        subtitle: 'سندات القبض من العملاء وسندات الصرف للموردين',
        route: 'payments',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.receipt_long_outlined,
        color: AppColors.WARNING_AMBER,
        title: 'المصروفات',
        subtitle: 'المصروفات التشغيلية واليومية وصافي أرباح المحل',
        route: 'expenses',
        ownerOnly: true,
        badge: 0,
      ),
      (
        icon: Icons.undo_outlined,
        color: AppColors.WARNING_AMBER,
        title: 'المرتجعات',
        subtitle: 'مرتجعات المبيعات للعملاء ومرتجعات الشراء للموردين',
        route: 'returns',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.analytics_outlined,
        color: AppColors.PRIMARY_BLUE_DARK,
        title: 'التقارير',
        subtitle: 'كشوفات الحسابات والأرباح والمبيعات المفصلة',
        route: 'reports',
        ownerOnly: true,
        badge: 0,
      ),
      (
        icon: Icons.checklist_outlined,
        color: AppColors.PRIMARY_BLUE,
        title: 'الجرد',
        subtitle: 'جرد المخزون الفعلي بالمحل وتسوية العجز والفائض',
        route: 'count',
        ownerOnly: false,
        badge: 0,
      ),
      (
        icon: Icons.history_edu_outlined,
        color: AppColors.TEXT_SECONDARY,
        title: 'سجل العمليات',
        subtitle: 'سجل الرقابة المحاسبي لكافة حركات المستخدمين',
        route: 'audit',
        ownerOnly: true,
        badge: 0,
      ),
      (
        icon: Icons.account_balance_outlined,
        color: AppColors.SUCCESS_GREEN,
        title: 'رصيد المحل',
        subtitle: 'الخزينة النقدية وصافي أرباح المحل وديون السوق',
        route: 'balance',
        ownerOnly: true,
        badge: 0,
      ),
      (
        icon: Icons.settings_outlined,
        color: AppColors.PRIMARY_BLUE_DARK,
        title: 'الإعدادات',
        subtitle: 'المستخدمين، الطابعات، والنسخ الاحتياطي',
        route: 'settings',
        ownerOnly: true,
        badge: 0,
      ),
    ].where((item) => !item.ownerOnly || isOwner).toList();

    final crossAxisCount = width >= 840
        ? 4
        : (width >= 580 ? 3 : 2);

    final childAspectRatio = width >= 840
        ? 3.4
        : (width >= 580 ? 3.0 : 2.55);

    return Scaffold(
      backgroundColor: AppColors.NEUTRAL_BG,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: width >= 600 ? 16 : 10,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.PRIMARY_BLUE, AppColors.PRIMARY_BLUE_DARK],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.dashboard_customize_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'كافة أقسام المحل والاختصارات',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 1),
                          Text(
                            'الوصول السريع لجميع أدوات وإدارات النظام',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${shortcuts.length} قسم',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: shortcuts.length,
                itemBuilder: (context, index) {
                  final s = shortcuts[index];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 0.5,
                    shadowColor: Colors.black.withValues(alpha: 0.05),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onNavigate(s.route),
                      splashColor: s.color.withValues(alpha: 0.1),
                      highlightColor: s.color.withValues(alpha: 0.05),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: s.color.withValues(alpha: 0.18),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: s.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(s.icon, color: s.color, size: 19),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: AppColors.TEXT_PRIMARY,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (s.badge > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.DANGER_RED,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${s.badge}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    s.subtitle,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: AppColors.TEXT_SECONDARY,
                                      height: 1.15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_left_rounded,
                              size: 16,
                              color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

