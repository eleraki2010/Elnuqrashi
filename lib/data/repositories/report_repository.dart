import '../../core/database/app_database.dart';

class TopProductItem {
  final String productName;
  final int totalQuantity;
  final double totalSales;
  final double totalProfit;

  TopProductItem({
    required this.productName,
    required this.totalQuantity,
    required this.totalSales,
    required this.totalProfit,
  });
}

class PeriodReportSummary {
  final double totalSales;
  final int totalInvoices;
  final double totalPurchases;
  final double totalGrossProfit;
  final double totalReturnProfit;
  final double totalReturns;
  final double totalExpenses;
  final double totalTax;
  final double salesBeforeTax;
  final List<TopProductItem> topSellingProducts;

  /// ربح المبيعات الصافي = أرباح الفواتير المكتملة − ربح الأصناف المرتجعة.
  /// (المرجع يُرجع البضاعة والربح المرافق لها، فلا يُحتسب في صافي الأرباح.)
  double get totalProfit => totalGrossProfit - totalReturnProfit;

  /// صافي المبيعات بعد خصم المرتجعات (الرقم المحاسبي الحقيقي).
  double get netSales => totalSales - totalReturns;

  /// صافي الربح الحقيقي بعد خصم المصروفات التشغيلية من ربح المبيعات.
  double get netProfitAfterExpenses => totalProfit - totalExpenses;

  PeriodReportSummary({
    required this.totalSales,
    required this.totalInvoices,
    required this.totalPurchases,
    required this.totalGrossProfit,
    this.totalReturnProfit = 0.0,
    this.totalReturns = 0.0,
    this.totalExpenses = 0.0,
    this.totalTax = 0.0,
    this.salesBeforeTax = 0.0,
    required this.topSellingProducts,
  });
}

