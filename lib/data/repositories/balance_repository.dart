import '../../core/database/app_database.dart';
import '../models/shop_balance.dart';

/// يحسب الرصيد المالي الإجمالي للمحل من الحركات المسجّلة فعلياً
/// مع الالتزام الصارم بالقواعد والمعايير المحاسبية.
class BalanceRepository {
  Future<ShopBalance> getShopBalance() async {
    final db = await AppDatabase.instance;

    // 1. النقد الذي دخل فعلياً الصندوق من فواتير المبيعات المكتملة.
    // MIN(paid_amount, total) = ما استُلم واستقر في الصندوق:
    // - فاتورة نقدية كاملة: paid >= total → total (الباقي أُعيد للعميل فوراً).
    // - فاتورة آجلة أو مدفوعة جزئياً: paid < total → الجزء المسدد نقداً فقط.
    final salesCashRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(MIN(paid_amount, total)), 0.0) as cash_from_sales
      FROM sale_invoices
      WHERE status = 'completed'
    ''',
    );
    final cashFromSales =
        (salesCashRes.first['cash_from_sales'] as num?)?.toDouble() ?? 0.0;

    // 2. تحصيلات وسدادات ديون العملاء النقدية (سندات القبض الواردة).
    final collectionsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as collections_in
      FROM payments
      WHERE direction = 'in' AND party_type = 'customer'
    ''',
    );
    final collectionsIn =
        (collectionsRes.first['collections_in'] as num?)?.toDouble() ?? 0.0;

    // 3. نقد مسترد من الموردين عند رد بضاعة نقداً (سندات قبض من موردين).
    final supplierRefundsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as supplier_refunds_in
      FROM payments
      WHERE direction = 'in' AND party_type = 'supplier'
    ''',
    );
    final supplierRefundsIn =
        (supplierRefundsRes.first['supplier_refunds_in'] as num?)?.toDouble() ??
            0.0;

    // 4. مدفوعات الموردين الخارجة من الصندوق (عند الشراء أو سداد حسابات سابقة).
    final supplierPaymentsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as supplier_out
      FROM payments
      WHERE direction = 'out'
    ''',
    );
    final supplierPaymentsOut =
        (supplierPaymentsRes.first['supplier_out'] as num?)?.toDouble() ?? 0.0;

    // 5. المصروفات التشغيلية المسجلة (إيجار، رواتب، كهرباء، صيانة...).
    final expensesRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as expenses_out
      FROM expenses
    ''',
    );
    final expensesOut =
        (expensesRes.first['expenses_out'] as num?)?.toDouble() ?? 0.0;

    // 6. المرتجعات النقدية الخارجة من الصندوق للعملاء.
    // المرتجع يُخصم أولاً من دين العميل، وما زاد يُردّ له نقداً من الصندوق.
    final returnsRefundRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(return_amount - debt_reduction), 0.0) as returns_refund_out
      FROM return_invoices
      WHERE (return_amount - debt_reduction) > 0
    ''',
    );
    final returnsRefundOut =
        (returnsRefundRes.first['returns_refund_out'] as num?)?.toDouble() ??
            0.0;

    // 7. تقييم المخزون الحالي بالتكلفة التاريخية (سعر الشراء) وفقاً للمعاير المحاسبية.
    final inventoryRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity * purchase_price), 0.0) as inventory_value
      FROM products
      WHERE quantity > 0
    ''',
    );
    final inventoryValue =
        (inventoryRes.first['inventory_value'] as num?)?.toDouble() ?? 0.0;

    // 8. حسابات العملاء:
    // - ديون العملاء (لنا / ذمم مدينة): balance_due > 0
    // - أرصدة دائنة للعملاء (أمانات/دفعات زائدة): balance_due < 0
    final customerRes = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(CASE WHEN balance_due > 0 THEN balance_due ELSE 0.0 END), 0.0) as customer_debt,
        COALESCE(SUM(CASE WHEN balance_due < 0 THEN -balance_due ELSE 0.0 END), 0.0) as customer_credit
      FROM customers
    ''',
    );
    final customerDebt =
        (customerRes.first['customer_debt'] as num?)?.toDouble() ?? 0.0;
    final customerCredit =
        (customerRes.first['customer_credit'] as num?)?.toDouble() ?? 0.0;

    // 9. حسابات الموردين:
    // - مستحقات الموردين (علينا / ذمم دائنة): balance_owed > 0
    // - دفعات مقدمة للموردين (لنا طرف المورد): balance_owed < 0
    final supplierRes = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(CASE WHEN balance_owed > 0 THEN balance_owed ELSE 0.0 END), 0.0) as supplier_owed,
        COALESCE(SUM(CASE WHEN balance_owed < 0 THEN -balance_owed ELSE 0.0 END), 0.0) as supplier_advance
      FROM suppliers
    ''',
    );
    final supplierOwed =
        (supplierRes.first['supplier_owed'] as num?)?.toDouble() ?? 0.0;
    final supplierAdvance =
        (supplierRes.first['supplier_advance'] as num?)?.toDouble() ?? 0.0;

    return ShopBalance(
      cashFromSales: cashFromSales,
      collectionsIn: collectionsIn,
      supplierRefundsIn: supplierRefundsIn,
      supplierPaymentsOut: supplierPaymentsOut,
      expensesOut: expensesOut,
      returnsRefundOut: returnsRefundOut,
      inventoryValue: inventoryValue,
      customerDebt: customerDebt,
      customerCredit: customerCredit,
      supplierOwed: supplierOwed,
      supplierAdvance: supplierAdvance,
    );
  }
}
