import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../models/return_invoice.dart';

/// مرتجع مرفق ببياناته القابلة للعرض (رقم الفاتورة الأصلية، العميل، العناصر).
class DetailedReturn {
  final ReturnInvoice invoice;
  final String originalInvoiceNumber;
  final String? customerName;
  final List<ReturnInvoiceItem> items;

  DetailedReturn({
    required this.invoice,
    required this.originalInvoiceNumber,
    this.customerName,
    this.items = const [],
  });
}

class ReturnRepository {
  final _uuid = const Uuid();

  Future<void> createReturnInvoice({
    required ReturnInvoice invoice,
    required List<ReturnInvoiceItem> items,
    bool isCashRefund = false,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. حساب التسوية وتحديث الحسابات:
      // إذا كان العميل نقدياً (customerId == null) أو تم اختيار رد نقدي من الخزينة:
      // - debtReduction = 0.0 (لا يُخصم من دين العميل).
      // - المبلغ يُردّ نقداً من الصندوق (cashRefundOut = returnAmount - debtReduction = returnAmount)
      // وإذا كان خصماً من حساب العميل (isCashRefund == false و customerId != null):
      // - debtReduction = returnAmount (يُخصم من حساب العميل لتخفيض دينه أو رصيده).
      // - cashRefundOut = 0.0 (لا يخرج نقد من الخزينة).
      final bool cashRefund = isCashRefund || invoice.customerId == null;
      final debtReduction = cashRefund ? 0.0 : invoice.returnAmount;
      final returnInvoice = invoice.copyWith(debtReduction: debtReduction);

      // 2. إدراج فاتورة المرتجع
      await txn.insert('return_invoices', returnInvoice.toMap());

      // 2.5. حلّ تكلفة كل صنف وقت البيع الأصلي (من عناصر الفاتورة الأصلية،
      // ومعها سعر الشراء الحالي احتياطاً) حتى يُخصم ربح المرتجع من الأرباح
      // بنفس قيمة الربح الذي حُسب عند البيع.
      final costRows = await txn.rawQuery(
        '''
        SELECT sii.product_id,
               COALESCE(sii.unit_cost, p.purchase_price) as unit_cost
        FROM sale_invoice_items sii
        JOIN products p ON sii.product_id = p.id
        WHERE sii.invoice_id = ?
        ''',
        [invoice.originalSaleInvoiceId],
      );
      final costByProduct = <String, double>{
        for (final r in costRows)
          r['product_id'] as String: (r['unit_cost'] as num?)?.toDouble() ?? 0.0,
      };

      // 3. إدراج عناصر المرتجع
      for (final item in items) {
        item.returnInvoiceId = invoice.id;
        item.unitCost ??= costByProduct[item.productId];
        await txn.insert('return_invoice_items', item.toMap());
      }

      // 4. حركة مخزنية موجبة وإعادة الأصناف للمخزون
      for (final item in items) {
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'return',
          'quantity_change': item.quantity,
          'reference_id': invoice.id,
          'note': 'مرتجع مبيعات - فاتورة رقم ${invoice.originalSaleInvoiceId}',
          'created_at': now.toIso8601String(),
        });

        // زيادة كمية المنتج في المخزن
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [item.quantity, now.toIso8601String(), item.productId],
        );
      }

      // 5. خصم قيمة المرتجع من حساب العميل (فقط عند التسوية على الحساب)
      if (!cashRefund && invoice.customerId != null && debtReduction > 0) {
        await txn.rawUpdate(
          'UPDATE customers SET balance_due = balance_due - ?, updated_at = ? WHERE id = ?',
          [debtReduction, now.toIso8601String(), invoice.customerId],
        );
      }

      // 6. توثيق العملية في سجل التدقيق مع بيان الأثر على الخزينة وحساب العميل
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'return_invoices',
        'record_id': invoice.id,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"return_amount": ${invoice.returnAmount}, "debt_reduction": $debtReduction, "cash_refund_out": ${returnInvoice.cashRefundOut}}',
        'user_id': userId,
        'note': cashRefund
            ? 'مرتجع مبيعات نقدي (صرف نقد من الخزينة: ${invoice.returnAmount.toStringAsFixed(0)} ج.م، إعادة للمخزون)'
            : 'مرتجع مبيعات آجل (خصم من حساب العميل: ${debtReduction.toStringAsFixed(0)} ج.م، إعادة للمخزون)',
        'created_at': now.toIso8601String(),
      });
    });
  }

  Future<List<ReturnInvoice>> getReturnsByCustomer(String customerId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'return_invoices',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => ReturnInvoice.fromMap(m)).toList();
  }

  Future<List<ReturnInvoice>> getReturnsByOriginalInvoice(String saleInvoiceId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'return_invoices',
      where: 'original_sale_invoice_id = ?',
      whereArgs: [saleInvoiceId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => ReturnInvoice.fromMap(m)).toList();
  }

  /// الكمية المرتجعة سابقاً لكل منتج في فاتورة بيع محددة.
  /// تُستخدم لمنع تجاوز إجمالي الكمية المباعة عند إنشاء مرتجع جديد.
  Future<Map<String, int>> getReturnedQuantitiesBySaleInvoice(
      String saleInvoiceId) async {
    final db = await AppDatabase.instance;
    final maps = await db.rawQuery(
      '''
      SELECT ri.original_sale_invoice_id, rii.product_id, SUM(rii.quantity) as qty
      FROM return_invoice_items rii
      JOIN return_invoices ri ON rii.return_invoice_id = ri.id
      WHERE ri.original_sale_invoice_id = ?
      GROUP BY rii.product_id
      ''',
      [saleInvoiceId],
    );
    return {
      for (final m in maps)
        m['product_id'] as String: (m['qty'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<ReturnInvoice>> getAllReturns() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'return_invoices',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => ReturnInvoice.fromMap(m)).toList();
  }

  /// مرتجع مع بياناته الكاملة (رقم الفاتورة الأصلية، اسم العميل، العناصر).
  /// يُستخدم في شاشة سجل المرتجعات وكشف حساب العميل لعرض تفاصيل قابلة للقراءة.
  Future<List<DetailedReturn>> getAllReturnsDetailed() async {
    final db = await AppDatabase.instance;
    final maps = await db.rawQuery('''
      SELECT ri.*,
             si.invoice_number as original_invoice_number,
             c.name as customer_name
      FROM return_invoices ri
      LEFT JOIN sale_invoices si ON si.id = ri.original_sale_invoice_id
      LEFT JOIN customers c ON c.id = ri.customer_id
      ORDER BY ri.created_at DESC
    ''');

    final results = <DetailedReturn>[];
    for (final m in maps) {
      final invoice = ReturnInvoice.fromMap(m);
      results.add(
        DetailedReturn(
          invoice: invoice,
          originalInvoiceNumber:
              m['original_invoice_number'] as String? ?? '—',
          customerName: m['customer_name'] as String?,
          items: await getReturnItems(invoice.id),
        ),
      );
    }
    return results;
  }

  Future<List<ReturnInvoiceItem>> getReturnItems(String returnInvoiceId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'return_invoice_items',
      where: 'return_invoice_id = ?',
      whereArgs: [returnInvoiceId],
    );
    return maps.map((m) => ReturnInvoiceItem.fromMap(m)).toList();
  }

  Future<double> getTotalReturnAmount({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;

    String query = 'SELECT COALESCE(SUM(return_amount), 0.0) as total FROM return_invoices WHERE 1=1';
    List<dynamic> args = [];

    if (startDate != null) {
      query += ' AND created_at >= ?';
      args.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      query += ' AND created_at <= ?';
      args.add(endDate.toIso8601String());
    }

    final result = await db.rawQuery(query, args);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<ReturnInvoice?> getReturnById(String returnId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'return_invoices',
      where: 'id = ?',
      whereArgs: [returnId],
    );
    if (maps.isEmpty) return null;

    final invoice = ReturnInvoice.fromMap(maps.first);
    final items = await getReturnItems(returnId);
    return invoice.copyWith(items: items);
  }
}
