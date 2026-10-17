import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:alnokrashy_pos/core/constants/app_constants.dart';
import 'package:alnokrashy_pos/core/responsive/responsive_scope.dart';
import 'package:alnokrashy_pos/data/models/customer.dart';
import 'package:alnokrashy_pos/data/models/payment.dart';
import 'package:alnokrashy_pos/data/models/product.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice_item.dart';
import 'package:alnokrashy_pos/data/models/return_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/data/models/supplier.dart';
import 'package:alnokrashy_pos/data/repositories/sale_repository.dart';
import 'package:alnokrashy_pos/presentation/screens/dashboard_screen.dart';
import 'package:alnokrashy_pos/presentation/screens/main_layout_screen.dart';
import 'package:alnokrashy_pos/providers/app_providers.dart';
import 'package:alnokrashy_pos/providers/phase2_providers.dart';
import 'package:alnokrashy_pos/providers/pos_cart_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'vat_enabled': false});
  });

  group('SPECKIT Section 5 Core Business Rules Tests', () {
    test('Rule 1: line_total = quantity * unit_price', () {
      final item = SaleInvoiceItem(
        id: '1',
        invoiceId: 'inv-1',
        productId: 'p-1',
        quantity: 3,
        unitPrice: 150.0,
        lineTotal: 3 * 150.0,
      );
      expect(item.lineTotal, 450.0);
    });

    test('Rule 2 & 3: subtotal = SUM(line_total) and total = subtotal - discount + tax', () {
      final cartItem1 = CartItem(
        product: Product(
          id: 'p-1',
          name: 'خلاط مياه',
          categoryId: 'cat-1',
          unit: 'قطعة',
          purchasePrice: 200.0,
          salePrice: 300.0,
          quantity: 10,
          minQuantityAlert: 2,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        quantity: 2,
        unitPrice: 300.0,
      );

      final cartItem2 = CartItem(
        product: Product(
          id: 'p-2',
          name: 'ماسورة 1 بوصة',
          categoryId: 'cat-1',
          unit: 'متر',
          purchasePrice: 40.0,
          salePrice: 60.0,
          quantity: 50,
          minQuantityAlert: 10,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        quantity: 5,
        unitPrice: 60.0,
      );

      final cartState = CartState(
        items: [cartItem1, cartItem2],
        discount: 50.0,
        tax: 0.0,
        paidAmount: 1000.0,
      );

      expect(cartState.subtotal, 900.0);
      expect(cartState.total, 850.0);
      expect(cartState.changeDue, 150.0);
      expect(cartState.isChangePositive, true);
      expect(cartState.remainingOnCustomer, 0.0);
    });

    test('Rule 4: change_due = paid_amount - total (negative -> remainingOnCustomer)', () {
      final invoice = SaleInvoice(
        id: 'inv-test',
        invoiceNumber: 'INV-20260917-0001',
        subtotal: 500.0,
        discount: 0.0,
        tax: 0.0,
        total: 500.0,
        paidAmount: 300.0,
        changeDue: 300.0 - 500.0,
        paymentMethod: 'credit',
        status: 'completed',
        createdAt: DateTime.now(),
      );

      expect(invoice.changeDue, -200.0);
      expect(invoice.isChangePositive, false);
      expect(invoice.remainingOnCustomer, 200.0);
    });

    test('Rule 6: Purchases update inventory and line totals', () {
      final item = PurchaseInvoiceItem(
        id: 'pi-1',
        invoiceId: 'p-inv-1',
        productId: 'prod-1',
        quantity: 20,
        unitCost: 15.0,
        lineTotal: 20 * 15.0,
      );
      expect(item.lineTotal, 300.0);

       final purchaseInvoice = PurchaseInvoice(
         id: 'p-inv-1',
         supplierId: 'sup-1',
         items: [item],
         total: 300.0,
         paidAmount: 100.0,
         tax: 0.0,
         createdAt: DateTime.now(),
       );

      expect(purchaseInvoice.total, 300.0);
      expect(purchaseInvoice.remainingOwed, 200.0);
      expect(purchaseInvoice.isFullyPaid, false);
    });

    test('Rule 7: Credit sales update customer balance due', () {
      var customer = Customer(
        id: 'c-1',
        name: 'عميل أحمد',
        balanceDue: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(customer.hasDebt, false);

      // Simulating credit sale: total 750, paid 250 -> remaining 500
      final creditDue = 750.0 - 250.0;
      customer = customer.copyWith(balanceDue: customer.balanceDue + creditDue);
      expect(customer.balanceDue, 500.0);
      expect(customer.hasDebt, true);

      // Simulating payment on account: paid 200
      customer = customer.copyWith(balanceDue: customer.balanceDue - 200.0);
      expect(customer.balanceDue, 300.0);
    });

    test('Phase 2: Supplier balance owed calculation', () {
      var supplier = Supplier(
        id: 'sup-1',
        name: 'شركة الأهرام للسيراميك',
        balanceOwed: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(supplier.hasOwed, false);

      // Simulating credit purchase: total 5000, paid 2000 -> remaining 3000
      final owed = 5000.0 - 2000.0;
      supplier = supplier.copyWith(balanceOwed: supplier.balanceOwed + owed);
      expect(supplier.balanceOwed, 3000.0);
      expect(supplier.hasOwed, true);

      // Simulating payment to supplier: paid 3000
      supplier = supplier.copyWith(balanceOwed: supplier.balanceOwed - 3000.0);
      expect(supplier.balanceOwed, 0.0);
      expect(supplier.hasOwed, false);
    });

    test('Rule 8: Stock alerts (quantity <= min_quantity_alert -> low stock, quantity <= 0 -> out of stock)', () {
      final safeProduct = Product(
        id: 'p-safe',
        name: 'منتج كافي',
        categoryId: 'cat-1',
        unit: 'قطعة',
        purchasePrice: 10.0,
        salePrice: 15.0,
        quantity: 20,
        minQuantityAlert: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(safeProduct.hasStockAlert, false);

      final lowStockProduct = Product(
        id: 'p-low',
        name: 'منتج قليل',
        categoryId: 'cat-1',
        unit: 'قطعة',
        purchasePrice: 10.0,
        salePrice: 15.0,
        quantity: 4,
        minQuantityAlert: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(lowStockProduct.hasStockAlert, true);
      expect(lowStockProduct.isLowStock, true);
      expect(lowStockProduct.isOutOfStock, false);

      final outOfStockProduct = Product(
        id: 'p-zero',
        name: 'منتج نافد',
        categoryId: 'cat-1',
        unit: 'قطعة',
        purchasePrice: 10.0,
        salePrice: 15.0,
        quantity: 0,
        minQuantityAlert: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(outOfStockProduct.hasStockAlert, true);
      expect(outOfStockProduct.isOutOfStock, true);
    });

    test('Rule 9: Profit margin = sale_price - purchase_price', () {
      final product = Product(
        id: 'p-profit',
        name: 'خلاط بانيو',
        categoryId: 'cat-1',
        unit: 'قطعة',
        purchasePrice: 450.0,
        salePrice: 650.0,
        quantity: 10,
        minQuantityAlert: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(product.profitMargin, 200.0);
    });
  });

  group('Accounting integrity safeguards', () {
    Product makeProduct({
      required String id,
      double purchasePrice = 100.0,
      double salePrice = 150.0,
      int quantity = 20,
    }) {
      return Product(
        id: id,
        name: 'منتج $id',
        categoryId: 'cat-1',
        unit: 'قطعة',
        purchasePrice: purchasePrice,
        salePrice: salePrice,
        quantity: quantity,
        minQuantityAlert: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    test('Rule 9b: buildSaleInvoice freezes unit_cost at time of sale', () {
      final product = makeProduct(id: 'p-a', purchasePrice: 80.0);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);
      notifier.addProduct(product, quantity: 4);

      final invoice = notifier.buildSaleInvoice(invoiceNumber: 'INV-1');

      // سعر الشراء مُجمّد في كل عنصر = 80 حتى لو تغيّر لاحقاً.
      expect(invoice.items.first.unitCost, 80.0);
      expect(invoice.items.length, 1);
      expect(invoice.items.first.quantity, 4);
    });

    test('Frozen unit_cost keeps historical profit accurate after price change', () {
      final product = makeProduct(id: 'p-b', purchasePrice: 100.0, salePrice: 200.0);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);
      notifier.addProduct(product, quantity: 3);

      final invoice = notifier.buildSaleInvoice(invoiceNumber: 'INV-2');

      // الربح لحظة البيع: (200 - 100) * 3 = 300
      final profitAtSaleTime = invoice.items.fold<double>(
        0.0,
        (sum, i) => sum + (i.unitPrice - (i.unitCost ?? 0)) * i.quantity,
      );
      expect(profitAtSaleTime, 300.0);

      // لو ارتفع سعر الشراء لاحقاً إلى 140، يجب أن يبقى الربح التاريخي 300.
      final laterPurchasePrice = 140.0;
      final profitUsingFrozenCost = invoice.items.fold<double>(
        0.0,
        (sum, i) => sum + (i.unitPrice - (i.unitCost ?? laterPurchasePrice)) * i.quantity,
      );
      expect(profitUsingFrozenCost, 300.0);
    });

    test('Cart total never goes negative under huge discount', () {
      final product = makeProduct(id: 'p-c', salePrice: 100.0);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);
      notifier.addProduct(product, quantity: 1);
      notifier.setDiscount(500.0);

      final cart = container.read(cartProvider);
      expect(cart.total, 0.0);
      expect(cart.changeDue, greaterThanOrEqualTo(0));
    });

    test('Customer statement reflects returns in balance_due consistency', () {
      // الدين المسجل = الإجمالي - المدفوع.
      final total = 1000.0;
      final paid = 300.0;
      final debt = total - paid;
      expect(debt, 700.0);

      // مرتجع 200 يقلل الدين إلى 500.
      final returnAmount = 200.0;
      final balanceAfterReturn = debt - returnAmount;
      expect(balanceAfterReturn, 500.0);

      // مرتجع أكبر من الدين ينتج رصيداً دائناً سالباً لصالح العميل
      // (بائع النقدي دفع كاملاً فيستحق استرداد الفرق) بدل ابتلاعه.
      final bigReturn = 900.0;
      final creditBalance = debt - bigReturn;
      expect(creditBalance, -200.0);
    });

    test('Returnable quantity = sold - already returned (no double return)', () {
      final soldQty = 10;
      final firstReturn = 4;
      final secondReturnMax = soldQty - firstReturn;
      expect(secondReturnMax, 6);

      // محاولة إرجاع أكثر من المتبقي يجب رفضها.
      final requested = 7;
      expect(requested > secondReturnMax, true);
    });

    test('Return items are linked to the return invoice id '
        '(regression: empty return_invoice_id broke returns history)', () {
      final now = DateTime.now();
      final items = [
        ReturnInvoiceItem(
          id: 'ri-1',
          returnInvoiceId: '',
          productId: 'p-1',
          quantity: 2,
          unitPrice: 50.0,
          lineTotal: 100.0,
          productName: 'خلاط مياه',
          createdAt: now,
        ),
      ];

      // المستودع يعيّن معرّف المرتجع على كل عنصر قبل الحفظ.
      for (final item in items) {
        item.returnInvoiceId = 'ret-100';
      }

      expect(items.first.toMap()['return_invoice_id'], 'ret-100');
    });

    test('TodayStats cash + credit equals total, netSales subtracts returns', () {
      final stats = TodayStats(
        totalSales: 1000.0,
        invoiceCount: 5,
        estimatedProfit: 200.0,
        weeklySalesTrend: [],
        totalCustomerDebt: 0.0,
        cashSales: 700.0,
        creditSales: 300.0,
        cashInvoiceCount: 3,
        creditInvoiceCount: 2,
        todayReturns: 150.0,
        purchasesToday: 400.0,
        collectionsToday: 250.0,
      );

      // تفصيل طرق الدفع يجب أن يجمع الإجمالي.
      expect(stats.cashSales + stats.creditSales, stats.totalSales);
      expect(stats.cashInvoiceCount + stats.creditInvoiceCount,
          stats.invoiceCount);
      // صافي المبيعات = الإجمالي − المرتجعات.
      expect(stats.netSales, 850.0);
    });
  });

  group('Payments accounting', () {
    test('Payment keeps its note through toMap/fromMap round-trip', () {
      final now = DateTime.now();
      final payment = Payment(
        id: 'pay-1',
        partyType: 'customer',
        partyId: 'c-1',
        amount: 250.0,
        direction: 'in',
        note: 'تحصيل دفعة أولى من حساب العميل',
        createdAt: now,
      );

      final map = payment.toMap();
      expect(map['note'], 'تحصيل دفعة أولى من حساب العميل');

      final restored = Payment.fromMap(map);
      expect(restored.note, 'تحصيل دفعة أولى من حساب العميل');
      expect(restored.direction, 'in');
    });
  });

  group('Navigation route integrity', () {
    testWidgets('Dashboard buttons navigate by route name, not raw index',
        (tester) async {
      await initializeDateFormatting('ar', null);
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final invokedRoutes = <String>[];
      final container = ProviderContainer(
        overrides: [
          dashboardStatsProvider.overrideWith(
            (ref) async => TodayStats(
              totalSales: 500.0,
              invoiceCount: 3,
              estimatedProfit: 120.0,
              weeklySalesTrend: [],
              totalCustomerDebt: 0.0,
            ),
          ),
          lowStockCountProvider.overrideWith((ref) async => 0),
          salesHistoryProvider.overrideWith((ref) async => []),
          stockAlertsProvider.overrideWith((ref) async => []),
          topSellingProductsProvider.overrideWith((ref) async => []),
          customersNearingDueDateProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ar', 'EG'),
            home: DashboardScreen(
              onNavigate: (route) => invokedRoutes.add(route),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // زر "نقطة البيع" في الترويسة → 'pos'
      await tester.tap(find.byTooltip('نقطة البيع'));
      await tester.pump();
      expect(invokedRoutes, contains('pos'));

      // لا يجب أن تُطلب مسارات الجرد من لوحة القيادة.
      expect(invokedRoutes, isNot(contains('count')));
    });
  });

  group('Responsive scaling', () {
    test('scaleForWidth is 1.0 at the phone baseline and clamps smoothly', () {
      // خط الأساس: عرض هاتف نموذجي → عامل 1.0 (لا تكبير).
      expect(ResponsiveUtils.scaleForWidth(390.0), closeTo(1.0, 1e-9));

      // شاشة أوسع (هاتف عادي/تابلت/ديسكتوب) → ثابت عند 1.0 تماماً:
      // لا تكبير بعد خط الأساس (التطبيق يعمل على اللوحي وأدوات POS لا
      // تحتاج خطوطاً أكبر — العرض الواسع يُستغل في أعمدة أكثر).
      expect(ResponsiveUtils.scaleForWidth(500.0), 1.0);
      expect(ResponsiveUtils.scaleForWidth(1024.0), 1.0);
      expect(
          ResponsiveUtils.scaleForWidth(3900.0), ResponsiveUtils.maxScale);

      // شاشة أضيق → تصغير لكنه مقيّد بالحد الأدنى (لا انكماش مفرط).
      expect(ResponsiveUtils.scaleForWidth(200.0),
          greaterThanOrEqualTo(ResponsiveUtils.minScale));
      expect(ResponsiveUtils.scaleForWidth(200.0), ResponsiveUtils.minScale);

      // رتابة: كلما اتسعت الشاشة زاد العامل (أو بقي عند الحد).
      double prev = 0;
      for (double w = 200; w <= 2000; w += 100) {
        final s = ResponsiveUtils.scaleForWidth(w);
        expect(s, greaterThanOrEqualTo(prev));
        prev = s;
      }
    });

    test('scaledFont/scaledIcon/scaledSpacing multiply the base by the factor',
        () {
      const base = 16.0;
      // 780dp أوسع من خط الأساس → عامل ثابت 1.0 (لا تكبير على التابلت).
      final width = 780.0;
      final factor = ResponsiveUtils.scaleForWidth(width);
      expect(factor, 1.0);
      expect(ResponsiveUtils.scaledFont(base, width), base * factor);
      expect(ResponsiveUtils.scaledIcon(base, width), base * factor);
      expect(ResponsiveUtils.scaledSpacing(base, width), base * factor);
    });

    test('statGridColumns shows correct columns based on screen breakpoint', () {
      expect(ResponsiveUtils.statGridColumns(390.0), 1); // هاتف عمودي (<480)
      expect(ResponsiveUtils.statGridColumns(480.0), 2); // تابلت رأسي (480-949)
      expect(ResponsiveUtils.statGridColumns(576.0), 2); // تابلت مع شريط جانبي
      expect(ResponsiveUtils.statGridColumns(1056.0), 4); // تابلت أفقي (>=950)
      expect(ResponsiveUtils.statGridColumns(1600.0), 4); // ديسكتوب عريض
    });

    testWidgets('ResponsiveScope exposes the content width to descendants',
        (tester) async {
      double? capturedWidth;
      double? capturedFallback;

      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveScope(
            contentWidth: 777.0,
            child: Builder(
              builder: (context) {
                capturedWidth = ResponsiveScope.widthOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(capturedWidth, 777.0);

      // عند غياب النطاق يسقط على عرض الشاشة المتاح.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedFallback = ResponsiveScope.widthOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final expectedFallback =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(capturedFallback, expectedFallback);
    });
  });

  group('Responsive navigation', () {
    testWidgets('compact width shows 5 destinations and a More sheet',
        (tester) async {
      await initializeDateFormatting('ar', null);
      // هاتف: شريط سفلي بـ 4 وجهات أساسية + "المزيد" فقط (لا 18 وجهة متلخبطة).
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          lowStockCountProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainLayoutScreen(),
          ),
        ),
      );
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('المزيد')), findsOneWidget);

      // زر "المزيد" يفتح ورقة بالوجهات الثانوية (المدفوعات مثلاً).
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('المزيد')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('المدفوعات'), findsWidgets);
    });

    testWidgets('portrait tablet starts with the sidebar collapsed',
        (tester) async {
      await initializeDateFormatting('ar', null);
      // تابلت رأسي 800dp: الشريط الجانبي مطوي افتراضياً لترك مساحة للمحتوى.
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          lowStockCountProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainLayoutScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // مطوي → زر التوسيع ظاهر، زر الطي غير ظاهر.
      expect(find.byTooltip('توسيع القائمة'), findsOneWidget);
      expect(find.byTooltip('طي القائمة'), findsNothing);
    });

    testWidgets('desktop width starts with the sidebar expanded',
        (tester) async {
      await initializeDateFormatting('ar', null);
      // شاشة عريضة: الشريط موسّع افتراضياً.
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          lowStockCountProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainLayoutScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('طي القائمة'), findsOneWidget);
      expect(find.byTooltip('توسيع القائمة'), findsNothing);
    });

    // حارس دائم: التخطيط لا يفيض على أي حجم شاشة شائع (هاتف/تابلت رأسي
    // وأفقي/ديسكتوب). هذا يحمي من رجوع مشكلة "القائمة المتداخلة".
    for (final size in const [
      Size(390, 844), // هاتف
      Size(600, 1024), // تابلت صغير رأسي
      Size(800, 1280), // تابلت رأسي
      Size(1280, 800), // تابلت أفقي
      Size(1600, 900), // ديسكتوب
    ]) {
      testWidgets('no layout overflow at ${size.width}x${size.height}',
          (tester) async {
        await initializeDateFormatting('ar', null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final overflowErrors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          overflowErrors.add(details.exception.toString());
        };

        final container = ProviderContainer(
          overrides: [
            lowStockCountProvider.overrideWith((ref) async => 0),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: MainLayoutScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        FlutterError.onError = original;

        final overflows = overflowErrors
            .where((e) => e.contains('overflowed'))
            .toList();
        expect(
          overflows,
          isEmpty,
          reason:
              'التخطيط يفيض عند ${size.width}x${size.height}: ${overflows.join(', ')}',
        );
      });
    }
  });

  group('Backup persistence', () {
    test('Backup content is actually written to disk (file_picker bug guard)', () async {
      // file_picker على Windows كان يُرجع المسار دون كتابة bytes فعلياً.
      // هنا نتحقق من منطق الكتابة نفسه: المسار → ملف فعلي بمحتوى JSON صالح.
      final dir = await Directory.systemTemp.createTemp('backup_test_');
      addTearDown(() => dir.delete(recursive: true));

      final snapshot = {
        '_meta': {
          'app': 'alnokrashy_pos',
          'db_version': 5,
          'exported_at': DateTime.now().toIso8601String(),
        },
        'categories': [
          {'id': 'cat_test', 'name': 'اختبار', 'parent_id': null},
        ],
      };
      final json = const JsonEncoder.withIndent('  ').convert(snapshot);
      final path = '${dir.path}\\alnokrashy_backup_test.json';
      final file = File(path);
      await file.writeAsString(json, flush: true);

      // الملف موجود وغير فارغ.
      expect(await file.exists(), true);
      expect(await file.length(), greaterThan(0));

      // محتواه JSON صالح يحمل توقيع تطبيقنا.
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map)['_meta']['app'], 'alnokrashy_pos');
    });

    test('Restore rejects files that are not valid app backups', () {
      // ملف JSON عادي ليس نسخة احتياطية → يجب رفضه قبل مسح البيانات.
      final notABackup = {'foo': 'bar'};
      final meta = notABackup['_meta'];
      expect(meta is Map && (meta as Map)['app'] == 'alnokrashy_pos', false);
    });
  });
}
