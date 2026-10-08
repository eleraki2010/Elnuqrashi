import 'dart:io';

import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/data/repositories/sale_repository.dart';
import 'package:alnokrashy_pos/presentation/screens/returns_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبار واجهة: إنشاء مرتجع عبر شاشة المرتجعات (إصلاح "لا يمكن عمل مرتجع").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory testSupportDir = Directory.systemTemp;

  group('ReturnsScreen UI', () {
    setUpAll(() async {
      testSupportDir =
          await Directory.systemTemp.createTemp('alnokrashy_returns_test_');
      TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
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

      // بذرة: تصنيف + منتج + فاتورة مكتملة قابلة للإرجاع.
      final now = DateTime.now().toIso8601String();
      await db.insert('categories', {
        'id': 'cat-t',
        'name': 'تجريبي',
        'parent_id': null,
      });
      await db.insert('products', {
        'id': 'p-t',
        'name': 'منتج قابل للإرجاع',
        'category_id': 'cat-t',
        'unit': 'قطعة',
        'purchase_price': 10.0,
        'sale_price': 100.0,
        'quantity': 20,
        'min_quantity_alert': 0,
        'created_at': now,
        'updated_at': now,
      });
      await SaleRepository().createSaleInvoice(
        invoice: SaleInvoice(
          id: 'inv-ui',
          invoiceNumber: '20260100',
          subtotal: 200,
          total: 200,
          paidAmount: 200,
          changeDue: 0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
        items: [
          SaleInvoiceItem(
            id: 'item-ui',
            invoiceId: 'inv-ui',
            productId: 'p-t',
            quantity: 2,
            unitPrice: 100,
            lineTotal: 200,
            unitCost: 10,
            productName: 'منتج قابل للإرجاع',
          ),
        ],
      );
    });

    testWidgets('can create a return through the UI', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Column(
              children: [
                FutureBuilder(
                  future: SaleRepository().getAllSalesInvoices(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text('ERR: ${snap.error}');
                    }
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Text('WAIT');
                    }
                    return Text('DATA: ${snap.data?.length ?? -1}');
                  },
                ),
                const Expanded(child: ReturnsScreen()),
              ],
            ),
          ),
        ),
      );
      // sqflite FFI يعمل عبر عزل حقيقي: futures الناتجة أثناء البناء لا
      // تكتمل داخل الوقت الزائف — نغسلها بدورات (pump + وقت حقيقي قصير).
      Future<void> flush(WidgetTester tester, {int cycles = 8}) async {
        for (var i = 0; i < cycles; i++) {
          await tester.pump();
          await tester
              .runAsync(() => Future<void>.delayed(const Duration(
                  milliseconds: 120)));
          await tester.pump();
        }
      }

      await flush(tester);

      // 1) فتح قائمة الفواتير (عناصر القائمة تُبنى عند الفتح فقط).
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // 2) اختيار الفاتورة.
      expect(find.text('الفاتورة #20260100 - 200 ج.م'), findsOneWidget);
      await tester.tap(find.text('الفاتورة #20260100 - 200 ج.م'));
      await flush(tester);

      // 3) اختيار الصنف (Checkbox جديد داخل سطر الكمية — الرقم الافتراضي
      // هو أقصى كمية قابلة للإرجاع).
      expect(find.textContaining('منتج قابل للإرجاع'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      // 4) تأكيد المرتجع (الزر أسفل نوافذ المعايرة 600px غالباً —
      // نمرّره للعرض أولاً حتى لا يخطئ الضغط). سحب إحداثي مبسّط على
      // منطقة محتوى تبويب "مرتجع جديد" (لا يعتمد على فلدرس المؤشرات
      // القابلة للتمرير المتعددة في الشجرة).
      expect(find.text('تأكيد المرتجع'), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        final bottom = tester.getBottomLeft(find.text('تأكيد المرتجع')).dy;
        if (bottom <= 590) break;
        await tester.dragFrom(const Offset(400, 450), const Offset(0, -200));
        await tester.pump();
      }
      await tester.tap(find.text('تأكيد المرتجع'));
      await flush(tester, cycles: 12);

      // رسالة النجاح ظهرت.
      expect(find.textContaining('تم إنشاء المرتجع بنجاح'), findsOneWidget);

      // قاعدة البيانات فعلاً احتوت المرتجع.
      final rows = await tester.runAsync<List<Map<String, dynamic>>>(
        () async {
          final db = await AppDatabase.instance;
          return db.query('return_invoices');
        },
      );
      expect(rows, hasLength(1));
      expect((rows!.first['return_amount'] as num).toDouble(), 200.0);
    });
  });
}
