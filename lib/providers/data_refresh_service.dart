import 'app_providers.dart';
import 'phase2_providers.dart';

/// وحدة مركزية لتحديث وإبطال المزودات (Providers) فورياً
/// عند إدخال أو تعديل أو حذف أي بيانات في النظام لضمان تحميلها
/// التلقائي المباشر في جميع الشاشات دون الحاجة لضغط زر تحديث.

/// يُستدعى فوراً بعد إتمام بيع، تعليق، إلغاء، أو حذف فاتورة بيع
void refreshAfterSale(dynamic ref) {
  ref.invalidate(salesHistoryProvider);
  ref.invalidate(productListProvider);
  ref.invalidate(stockAlertsProvider);
  ref.invalidate(lowStockCountProvider);
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(topSellingProductsProvider);
  ref.invalidate(customersListProvider);
  ref.invalidate(totalCustomerDebtProvider);
  ref.invalidate(overdueCustomersProvider);
  ref.invalidate(paymentsProvider);
  ref.invalidate(shopBalanceProvider);
  ref.invalidate(auditLogProvider);
}

/// يُستدعى فوراً بعد تسجيل فاتورة شراء أو توريد بضاعة جديدة
void refreshAfterPurchase(dynamic ref) {
  ref.invalidate(purchasesListProvider);
  ref.invalidate(productListProvider);
  ref.invalidate(stockAlertsProvider);
  ref.invalidate(lowStockCountProvider);
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(suppliersListProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(paymentsProvider);
  ref.invalidate(shopBalanceProvider);
  ref.invalidate(auditLogProvider);
}

/// يُستدعى فوراً بعد إضافة أو تعديل أو حذف أي دفعة مالية (سند قبض عميل / سداد مورد)
void refreshAfterPayment(dynamic ref) {
  ref.invalidate(paymentsProvider);
  ref.invalidate(customersListProvider);
  ref.invalidate(totalCustomerDebtProvider);
  ref.invalidate(overdueCustomersProvider);
  ref.invalidate(suppliersListProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(shopBalanceProvider);
  ref.invalidate(auditLogProvider);
}

/// يُستدعى فوراً بعد تسجيل أو تعديل أو حذف مصروف تشغيلي
void refreshAfterExpense(dynamic ref) {
  ref.invalidate(expensesListProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(shopBalanceProvider);
  ref.invalidate(auditLogProvider);
}

/// يُستدعى فوراً بعد إضافة أو تعديل منتج، أو تسجيل تالف/كسر، أو جرد مخزني
void refreshAfterProductChange(dynamic ref) {
  ref.invalidate(productListProvider);
  ref.invalidate(stockAlertsProvider);
  ref.invalidate(lowStockCountProvider);
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(topSellingProductsProvider);
  ref.invalidate(auditLogProvider);
}

/// يُستدعى فوراً بعد إضافة أو تعديل أو حذف عميل
void refreshAfterCustomerChange(dynamic ref) {
  ref.invalidate(customersListProvider);
  ref.invalidate(totalCustomerDebtProvider);
  ref.invalidate(overdueCustomersProvider);
  ref.invalidate(dashboardStatsProvider);
}

/// يُستدعى فوراً بعد إضافة أو تعديل أو حذف مورد
void refreshAfterSupplierChange(dynamic ref) {
  ref.invalidate(suppliersListProvider);
  ref.invalidate(dashboardStatsProvider);
}

/// يُستدعى فوراً بعد تسجيل مرتجع مبيعات أو مرتجع مشتريات
void refreshAfterReturn(dynamic ref) {
  refreshAfterSale(ref);
  ref.invalidate(purchasesListProvider);
  ref.invalidate(suppliersListProvider);
}

/// يُستدعى فوراً بعد إضافة تصنيف جديد
void refreshAfterCategoryChange(dynamic ref) {
  ref.invalidate(categoriesListProvider);
}
