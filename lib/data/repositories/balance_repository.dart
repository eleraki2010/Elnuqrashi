import '../../core/database/app_database.dart';
import '../models/shop_balance.dart';

/// يحسب الرصيد المالي الإجمالي للمحل من الحركات المسجّلة فعلياً.
///
/// نحسب التدفقات النقدية الحقيقية فقط (لا الأرقام التقديرية):
/// - داخل: ما دُفع من المبيعات + تحصيلات الديون.
/// - خارج: مدفوعات الموردين + المصروفات.
class BalanceRepository {
  Future<ShopBalance> getShopBalance() async {
    final db = await AppDatabase.instance;

    // 1. النقد الذي دخل فعلياً من المبيعات المكتملة.
    // MIN(paid_amount, total) = ما استُلم فعلياً من الصندوق:
    // - فاتورة نقدية كاملة: paid = total → total.
    // - فاتورة آجلة: paid < total → فقط الجزء المسدد (لا يُحتسب الباقي الآجل).
    // - دفعة زائدة: paid > total → يُحسب total فقط (الباقي رُفع نقدًا للعميل).
    final salesCashRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(MIN(paid_amount, total)), 0.0) as cash_from_sales
      FROM sale_invoices
      WHERE status = 'completed'
    ''',
    );
    final cashFromSales =
        (salesCashRes.first['cash_from_sales'] as num?)?.toDouble() ?? 0.0;

    // 2. تحصيلات العملاء الداخلة (سداد الديون).
    final collectionsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as collections_in
      FROM payments
      WHERE direction = 'in'
    ''',
    );
    final collectionsIn =
        (collectionsRes.first['collections_in'] as num?)?.toDouble() ?? 0.0;

    // 3. مدفوعات الموردين الخارجة.
    final supplierPaymentsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as supplier_out
      FROM payments
      WHERE direction = 'out'
    ''',
    );
    final supplierPaymentsOut =
        (supplierPaymentsRes.first['supplier_out'] as num?)?.toDouble() ?? 0.0;

    // 4. المصروفات التشغيلية المسجلة.
    final expensesRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as expenses_out
      FROM expenses
    ''',
    );
    final expensesOut =
        (expensesRes.first['expenses_out'] as num?)?.toDouble() ?? 0.0;

    // 5. المرتجعات النقدية الخارجة من الصندوق.
    // القاعدة المحاسبية: المرتجع يُسدّد به أولاً المتبقي على العميل، وما زاد
    // يُسلَّم نقداً. نحسب فقط الجزء النقدي = (return_amount − debt_reduction).
    // مثال: مرتجع 200 لفاتورة عليها دين 150 → 150 خصم دين + 50 نقد خارج.
    // هذا يضمن أن الخزينة تعرض المبالغ المُستلمة والمُدفعَة فعلياً فقط.
    final returnsRefundRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(return_amount - debt_reduction), 0.0) as returns_refund_out
      FROM return_invoices
      WHERE (return_amount - debt_reduction) > 0
    ''',
    );
    final returnsRefundOut =
        (returnsRefundRes.first['returns_refund_out'] as num?)?.toDouble() ?? 0.0;

    // 6. قيمة المخزون الحالي بسعر الشراء.
    final inventoryRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity * purchase_price), 0.0) as inventory_value
      FROM products
      WHERE quantity > 0
    ''',
    );
    final inventoryValue =
        (inventoryRes.first['inventory_value'] as num?)?.toDouble() ?? 0.0;

    // 7. إجمالي ديون العملاء (أموال للمحل).
    final customerDebtRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(balance_due), 0.0) as customer_debt
      FROM customers
    ''',
    );
    final customerDebt =
        (customerDebtRes.first['customer_debt'] as num?)?.toDouble() ?? 0.0;

    // 8. إجمالي المستحقات للموردين (أموال على المحل).
    final supplierOwedRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(balance_owed), 0.0) as supplier_owed
      FROM suppliers
    ''',
    );
    final supplierOwed =
        (supplierOwedRes.first['supplier_owed'] as num?)?.toDouble() ?? 0.0;

    return ShopBalance(
      cashFromSales: cashFromSales,
      collectionsIn: collectionsIn,
      supplierPaymentsOut: supplierPaymentsOut,
      expensesOut: expensesOut,
      returnsRefundOut: returnsRefundOut,
      inventoryValue: inventoryValue,
      customerDebt: customerDebt,
      supplierOwed: supplierOwed,
    );
  }
}
