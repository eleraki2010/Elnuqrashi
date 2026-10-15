import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/customer.dart';
import '../data/models/purchase_invoice.dart';
import '../data/models/supplier.dart';
import '../data/repositories/purchase_repository.dart';
import '../data/repositories/purchase_return_repository.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/supplier_repository.dart';
import 'app_providers.dart';

// Repositories

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return SupplierRepository();
});

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepository();
});

final purchaseReturnRepositoryProvider =
    Provider<PurchaseReturnRepository>((ref) {
  return PurchaseReturnRepository();
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository();
});

// Customer Search Query Notifier
class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final customerSearchProvider =
    NotifierProvider<CustomerSearchNotifier, String>(CustomerSearchNotifier.new);

// Customers List Provider
final customersListProvider = FutureProvider<List<Customer>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final query = ref.watch(customerSearchProvider);
  if (query.isEmpty) {
    return await repo.getAllCustomers();
  } else {
    return await repo.searchCustomers(query);
  }
});

// Supplier Search Query Notifier
class SupplierSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
  void clear() => state = '';
}

final supplierSearchProvider =
    NotifierProvider<SupplierSearchNotifier, String>(SupplierSearchNotifier.new);

// Suppliers List Provider
final suppliersListProvider = FutureProvider<List<Supplier>>((ref) async {
  final repo = ref.watch(supplierRepositoryProvider);
  final query = ref.watch(supplierSearchProvider);
  if (query.isEmpty) {
    return await repo.getAllSuppliers();
  } else {
    return await repo.searchSuppliers(query);
  }
});

// Overdue Customers Provider (عملاء تجاوزوا موعد سداد مديونيتهم)
// يُعاد تحميله مع قائمة العملاء ليعكس أي تحصيل أو موعد جديد.
final overdueCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  ref.watch(customersListProvider);
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getOverdueCustomers();
});

// Purchases List Provider
final purchasesListProvider = FutureProvider<List<PurchaseInvoice>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getAllPurchaseInvoices();
});

// Customers Nearing Due Date Provider (top 5)
final customersNearingDueDateProvider = FutureProvider<List<Customer>>((ref) async {
  ref.watch(salesHistoryProvider);
  ref.watch(customersListProvider);
  final repo = ref.watch(customerRepositoryProvider);
  return await repo.getCustomersNearingDueDate(limit: 5);
});

// All Customers Nearing Due Date Provider (for "عرض المزيد")
final allCustomersNearingDueDateProvider = FutureProvider<List<Customer>>((ref) async {
  ref.watch(salesHistoryProvider);
  ref.watch(customersListProvider);
  final repo = ref.watch(customerRepositoryProvider);
  return await repo.getCustomersNearingDueDate(limit: 50);
});