class ReportRepository {
  Future<PeriodReportSummary> getReportForRange(DateTime start, DateTime end) async {
    final db = await AppDatabase.instance;
    final startStr = DateTime(start.year, start.month, start.day).toIso8601String();
    final endStr = DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String();

    // 1. Sales Summary & VAT
    final salesRes = await db.rawQuery('''
      SELECT 
        COUNT(*) as invoice_count,
        COALESCE(SUM(total), 0.0) as total_sales,
        COALESCE(SUM(tax), 0.0) as total_tax,
        COALESCE(SUM(subtotal), 0.0) as sales_before_tax
      FROM sale_invoices
      WHERE status = 'completed'
        AND created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);

    final totalSales = (salesRes.first['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (salesRes.first['total_tax'] as num?)?.toDouble() ?? 0.0;
    final salesBeforeTax = (salesRes.first['sales_before_tax'] as num?)?.toDouble() ?? 0.0;
    final invoiceCount = (salesRes.first['invoice_count'] as num?)?.toInt() ?? 0;

    // 2. Purchases Summary
    final purchasesRes = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(total), 0.0) as total_purchases
      FROM purchase_invoices
      WHERE created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);

    final totalPurchases = (purchasesRes.first['total_purchases'] as num?)?.toDouble() ?? 0.0;

    // 3. Gross Profit Calculation (Rule 9: (sale_price - purchase_price) * quantity_sold)
    final profitRes = await db.rawQuery('''
      SELECT 
        COALESCE(SUM((sii.unit_price - COALESCE(sii.unit_cost, p.purchase_price)) * sii.quantity), 0.0) as total_profit
      FROM sale_invoice_items sii
      JOIN sale_invoices si ON sii.invoice_id = si.id
      JOIN products p ON sii.product_id = p.id
      WHERE si.status = 'completed'
        AND si.created_at >= ? AND si.created_at <= ?
    ''', [startStr, endStr]);

    final discountsRes = await db.rawQuery('''
      SELECT COALESCE(SUM(discount), 0.0) as total_discounts
      FROM sale_invoices
      WHERE status = 'completed'
        AND created_at >= ? AND created_at <= ?
    ''', [startStr, endStr]);

    final totalDiscounts =
        (discountsRes.first['total_discounts'] as num?)?.toDouble() ?? 0.0;
    final totalGrossProfit =
        ((profitRes.first['total_profit'] as num?)?.toDouble() ?? 0.0) - totalDiscounts;

    // 3.5. Returns Summary (المرتجعات تقلل صافي المبيعات والأرباح)
    final returnsRes = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(return_amount), 0.0) as total_returns
      FROM return_invoices
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startStr, endStr],
    );

    final totalReturns =
        (returnsRes.first['total_returns'] as num?)?.toDouble() ?? 0.0;

    // 3.55. Return Profit (ربح الأصناف المرتجعة يُخصم من أرباح المبيعات)
    final returnProfitRes = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM((rii.unit_price - COALESCE(rii.unit_cost, p.purchase_price)) * rii.quantity), 0.0) as return_profit
      FROM return_invoice_items rii
      JOIN return_invoices ri ON rii.return_invoice_id = ri.id
      JOIN products p ON rii.product_id = p.id
      WHERE ri.created_at >= ? AND ri.created_at <= ?
    ''',
      [startStr, endStr],
    );

    final totalReturnProfit =
        (returnProfitRes.first['return_profit'] as num?)?.toDouble() ?? 0.0;

    // 3.6. Expenses Summary (المصروفات تُخصم من صافي الربح)
    final expensesRes = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(amount), 0.0) as total_expenses
      FROM expenses
      WHERE created_at >= ? AND created_at <= ?
    ''',
      [startStr, endStr],
    );

    final totalExpenses =
        (expensesRes.first['total_expenses'] as num?)?.toDouble() ?? 0.0;

    // 4. Top Selling Products (صافي: المبيعات − المرتجعات داخل الفترة)
    final topRes = await db.rawQuery('''
      SELECT
        p.name as product_name,
        COALESCE(s.qty, 0) - COALESCE(r.qty, 0) as total_quantity,
        COALESCE(s.sales, 0.0) - COALESCE(r.amount, 0.0) as total_sales,
        COALESCE(s.profit, 0.0) - COALESCE(r.profit, 0.0) as total_profit
      FROM products p
      LEFT JOIN (
        SELECT sii.product_id,
               SUM(sii.quantity) as qty,
               SUM(sii.line_total) as sales,
               SUM((sii.unit_price - COALESCE(sii.unit_cost, p2.purchase_price)) * sii.quantity) as profit
        FROM sale_invoice_items sii
        JOIN sale_invoices si ON sii.invoice_id = si.id
        JOIN products p2 ON sii.product_id = p2.id
        WHERE si.status = 'completed'
          AND si.created_at >= ? AND si.created_at <= ?
        GROUP BY sii.product_id
      ) s ON s.product_id = p.id
      LEFT JOIN (
        SELECT rii.product_id,
               SUM(rii.quantity) as qty,
               SUM(rii.line_total) as amount,
               SUM((rii.unit_price - COALESCE(rii.unit_cost, p3.purchase_price)) * rii.quantity) as profit
        FROM return_invoice_items rii
        JOIN return_invoices ri ON rii.return_invoice_id = ri.id
        JOIN products p3 ON rii.product_id = p3.id
        WHERE ri.created_at >= ? AND ri.created_at <= ?
        GROUP BY rii.product_id
      ) r ON r.product_id = p.id
      WHERE COALESCE(s.qty, 0) > 0 OR COALESCE(r.qty, 0) > 0
      ORDER BY total_quantity DESC
      LIMIT 10
    ''', [startStr, endStr, startStr, endStr]);

    final topProducts = topRes.map((m) {
      return TopProductItem(
        productName: m['product_name'] as String? ?? 'منتج',
        totalQuantity: (m['total_quantity'] as num?)?.toInt() ?? 0,
        totalSales: (m['total_sales'] as num?)?.toDouble() ?? 0.0,
        totalProfit: (m['total_profit'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    return PeriodReportSummary(
      totalSales: totalSales,
      totalInvoices: invoiceCount,
      totalPurchases: totalPurchases,
      totalGrossProfit: totalGrossProfit,
      totalReturnProfit: totalReturnProfit,
      totalReturns: totalReturns,
      totalExpenses: totalExpenses,
      totalTax: totalTax,
      salesBeforeTax: salesBeforeTax,
      topSellingProducts: topProducts,
    );
  }

  Future<PeriodReportSummary> getDailyReport(DateTime date) {
    return getReportForRange(date, date);
  }

  Future<PeriodReportSummary> getMonthlyReport(int year, int month) {
    final start = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0).day;
    final end = DateTime(year, month, lastDay);
    return getReportForRange(start, end);
  }
}
