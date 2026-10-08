import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/sale_invoice.dart';
import '../models/sale_invoice_item.dart';

class TodayStats {
  final double totalSales;
  final int invoiceCount;
  final double estimatedProfit;
  final List<DailySalesPoint> weeklySalesTrend;
  final double totalCustomerDebt;

  /// تفصيل طرق الدفع لليوم (كاش/محفظة مقابل الآجل).
  final double cashSales;
  final double creditSales;
  final int cashInvoiceCount;
  final int creditInvoiceCount;

  /// عمليات مالية أخرى تهم صاحب المحل في لوحة القيادة.
  final double todayReturns;
  final double purchasesToday;
  final double collectionsToday; // تحصيلات العملاء الداخلة للصندوق
  final double expensesToday; // المصروفات التشغيلية لليوم

  TodayStats({
    required this.totalSales,
    required this.invoiceCount,
    required this.estimatedProfit,
    required this.weeklySalesTrend,
    required this.totalCustomerDebt,
    this.cashSales = 0.0,
    this.creditSales = 0.0,
    this.cashInvoiceCount = 0,
    this.creditInvoiceCount = 0,
    this.todayReturns = 0.0,
    this.purchasesToday = 0.0,
    this.collectionsToday = 0.0,
    this.expensesToday = 0.0,
  });

  /// صافي المبيعات بعد خصم المرتجعات (الرقم المحاسبي الحقيقي).
  double get netSales => totalSales - todayReturns;

  /// صافي الربح بعد خصم المصروفات التشغيلية (الربح الحقيقي للمحل).
  double get netProfitAfterExpenses => estimatedProfit - expensesToday;
}

class DailySalesPoint {
  final String label;
  final double sales;
  final double profit;

  DailySalesPoint({
    required this.label,
    required this.sales,
    required this.profit,
  });
}

class TopSellingProduct {
  final String productId;
  final String productName;
  final double totalQuantity;
  final double totalRevenue;
  final double totalProfit;

