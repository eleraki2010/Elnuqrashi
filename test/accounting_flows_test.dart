import 'dart:io';

import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/data/models/customer.dart';
import 'package:alnokrashy_pos/data/models/product.dart';
import 'package:alnokrashy_pos/data/models/return_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/data/repositories/balance_repository.dart';
import 'package:alnokrashy_pos/data/repositories/customer_repository.dart';
import 'package:alnokrashy_pos/data/repositories/return_repository.dart';
import 'package:alnokrashy_pos/data/repositories/sale_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات الأسس المحاسبية: المرتجع الجزئي، المرتجع النقدي الكامل،
/// ودورة (بيع آجل ← إلغاء ← استرجاع ← حذف المسودة) وديونها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testSupportDir;

  setUpAll(() async {
    testSupportDir = await Directory.systemTemp.createTemp(
      'alnokrashy_accounting_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return testSupportDir.path;
            }
            return null;
          },
        );
    await AppDatabase.instance;
  });

  tearDownAll(() async {
    try {
      if (await testSupportDir.exists()) {
        await testSupportDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  /// تجهيز منتج وعميل وفئة وتصفير الجداول المعنية.
  Future<({Product product, Customer customer})> seed(String tag) async {
    final db = await AppDatabase.instance;
    await db.delete('return_invoice_items');
    await db.delete('return_invoices');
    await db.delete('sale_invoice_items');
    await db.delete('sale_invoices');
    await db.delete('payments');
    await db.delete('stock_movements');
    await db.delete('audit_logs');
    await db.delete('expenses');
    await db.delete('customers');
    await db.delete('products');
    await db.delete('purchase_invoices');
    await db.delete('suppliers');

    // الفئة التي يشير إليها المنتج — شرط FK على products.category_id.
    await db.execute(
      "INSERT OR IGNORE INTO categories (id, name, parent_id) "
      "VALUES ('cat-1', 'فئة الاختبار', NULL)",
    );
    final now = DateTime(2026, 10, 5, 10);
    final product = Product(
      id: 'prod-$tag',
      name: 'منتج اختبار $tag',
      categoryId: 'cat-1',
      unit: 'قطعة',
      purchasePrice: 50,
      salePrice: 100,
      quantity: 10,
      minQuantityAlert: 2,
      createdAt: now,
      updatedAt: now,
    );
    final customer = Customer(
      id: 'cust-$tag',
      name: 'عميل اختبار $tag',
      balanceDue: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('products', product.toMap());
    await db.insert('customers', customer.toMap());
    return (product: product, customer: customer);
  }

  SaleInvoice creditSale({
    required String id,
    required String number,
    required String productId,
    required String customerId,
    required int quantity,
  }) {
    final now = DateTime(2026, 10, 5, 11);
    final total = quantity * 100.0;
    return SaleInvoice(
      id: id,
      invoiceNumber: number,
      customerId: customerId,
      total: total,
      subtotal: total,
      paidAmount: 0,
      changeDue: 0,
      paymentMethod: 'credit',
      status: 'completed',
      createdAt: now,
      items: [
        SaleInvoiceItem(
          id: 'item-$id',
          invoiceId: id,
          productId: productId,
          quantity: quantity,
          unitPrice: 100,
          lineTotal: total,
          productName: 'منتج',
        ),
      ],
    );
  }

  test(
    'partial return: 3 of 5 — debt reduced by 300, stock back by 3',
    () async {
      final seeded = await seed('p1');
      final saleRepo = SaleRepository();
      final returnRepo = ReturnRepository();

      final sale = creditSale(
        id: 'inv-p1',
        number: '20261001',
        productId: seeded.product.id,
        customerId: seeded.customer.id,
        quantity: 5,
      );
      await saleRepo.createSaleInvoice(invoice: sale, items: sale.items);

      // بعد البيع: مخزون 5 ودين العميل 500.
      var db = await AppDatabase.instance;
      var qty =
          (await db.query(
                'products',
                where: 'id = ?',
                whereArgs: ['prod-p1'],
              )).first['quantity']
              as int;
      var debt =
          (await db.query(
                'customers',
                where: 'id = ?',
                whereArgs: ['cust-p1'],
              )).first['balance_due']
              as num;
      expect(qty, 5);
      expect(debt, 500.0);

      // مرتجع جزئي: 3 قطع (القيمة 300) — دين 500 يغطيها بالكامل.
      final returnInvoice = ReturnInvoice(
        id: 'ret-p1',
        originalSaleInvoiceId: 'inv-p1',
        customerId: seeded.customer.id,
        returnAmount: 300,
        createdAt: DateTime(2026, 10, 5, 12),
        items: [
          ReturnInvoiceItem(
            id: 'retitem-p1',
            returnInvoiceId: 'ret-p1',
            productId: seeded.product.id,
            quantity: 3,
            unitPrice: 100,
            lineTotal: 300,
            productName: 'منتج',
            createdAt: DateTime(2026, 10, 5, 12),
          ),
        ],
      );
      await returnRepo.createReturnInvoice(
        invoice: returnInvoice,
        items: returnInvoice.items,
      );

      // المحاسبة بعد المرتجع الجزئي:
      // - المخزون يعود 3 (5 ← 8) لا 5 كاملة.
      // - دين العميل ينخفض 300 (500 ← 200).
      // - لا نقد يخرج من الصندوق (debt_reduction = return_amount).
      qty =
          (await db.query(
                'products',
                where: 'id = ?',
                whereArgs: ['prod-p1'],
              )).first['quantity']
              as int;
      debt =
          (await db.query(
                'customers',
                where: 'id = ?',
                whereArgs: ['cust-p1'],
              )).first['balance_due']
              as num;
      expect(qty, 8);
      expect(debt, 200.0);

      final storedReturn = (await db.query(
        'return_invoices',
        where: 'id = ?',
        whereArgs: ['ret-p1'],
      )).first;
      expect(storedReturn['return_amount'], 300.0);
      expect(storedReturn['debt_reduction'], 300.0);

      // المخزون لم يخرج نقدًا: المرتجع كله خصم دين.
      final balance = await BalanceRepository().getShopBalance();
      expect(balance.returnsRefundOut, 0.0);
    },
  );

  test('full cash return without customer: cash out of the register', () async {
    final seeded = await seed('p2');
    final saleRepo = SaleRepository();
    final returnRepo = ReturnRepository();

    final now = DateTime(2026, 10, 5, 11);
    final sale = SaleInvoice(
      id: 'inv-p2',
      invoiceNumber: '20261002',
      total: 200,
      subtotal: 200,
      paidAmount: 200,
      changeDue: 0,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: now,
      items: [
        SaleInvoiceItem(
          id: 'item-inv-p2',
          invoiceId: 'inv-p2',
          productId: seeded.product.id,
          quantity: 2,
          unitPrice: 100,
          lineTotal: 200,
          productName: 'منتج',
        ),
      ],
    );
    await saleRepo.createSaleInvoice(invoice: sale, items: sale.items);

    // مرتجع كامل لفاتورة نقدية بلا عميل → 200 نقد خارج من الصندوق.
    final returnInvoice = ReturnInvoice(
      id: 'ret-p2',
      originalSaleInvoiceId: 'inv-p2',
      returnAmount: 200,
      createdAt: DateTime(2026, 10, 5, 12),
      items: [
        ReturnInvoiceItem(
          id: 'retitem-p2',
          returnInvoiceId: 'ret-p2',
          productId: seeded.product.id,
          quantity: 2,
          unitPrice: 100,
          lineTotal: 200,
          productName: 'منتج',
          createdAt: DateTime(2026, 10, 5, 12),
        ),
      ],
    );
    await returnRepo.createReturnInvoice(
      invoice: returnInvoice,
      items: returnInvoice.items,
    );

    final balance = await BalanceRepository().getShopBalance();
    expect(balance.returnsRefundOut, 200.0);

    final db = await AppDatabase.instance;
    final storedReturn = (await db.query(
      'return_invoices',
      where: 'id = ?',
      whereArgs: ['ret-p2'],
    )).first;
    expect(storedReturn['debt_reduction'], 0.0);
  });

  test('cancel → restore → delete cycle leaves the customer debt balanced '
      '(no double reversal)', () async {
    final seeded = await seed('p3');
    final saleRepo = SaleRepository();

    final sale = creditSale(
      id: 'inv-p3',
      number: '20261003',
      productId: seeded.product.id,
      customerId: seeded.customer.id,
      quantity: 3,
    );
    await saleRepo.createSaleInvoice(invoice: sale, items: sale.items);

    Future<double> debt() async {
      final db = await AppDatabase.instance;
      final v =
          (await db.query(
                'customers',
                where: 'id = ?',
                whereArgs: ['cust-p3'],
              )).first['balance_due']
              as num;
      return v.toDouble();
    }

    Future<int> qty() async {
      final db = await AppDatabase.instance;
      return (await db.query(
            'products',
            where: 'id = ?',
            whereArgs: ['prod-p3'],
          )).first['quantity']
          as int;
    }

    expect(await debt(), 300.0);
    expect(await qty(), 7);

    // 1) إلغاء الفاتورة المكتملة: دين 0، مخزون يعود 10.
    await saleRepo.cancelSaleInvoice('inv-p3');
    expect(await debt(), 0.0);
    expect(await qty(), 10);

    // 2) استرجاعها كمعلّقة: يُعاد تسجيل دين المتبقي (300) — القاعدة
    //    الموحدة أن دين كل معلّقة مسجَّل على عميلها.
    await saleRepo.restoreSaleInvoice('inv-p3');
    expect(await debt(), 300.0);
    expect(await qty(), 10); // المعلّقة لا تمس المخزون

    // 3) تحميل المسودة في العربة يُحذفها: يُعكس الدين مرة واحدة فقط.
    await saleRepo.deleteSaleInvoice('inv-p3');
    expect(await debt(), 0.0); // لا عكس مزدوج (كان 0 - 300 قبل الإصلاح).
  });

  test(
    'customer statement ledger ends exactly on the recorded balance',
    () async {
      final seeded = await seed('p4');
      final saleRepo = SaleRepository();
      final custRepo = CustomerRepository();
      final returnRepo = ReturnRepository();

      // فاتورة آجل 400 ثم تحصيل 100 ثم مرتجع 100 (خصم دين).
      final sale = creditSale(
        id: 'inv-p4',
        number: '20261004',
        productId: seeded.product.id,
        customerId: seeded.customer.id,
        quantity: 4,
      );
      await saleRepo.createSaleInvoice(invoice: sale, items: sale.items);
      await custRepo.addCustomerPayment(
        customerId: seeded.customer.id,
        amount: 100,
      );
      final ret = ReturnInvoice(
        id: 'ret-p4',
        originalSaleInvoiceId: 'inv-p4',
        customerId: seeded.customer.id,
        returnAmount: 100,
        createdAt: DateTime(2026, 10, 5, 13),
        items: [
          ReturnInvoiceItem(
            id: 'retitem-p4',
            returnInvoiceId: 'ret-p4',
            productId: seeded.product.id,
            quantity: 1,
            unitPrice: 100,
            lineTotal: 100,
            productName: 'منتج',
            createdAt: DateTime(2026, 10, 5, 13),
          ),
        ],
      );
      await returnRepo.createReturnInvoice(invoice: ret, items: ret.items);

      final statement = await custRepo.getCustomerStatement(seeded.customer.id);
      expect(statement, isNotNull);

      // قواعد الرصيد الجاري في شاشة كشف حساب العميل.
      var running = 0.0;
      final invoices = statement!.invoices;
      for (final inv in invoices) {
        running += (inv.total - inv.paidAmount).clamp(0.0, double.infinity);
      }
      for (final p in statement.payments) {
        running -= p.amount;
      }
      for (final r in statement.returns) {
        running -= r.invoice.debtReduction;
      }
      expect(running, statement.customer.balanceDue);
      // الديون المتبقية: 400 − 100 تحصيل − 100 مرتجع = 200.
      expect(statement.customer.balanceDue, 200.0);
    },
  );
}
