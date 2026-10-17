import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';

class PurchaseRepository {
  final _uuid = const Uuid();

  Future<void> createPurchaseInvoice({
    required PurchaseInvoice invoice,
    required List<PurchaseInvoiceItem> items,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // 1. Insert Purchase Invoice
      await txn.insert('purchase_invoices', invoice.toMap());

      // 2. Insert Items & Auto update inventory
      for (final item in items) {
        await txn.insert('purchase_invoice_items', item.toMap());

        // Stock movement: positive
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'purchase',
          'quantity_change': item.quantity,
          'reference_id': invoice.id,
          'note': 'فاتورة شراء وتوريد بضاعة',
          'created_at': invoice.createdAt.toIso8601String(),
        });

        // Add quantity to product and update purchase_price
        await txn.rawUpdate(
          '''
          UPDATE products 
          SET quantity = quantity + ?, purchase_price = ?, updated_at = ? 
          WHERE id = ?
        ''',
          [
            item.quantity,
            item.unitCost,
            DateTime.now().toIso8601String(),
            item.productId,
          ],
        );
      }

      // 3. If credit purchase, add to supplier balance_owed
      final debtToSupplier = invoice.total - invoice.paidAmount;
      if (debtToSupplier > 0) {
        await txn.rawUpdate(
          '''
          UPDATE suppliers 
          SET balance_owed = balance_owed + ?, updated_at = ? 
          WHERE id = ?
        ''',
          [
            debtToSupplier,
            DateTime.now().toIso8601String(),
            invoice.supplierId,
          ],
        );
      }

      // 4. If paid amount > 0, record payment
      if (invoice.paidAmount > 0) {
        await txn.insert('payments', {
          'id': _uuid.v4(),
          'party_type': 'supplier',
          'party_id': invoice.supplierId,
          'amount': invoice.paidAmount,
          'direction': 'out',
          'created_at': invoice.createdAt.toIso8601String(),
        });
      }

