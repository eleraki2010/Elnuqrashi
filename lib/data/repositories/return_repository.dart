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
    String? userId,
  }) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // 1. حساب مقدار المرتجع الذي يُسدّد به دين العميل (قبل الإدراج حتى
      //    تُحفظ القيمة الصحيحة في سطر المرتجع نفسه).
      // القاعدة المحاسبية: المرتجع يُسدّد به أولاً المتبقي على العميل من
      // فاتورته (إن بقي شيء)، وما زاد يُسلَّم للعميل نقداً من الصندوق:
      //   - فاتورة بها متبقٍ (آجل أو دفع جزئي): المرتجع يخفض الدين حتى
      //     حدّ المتبقي، والباقي يخرج نقداً.
      //   - فاتورة مدفوعة بالكامل: المرتجع بالكامل يخرج نقداً (debt_reduction=0).
      // المقدار المخصوم يُحفظ في `debt_reduction` ليبقى كشف الحساب والخزينة
      // متسقين حتى لو سدّد العميل باقي دينه لاحقاً.
      double debtReduction = 0.0;
      if (invoice.customerId != null) {
        final custMaps = await txn.query(
          'customers',
          columns: ['balance_due'],
          where: 'id = ?',
          whereArgs: [invoice.customerId],
          limit: 1,
        );
        final currentDebt =
            (custMaps.first['balance_due'] as num?)?.toDouble() ?? 0.0;
        if (currentDebt > 0.01 && invoice.returnAmount > 0) {
          debtReduction = invoice.returnAmount < currentDebt
              ? invoice.returnAmount
              : currentDebt;
        }
      }
      final cashOut = invoice.returnAmount - debtReduction;
      final returnInvoice = invoice.copyWith(debtReduction: debtReduction);

      // 2. Insert return invoice (بقيمة debt_reduction المحسوبة)
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

      // 3. Insert return items
      // مهم: ربط كل عنصر بمعرّف فاتورة المرتجع (كان يُحفظ فارغاً فتنكسر
      // استعلامات السجل والحماية من الإرجاع المزدوج).
      for (final item in items) {
        item.returnInvoiceId = invoice.id;
        item.unitCost ??= costByProduct[item.productId];
        await txn.insert('return_invoice_items', item.toMap());
      }

      // 4. Create stock movements (positive - items returned to stock)
      for (final item in items) {
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'return',
          'quantity_change': item.quantity,
          'reference_id': invoice.id,
          'note': 'مرتجع - فاتورة رقم ${invoice.originalSaleInvoiceId}',
          'created_at': DateTime.now().toIso8601String(),
        });

        // Update product quantity
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [item.quantity, DateTime.now().toIso8601String(), item.productId],
        );
      }

      // 5. خصم ما سُدّد به المرتجع من دين العميل.
      if (debtReduction > 0.01 && invoice.customerId != null) {
        await txn.rawUpdate(
          'UPDATE customers SET balance_due = balance_due - ?, updated_at = ? WHERE id = ?',
          [debtReduction, DateTime.now().toIso8601String(), invoice.customerId],
        );
      }

      // 6. Audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'return_invoices',
        'record_id': invoice.id,
        'action': 'create',
        'old_values': null,
        'new_values': '{"return_amount": ${invoice.returnAmount}, "debt_reduction": $debtReduction, "cash_out": $cashOut, "reason": "${invoice.reason}"}',
        'user_id': userId,
        'note': 'مرتجع من الفاتورة ${invoice.originalSaleInvoiceId} (خصم دين ${debtReduction.toStringAsFixed(0)}، نقد ${cashOut.toStringAsFixed(0)})',
        'created_at': DateTime.now().toIso8601String(),
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
