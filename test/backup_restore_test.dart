import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:alnokrashy_pos/core/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testSupportDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testSupportDir = await Directory.systemTemp.createTemp('alnokrashy_bk_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return testSupportDir.path;
            }
            if (call.method == 'getApplicationDocumentsDirectory') {
              return testSupportDir.path;
            }
            return null;
          },
        );
    SharedPreferences.setMockInitialValues({});
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

  test('Test restoreFromSnapshot with foreign key mismatch and extra columns', () async {
    final db = await AppDatabase.instance;
    expect(db.isOpen, isTrue);

    // Let's create a snapshot with:
    // 1. A product referencing a category that doesn't exist
    // 2. An invoice item referencing a product that doesn't exist
    // 3. A table row containing an unknown/obsolete column
    // 4. Missing users table (older backup)
    final snapshot = <String, dynamic>{
      '_meta': {'app': 'alnokrashy_pos', 'db_version': 11},
      'categories': [
        {'id': 'cat_1', 'name': 'تصنيف 1', 'parent_id': null}
      ],
      'products': [
        {
          'id': 'prod_orphan',
          'name': 'منتج يتيم',
          'category_id': 'non_existent_category_id', // FOREIGN KEY VIOLATION!
          'unit': 'قطعة',
          'purchase_price': 10.0,
          'sale_price': 15.0,
          'quantity': 5,
          'min_quantity_alert': 2,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'extra_deprecated_column': 'some_val', // EXTRA COLUMN!
        }
      ],
      'sale_invoices': [],
      'sale_invoice_items': [],
      // 'users' missing!
    };

    // This should NOT throw and handle foreign key mismatches, extra columns, and missing users!
    await BackupService.restoreFromSnapshot(snapshot);
    expect(true, isTrue);
  });

  test('Test exportSnapshot and restoreFromSnapshot includes product images, customers, debts, and accounts', () async {
    final db = await AppDatabase.instance;

    // 1. Create a dummy product image file on disk
    final imgDir = Directory('${testSupportDir.path}/test_images');
    await imgDir.create(recursive: true);
    final dummyImgFile = File('${imgDir.path}/prod_test_123.png');
    await dummyImgFile.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9]);

    // 2. Insert Category
    await db.insert('categories', {
      'id': 'cat_full_test',
      'name': 'قسم الاختبار الكامل',
      'parent_id': null,
    });

    // 3. Insert Product with image path
    await db.insert('products', {
      'id': 'prod_with_img',
      'name': 'محبس نحاس 1 بوصة',
      'barcode': '1234567890123',
      'category_id': 'cat_full_test',
      'unit': 'قطعة',
      'purchase_price': 80.0,
      'sale_price': 110.0,
      'quantity': 25,
      'min_quantity_alert': 3,
      'image_url': dummyImgFile.path,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // 4. Insert Customer with debt and due date
    await db.insert('customers', {
      'id': 'cust_debtor_1',
      'name': 'المهندس أحمد حسني',
      'phone': '01012345678',
      'address': 'شارع الجمهورية، المنصورة',
      'balance_due': 4500.0,
      'payment_due_date': '2026-11-01',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // 5. Insert Supplier with owed balance
    await db.insert('suppliers', {
      'id': 'supp_pipes_1',
      'name': 'شركة الأمل للمواسير',
      'phone': '01298765432',
      'balance_owed': 12000.0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // 6. Insert Sale Invoice
    await db.insert('sale_invoices', {
      'id': 'inv_sale_1',
      'invoice_number': 'INV-2026-001',
      'customer_id': 'cust_debtor_1',
      'subtotal': 1100.0,
      'discount': 0.0,
      'tax': 0.0,
      'total': 1100.0,
      'paid_amount': 500.0,
      'change_due': 0.0,
      'payment_method': 'debt',
      'status': 'completed',
      'created_at': DateTime.now().toIso8601String(),
    });

    // 7. Insert Payment
    await db.insert('payments', {
      'id': 'pay_1',
      'party_type': 'customer',
      'party_id': 'cust_debtor_1',
      'amount': 500.0,
      'direction': 'in',
      'note': 'دفعة نقدية تحت الحساب',
      'created_at': DateTime.now().toIso8601String(),
    });

    // 8. Insert Expense
    await db.insert('expenses', {
      'id': 'exp_1',
      'title': 'فاتورة كهرباء المحل',
      'amount': 350.0,
      'category': 'فواتير (كهرباء/مياه)',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Export the snapshot
    final snapshot = await BackupService.exportSnapshot();

    // Verify snapshot contents
    expect(snapshot['products'], isNotEmpty);
    expect(snapshot['customers'], isNotEmpty);
    expect(snapshot['suppliers'], isNotEmpty);
    expect(snapshot['sale_invoices'], isNotEmpty);
    expect(snapshot['payments'], isNotEmpty);
    expect(snapshot['expenses'], isNotEmpty);

    // Verify product image was embedded in Base64
    expect(snapshot['_product_images_base64'], isNotNull);
    final embeddedImages = snapshot['_product_images_base64'] as Map<String, dynamic>;
    expect(embeddedImages.containsKey('prod_test_123.png'), isTrue);

    // Now delete the original image file to simulate new device or app reinstall
    await dummyImgFile.delete();
    expect(await dummyImgFile.exists(), isFalse);

    // Wipe database to test full restore
    await BackupService.restoreFromSnapshot(snapshot);

    // Verify customer was restored with exact debt and details
    final restoredCustomers = await db.query('customers', where: 'id = ?', whereArgs: ['cust_debtor_1']);
    expect(restoredCustomers.length, 1);
    expect(restoredCustomers.first['name'], 'المهندس أحمد حسني');
    expect(restoredCustomers.first['balance_due'], 4500.0);
    expect(restoredCustomers.first['phone'], '01012345678');

    // Verify suppliers were restored
    final restoredSuppliers = await db.query('suppliers', where: 'id = ?', whereArgs: ['supp_pipes_1']);
    expect(restoredSuppliers.length, 1);
    expect(restoredSuppliers.first['balance_owed'], 12000.0);

    // Verify product was restored AND image was reconstructed on disk!
    final restoredProducts = await db.query('products', where: 'id = ?', whereArgs: ['prod_with_img']);
    expect(restoredProducts.length, 1);
    final restoredImgPath = restoredProducts.first['image_url'] as String;
    expect(restoredImgPath, isNotEmpty);
    final restoredImgFile = File(restoredImgPath);
    expect(await restoredImgFile.exists(), isTrue);
    expect(await restoredImgFile.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8, 9]);

    // Verify financial payments and expenses
    final restoredPayments = await db.query('payments', where: 'id = ?', whereArgs: ['pay_1']);
    expect(restoredPayments.length, 1);
    expect(restoredPayments.first['amount'], 500.0);

    final restoredExpenses = await db.query('expenses', where: 'id = ?', whereArgs: ['exp_1']);
    expect(restoredExpenses.length, 1);
    expect(restoredExpenses.first['amount'], 350.0);
  });
}

