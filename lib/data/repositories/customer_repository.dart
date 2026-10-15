import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../models/return_invoice.dart';
import '../models/sale_invoice.dart';
import '../models/sale_invoice_item.dart';

/// مرتجع ضمن كشف حساب العميل مع طريقة دفع الفاتورة الأصلية
/// (لمعرفة أثره على دين العميل: فقط مرتجع الآجل يخصم من الحساب).
class StatementReturn {
  final ReturnInvoice invoice;
  final String? originalPaymentMethod;

  StatementReturn({required this.invoice, this.originalPaymentMethod});
}

class CustomerStatement {
  final Customer customer;
  final List<SaleInvoice> invoices;
  final List<Payment> payments;
  final List<StatementReturn> returns;

  CustomerStatement({
    required this.customer,
    required this.invoices,
    required this.payments,
    this.returns = const [],
  });
}

class CustomerRepository {
  final _uuid = const Uuid();

  /// ترتيب موحّد: الأعلى مديونية أولاً (تنازلياً)، ثم من لهم رصيد مسبق،
  /// ثم خالصون — والاسم تفريعاً داخل كل مجموعة.
  static const String _debtOrder =
      'CASE WHEN balance_due > 0.01 THEN 0 WHEN balance_due < -0.01 THEN 1 '
      'ELSE 2 END, balance_due DESC, name ASC';

