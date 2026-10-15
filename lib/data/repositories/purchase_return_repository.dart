import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/purchase_return_invoice.dart';

class DetailedPurchaseReturn {
  final PurchaseReturnInvoice invoice;
  final String? originalInvoiceNumber;
  final String supplierName;
  final List<PurchaseReturnInvoiceItem> items;

  DetailedPurchaseReturn({
    required this.invoice,
    this.originalInvoiceNumber,
    required this.supplierName,
    this.items = const [],
  });
}

class PurchaseReturnRepository {
  final _uuid = const Uuid();

  Future<void> createPurchaseReturn({
    required PurchaseReturnInvoice invoice,
    required List<PurchaseReturnInvoiceItem> items,
    bool isCashRefund = false,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. حساب التسوية المحاسبية لمرتجع المشتريات:
      // - إذا كان رداً نقدياً (isCashRefund == true):
      //   المورد يسدد النقد فوراً للخزينة (cashRefundIn = returnAmount, debtReduction = 0)
      // - إذا كان تسوية على الحساب (isCashRefund == false):
      //   يُخصم المرتجع بالكامل من رصيد ومستحقات المورد (debtReduction = returnAmount, cashRefundIn = 0)
      final debtReduction = isCashRefund ? 0.0 : invoice.returnAmount;
      final cashRefundIn = isCashRefund ? invoice.returnAmount : 0.0;

      final returnInvoice = invoice.copyWith(
        debtReduction: debtReduction,
        cashRefundIn: cashRefundIn,
      );

      // 2. إدراج فاتورة المرتجع
      await txn.insert('purchase_return_invoices', returnInvoice.toMap());

      // 3. إدراج الأصناف وتخفيض المخزون
      for (final item in items) {
        item.returnInvoiceId = returnInvoice.id;
        await txn.insert('purchase_return_invoice_items', item.toMap());

        // حركة مخزنية سالبة (خروج البضاعة المرتجعة للمورد)
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'purchase_return',
          'quantity_change': -item.quantity,
          'reference_id': returnInvoice.id,
          'note': 'مرتجع مشتريات للمورد',
          'created_at': now.toIso8601String(),
        });

        // خصم الكمية من رصيد المنتج في المخزن
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
          [item.quantity, now.toIso8601String(), item.productId],
        );
      }

      // 4. تسوية حساب المورد أو الخزينة:
      if (!isCashRefund && debtReduction > 0) {
        // خصم قيمة المرتجع بالكامل من مستحقات المورد
        await txn.rawUpdate(
          'UPDATE suppliers SET balance_owed = balance_owed - ?, updated_at = ? WHERE id = ?',
          [debtReduction, now.toIso8601String(), invoice.supplierId],
        );
      } else if (isCashRefund && cashRefundIn > 0) {
        // تسجيل دفعة قبض نقدية واردة للخزينة من المورد
        final shortId = returnInvoice.id.length > 8 ? returnInvoice.id.substring(0, 8) : returnInvoice.id;
        await txn.insert('payments', {
          'id': _uuid.v4(),
          'party_type': 'supplier',
          'party_id': invoice.supplierId,
          'amount': cashRefundIn,
          'direction': 'in',
          'note': 'استرداد نقدي من مرتجع مشتريات للمورد (فاتورة #$shortId)',
          'created_at': now.toIso8601String(),
        });
      }

      // 5. توثيق العملية في سجل التدقيق
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchase_return_invoices',
        'record_id': returnInvoice.id,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"return_amount": ${returnInvoice.returnAmount}, "debt_reduction": $debtReduction, "cash_refund_in": $cashRefundIn, "reason": "${returnInvoice.reason}"}',
        'user_id': userId,
        'note': isCashRefund
            ? 'مرتجع مشتريات نقدي (استرداد نقد للخزينة: ${cashRefundIn.toStringAsFixed(0)} ج.م، خصم من المخزون)'
            : 'مرتجع مشتريات آجل (خصم من رصيد المورد: ${debtReduction.toStringAsFixed(0)} ج.م، خصم من المخزون)',
        'created_at': now.toIso8601String(),
      });
    });
  }

  Future<List<DetailedPurchaseReturn>> getAllPurchaseReturnsDetailed() async {
    final db = await AppDatabase.instance;
    final returnMaps = await db.rawQuery('''
      SELECT pri.*, s.name as supplier_name, pi.id as original_invoice_id
      FROM purchase_return_invoices pri
      JOIN suppliers s ON pri.supplier_id = s.id
      LEFT JOIN purchase_invoices pi ON pri.original_purchase_invoice_id = pi.id
      ORDER BY pri.created_at DESC
    ''');

    final List<DetailedPurchaseReturn> result = [];

    for (final m in returnMaps) {
      final returnId = m['id'] as String;
      final itemMaps = await db.query(
        'purchase_return_invoice_items',
        where: 'return_invoice_id = ?',
        whereArgs: [returnId],
      );

      final items =
          itemMaps.map((im) => PurchaseReturnInvoiceItem.fromMap(im)).toList();

      result.add(
        DetailedPurchaseReturn(
          invoice: PurchaseReturnInvoice.fromMap(m),
          originalInvoiceNumber: m['original_invoice_id'] != null
              ? (m['original_invoice_id'] as String).substring(0, 8)
              : null,
          supplierName: (m['supplier_name'] as String?) ?? 'مورد',
          items: items,
        ),
      );
    }

    return result;
  }

  Future<Map<String, int>> getReturnedQuantitiesByPurchaseInvoice(
    String purchaseInvoiceId,
  ) async {
    final db = await AppDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT prii.product_id, SUM(prii.quantity) as returned_qty
      FROM purchase_return_invoice_items prii
      JOIN purchase_return_invoices pri ON prii.return_invoice_id = pri.id
      WHERE pri.original_purchase_invoice_id = ?
      GROUP BY prii.product_id
    ''', [purchaseInvoiceId]);

    final result = <String, int>{};
    for (final r in rows) {
      final productId = r['product_id'] as String;
      final qty = (r['returned_qty'] as num?)?.toInt() ?? 0;
      result[productId] = qty;
    }
    return result;
  }

  Future<DetailedPurchaseReturn?> getPurchaseReturnWithItems(
    String returnInvoiceId,
  ) async {
    final db = await AppDatabase.instance;
    final returnMaps = await db.rawQuery('''
      SELECT pri.*, s.name as supplier_name, pi.id as original_invoice_id
      FROM purchase_return_invoices pri
      JOIN suppliers s ON pri.supplier_id = s.id
      LEFT JOIN purchase_invoices pi ON pri.original_purchase_invoice_id = pi.id
      WHERE pri.id = ?
      LIMIT 1
    ''', [returnInvoiceId]);

    if (returnMaps.isEmpty) return null;

    final m = returnMaps.first;
    final itemMaps = await db.query(
      'purchase_return_invoice_items',
      where: 'return_invoice_id = ?',
      whereArgs: [returnInvoiceId],
    );

    final items =
        itemMaps.map((im) => PurchaseReturnInvoiceItem.fromMap(im)).toList();

    return DetailedPurchaseReturn(
      invoice: PurchaseReturnInvoice.fromMap(m),
      originalInvoiceNumber: m['original_invoice_id'] != null
          ? (m['original_invoice_id'] as String).substring(0, 8)
          : null,
      supplierName: (m['supplier_name'] as String?) ?? 'مورد',
      items: items,
    );
  }
}

