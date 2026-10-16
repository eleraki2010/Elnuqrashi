import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/data/models/customer.dart';
import 'package:alnokrashy_pos/data/models/expense.dart';
import 'package:alnokrashy_pos/data/models/product.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice_item.dart';
import 'package:alnokrashy_pos/data/models/return_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/data/models/supplier.dart';
import 'package:alnokrashy_pos/data/repositories/balance_repository.dart';
import 'package:alnokrashy_pos/data/repositories/customer_repository.dart';
import 'package:alnokrashy_pos/data/repositories/expense_repository.dart';
import 'package:alnokrashy_pos/data/repositories/product_repository.dart';
import 'package:alnokrashy_pos/data/repositories/purchase_repository.dart';
import 'package:alnokrashy_pos/data/repositories/return_repository.dart';
import 'package:alnokrashy_pos/data/repositories/sale_repository.dart';
import 'package:alnokrashy_pos/data/repositories/supplier_repository.dart';

import 'dart:io';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testSupportDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testSupportDir = await Directory.systemTemp.createTemp('alnokrashy_acc_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory' ||
                call.method == 'getApplicationDocumentsDirectory') {
              return testSupportDir.path;
            }
            return null;
          },
        );
  });

  tearDownAll(() async {
    try {
      final db = await AppDatabase.instance;
      await db.close();
    } catch (_) {}
    if (await testSupportDir.exists()) {
      await testSupportDir.delete(recursive: true);
    }
  });

  test('Full Accounting Lifecycle E2E Simulation (شراء، بيع، مصروفات، مرتجع، تحصيل، سداد، ومركز مالي)', () async {
    // 0. إعادة ضبط قاعدة البيانات لبدء بيئة نظيفة ومستقلة
    final db = await AppDatabase.instance;
    await db.delete('sale_invoice_items');
    await db.delete('sale_invoices');
    await db.delete('purchase_invoice_items');
    await db.delete('purchase_invoices');
    await db.delete('return_invoice_items');
    await db.delete('return_invoices');
    await db.delete('payments');
    await db.delete('expenses');
    await db.delete('stock_movements');
    await db.delete('products');
    await db.delete('customers');
    await db.delete('suppliers');

    final productRepo = ProductRepository();
    final supplierRepo = SupplierRepository();
    final customerRepo = CustomerRepository();
    final purchaseRepo = PurchaseRepository();
    final saleRepo = SaleRepository();
    final returnRepo = ReturnRepository();
    final expenseRepo = ExpenseRepository();
    final balanceRepo = BalanceRepository();

    // ==========================================
    // المرحلة 1: إنشاء الأصناف والمورد
    // ==========================================
    final supplier = Supplier(
      id: 'sup-1',
      name: 'شركة الأهرام للأدوات والمواسير',
      phone: '01000000001',
      balanceOwed: 0.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await supplierRepo.insertSupplier(supplier);

    await db.insert('categories', {
      'id': 'cat-1',
      'name': 'أدوات سباكة',
    });

    final productMixer = Product(
      id: 'prod-mixer',
      name: 'خلاط مياه تركي',
      categoryId: 'cat-1',
      unit: 'قطعة',
      purchasePrice: 200.0,
      salePrice: 300.0,
      quantity: 0,
      minQuantityAlert: 2,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await productRepo.insertProduct(productMixer);

    final productPipe = Product(
      id: 'prod-pipe',
      name: 'ماسورة 1 بوصة',
      categoryId: 'cat-1',
      unit: 'متر',
      purchasePrice: 40.0,
      salePrice: 60.0,
      quantity: 0,
      minQuantityAlert: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await productRepo.insertProduct(productPipe);

    // ==========================================
    // المرحلة 2: فاتورة مشتريات (توريد بضاعة + دفع جزئي للمورد)
    // ==========================================
    // 10 خلاط @ 200 = 2000
    // 20 ماسورة @ 40 = 800
    // الإجمالي = 2800 ج.م
    // المسدد للمورد نقداً = 1000 ج.م
    // الآجل المتبقي للمورد = 1800 ج.م
    final purchaseInvoice = PurchaseInvoice(
      id: 'pur-inv-1',
      supplierId: supplier.id,
      total: 2800.0,
      paidAmount: 1000.0,
      tax: 0.0,
      createdAt: DateTime.now(),
    );
    final purchaseItems = [
      PurchaseInvoiceItem(
        id: 'pi-1',
        invoiceId: 'pur-inv-1',
        productId: productMixer.id,
        quantity: 10,
        unitCost: 200.0,
        lineTotal: 2000.0,
      ),
      PurchaseInvoiceItem(
        id: 'pi-2',
        invoiceId: 'pur-inv-1',
        productId: productPipe.id,
        quantity: 20,
        unitCost: 40.0,
        lineTotal: 800.0,
      ),
    ];
    await purchaseRepo.createPurchaseInvoice(
      invoice: purchaseInvoice,
      items: purchaseItems,
    );

    // تحقق من المخزون بعد الشراء
    final pMixerAfterPurchase = await productRepo.getProductById(productMixer.id);
    final pPipeAfterPurchase = await productRepo.getProductById(productPipe.id);
    expect(pMixerAfterPurchase!.quantity, 10);
    expect(pPipeAfterPurchase!.quantity, 20);

    // تحقق من دين المورد
    final supAfterPurchase = await supplierRepo.getSupplierById(supplier.id);
    expect(supAfterPurchase!.balanceOwed, 1800.0);

    // ==========================================
    // المرحلة 3: عملية بيع نقدي (زبون عابر)
    // ==========================================
    // بيع 2 خلاط @ 300 = 600 ج.م (دفع نقدي كامل)
    // ربح العملية = 2 * (300 - 200) = 200 ج.م
    final cashSaleInvoice = SaleInvoice(
      id: 'sale-cash-1',
      invoiceNumber: '20260001',
      subtotal: 600.0,
      discount: 0.0,
      tax: 0.0,
      total: 600.0,
      paidAmount: 600.0,
      changeDue: 0.0,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: DateTime.now(),
    );
    final cashSaleItems = [
      SaleInvoiceItem(
        id: 'sii-1',
        invoiceId: 'sale-cash-1',
        productId: productMixer.id,
        quantity: 2,
        unitPrice: 300.0,
        unitCost: 200.0,
        lineTotal: 600.0,
      ),
    ];
    await saleRepo.createSaleInvoice(
      invoice: cashSaleInvoice,
      items: cashSaleItems,
    );

    // المخزون بعد البيع النقدي: الخلاط ينقص من 10 إلى 8
    final pMixerAfterSale1 = await productRepo.getProductById(productMixer.id);
    expect(pMixerAfterSale1!.quantity, 8);

    // ==========================================
    // المرحلة 4: بيع آجل لعميل مسجل (دفع جزئي + تسجيل دين)
    // ==========================================
    final customer = Customer(
      id: 'cust-1',
      name: 'الحاج محمد صابر',
      phone: '01111111111',
      balanceDue: 0.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await customerRepo.insertCustomer(customer);

    // بيع: 3 خلاط @ 300 = 900 ج.م
    // 5 مواسير @ 60 = 300 ج.م
    // الإجمالي = 1200 ج.م
    // دفع العميل: 400 ج.م نقداً
    // المتبقي عليه كدين: 800 ج.م
    // ربح العملية = (3 * 100) + (5 * 20) = 300 + 100 = 400 ج.م
    final creditSaleInvoice = SaleInvoice(
      id: 'sale-credit-1',
      invoiceNumber: '20260002',
      customerId: customer.id,
      subtotal: 1200.0,
      discount: 0.0,
      tax: 0.0,
      total: 1200.0,
      paidAmount: 400.0,
      changeDue: -800.0,
      paymentMethod: 'credit',
      status: 'completed',
      createdAt: DateTime.now(),
    );
    final creditSaleItems = [
      SaleInvoiceItem(
        id: 'sii-2',
        invoiceId: 'sale-credit-1',
        productId: productMixer.id,
        quantity: 3,
        unitPrice: 300.0,
        unitCost: 200.0,
        lineTotal: 900.0,
      ),
      SaleInvoiceItem(
        id: 'sii-3',
        invoiceId: 'sale-credit-1',
        productId: productPipe.id,
        quantity: 5,
        unitPrice: 60.0,
        unitCost: 40.0,
        lineTotal: 300.0,
      ),
    ];
    await saleRepo.createSaleInvoice(
      invoice: creditSaleInvoice,
      items: creditSaleItems,
    );

    // تحقق من المخزون: خلاط = 5، ماسورة = 15
    final pMixerAfterSale2 = await productRepo.getProductById(productMixer.id);
    final pPipeAfterSale2 = await productRepo.getProductById(productPipe.id);
    expect(pMixerAfterSale2!.quantity, 5);
    expect(pPipeAfterSale2!.quantity, 15);

    // تحقق من دين العميل: 800 ج.م
    final custAfterSale2 = await customerRepo.getCustomerById(customer.id);
    expect(custAfterSale2!.balanceDue, 800.0);

    // ==========================================
    // المرحلة 5: تسجيل مصروفات تشغيلية
    // ==========================================
    // فاتورة كهرباء = 150 ج.م
    final expense = Expense(
      id: 'exp-1',
      title: 'كهرباء ومياه المحل',
      amount: 150.0,
      category: 'فواتير (كهرباء/مياه)',
      createdAt: DateTime.now(),
    );
    await expenseRepo.insertExpense(expense);

    // ==========================================
    // المرحلة 6: مرتجع مبيعات (العميل أعاد ماسورة قيمتها 60 ج.م على الحساب)
    // ==========================================
    // تكلفة الماسورة الأصلية = 40 ج.م، سعر بيعها = 60 ج.م
    // تُخصم من دين العميل: 800 - 60 = 740 ج.م
    // وتُعاد إلى المخزون: 15 + 1 = 16 ماسورة
    final returnInvoice = ReturnInvoice(
      id: 'ret-1',
      originalSaleInvoiceId: creditSaleInvoice.id,
      customerId: customer.id,
      returnAmount: 60.0,
      debtReduction: 60.0,
      reason: 'زيادة عن حاجة العمل',
      createdAt: DateTime.now(),
    );
    final returnItems = [
      ReturnInvoiceItem(
        id: 'ri-1',
        returnInvoiceId: 'ret-1',
        productId: productPipe.id,
        quantity: 1,
        unitPrice: 60.0,
        unitCost: 40.0,
        lineTotal: 60.0,
        productName: 'ماسورة 1 بوصة',
        createdAt: DateTime.now(),
      ),
    ];
    await returnRepo.createReturnInvoice(
      invoice: returnInvoice,
      items: returnItems,
      isCashRefund: false,
    );

    // التحقق من دين العميل بعد المرتجع
    final custAfterReturn = await customerRepo.getCustomerById(customer.id);
    expect(custAfterReturn!.balanceDue, 740.0);

    // التحقق من استعادة المخزون
    final pPipeAfterReturn = await productRepo.getProductById(productPipe.id);
    expect(pPipeAfterReturn!.quantity, 16);

    // ==========================================
    // المرحلة 7: تحصيل دفعة نقدية من دين العميل (سند قبض)
    // ==========================================
    // العميل دفع 500 ج.م نقداً في الخزينة
    // المتبقي عليه: 740 - 500 = 240 ج.م
    await customerRepo.addCustomerPayment(
      customerId: customer.id,
      amount: 500.0,
      note: 'سداد جزء من الحساب نقداً',
    );
    final custAfterPayment = await customerRepo.getCustomerById(customer.id);
    expect(custAfterPayment!.balanceDue, 240.0);

    // ==========================================
    // المرحلة 8: سداد دفعة للمورد من الخزينة (سند صرف)
    // ==========================================
    // سداد 800 ج.م للمورد
    // دين المورد ينخفض من 1800 إلى 1000 ج.م
    await supplierRepo.addSupplierPayment(
      supplierId: supplier.id,
      amount: 800.0,
      note: 'سداد دفعة للمورد نقداً',
    );
    final supAfterPayment = await supplierRepo.getSupplierById(supplier.id);
    expect(supAfterPayment!.balanceOwed, 1000.0);

    // ==========================================
    // المرحلة 9: الحساب المالي الختامي الشامل (ShopBalance Audit)
    // ==========================================
    final shopBalance = await balanceRepo.getShopBalance();

    // 1. النقدية الداخلة للصندوق:
    // مبيعات نقدية = 600 (الفاتورة 1) + 400 (المقبوض من الفاتورة 2) = 1000 ج.م
    expect(shopBalance.cashFromSales, 1000.0);
    // تحصيلات ديون العملاء = 500 ج.م
    expect(shopBalance.collectionsIn, 500.0);
    // إجمالي الداخل = 1000 + 500 = 1500 ج.م
    expect(shopBalance.totalCashIn, 1500.0);

    // 2. النقدية الخارجة من الصندوق:
    // مدفوعات الموردين = 1000 (عند الشراء) + 800 (سند الصرف اللاحق) = 1800 ج.م
    expect(shopBalance.supplierPaymentsOut, 1800.0);
    // مصروفات تشغيلية = 150 ج.م
    expect(shopBalance.expensesOut, 150.0);
    // مرتجع نقدي خارج = 0 (لأنه خُصم من حساب العميل وليس نقداً)
    expect(shopBalance.returnsRefundOut, 0.0);
    // إجمالي الخارج = 1800 + 150 = 1950 ج.م
    expect(shopBalance.totalCashOut, 1950.0);

    // 3. صافي رصيد الصندوق: 1500 - 1950 = -450 ج.م
    expect(shopBalance.cashBalance, -450.0);

    // 4. تقييم المخزون الحالي بالتكلفة:
    // 5 خلاط @ 200 = 1000
    // 16 ماسورة @ 40 = 640
    // إجمالي المخزون = 1640 ج.م
    expect(shopBalance.inventoryValue, 1640.0);

    // 5. ديون السوق:
    // ديون العملاء لنا = 240 ج.م
    expect(shopBalance.customerDebt, 240.0);
    // ديون الموردين علينا = 1000 ج.م
    expect(shopBalance.supplierOwed, 1000.0);

    // 6. المعادلة المحاسبية الأساسية للمركز المالي:
    // إجمالي الأصول = النقدية (-450) + المخزون (1640) + ديون العملاء (240) = 1430 ج.م
    expect(shopBalance.totalAssets, 1430.0);
    // إجمالي الخصوم = ديون الموردين (1000) = 1000 ج.م
    expect(shopBalance.totalLiabilities, 1000.0);
    // صافي رأس المال وحقوق الملكية = الأصول - الخصوم = 1430 - 1000 = 430 ج.م
    expect(shopBalance.netWorth, 430.0);

    // 7. مطابقة الأرباح التشغيلية مع تغير حقوق الملكية (P&L Reconciliation):
    // أرباح المبيعات = ربح البيع 1 (200) + ربح البيع 2 (400) - ربح المرتجع (20) = 580 ج.م
    // صافي الربح بعد المصروفات (150) = 580 - 150 = 430 ج.م!
    // صافي الربح يطابق 100% صافي المركز المالي للمحل (Net Profit == Net Worth)
    expect(shopBalance.netWorth, 430.0);
  });
}
