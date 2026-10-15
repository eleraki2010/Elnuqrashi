import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/models/category.dart';
import '../data/models/expense.dart';
import '../data/models/product.dart';
import '../data/models/sale_invoice.dart';
import '../data/models/shop_balance.dart';
import '../data/models/shop_profile.dart';
import '../data/repositories/balance_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/payment_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sale_repository.dart';
import '../data/repositories/shop_profile_repository.dart';
import '../data/repositories/stock_movement_repository.dart';
import '../data/repositories/return_repository.dart';
import '../data/repositories/audit_log_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Repositories
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository();
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository();
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository();
});

final stockMovementRepositoryProvider = Provider<StockMovementRepository>((ref) {
  return StockMovementRepository();
});

final returnRepositoryProvider = Provider<ReturnRepository>((ref) {
  return ReturnRepository();
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository();
});

// Search provider
final searchProvider = StateProvider<String>((ref) => '');

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository();
});

final balanceRepositoryProvider = Provider<BalanceRepository>((ref) {
  return BalanceRepository();
});

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository();
});

// Categories list
final categoriesListProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(categoryRepositoryProvider);
  return await repo.getAllCategories();
});

// Search Query Notifier
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

// Selected Category Filter Notifier
class SelectedCategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setCategory(String? categoryId) => state = categoryId;
}

final selectedCategoryFilterProvider =
    NotifierProvider<SelectedCategoryFilterNotifier, String?>(SelectedCategoryFilterNotifier.new);

// Products List Provider (triggers on search or filter changes)
final productListProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final query = ref.watch(searchQueryProvider);
  final categoryId = ref.watch(selectedCategoryFilterProvider);

  if (query.isEmpty && (categoryId == null || categoryId == 'all')) {
    return await repo.getAllProducts();
  } else {
    return await repo.searchProducts(query, categoryId: categoryId);
  }
});

// Stock Alerts Provider (low stock & out of stock)
final stockAlertsProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(productListProvider);
  final repo = ref.watch(productRepositoryProvider);
  return await repo.getStockAlertProducts();
});

// Low stock count for Dashboard
final lowStockCountProvider = FutureProvider<int>((ref) async {
  ref.watch(productListProvider);
  final repo = ref.watch(productRepositoryProvider);
  return await repo.getLowStockCount();
});

// Stock Summary Provider (خدمة المخزن: البضاعة + القيمة + العدد)
// يعيد التحميل تلقائياً عند تغير المنتجات ليعكس البضاعة بعد خصم المبيعات.
final stockSummaryProvider =
    FutureProvider<StockSummary>((ref) async {
  ref.watch(productListProvider);
  final repo = ref.watch(productRepositoryProvider);
  return await repo.getStockSummary();
});

// Sales History Provider
final salesHistoryProvider = FutureProvider<List<SaleInvoice>>((ref) async {
  final repo = ref.watch(saleRepositoryProvider);
  return await repo.getAllSaleInvoices();
});

// Today Stats Provider for Dashboard
final dashboardStatsProvider = FutureProvider<TodayStats>((ref) async {
  ref.watch(salesHistoryProvider);
  final repo = ref.watch(saleRepositoryProvider);
  return await repo.getTodayStats();
});

// Top Selling Products Provider (top 5)
final topSellingProductsProvider = FutureProvider<List<TopSellingProduct>>((ref) async {
  ref.watch(salesHistoryProvider);
  final repo = ref.watch(saleRepositoryProvider);
  return await repo.getTopSellingProducts(limit: 5);
});

// All Top Selling Products Provider (for "عرض المزيد")
final allTopSellingProductsProvider = FutureProvider<List<TopSellingProduct>>((ref) async {
  ref.watch(salesHistoryProvider);
  final repo = ref.watch(saleRepositoryProvider);
  return await repo.getTopSellingProducts(limit: 50);
});

// Total Customer Debt Provider
final totalCustomerDebtProvider = FutureProvider<double>((ref) async {
  ref.watch(salesHistoryProvider);
  final repo = ref.watch(customerRepositoryProvider);
  final customers = await repo.getAllCustomers();
  final totalDebt = customers.fold<double>(
    0.0,
    (sum, c) => sum + c.balanceDue,
  );
  return totalDebt;
});

// Payments List Provider (تحصيلات العملاء ومدفوعات الموردين)
// يُعاد تحميله تلقائياً عند تغير المبيعات، ويُبطل يدوياً بعد إضافة دفعة.
final paymentsProvider =
    FutureProvider<List<PaymentWithParty>>((ref) async {
  ref.watch(salesHistoryProvider);
  final repo = ref.watch(paymentRepositoryProvider);
  return repo.getAllPaymentsWithParty();
});

// Expenses List Provider (المصروفات التشغيلية)
final expensesListProvider = FutureProvider<List<Expense>>((ref) async {
  final repo = ref.watch(expenseRepositoryProvider);
  return repo.getAllExpenses();
});

// Shop Balance Provider (الرصيد الإجمالي للمحل)
// يُعاد تحميله عند تغير المبيعات أو المصروفات ليعكس أحدث الأرقام.
final shopBalanceProvider = FutureProvider<ShopBalance>((ref) async {
  ref.watch(salesHistoryProvider);
  ref.watch(expensesListProvider);
  final repo = ref.watch(balanceRepositoryProvider);
  return repo.getShopBalance();
});

// Shop Profile Provider (بيانات المحل: الشعار)
final shopProfileRepositoryProvider = Provider<ShopProfileRepository>((ref) {
  return ShopProfileRepository();
});

final shopProfileProvider = FutureProvider<ShopProfile>((ref) async {
  final repo = ref.watch(shopProfileRepositoryProvider);
  return repo.getProfile();
});

// Audit Log Provider (سجل العمليات: من اتخذ كل قرار مالي)
// يُعاد تحميله عند تغير المبيعات والمصروفات والمدفوعات ليعكس آخر العمليات.
final auditLogProvider =
    FutureProvider<List<DetailedAuditLog>>((ref) async {
  ref.watch(salesHistoryProvider);
  ref.watch(expensesListProvider);
  ref.watch(paymentsProvider);
  final repo = ref.watch(auditLogRepositoryProvider);
  return repo.getAllLogsDetailed();
});

// VAT Enabled Notifier
class VatEnabledNotifier extends StateNotifier<bool> {
  VatEnabledNotifier() : super(false) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('vat_enabled') ?? true;
  }

  void setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vat_enabled', value);
  }
}

final vatEnabledProvider = StateNotifierProvider<VatEnabledNotifier, bool>((ref) {
  return VatEnabledNotifier();
}); // riverpod