  Future<List<Customer>> getAllCustomers() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      orderBy: _debtOrder,
    );
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  /// عملاء متأخرون عن موعد السداد (للافتالة/التنبيه داخل التطبيق).
  Future<List<Customer>> getOverdueCustomers() async {
    final db = await AppDatabase.instance;
    final maps = await db.rawQuery(
      '''
      SELECT * FROM customers
      WHERE balance_due > 0.01
        AND payment_due_date IS NOT NULL
        AND payment_due_date < date('now')
      ORDER BY payment_due_date ASC, balance_due DESC
      ''',
    );
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await AppDatabase.instance;
    final clean = query.trim();
    if (clean.isEmpty) return getAllCustomers();

    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$clean%', '%$clean%'],
      orderBy: _debtOrder,
    );
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<Customer?> getCustomerById(String id) async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  Future<void> insertCustomer(Customer customer) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await AppDatabase.instance;
    await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  /// تعيين موعد سداد المديونية (أو إلغاؤه بـ null).
  Future<void> updateCustomerPaymentDueDate(
    String customerId,
    DateTime? dueDate,
  ) async {
    final db = await AppDatabase.instance;
    await db.rawUpdate(
      'UPDATE customers SET payment_due_date = ?, updated_at = ? WHERE id = ?',
      [
        dueDate?.toIso8601String(),
        DateTime.now().toIso8601String(),
        customerId,
      ],
    );
  }

  Future<void> deleteCustomer(String id) async {
    final db = await AppDatabase.instance;

    // القاعدة المحاسبية (بطلب الصاحب): لا يُحذف عميل له مديونية أو رصيد
    // مسبق — لكن إذا تصفَّر حسابه (لا دين ولا رصيد مسبق) يُسمح بالحذف حتى
    // مع وجود فواتير سابقة، لأنها لا تترك أثراً مالياً على الدفاتر
    // (الفواتير تبقى محفوظة ويُستبدل عميدها بـ null عبر ON DELETE SET NULL).
    final customer = await getCustomerById(id);
    if (customer != null && customer.hasDebt) {
      throw StateError(
        'لا يمكن حذف العميل "${customer.name}" لوجود مديونية مستحقة قدرها '
        '${customer.balanceDue.toStringAsFixed(0)} ${AppStrings.CURRENCY}. '
        'يرجى تحصيل المديونية (أو خصمها) حتى يتصفَّر الحساب أولاً.',
      );
    }
    if (customer != null && customer.hasCredit) {
      throw StateError(
        'لا يمكن حذف العميل "${customer.name}" لوجود رصيد مسبق له قدره '
        '${(-customer.balanceDue).toStringAsFixed(0)} ${AppStrings.CURRENCY}. '
        'حلَّ الرصيد قبل الحذف حتى يتصفَّر الحساب.',
      );
    }

    await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addCustomerPayment({
    required String customerId,
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
        'party_type': 'customer',
        'party_id': customerId,
        'amount': amount,
        'direction': 'in',
        'note': note,
        'created_at': now.toIso8601String(),
      });

      // 2. Reduce customer balance_due
      await txn.rawUpdate('''
        UPDATE customers 
        SET balance_due = balance_due - ?, updated_at = ? 
        WHERE id = ?
      ''', [amount, now.toIso8601String(), customerId]);

      // 3. Audit log (تتبع العمليات المالية) مع المستخدم المتخذ للقرار.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'payments',
        'record_id': customerId,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"direction": "in", "amount": $amount, "party": "customer"}',
        'user_id': userId,
        'note': note ?? 'سند قبض — تحصيل دفعة من حساب العميل',
        'created_at': now.toIso8601String(),
      });
    });
  }

  /// كشف حساب العميل: فواتيره (المكتملة والمعلّقة — لا الملغاة لأنها
  /// عُدَّت من الأرصدة) + دفعات السداد + مرتجعاته مع طريقة دفع الفاتورة
  /// الأصلية ليُحسب الرصيد الجاري مطابقاً لقواعد الديون.
  Future<CustomerStatement?> getCustomerStatement(String customerId) async {
    final customer = await getCustomerById(customerId);
    if (customer == null) return null;

    final db = await AppDatabase.instance;

    final invoiceMaps = await db.query(
      'sale_invoices',
      where: "customer_id = ? AND status IN ('completed', 'held')",
      whereArgs: [customerId],
      orderBy: 'created_at ASC',
    );
    final invoices = <SaleInvoice>[];
    for (final m in invoiceMaps) {
      final inv = SaleInvoice.fromMap(m);
      final itemMaps = await db.query(
        'sale_invoice_items',
        where: 'sale_invoice_id = ?',
        whereArgs: [inv.id],
      );
      final items = itemMaps.map((im) => SaleInvoiceItem.fromMap(im)).toList();
      invoices.add(inv.copyWith(items: items));
    }

    final paymentMaps = await db.query(
      'payments',
      where: 'party_type = ? AND party_id = ?',
      whereArgs: ['customer', customerId],
      orderBy: 'created_at ASC',
    );
    final payments = paymentMaps.map((m) => Payment.fromMap(m)).toList();

    // المرتجعات المرتبطة بحساب العميل. المقدار المخصوم من الدين محفوظ في
    // `debt_reduction` (الزائد عن الدين سُلِّم نقداً ولا يمس رصيد العميل).
    final returnMaps = await db.rawQuery(
      '''
      SELECT ri.*, si.payment_method as original_payment_method
      FROM return_invoices ri
      LEFT JOIN sale_invoices si ON si.id = ri.original_sale_invoice_id
      WHERE ri.customer_id = ?
      ORDER BY ri.created_at ASC
      ''',
      [customerId],
    );
    final returns = <StatementReturn>[];
    for (final m in returnMaps) {
      final ret = ReturnInvoice.fromMap(m);
      final itemMaps = await db.query(
        'return_invoice_items',
        where: 'return_invoice_id = ?',
        whereArgs: [ret.id],
      );
      final items = itemMaps.map((im) => ReturnInvoiceItem.fromMap(im)).toList();
      returns.add(StatementReturn(
        invoice: ret.copyWith(items: items),
        originalPaymentMethod: m['original_payment_method'] as String?,
      ));
    }

    return CustomerStatement(
      customer: customer,
      invoices: invoices,
      payments: payments,
      returns: returns,
    );
  }
}
