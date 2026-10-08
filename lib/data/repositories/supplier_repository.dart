import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/payment.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier.dart';

/// بيان واحد في كشف حساب المورد (فاتورة شراء أو دفعة سداد) مع
/// الرصيد الدائري بعد تسجيله.
class StatementEntry {
  final DateTime date;

  /// true = فاتورة شراء (مدين — تزيد المستحق)، false = دفعة سداد (دائن).
  final bool isPurchase;

  /// نص البيان للعرض (قالب ثابت)؛ التفاصيل تُفتح من الشاشة.
  final String title;

  /// مبلغ البيان: إجمالي الفاتورة للشراء، مبلغ الدفعة للسداد.
  final double amount;

  /// معرّف المصدر (id فاتورة الشراء أو id الدفعة) لفتح التفاصيل.
  final String referenceId;

  double runningBalance;

  StatementEntry({
    required this.date,
    required this.isPurchase,
    required this.title,
    required this.amount,
    required this.referenceId,
    required this.runningBalance,
  });
}

class SupplierStatement {
  final Supplier supplier;
  final List<PurchaseInvoice> purchases;
  final List<Payment> payments;

  SupplierStatement({
    required this.supplier,
    required this.purchases,
    required this.payments,
  });

  double get totalPurchases => purchases.fold(0.0, (sum, p) => sum + p.total);

  double get totalPayments => payments.fold(0.0, (sum, p) => sum + p.amount);

  /// كشف الحساب الموحد لكل عمليات المورد (شراء + دفعات) مرتباً زمنياً
  /// مع رصيد دائري بعد كل بيان.
  ///
  /// الرصيد الافتتاحي = الرصيد الحالي − مجموع تأثير العمليات، فينتهي
  /// الكشف بالضبط على رصيد المورد المسجَّل (حتى لو كان يملك رصيداً
  /// تاريخياً سابقاً لهذه العمليات).
  List<StatementEntry> buildEntries() {
    final entries = <StatementEntry>[];
    for (final p in purchases) {
      entries.add(
        StatementEntry(
          date: p.createdAt,
          isPurchase: true,
          title: p.remainingOwed > 0
              ? 'فاتورة شراء (توريد بضاعة) — عليها متبقٍ'
              : 'فاتورة شراء (توريد بضاعة) — مدفوعة بالكامل',
          amount: p.total,
          referenceId: p.id,
          runningBalance: 0,
        ),
      );
    }
    for (final p in payments) {
      entries.add(
        StatementEntry(
          date: p.createdAt,
          isPurchase: false,
          title: (p.note != null && p.note!.trim().isNotEmpty)
              ? 'دفعة سداد للمورد — ${p.note!.trim()}'
              : 'دفعة سداد للمورد',
          amount: p.amount,
          referenceId: p.id,
          runningBalance: 0,
        ),
      );
    }
    entries.sort((a, b) => a.date.compareTo(b.date));

    final effect = entries.fold(
      0.0,
      (sum, e) => sum + (e.isPurchase ? e.amount : -e.amount),
    );
    var running = supplier.balanceOwed - effect;
    for (final e in entries) {
      running += e.isPurchase ? e.amount : -e.amount;
      e.runningBalance = running;
    }
    return entries;
  }
}

class SupplierRepository {
  final _uuid = const Uuid();

  Future<List<Supplier>> getAllSuppliers() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Supplier.fromMap(m)).toList();
  }

  Future<List<Supplier>> searchSuppliers(String query) async {
    final db = await AppDatabase.instance;
    final clean = query.trim();
    if (clean.isEmpty) return getAllSuppliers();

    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$clean%', '%$clean%'],
      orderBy: 'name ASC',
    );
    return maps.map((m) => Supplier.fromMap(m)).toList();
  }

  Future<Supplier?> getSupplierById(String id) async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Supplier.fromMap(maps.first);
  }

  Future<void> insertSupplier(Supplier supplier) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'suppliers',
      supplier.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSupplier(Supplier supplier) async {
    final db = await AppDatabase.instance;
    await db.update(
      'suppliers',
      supplier.toMap(),
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
  }

  Future<void> deleteSupplier(String id) async {
    final db = await AppDatabase.instance;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addSupplierPayment({
    required String supplierId,
    required double amount,
    String? note,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. Insert Payment
      await txn.insert('payments', {
        'id': _uuid.v4(),
        'party_type': 'supplier',
        'party_id': supplierId,
        'amount': amount,
        'direction': 'out',
        'note': note,
        'created_at': now.toIso8601String(),
      });

      // 2. Reduce supplier balance_owed
      await txn.rawUpdate(
        '''
        UPDATE suppliers 
        SET balance_owed = balance_owed - ?, updated_at = ? 
        WHERE id = ?
      ''',
        [amount, now.toIso8601String(), supplierId],
      );

      // 3. Audit log (تتبع العمليات المالية)
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'payments',
        'record_id': supplierId,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"direction": "out", "amount": $amount, "party": "supplier"}',
        'user_id': userId,
        'note': note ?? 'سداد دفعة للمورد',
        'created_at': now.toIso8601String(),
      });
    });
  }

  Future<SupplierStatement?> getSupplierStatement(String supplierId) async {
    final supplier = await getSupplierById(supplierId);
    if (supplier == null) return null;

    final db = await AppDatabase.instance;

    final purchaseMaps = await db.query(
      'purchase_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );
    final purchases = purchaseMaps
        .map((m) => PurchaseInvoice.fromMap(m))
        .toList();

    final paymentMaps = await db.query(
      'payments',
      where: 'party_type = ? AND party_id = ?',
      whereArgs: ['supplier', supplierId],
      orderBy: 'created_at DESC',
    );
    final payments = paymentMaps.map((m) => Payment.fromMap(m)).toList();

    return SupplierStatement(
      supplier: supplier,
      purchases: purchases,
      payments: payments,
    );
  }
}