  TopSellingProduct({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.totalProfit,
  });

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'total_quantity': totalQuantity,
      'total_revenue': totalRevenue,
      'total_profit': totalProfit,
    };
  }

  factory TopSellingProduct.fromMap(Map<String, dynamic> map) {
    return TopSellingProduct(
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (map['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (map['total_profit'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SaleRepository {
  final _uuid = const Uuid();

  Future<String> generateNextInvoiceNumber() async {
    final db = await AppDatabase.instance;
    final year = DateTime.now().year;

    // الترقيم: سنة + تسلسل من 4 أرقام (20260001) — يتجدد مع كل سنة،
    // ويُحسب بعدّ كل فواتير السنة بما فيها الملغاة لمنع التكرار.
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sale_invoices WHERE invoice_number LIKE ?",
      ['$year%'],
    );
    final count = ((result.first['count'] as num?)?.toInt() ?? 0) + 1;
    return '$year${count.toString().padLeft(4, '0')}';
  }

  Future<void> createSaleInvoice({
    required SaleInvoice invoice,
    required List<SaleInvoiceItem> items,
  }) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // 1. Insert invoice
      await txn.insert('sale_invoices', invoice.toMap());

      // 2. Insert invoice items & update inventory
      for (final item in items) {
        await txn.insert('sale_invoice_items', item.toMap());

        if (invoice.status == 'completed') {
          // Add negative stock movement
          await txn.insert('stock_movements', {
            'id': _uuid.v4(),
            'product_id': item.productId,
            'type': 'sale',
            'quantity_change': -item.quantity,
            'reference_id': invoice.id,
            'note': 'فاتورة مبيعات رقم ${invoice.invoiceNumber}',
            'created_at': invoice.createdAt.toIso8601String(),
          });

          // Deduct quantity from product
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
            [item.quantity, DateTime.now().toIso8601String(), item.productId],
          );
        }
      }

      // 3. تسجيل المتبقي على العميل كدين (balance_due).
      // القاعدة المحاسبية: كل مبلغ غير مسدد ومربوط بعميل يجب أن يظهر
      // في حسابه — سواء كانت الفاتورة آجلة أو نقدية/محفظة دُفع جزئياً.
      // هكذا تتوازن المعادلة: المخزون الخارج = نقد داخل + ذمم مدينة.
      if (invoice.customerId != null) {
        final remainingDebt = invoice.total - invoice.paidAmount;
        if (remainingDebt > 0) {
          await txn.rawUpdate(
            'UPDATE customers SET balance_due = balance_due + ?, updated_at = ? WHERE id = ?',
            [
              remainingDebt,
              DateTime.now().toIso8601String(),
              invoice.customerId,
            ],
          );
        }
      }

      // 4. توثيق إنشاء الفاتورة في سجل العمليات مع المستخدم المتخذ للقرار.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sale_invoices',
        'record_id': invoice.id,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"invoice_number": "${invoice.invoiceNumber}", "status": "${invoice.status}", "total": ${invoice.total}, "paid_amount": ${invoice.paidAmount}, "payment_method": "${invoice.paymentMethod}"}',
        'user_id': invoice.cashierId,
        'note': invoice.status == 'held'
            ? 'تعليق فاتورة رقم ${invoice.invoiceNumber}'
            : 'إنشاء فاتورة مبيعات رقم ${invoice.invoiceNumber}',
        'created_at': invoice.createdAt.toIso8601String(),
      });
    });
  }

  Future<List<SaleInvoice>> getAllSaleInvoices() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'sale_invoices',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => SaleInvoice.fromMap(m)).toList();
  }

  Future<SaleInvoice?> getSaleInvoiceWithItems(String invoiceId) async {
    final db = await AppDatabase.instance;

    final invoiceMaps = await db.rawQuery(
      '''
      SELECT si.*, c.name as customer_name
      FROM sale_invoices si
      LEFT JOIN customers c ON si.customer_id = c.id
      WHERE si.id = ?
    ''',
      [invoiceId],
    );

    if (invoiceMaps.isEmpty) return null;

    final itemsMaps = await db.rawQuery(
      '''
      SELECT sii.*, p.name as product_name
      FROM sale_invoice_items sii
      LEFT JOIN products p ON sii.product_id = p.id
      WHERE sii.invoice_id = ?
    ''',
      [invoiceId],
    );

    final items = itemsMaps.map((m) => SaleInvoiceItem.fromMap(m)).toList();
    return SaleInvoice.fromMap(invoiceMaps.first, items: items);
  }

  Future<TodayStats> getTodayStats() async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    ).toIso8601String();

    final invoiceResult = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as invoice_count,
        COALESCE(SUM(total), 0.0) as total_sales
      FROM sale_invoices
      WHERE status = 'completed'
        AND created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );

    final profitResult = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM((sii.unit_price - COALESCE(sii.unit_cost, p.purchase_price)) * sii.quantity), 0.0) as total_profit
      FROM sale_invoice_items sii
      JOIN sale_invoices si ON sii.invoice_id = si.id
      JOIN products p ON sii.product_id = p.id
      WHERE si.status = 'completed'
        AND si.created_at >= ? AND si.created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );

    final count = (invoiceResult.first['invoice_count'] as num?)?.toInt() ?? 0;
    final sales =
        (invoiceResult.first['total_sales'] as num?)?.toDouble() ?? 0.0;
    final profit =
        (profitResult.first['total_profit'] as num?)?.toDouble() ?? 0.0;

    // تفصيل المبيعات حسب طريقة الدفع (كاش/محفظة مقابل آجل).
    final methodRes = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN payment_method = 'credit' THEN total ELSE 0 END), 0.0) as credit_sales,
        COALESCE(SUM(CASE WHEN payment_method != 'credit' THEN total ELSE 0 END), 0.0) as cash_sales,
        SUM(CASE WHEN payment_method = 'credit' THEN 1 ELSE 0 END) as credit_count,
        SUM(CASE WHEN payment_method != 'credit' THEN 1 ELSE 0 END) as cash_count
      FROM sale_invoices
      WHERE status = 'completed'
        AND created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final creditSales =
        (methodRes.first['credit_sales'] as num?)?.toDouble() ?? 0.0;
    final cashSales =
        (methodRes.first['cash_sales'] as num?)?.toDouble() ?? 0.0;
    final creditCount =
        (methodRes.first['credit_count'] as num?)?.toInt() ?? 0;
    final cashCount =
        (methodRes.first['cash_count'] as num?)?.toInt() ?? 0;

    // مرتجعات اليوم (تخصم من صافي المبيعات).
    final returnsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(return_amount), 0.0) as today_returns
      FROM return_invoices
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final todayReturns =
        (returnsRes.first['today_returns'] as num?)?.toDouble() ?? 0.0;

    // ربح الأصناف المرتجعة اليوم (يُخصم من أرباح اليوم حتى لا يتضخم الربح
    // بربح بضاعة أُرجعت — نفس قاعدة تقرير الفترات).
    final returnProfitRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM((rii.unit_price - COALESCE(rii.unit_cost, p.purchase_price)) * rii.quantity), 0.0) as today_return_profit
      FROM return_invoice_items rii
      JOIN return_invoices ri ON rii.return_invoice_id = ri.id
      JOIN products p ON rii.product_id = p.id
      WHERE ri.created_at >= ? AND ri.created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final todayReturnProfit = (returnProfitRes.first['today_return_profit'] as num?)?.toDouble() ?? 0.0;

    // مشتريات اليوم (تدفق نقدي خارج للبضاعة).
    final purchasesRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0.0) as purchases_today
      FROM purchase_invoices
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final purchasesToday =
        (purchasesRes.first['purchases_today'] as num?)?.toDouble() ?? 0.0;

    // تحصيلات العملاء الداخلة للصندوق اليوم.
    final collectionsRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as collections_today
      FROM payments
      WHERE direction = 'in'
        AND created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final collectionsToday =
        (collectionsRes.first['collections_today'] as num?)?.toDouble() ?? 0.0;

    // المصروفات التشغيلية اليوم (تُخصم من صافي الربح).
    final expensesRes = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as expenses_today
      FROM expenses
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startOfDay, endOfDay],
    );
    final expensesToday =
        (expensesRes.first['expenses_today'] as num?)?.toDouble() ?? 0.0;

    final weeklyTrend = await _getWeeklySalesTrend(db);
    final totalDebt = await _getTotalCustomerDebt(db);

    return TodayStats(
      totalSales: sales,
      invoiceCount: count,
      estimatedProfit: profit - todayReturnProfit,
      weeklySalesTrend: weeklyTrend,
      totalCustomerDebt: totalDebt,
      cashSales: cashSales,
      creditSales: creditSales,
      cashInvoiceCount: cashCount,
      creditInvoiceCount: creditCount,
      todayReturns: todayReturns,
      purchasesToday: purchasesToday,
      collectionsToday: collectionsToday,
      expensesToday: expensesToday,
    );
  }

  Future<List<DailySalesPoint>> _getWeeklySalesTrend(DatabaseExecutor db) async {
    final now = DateTime.now();
    final List<DailySalesPoint> trend = [];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final startOfDay = DateTime(day.year, day.month, day.day).toIso8601String();
      final endOfDay = DateTime(
        day.year,
        day.month,
        day.day,
        23,
        59,
        59,
      ).toIso8601String();

      final salesResult = await db.rawQuery(
        '''
        SELECT 
          COALESCE(SUM(total), 0.0) as daily_sales
        FROM sale_invoices
        WHERE status = 'completed'
          AND created_at >= ? AND created_at <= ?
        ''',
        [startOfDay, endOfDay],
      );

      // الربح يُحسب من عناصر الفواتير (كل عنصر صف مستقل، فلا تضاعف).
      final profitResult = await db.rawQuery(
        '''
        SELECT 
          COALESCE(SUM((sii.unit_price - COALESCE(sii.unit_cost, p.purchase_price)) * sii.quantity), 0.0) as daily_profit
        FROM sale_invoice_items sii
        JOIN sale_invoices si ON si.id = sii.invoice_id
        JOIN products p ON sii.product_id = p.id
        WHERE si.status = 'completed'
          AND si.created_at >= ? AND si.created_at <= ?
        ''',
        [startOfDay, endOfDay],
      );

      final row = salesResult.first;
      final dailySales = (row['daily_sales'] as num?)?.toDouble() ?? 0.0;
      final dailyProfit =
          (profitResult.first['daily_profit'] as num?)?.toDouble() ?? 0.0;

      trend.add(DailySalesPoint(
        label: _formatDayLabel(day, now),
        sales: dailySales,
        profit: dailyProfit,
      ));
    }

    return trend;
  }

  static String _formatDayLabel(DateTime day, DateTime now) {
    final diff = now.difference(DateTime(day.year, day.month, day.day)).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${day.day}/${day.month}';
  }

  Future<double> _getTotalCustomerDebt(DatabaseExecutor db) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(balance_due), 0.0) as total_debt FROM customers WHERE balance_due > 0",
    );
    return (result.first['total_debt'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<TopSellingProduct>> getTopSellingProducts({int limit = 5}) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day - now.weekday + 1,
    ).toIso8601String();

    final result = await db.rawQuery(
      '''
      SELECT 
        p.id as product_id,
        p.name as product_name,
        SUM(sii.quantity) as total_quantity,
        SUM(sii.quantity * sii.unit_price) as total_revenue,
        SUM(sii.quantity * (sii.unit_price - COALESCE(sii.unit_cost, p.purchase_price))) as total_profit
      FROM sale_invoice_items sii
      JOIN sale_invoices si ON sii.invoice_id = si.id
      JOIN products p ON sii.product_id = p.id
      WHERE si.status = 'completed'
        AND si.created_at >= ?
      GROUP BY p.id, p.name
      ORDER BY total_revenue DESC
      LIMIT ?
      ''',
      [startOfWeek, limit],
    );

    return result.map((m) => TopSellingProduct.fromMap(m)).toList();
  }

  Future<void> cancelSaleInvoice(String invoiceId, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // Get invoice with items
      final invoiceMaps = await txn.query(
        'sale_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceMaps.isEmpty) return;

      final invoice = SaleInvoice.fromMap(invoiceMaps.first);
      if (invoice.status != 'completed') {
        // فقط الفواتير المكتملة تُخصم من المخزون أصلاً؛ غيرها لا يُعاد له شيء.
        return;
      }

      final itemsMaps = await txn.query(
        'sale_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final items = itemsMaps.map((m) => SaleInvoiceItem.fromMap(m)).toList();

      // Soft delete: status = cancelled
      await txn.update(
        'sale_invoices',
        {'status': 'cancelled'},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // Audit log entry (Rule 11)
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sale_invoices',
        'record_id': invoiceId,
        'action': 'cancel',
        'old_values': null,
        'new_values': '{"status": "cancelled"}',
        'user_id': userId,
        'note': 'إلغاء فاتورة مبيعات رقم ${invoice.invoiceNumber}',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Restore stock quantities
      for (final item in items) {
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'adjustment',
          'quantity_change': item.quantity,
          'reference_id': invoice.id,
          'note': 'إلغاء فاتورة مبيعات رقم ${invoice.invoiceNumber}',
          'created_at': DateTime.now().toIso8601String(),
        });

        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [item.quantity, DateTime.now().toIso8601String(), item.productId],
        );
      }

      // Reverse customer debt for any unpaid remainder (credit or partial cash/wallet).
      // عكس أي متبقٍ غير مسدد مسجّل على العميل (آجل أو دفع جزئي).
      if (invoice.customerId != null) {
        final remainingDebt = invoice.total - invoice.paidAmount;
        if (remainingDebt > 0) {
          await txn.rawUpdate(
            'UPDATE customers SET balance_due = balance_due - ?, updated_at = ? WHERE id = ?',
            [
              remainingDebt,
              DateTime.now().toIso8601String(),
              invoice.customerId,
            ],
          );
        }
      }
    });
  }
  /// استرجاع فاتورة ملغاة: يعيدها كفاتورة "معلّقة" (مسودة قابلة للتحرير)
  /// فيظهر زر "تحرير" في شاشة المبيعات، فتُحمَّل في عربة البيع لتعديلها
  /// وإتمامها كفاتورة جديدة.
  ///
  /// لماذا "المعلّقة" وليس "المكتملة"؟
  /// - الإلغاء أعاد أصلًا الكميات للمخزن وعكس دين العميل.
  /// - الفاتورة المعلّقة لا تخصم مخزونًا (كالإنشاء الأصلي).
  /// - لكن يُعاد تسجيل دين المتبقي على العميل (القاعدة الموحدة: كل فاتورة
  ///   معلّقة بمتبقٍ دينها مسجَّل على حسابه). فالإلغاء عكس الدين أول مرة،
  ///   وعند تحميل المسودة في العربة تُحذف فيُعكس الدين مرة واحدة فقط —
  ///   دون إعادة تسجيل هنا يحدث عكس مزدوج من دين لم يُسجَّل.
  /// - تُستعاد آلية الفواتير المعلّقة المُختبرة (تحميل + إتمام) كما هي.
  ///
  /// حماية الدفاتر: لا يمكن استرجاع فاتورة عليها مرتجعات (يُحذف المرتجع أولاً).
  Future<void> restoreSaleInvoice(String invoiceId, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final invoiceMaps = await txn.query(
        'sale_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceMaps.isEmpty) return;

      final invoice = SaleInvoice.fromMap(invoiceMaps.first);
      if (invoice.status != 'cancelled') {
        throw StateError(
          'فقط الفواتير الملغاة يمكن استرجاعها (الحالة الحالية: ${invoice.statusArabic}).',
        );
      }

      // 1. منع استرجاع فاتورة عليها مرتجعات قبل حذف المرتجعات.
      final returnsCount = (await txn.query(
        'return_invoices',
        where: 'original_sale_invoice_id = ?',
        whereArgs: [invoiceId],
      )).length;
      if (returnsCount > 0) {
        throw StateError(
          'لا يمكن استرجاع الفاتورة ${invoice.invoiceNumber} لوجود $returnsCount مرتجع مرتبط بها. '
          'احذف المرتجعات أولاً من شاشة المرتجعات.',
        );
      }

      // 2. ملغاة → معلّقة: مسودة قابلة للتحرير. لا تُمسَّ الكميات
      //    (المخزون أعاده الإلغاء أصلاً، والمعلّقة لا تخصم مخزونًا).
      await txn.update(
        'sale_invoices',
        {'status': 'held'},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // 3. إعادة تسجيل دين المتبقي على العميل (إن وُجد): الإلغاء عكسه أول مرة،
      //    والقاعدة الموحدة أن دين كل فاتورة معلّقة مسجَّل على حساب عميلها
      //    — فيُعكس مرة واحدة فقط عند حذف المسودة لاحقًا (تحميلها في العربة)
      //    بدل العكس المزدوج من دين غير مسجَّل.
      double debtReadded = 0.0;
      if (invoice.customerId != null) {
        final remainingDebt = invoice.total - invoice.paidAmount;
        if (remainingDebt > 0) {
          debtReadded = remainingDebt;
          await txn.rawUpdate(
            'UPDATE customers SET balance_due = balance_due + ?, updated_at = ? WHERE id = ?',
            [
              remainingDebt,
              DateTime.now().toIso8601String(),
              invoice.customerId,
            ],
          );
        }
      }

      // 4. توثيق عملية الاسترجاع في سجل العمليات.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sale_invoices',
        'record_id': invoiceId,
        'action': 'restore',
        'old_values': '{"status": "cancelled"}',
        'new_values': '{"status": "held", "debt_readded": $debtReadded}',
        'user_id': userId,
        'note': 'استرجاع فاتورة ملغاة رقم ${invoice.invoiceNumber} للتحرير'
            '${debtReadded > 0 ? ' (إعادة تسجيل متبقيها ${debtReadded.toStringAsFixed(0)} على حساب العميل)' : ''}',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<SaleInvoice>> getInvoicesByStatus(String status) async {
    final db = await AppDatabase.instance;

    final maps = await db.query(
      'sale_invoices',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );

    // مهم: يجب جلب عناصر كل فاتورة، وإلا تُحمَّل الفاتورة المعلّقة فارغة
    // فلا يمكن استكمالها في شاشة البيع (regression سابق).
    final invoices = <SaleInvoice>[];
    for (final m in maps) {
      final itemMaps = await db.query(
        'sale_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [m['id']],
      );
      final items =
          itemMaps.map((im) => SaleInvoiceItem.fromMap(im)).toList();
      invoices.add(SaleInvoice.fromMap(m, items: items));
    }
    return invoices;
  }

  Future<List<SaleInvoice>> getAllSalesInvoices() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'sale_invoices',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => SaleInvoice.fromMap(m)).toList();
  }

  Future<SaleInvoice?> getInvoiceById(String invoiceId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'sale_invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
    if (maps.isEmpty) return null;

    final invoice = SaleInvoice.fromMap(maps.first);

    // Get items — مع اسم المنتج (product_name حقل عرض فقط غير محفوظ في
    // جدول العناصر): بدون JOIN تظهر productName null وتنكسر الشاشات
    // التي تعرضها (كشاشة المرتجعات تحديداً كانت تنهار على السطر
    // "(item as dynamic).productName as String").
    final itemMaps = await db.rawQuery(
      '''
      SELECT sii.*, p.name as product_name
      FROM sale_invoice_items sii
      LEFT JOIN products p ON p.id = sii.product_id
      WHERE sii.invoice_id = ?
      ''',
      [invoiceId],
    );

    final items = itemMaps.map((m) => SaleInvoiceItem.fromMap(m)).toList();
    return invoice.copyWith(items: items);
  }

  Future<SaleInvoice?> getSaleInvoiceById(String invoiceId) async {
    return getInvoiceById(invoiceId);
  }

  /// حذف فاتورة من السجل مع عكس كل آثارها المالية والمخزنية.
  ///
  /// القواعد (حماية الدفاتر):
  /// - الفاتورة المعلّقة (held): تُحذف مباشرة (مسودة) مع عكس دين العميل إن
  ///   كانت آجلة.
  /// - الفاتورة المكتملة التي استُلم عليها نقد (paid_amount > 0): لا تُحذف
  ///   إلا بعد تصفير حساب العميل (balance_due == 0) لئلا تضيع أموال حُصّلت.
  /// - لا يمكن حذف فاتورة عليها مرتجعات قبل حذف المرتجعات.
  Future<void> deleteSaleInvoice(String invoiceId, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final invoiceMaps = await txn.query(
        'sale_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceMaps.isEmpty) return;

      final invoice = SaleInvoice.fromMap(invoiceMaps.first);

      // 1. منع حذف فاتورة عليها مرتجعات (قيد RESTRICT في قاعدة البيانات).
      final returnsCount = (await txn.query(
        'return_invoices',
        where: 'original_sale_invoice_id = ?',
        whereArgs: [invoiceId],
      )).length;
      if (returnsCount > 0) {
        throw StateError(
          'لا يمكن حذف الفاتورة ${invoice.invoiceNumber} لوجود $returnsCount مرتجع مرتبط بها. '
          'احذف المرتجعات أولاً من شاشة المرتجعات.',
        );
      }

      // 2. فاتورة مكتملة عليها نقد → تتطلب تصفير حساب العميل أولاً.
      if (invoice.status == 'completed' && invoice.paidAmount > 0) {
        if (invoice.customerId == null) {
          throw StateError(
            'لا يمكن حذف الفاتورة ${invoice.invoiceNumber} لأنها فاتورة نقدية '
            'استُلم عليها مبلغ ${invoice.paidAmount.toStringAsFixed(0)} ج.م '
            'وليست مرتبطة بحساب عملف. استخدم "إلغاء الفاتورة" بدلاً من الحذف.',
          );
        }
        final customerMaps = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [invoice.customerId],
          limit: 1,
        );
        if (customerMaps.isNotEmpty) {
          final balanceDue =
              (customerMaps.first['balance_due'] as num?)?.toDouble() ?? 0.0;
          if (balanceDue.abs() > 0.005) {
            throw StateError(
              'لا يمكن حذف الفاتورة ${invoice.invoiceNumber} قبل تصفير حساب العميل. '
              'الرصيد المستحق على العميل حالياً ${balanceDue.toStringAsFixed(0)} ج.م. '
              'قم بتحصيل المديونية أولاً من شاشة المدفوعات.',
            );
          }
        }
      }

      // 3. عكس دين العميل (أي متبقٍ غير مسدد: آجل أو دفع جزئي).
      if (invoice.customerId != null) {
        final remainingDebt = invoice.total - invoice.paidAmount;
        if (remainingDebt > 0) {
          await txn.rawUpdate(
            'UPDATE customers SET balance_due = balance_due - ?, updated_at = ? WHERE id = ?',
            [
              remainingDebt,
              DateTime.now().toIso8601String(),
              invoice.customerId,
            ],
          );
        }
      }

      // 4. إعادة كميات الفاتورة المكتملة إلى المخزن.
      if (invoice.status == 'completed') {
        final itemMaps = await txn.query(
          'sale_invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        for (final im in itemMaps) {
          final qty = (im['quantity'] as num?)?.toDouble() ?? 0.0;
          final productId = im['product_id'] as String;
          await txn.insert('stock_movements', {
            'id': _uuid.v4(),
            'product_id': productId,
            'type': 'adjustment',
            'quantity_change': qty,
            'reference_id': invoice.id,
            'note': 'حذف فاتورة مبيعات رقم ${invoice.invoiceNumber}',
            'created_at': DateTime.now().toIso8601String(),
          });
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
            [qty, DateTime.now().toIso8601String(), productId],
          );
        }
      }

      // 5. حذف الفاتورة (العناصر تُحذف تلقائياً عبر ON DELETE CASCADE).
      await txn.delete(
        'sale_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // 6. توثيق عملية الحذف في سجل العمليات مع المستخدم المتخذ للقرار.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sale_invoices',
        'record_id': invoiceId,
        'action': 'delete',
        'old_values':
            '{"invoice_number": "${invoice.invoiceNumber}", "status": "${invoice.status}", "total": ${invoice.total}, "paid_amount": ${invoice.paidAmount}}',
        'new_values': null,
        'user_id': userId,
        'note': 'حذف فاتورة ${invoice.statusArabic} رقم ${invoice.invoiceNumber}',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }
}