      // 5. توثيق فاتورة الشراء في سجل العمليات مع المستخدم المتخذ للقرار.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchase_invoices',
        'record_id': invoice.id,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"total": ${invoice.total}, "paid_amount": ${invoice.paidAmount}}',
        'user_id': userId,
        'note': 'تسجيل فاتورة شراء (توريد بضاعة)',
        'created_at': invoice.createdAt.toIso8601String(),
      });
    });
  }

  Future<List<PurchaseInvoice>> getAllPurchaseInvoices() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT pi.*, s.name as supplier_name
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON pi.supplier_id = s.id
      ORDER BY pi.created_at DESC
    ''');

    return maps
        .map(
          (m) => PurchaseInvoice.fromMap(
            m,
            supplierName: m['supplier_name'] as String?,
          ),
        )
        .toList();
  }

  Future<PurchaseInvoice?> getPurchaseInvoiceWithItems(String invoiceId) async {
    final db = await AppDatabase.instance;

    final invoiceMaps = await db.rawQuery(
      '''
      SELECT pi.*, s.name as supplier_name
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON pi.supplier_id = s.id
      WHERE pi.id = ?
      LIMIT 1
    ''',
      [invoiceId],
    );

    if (invoiceMaps.isEmpty) return null;

    final itemsMaps = await db.rawQuery(
      '''
      SELECT pii.*, p.name as product_name
      FROM purchase_invoice_items pii
      LEFT JOIN products p ON pii.product_id = p.id
      WHERE pii.invoice_id = ?
    ''',
      [invoiceId],
    );

    final items = itemsMaps.map((m) => PurchaseInvoiceItem.fromMap(m)).toList();
    return PurchaseInvoice.fromMap(
      invoiceMaps.first,
      items: items,
      supplierName: invoiceMaps.first['supplier_name'] as String?,
    );
  }

  /// حذف فاتورة شراء مع استرجاع حركة المخزون وعكس مديونية المورد (للأدمن فقط)
  Future<void> deletePurchaseInvoice(String invoiceId, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final invoiceMaps = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceMaps.isEmpty) return;
      final invoiceMap = invoiceMaps.first;
      final total = (invoiceMap['total'] as num).toDouble();
      final paidAmount = (invoiceMap['paid_amount'] as num).toDouble();
      final supplierId = invoiceMap['supplier_id'] as String;
      final createdAt = invoiceMap['created_at'] as String;

      final itemMaps = await txn.query(
        'purchase_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );

      for (final im in itemMaps) {
        final productId = im['product_id'] as String;
        final qty = im['quantity'] as int;

        await txn.rawUpdate(
          '''
          UPDATE products 
          SET quantity = CASE WHEN quantity >= ? THEN quantity - ? ELSE 0 END,
              updated_at = ?
          WHERE id = ?
          ''',
          [qty, qty, DateTime.now().toIso8601String(), productId],
        );
      }

      final debtToSupplier = total - paidAmount;
      if (debtToSupplier > 0) {
        await txn.rawUpdate(
          '''
          UPDATE suppliers
          SET balance_owed = CASE WHEN balance_owed >= ? THEN balance_owed - ? ELSE 0.0 END,
              updated_at = ?
          WHERE id = ?
          ''',
          [debtToSupplier, debtToSupplier, DateTime.now().toIso8601String(), supplierId],
        );
      }

      if (paidAmount > 0) {
        await txn.delete(
          'payments',
          where: 'party_type = ? AND party_id = ? AND amount = ? AND created_at = ?',
          whereArgs: ['supplier', supplierId, paidAmount, createdAt],
        );
      }

      await txn.delete(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [invoiceId],
      );

      await txn.delete(
        'purchase_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );

      await txn.delete(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchase_invoices',
        'record_id': invoiceId,
        'action': 'delete',
        'old_values': '{"total": $total, "paid_amount": $paidAmount}',
        'new_values': null,
        'user_id': userId,
        'note': 'حذف فاتورة شراء وتوريد بضاعة وعكس كميات المخزن ورصيد المورد',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// تعديل فاتورة شراء مع إعادة ضبط الكميات ورصيد المورد (للأدمن فقط)
  Future<void> updatePurchaseInvoice({
    required PurchaseInvoice invoice,
    required List<PurchaseInvoiceItem> items,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final oldInvoiceMaps = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: [invoice.id],
        limit: 1,
      );
      if (oldInvoiceMaps.isEmpty) return;
      final oldInvoice = oldInvoiceMaps.first;
      final oldTotal = (oldInvoice['total'] as num).toDouble();
      final oldPaid = (oldInvoice['paid_amount'] as num).toDouble();
      final oldSupplierId = oldInvoice['supplier_id'] as String;
      final oldCreatedAt = oldInvoice['created_at'] as String;

      final oldItemMaps = await txn.query(
        'purchase_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoice.id],
      );
      for (final oldIm in oldItemMaps) {
        final pId = oldIm['product_id'] as String;
        final q = oldIm['quantity'] as int;
        await txn.rawUpdate(
          '''
          UPDATE products 
          SET quantity = CASE WHEN quantity >= ? THEN quantity - ? ELSE 0 END,
              updated_at = ?
          WHERE id = ?
          ''',
          [q, q, DateTime.now().toIso8601String(), pId],
        );
      }

      final oldDebt = oldTotal - oldPaid;
      if (oldDebt > 0) {
        await txn.rawUpdate(
          '''
          UPDATE suppliers
          SET balance_owed = CASE WHEN balance_owed >= ? THEN balance_owed - ? ELSE 0.0 END,
              updated_at = ?
          WHERE id = ?
          ''',
          [oldDebt, oldDebt, DateTime.now().toIso8601String(), oldSupplierId],
        );
      }

      if (oldPaid > 0) {
        await txn.delete(
          'payments',
          where: 'party_type = ? AND party_id = ? AND amount = ? AND created_at = ?',
          whereArgs: ['supplier', oldSupplierId, oldPaid, oldCreatedAt],
        );
      }

      await txn.delete(
        'purchase_invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoice.id],
      );
      await txn.delete(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [invoice.id],
      );

      await txn.update(
        'purchase_invoices',
        invoice.toMap(),
        where: 'id = ?',
        whereArgs: [invoice.id],
      );

      for (final item in items) {
        await txn.insert('purchase_invoice_items', item.toMap());

        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': item.productId,
          'type': 'purchase',
          'quantity_change': item.quantity,
          'reference_id': invoice.id,
          'note': 'تعديل فاتورة شراء وتوريد بضاعة',
          'created_at': invoice.createdAt.toIso8601String(),
        });

        await txn.rawUpdate(
          '''
          UPDATE products 
          SET quantity = quantity + ?, purchase_price = ?, updated_at = ? 
          WHERE id = ?
          ''',
          [
            item.quantity,
            item.unitCost,
            DateTime.now().toIso8601String(),
            item.productId,
          ],
        );
      }

      final newDebt = invoice.total - invoice.paidAmount;
      if (newDebt > 0) {
        await txn.rawUpdate(
          '''
          UPDATE suppliers 
          SET balance_owed = balance_owed + ?, updated_at = ? 
          WHERE id = ?
          ''',
          [
            newDebt,
            DateTime.now().toIso8601String(),
            invoice.supplierId,
          ],
        );
      }

      if (invoice.paidAmount > 0) {
        await txn.insert('payments', {
          'id': _uuid.v4(),
          'party_type': 'supplier',
          'party_id': invoice.supplierId,
          'amount': invoice.paidAmount,
          'direction': 'out',
          'note': 'سداد نقدي لفاتورة شراء معدلة',
          'created_at': invoice.createdAt.toIso8601String(),
        });
      }

      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchase_invoices',
        'record_id': invoice.id,
        'action': 'update',
        'old_values': '{"total": $oldTotal, "paid_amount": $oldPaid}',
        'new_values': '{"total": ${invoice.total}, "paid_amount": ${invoice.paidAmount}}',
        'user_id': userId,
        'note': 'تعديل فاتورة شراء وتوريد بضاعة وتحديث المخزن ورصيد المورد',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }
}
