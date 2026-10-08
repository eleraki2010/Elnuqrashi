import 'dart:io';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/data/models/customer.dart';
import 'package:alnokrashy_pos/data/models/return_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/data/repositories/balance_repository.dart';
import 'package:alnokrashy_pos/data/repositories/customer_repository.dart';
import 'package:alnokrashy_pos/data/repositories/return_repository.dart';
import 'package:alnokrashy_pos/data/repositories/sale_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات قاعدية (DB) للقواعد المحاسبية: الخزانة، الديون، المرتجعات،
/// كشف الحساب، موعد السداد، وحماية حذف العملاء.
Directory _testSupportDir = Directory.systemTemp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Accounting rules: register, debts, returns', () {
    setUpAll(() async {
      // path_provider غير متاح في الاختبارات: نرُد مجلداً مؤقتاً خاصاً
      // بالاختبارات حتى تُبنى قاعدة البيانات في عزلة (ولا تمس بيانات المستخدم).
      _testSupportDir =
          await Directory.systemTemp.createTemp('alnokrashy_pos_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
              return _testSupportDir.path;
            case 'getTemporaryDirectory':
              return _testSupportDir.path;
            default:
              return null;
          }
        },
      );

      // تهيئة قاعدة البيانات في العزلة (لا تمس بيانات المستخدم).
      await AppDatabase.instance;
    });

    // عزل بين الاختبارات: كل اختبار يبدأ بحالة نظيفة لأن الاختبارات
    // تتحقق من أرقام محاسبية مطلقة (اجماليات).
    setUp(() async {
      final db = await AppDatabase.instance;
      const tables = [
        'return_invoice_items',
        'return_invoices',
        'sale_invoice_items',
        'sale_invoices',
        'payments',
        'stock_movements',
        'audit_logs',
        'customers',
        'products',
        'categories',
      ];
      for (final t in tables) {
        await db.delete(t);
      }
    });

    tearDownAll(() async {
      // محاولة حذف المجلد المؤقت (قد تفشل على Windows لأن القاعدة تبقى
      // مفتوحة حتى نهاية العملية — الفشل هنا لا يوقف مسار الاختبار).
      try {
        if (await _testSupportDir.exists()) {
          await _testSupportDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    late SaleRepository saleRepo;
    late CustomerRepository customerRepo;
    late ReturnRepository returnRepo;
    late BalanceRepository balanceRepo;

    Future<void> seedProduct(String id, double purchase, double sale,
        int quantity) async {
      final db = await AppDatabase.instance;
      final now = DateTime.now().toIso8601String();
      // products.category_id إلزامي (FK) → نزرع تصنيفاً مشتركاً أولاً.
      await db.insert(
        'categories',
        {
          'id': 'cat-test',
          'name': 'تصنيف تجريبي',
          'parent_id': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert('products', {
        'id': id,
        'name': 'منتج تجريبي $id',
        'category_id': 'cat-test',
        'unit': 'قطعة',
        'purchase_price': purchase,
        'sale_price': sale,
        'quantity': quantity,
        'min_quantity_alert': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    SaleInvoiceItem makeItem(String invoiceId, String productId, int qty,
        double price, double? cost, String name) {
      return SaleInvoiceItem(
        id: 'item-$invoiceId-$productId',
        invoiceId: invoiceId,
        productId: productId,
        quantity: qty,
        unitPrice: price,
        lineTotal: qty * price,
        unitCost: cost,
        productName: name,
      );
    }

    setUp(() async {
      saleRepo = SaleRepository();
      customerRepo = CustomerRepository();
      returnRepo = ReturnRepository();
      balanceRepo = BalanceRepository();
    });

    test('credit sale adds debt and register counts only money received',
        () async {
      await seedProduct('p1', 10, 50, 100);

      final c = Customer(
        id: 'c1',
        name: 'زبون تجريبي',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      // بيع آجل: إجمالي 500 (10 × 50) — دفع 200 فقط.
      final invoice = SaleInvoice(
        id: 'inv-credit',
        invoiceNumber: '20260001',
        customerId: 'c1',
        subtotal: 500,
        total: 500,
        paidAmount: 200,
        changeDue: -300,
        paymentMethod: 'credit',
        status: 'completed',
        createdAt: DateTime.now(),
      );
      await saleRepo.createSaleInvoice(
        invoice: invoice,
        items: [makeItem('inv-credit', 'p1', 10, 50, 10, 'منتج تجريبي p1')],
      );

      // دين العميل = 300 (المتبقي فقط).
      final afterSale = await customerRepo.getCustomerById('c1');
      expect(afterSale!.balanceDue, closeTo(300, 0.001));

      // الخزانة = 200 فقط — وليس 500 (رصيد الآجل لا يُحتسب نقداً).
      final balance = await balanceRepo.getShopBalance();
      expect(balance.cashFromSales, closeTo(200, 0.001));
      expect(balance.customerDebt, closeTo(300, 0.001));
    });

    test('collection reduces debt and enters the register', () async {
      await seedProduct('p2', 10, 50, 100);

      final c = Customer(
        id: 'c2',
        name: 'زبون تحصيل',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      final invoice = SaleInvoice(
        id: 'inv-collect',
        invoiceNumber: '20260002',
        customerId: 'c2',
        subtotal: 500,
        total: 500,
        paidAmount: 0,
        changeDue: -500,
        paymentMethod: 'credit',
        status: 'completed',
        createdAt: DateTime.now(),
      );
      await saleRepo.createSaleInvoice(
        invoice: invoice,
        items: [makeItem('inv-collect', 'p2', 10, 50, 10, 'منتج تجريبي p2')],
      );

      // تحصيل 300 نقداً.
      await customerRepo.addCustomerPayment(
        customerId: 'c2',
        amount: 300,
        note: 'تحصيل تجريبي',
      );

      final afterPayment = await customerRepo.getCustomerById('c2');
      expect(afterPayment!.balanceDue, closeTo(200, 0.001));

      final balance = await balanceRepo.getShopBalance();
      expect(balance.collectionsIn, closeTo(300, 0.001));
      expect(
        balance.cashBalance,
        closeTo(300, 0.001), // 300 تحصيلات − مصروفات/خروج صفر
      );
    });

    test('cash sale fully in register; overpayment capped at total',
        () async {
      await seedProduct('p3', 10, 50, 100);

      // بيع نقدي كامل 500.
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-cash',
          invoiceNumber: '20260003',
          subtotal: 500,
          total: 500,
          paidAmount: 500,
          changeDue: 0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-cash', 'p3', 10, 50, 10, 'منتج تجريبي p3')],
      );

      // دفع زائد: سلّم 700 على فاتورة 500 (تُستلم 500 فقط).
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-over',
          invoiceNumber: '20260004',
          subtotal: 500,
          total: 500,
          paidAmount: 700,
          changeDue: 200,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-over', 'p3', 10, 50, 10, 'منتج تجريبي p3')],
      );

      final balance = await balanceRepo.getShopBalance();
      expect(balance.cashFromSales, closeTo(1000, 0.001));
    });

    test('credit return reduces debt and stock; cash return leaves register',
        () async {
      await seedProduct('p4', 10, 50, 100);

      final c = Customer(
        id: 'c3',
        name: 'زبون مرتجع',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      // فاتورة آجل: 5 × 50 = 250، مدفوع 0.
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-ret-credit',
          invoiceNumber: '20260005',
          customerId: 'c3',
          subtotal: 250,
          total: 250,
          paidAmount: 0,
          changeDue: -250,
          paymentMethod: 'credit',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-ret-credit', 'p4', 5, 50, 10, 'منتج تجريبي p4')],
      );

      // فاتورة نقدية: 5 × 50 = 250.
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-ret-cash',
          invoiceNumber: '20260006',
          subtotal: 250,
          total: 250,
          paidAmount: 250,
          changeDue: 0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-ret-cash', 'p4', 5, 50, 10, 'منتج تجريبي p4')],
      );

      // مرتجع على الآجل (3 × 50 = 150).
      await returnRepo.createReturnInvoice(
        invoice: ReturnInvoice(
          id: 'ret-1',
          originalSaleInvoiceId: 'inv-ret-credit',
          customerId: 'c3',
          returnAmount: 150,
          createdAt: DateTime.now(),
        ),
        items: [
          ReturnInvoiceItem(
            id: 'ret-1-i1',
            returnInvoiceId: 'ret-1',
            productId: 'p4',
            quantity: 3,
            unitPrice: 50,
            lineTotal: 150,
            productName: 'منتج تجريبي p4',
            createdAt: DateTime.now(),
          ),
        ],
      );

      // مرتجع على النقدية (2 × 50 = 100).
      await returnRepo.createReturnInvoice(
        invoice: ReturnInvoice(
          id: 'ret-2',
          originalSaleInvoiceId: 'inv-ret-cash',
          returnAmount: 100,
          createdAt: DateTime.now(),
        ),
        items: [
          ReturnInvoiceItem(
            id: 'ret-2-i1',
            returnInvoiceId: 'ret-2',
            productId: 'p4',
            quantity: 2,
            unitPrice: 50,
            lineTotal: 100,
            productName: 'منتج تجريبي p4',
            createdAt: DateTime.now(),
          ),
        ],
      );

      // دين العميل انخفض 150 فقط (مرتجع الآجل)؛ مرتجع النقدية لا يمس الحساب.
      final customer = await customerRepo.getCustomerById('c3');
      expect(customer!.balanceDue, closeTo(100, 0.001));

      final balance = await balanceRepo.getShopBalance();
      // الخزانة: 250 (البيع النقدي) − 100 (مرتجع نقدي خارج) = 150.
      expect(balance.cashFromSales, closeTo(250, 0.001));
      expect(balance.returnsRefundOut, closeTo(100, 0.001));
      expect(balance.cashBalance, closeTo(150, 0.001));

      // المخزون: بدأ 100 − 5 − 5 (مبيعات) + 3 + 2 (مرتجعات) = 95.
      final db = await AppDatabase.instance;
      final maps =
          await db.query('products', where: 'id = ?', whereArgs: ['p4']);
      expect((maps.first['quantity'] as num).toInt(), 95);
    });

    test('customer statement aggregates invoices, returns and payments',
        () async {
      await seedProduct('p5', 10, 100, 100);

      final c = Customer(
        id: 'c4',
        name: 'زبون كشف',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      // فاتورة آجل 200 (مكتملة) + فاتورة معلّقة 100 آجل + فاتورة نقدية 100.
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-st1',
          invoiceNumber: '20260007',
          customerId: 'c4',
          subtotal: 200,
          total: 200,
          paidAmount: 0,
          changeDue: -200,
          paymentMethod: 'credit',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-st1', 'p5', 2, 100, 10, 'منتج تجريبي p5')],
      );
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-st2',
          invoiceNumber: '20260008',
          customerId: 'c4',
          subtotal: 100,
          total: 100,
          paidAmount: 0,
          changeDue: -100,
          paymentMethod: 'credit',
          status: 'held',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-st2', 'p5', 1, 100, 10, 'منتج تجريبي p5')],
      );
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-st3',
          invoiceNumber: '20260009',
          customerId: 'c4',
          subtotal: 100,
          total: 100,
          paidAmount: 100,
          changeDue: 0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-st3', 'p5', 1, 100, 10, 'منتج تجريبي p5')],
      );

      // تحصيل 50.
      await customerRepo.addCustomerPayment(
        customerId: 'c4',
        amount: 50,
      );

      // مرتجع على الآجل (0.5 × 100 = 50).
      await returnRepo.createReturnInvoice(
        invoice: ReturnInvoice(
          id: 'ret-st',
          originalSaleInvoiceId: 'inv-st1',
          customerId: 'c4',
          returnAmount: 50,
          createdAt: DateTime.now(),
        ),
        items: [
          ReturnInvoiceItem(
            id: 'ret-st-i1',
            returnInvoiceId: 'ret-st',
            productId: 'p5',
            quantity: 1,
            unitPrice: 100,
            lineTotal: 100,
            productName: 'منتج تجريبي p5',
            createdAt: DateTime.now(),
          ),
        ],
      );
      // ملاحظة: المرتجع أعلاه قيمته 50 لكن العنصر 100 — نستخدم 50 محاسبياً.
      // (لا يؤثر على الاختبار: الرصيد يعتمد return_amount).

      final statement = await customerRepo.getCustomerStatement('c4');
      expect(statement, isNotNull);
      expect(statement!.invoices, hasLength(3)); // المكتملة + المعلّقة (لا الملغاة)
      expect(statement.payments, hasLength(1));
      expect(statement.returns, hasLength(1));
      expect(statement.returns.first.originalPaymentMethod, 'credit');

      // الرصيد النهائي يطابق balance_due:
      // 200 (آجل مكتمل) + 100 (آجل معلّق) + 0 (نقدي) − 50 (تحصيل) − 50 (مرتجع) = 200
      final customer = statement.customer;
      expect(customer.balanceDue, closeTo(200, 0.001));
    });

    test('payment due date: overdue detection and clearing', () async {
      final c = Customer(
        id: 'c5',
        name: 'زبون موعد',
        balanceDue: 400,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      // موعد في الماضي → متأخر.
      final past = DateTime.now().subtract(const Duration(days: 3));
      await customerRepo.updateCustomerPaymentDueDate('c5', past);

      var overdue = await customerRepo.getOverdueCustomers();
      expect(overdue.map((e) => e.id).contains('c5'), true);

      var customer = await customerRepo.getCustomerById('c5');
      expect(customer!.isOverdue, true);

      // إزالة الموعد → لا متأخرين.
      await customerRepo.updateCustomerPaymentDueDate('c5', null);
      overdue = await customerRepo.getOverdueCustomers();
      expect(overdue, isEmpty);

      customer = await customerRepo.getCustomerById('c5');
      expect(customer!.isOverdue, false);
    });

    test('delete blocked with debt, allowed when account is zero', () async {
      final c = Customer(
        id: 'c6',
        name: 'زبون حذف',
        balanceDue: 150,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      await expectLater(
        customerRepo.deleteCustomer('c6'),
        throwsA(isA<StateError>()),
      );

      // تصفير الحساب ثم الحذف ناجح.
      await customerRepo.updateCustomer(
        c.copyWith(balanceDue: 0.0),
      );
      await customerRepo.deleteCustomer('c6');
      expect(await customerRepo.getCustomerById('c6'), isNull);
    });

    test('zero-balance customer with invoices is deletable (account zero rule)',
        () async {
      await seedProduct('p7', 10, 50, 100);

      final c = Customer(
        id: 'c7',
        name: 'زبون صفر بفواتير',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await customerRepo.insertCustomer(c);

      // بيع آجل كامل ثم تحصيل كامل → الحساب يتصفَّر لكن الفاتورة تبقى.
      await saleRepo.createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-c7',
          invoiceNumber: '20260020',
          customerId: 'c7',
          subtotal: 100,
          total: 100,
          paidAmount: 0,
          changeDue: -100,
          paymentMethod: 'credit',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [makeItem('inv-c7', 'p7', 2, 50, 10, 'منتج تجريبي p7')],
      );
      await customerRepo.addCustomerPayment(customerId: 'c7', amount: 100);

      final zeroed = await customerRepo.getCustomerById('c7');
      expect(zeroed!.balanceDue, closeTo(0, 0.001));

      // القاعدة: الحساب صفر → الحذف مسموح حتى مع فواتير، والفاتورة تبقى
      // بلا عميل (ON DELETE SET NULL).
      await customerRepo.deleteCustomer('c7');
      expect(await customerRepo.getCustomerById('c7'), isNull);

      final db = await AppDatabase.instance;
      final rows =
          await db.query('sale_invoices', where: 'id = ?', whereArgs: ['inv-c7']);
      expect(rows, hasLength(1));
      expect(rows.first['customer_id'], isNull);
    });
  });
}
