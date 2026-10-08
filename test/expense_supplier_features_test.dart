import 'dart:io';

import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/data/models/expense.dart';
import 'package:alnokrashy_pos/data/models/payment.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice.dart';
import 'package:alnokrashy_pos/data/models/supplier.dart';
import 'package:alnokrashy_pos/data/repositories/expense_repository.dart';
import 'package:alnokrashy_pos/data/repositories/supplier_repository.dart';
import 'package:alnokrashy_pos/presentation/screens/expenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات الميزات الجديدة: فئات المصروفات وتعديلها، وكشف حساب المورد الموحد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testSupportDir;

  setUpAll(() async {
    testSupportDir = await Directory.systemTemp.createTemp(
      'alnokrashy_features_test_',
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

  group('ExpenseRepository', () {
    setUp(() async {
      final db = await AppDatabase.instance;
      await db.delete('expenses');
      await db.delete('expense_categories');
      await db.delete('audit_logs');
      // إعادة بذرة الفئات الافتراضية بعد الحذف.
      const defaults = [
        'إيجار',
        'فواتير (كهرباء/مياه)',
        'رواتب',
        'صيانة',
        'شحن ونقل',
        'أخرى',
      ];
      final now = DateTime.now().toIso8601String();
      for (final name in defaults) {
        await db.insert('expense_categories', {
          'id': name,
          'name': name,
          'created_at': now,
        });
      }
    });

    test('getCategories returns defaults on fresh table', () async {
      final repo = ExpenseRepository();
      final categories = await repo.getCategories();
      expect(categories, containsAll(ExpenseRepository.defaultCategories));
    });

    test('addCategory adds a custom category exactly once', () async {
      final repo = ExpenseRepository();
      await repo.addCategory('تسويق');
      await repo.addCategory('تسويق'); // تكرار لا يضيف مرة أخرى
      final categories = await repo.getCategories();
      expect(categories.where((c) => c == 'تسويق'), hasLength(1));
      expect(categories, hasLength(7));
    });

    test('updateExpense updates fields and writes an audit log', () async {
      final repo = ExpenseRepository();
      final expense = Expense(
        id: 'exp-edit-1',
        title: 'إيجار يوليه',
        amount: 3000,
        category: 'إيجار',
        createdAt: DateTime(2026, 7, 1),
      );
      await repo.insertExpense(expense);

      await repo.updateExpense(
        expense.copyWith(title: 'إيجار يوليو (معدّل)', amount: 2500),
      );

      final updated = (await repo.getAllExpenses()).single;
      expect(updated.title, 'إيجار يوليو (معدّل)');
      expect(updated.amount, 2500);
      expect(updated.category, 'إيجار');

      final db = await AppDatabase.instance;
      final audit = await db.query(
        'audit_logs',
        where: "table_name = 'expenses' AND action = 'update'",
      );
      expect(audit, hasLength(1));
    });
  });

  group('SupplierStatement.buildEntries', () {
    SupplierStatement buildStatement() {
      final supplier = Supplier(
        id: 's-1',
        name: 'مورد تجريبي',
        balanceOwed: 2000,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      return SupplierStatement(
        supplier: supplier,
        purchases: [
           PurchaseInvoice(
             id: 'pi-1',
             supplierId: 's-1',
             total: 5000,
             paidAmount: 2000,
             tax: 0.0,
             createdAt: DateTime(2026, 1, 5),
           ),
        ],
        payments: [
          Payment(
            id: 'pm-1',
            partyType: 'supplier',
            partyId: 's-1',
            amount: 2000,
            direction: 'out',
            createdAt: DateTime(2026, 1, 6),
          ),
          Payment(
            id: 'pm-2',
            partyType: 'supplier',
            partyId: 's-1',
            amount: 1000,
            direction: 'out',
            note: 'سداد جزئي',
            createdAt: DateTime(2026, 1, 7),
          ),
        ],
      );
    }

    test('entries are chronological with running balance ending on owed', () {
      final entries = buildStatement().buildEntries();
      expect(entries, hasLength(3));
      expect(entries.first.isPurchase, isTrue);
      expect(entries.map((e) => e.runningBalance).toList(), [
        5000.0,
        3000.0,
        2000.0,
      ]);
      // الرصيد الأخير = رصيد المورد الحالي بالضبط.
      expect(
        entries.last.runningBalance,
        buildStatement().supplier.balanceOwed,
      );
    });

    test('totals aggregate correctly', () {
      final st = buildStatement();
      expect(st.totalPurchases, 5000.0);
      expect(st.totalPayments, 3000.0);
    });
  });

  group('ExpensesScreen UI', () {
    setUp(() async {
      final db = await AppDatabase.instance;
      await db.delete('expenses');
      await db.insert('expenses', {
        'id': 'exp-ui-1',
        'title': 'إيجار المحل - أكتوبر',
        'amount': 3000.0,
        'category': 'إيجار',
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    testWidgets('shows an edit button on each expense row', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const ExpensesScreen()),
        ),
      );

      Future<void> flush(WidgetTester tester, {int cycles = 8}) async {
        for (var i = 0; i < cycles; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)),
          );
          await tester.pump();
        }
      }

      await flush(tester);

      // صف المصروف ظهرت مع زر التعديل.
      expect(find.text('إيجار المحل - أكتوبر'), findsOneWidget);
      expect(find.byTooltip('تعديل المصروف'), findsOneWidget);

      // فتح حوار التعديل (الحوار يُفتح بعد قراءة الفئات من القاعدة
      // عبر وقت حقيقي، كما في باقي اختبارات sqflite-FFI).
      await tester.tap(find.byTooltip('تعديل المصروف'));
      await flush(tester);
      expect(find.text('تعديل مصروف'), findsOneWidget);
      expect(find.text('حفظ التعديل'), findsOneWidget);
      // زر إضافة فئة جديدة بجوار قائمة الفئة.
      expect(find.byTooltip('إضافة فئة جديدة'), findsOneWidget);
    });
  });
}
