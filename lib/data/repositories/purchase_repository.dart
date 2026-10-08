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
}
