import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static const String _dbName = 'alnokrashy_pos.db';
  // v2: audit_logs. v3: جداول المرتجعات. v4: المستخدم الافتراضي (المالك).
  // v5: حفظ unit_cost في عناصر الفواتير لحساب أرباح تاريخية دقيقة.
  // v6: ملاحظات المدفوعات (note) لتوثيق التحصيلات ومدفوعات الموردين.
  // v7: موعد سداد المديونية (customers.payment_due_date) + جدول shop_profile
  //     لحفظ مسار شعار المحل (يظهر أعلى التطبيق وفي الفواتير والطباعة).
  // v8: المرتجع يسجّل مقدار ما خُصم من دين العميل (debt_reduction) ليبقى
  //     كشف الحساب والخزينة متسقين محاسبياً (الزائد عن الدين فقط يخرج نقداً).
  // v9: unit_cost في عناصر المرتجعات حتى يُخصم ربح الأصناف المرتجعة من الأرباح
  //     (صافي الربح كان يتضخم بربح ما أُرجع).
  // v10: جدول فئات المصروفات (default + مخصصة) لتتيح شاشة المصروفات
  //      إضافة فئات جديدة بجوار قائمة الفئة.
  // v11: جداول مرتجع المشتريات للموردين (purchase_return_invoices & items)
  //      وفئة مصروفات توالف وكسر المخزون.
  static const int dbVersion = 11;
  static const int _dbVersion = dbVersion;

  static Database? _database;

  static Future<Database> get instance async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final appSupportDir = await getApplicationSupportDirectory();
      await Directory(appSupportDir.path).create(recursive: true);
      path = join(appSupportDir.path, _dbName);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, _dbName);
    }

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 1. Category
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT
      )
    ''');

    // 2. Product
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT,
        category_id TEXT NOT NULL,
        unit TEXT NOT NULL,
        purchase_price REAL NOT NULL,
        sale_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        min_quantity_alert INTEGER NOT NULL,
        image_url TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE RESTRICT
      )
    ''');

    // 3. StockMovement
    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity_change INTEGER NOT NULL,
        reference_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 4. Customer
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        balance_due REAL NOT NULL DEFAULT 0.0,
        payment_due_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 5. Supplier
    await db.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        balance_owed REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 6. SaleInvoice
    await db.execute('''
      CREATE TABLE sale_invoices (
        id TEXT PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id TEXT,
        cashier_id TEXT,
        subtotal REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        tax REAL NOT NULL DEFAULT 0.0,
        total REAL NOT NULL,
        paid_amount REAL NOT NULL,
        change_due REAL NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
      )
    ''');

    // 7. SaleInvoiceItem
    await db.execute('''
      CREATE TABLE sale_invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        line_total REAL NOT NULL,
        unit_cost REAL,
        FOREIGN KEY (invoice_id) REFERENCES sale_invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');

     // 8. PurchaseInvoice
     await db.execute('''
       CREATE TABLE purchase_invoices (
         id TEXT PRIMARY KEY,
         supplier_id TEXT NOT NULL,
         total REAL NOT NULL,
         tax REAL NOT NULL DEFAULT 0.0,
         paid_amount REAL NOT NULL,
         created_at TEXT NOT NULL,
         FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE RESTRICT
       )
     ''');

    // 9. PurchaseInvoiceItem
    await db.execute('''
      CREATE TABLE purchase_invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES purchase_invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');

    // 10. Payment
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        party_type TEXT NOT NULL,
        party_id TEXT NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 11. User
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL
      )
    ''');

    // 12. Expense
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 13. AuditLog (Rule 11: Soft Delete + Audit Trail)
    await db.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        action TEXT NOT NULL,
        old_values TEXT,
        new_values TEXT,
        user_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 14. ReturnInvoice
    await db.execute('''
      CREATE TABLE return_invoices (
        id TEXT PRIMARY KEY,
        original_sale_invoice_id TEXT NOT NULL,
        customer_id TEXT,
        return_amount REAL NOT NULL,
        debt_reduction REAL NOT NULL DEFAULT 0.0,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (original_sale_invoice_id) REFERENCES sale_invoices (id) ON DELETE RESTRICT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
      )
    ''');

    // 15. ReturnInvoiceItem
    await db.execute('''
      CREATE TABLE return_invoice_items (
        id TEXT PRIMARY KEY,
        return_invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL,
        line_total REAL NOT NULL,
        product_name TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (return_invoice_id) REFERENCES return_invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');

    // 16. ShopProfile (بيانات المحل: شعار محلي)
    await db.execute('''
      CREATE TABLE shop_profile (
        id TEXT PRIMARY KEY,
        logo_path TEXT,
        updated_at TEXT
      )
    ''');

    // 17. ExpenseCategories (فئات المصروفات: الافتراضية + المخصصة)
    await db.execute('''
      CREATE TABLE expense_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
    await _seedDefaultExpenseCategories(db);

    // 18. PurchaseReturnInvoices (مرتجع المشتريات للموردين)
    await db.execute('''
      CREATE TABLE purchase_return_invoices (
        id TEXT PRIMARY KEY,
        original_purchase_invoice_id TEXT,
        supplier_id TEXT NOT NULL,
        return_amount REAL NOT NULL,
        debt_reduction REAL NOT NULL DEFAULT 0.0,
        cash_refund_in REAL NOT NULL DEFAULT 0.0,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (original_purchase_invoice_id) REFERENCES purchase_invoices (id) ON DELETE SET NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE RESTRICT
      )
    ''');

    // 19. PurchaseReturnInvoiceItems
    await db.execute('''
      CREATE TABLE purchase_return_invoice_items (
        id TEXT PRIMARY KEY,
        return_invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL,
        line_total REAL NOT NULL,
        product_name TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (return_invoice_id) REFERENCES purchase_return_invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');

    // Seed default categories
    await _seedDefaultCategories(db);
    // Seed default owner account (Phase 3: users & roles)
    await _seedDefaultOwner(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id TEXT PRIMARY KEY,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          action TEXT NOT NULL,
          old_values TEXT,
          new_values TEXT,
          user_id TEXT,
          note TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS return_invoices (
          id TEXT PRIMARY KEY,
          original_sale_invoice_id TEXT NOT NULL,
          customer_id TEXT,
          return_amount REAL NOT NULL,
          reason TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (original_sale_invoice_id) REFERENCES sale_invoices (id) ON DELETE RESTRICT,
          FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS return_invoice_items (
          id TEXT PRIMARY KEY,
          return_invoice_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_price REAL NOT NULL,
          line_total REAL NOT NULL,
          product_name TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (return_invoice_id) REFERENCES return_invoices (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
        )
      ''');
    }
    if (oldVersion < 4) {
      await _seedDefaultOwner(db);
    }
    if (oldVersion < 5) {
      // حفظ سعر الشراء لحظة البيع لحساب أرباح تاريخية دقيقة.
      // الترقية idempotent: إذا أُضيف العمود من قبل (تشغيل سابق ناقص) نتجاهل الخطأ.
      await _addColumnIfMissing(db, 'sale_invoice_items', 'unit_cost', 'REAL');
    }
    if (oldVersion < 6) {
      // ملاحظة على الدفعة (سبب التحصيل/السداد) لتوثيق العمليات المحاسبية.
      await _addColumnIfMissing(db, 'payments', 'note', 'TEXT');
    }
    if (oldVersion < 7) {
      // موعد سداد مديونية العميل (لتنبيه تأخر السداد داخل التطبيق).
      await _addColumnIfMissing(db, 'customers', 'payment_due_date', 'TEXT');
      // جدول بيانات المحل (مسار الشعار المحلي).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shop_profile (
          id TEXT PRIMARY KEY,
          logo_path TEXT,
          updated_at TEXT
        )
      ''');
    }
    if (oldVersion < 8) {
      // المرتجع يسجّل مقدار ما خُصم من دين العميل (الزائد عن الدين يخرج نقداً).
      await _addColumnIfMissing(
        db,
        'return_invoices',
        'debt_reduction',
        'REAL NOT NULL DEFAULT 0.0',
      );
    }
    if (oldVersion < 9) {
      // تكلفة الصنف وقت البيع الأصلي لحساب ربح المرتجع وخصمه من الأرباح.
      await _addColumnIfMissing(
        db,
        'return_invoice_items',
        'unit_cost',
        'REAL',
      );
    }
    if (oldVersion < 10) {
      // فئات المصروفات القابلة للتوسعة من شاشة المصروفات.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expense_categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL
        )
      ''');
      await _seedDefaultExpenseCategories(db);
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_return_invoices (
          id TEXT PRIMARY KEY,
          original_purchase_invoice_id TEXT,
          supplier_id TEXT NOT NULL,
          return_amount REAL NOT NULL,
          debt_reduction REAL NOT NULL DEFAULT 0.0,
          cash_refund_in REAL NOT NULL DEFAULT 0.0,
          reason TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (original_purchase_invoice_id) REFERENCES purchase_invoices (id) ON DELETE SET NULL,
          FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_return_invoice_items (
          id TEXT PRIMARY KEY,
          return_invoice_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_cost REAL NOT NULL,
          line_total REAL NOT NULL,
          product_name TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (return_invoice_id) REFERENCES purchase_return_invoices (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
        )
      ''');
      // فئة توالف وكسر المخزون
      await db.insert(
        'expense_categories',
        {'id': 'توالف وكسر مخزون', 'name': 'توالف وكسر مخزون', 'created_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// بذرة فئات المصروفات الافتراضية (نفس قائمة ExpenseRepository.defaultCategories).
  static Future<void> _seedDefaultExpenseCategories(Database db) async {
    const defaults = [
      'إيجار',
      'فواتير (كهرباء/مياه)',
      'رواتب',
      'صيانة',
      'شحن ونقل',
      'توالف وكسر مخزون',
      'أخرى',
    ];
    final now = DateTime.now().toIso8601String();
    for (final name in defaults) {
      await db.insert('expense_categories', {
        'id': name,
        'name': name,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedDefaultCategories(Database db) async {
    final categories = [
      {'id': 'cat_plumbing', 'name': 'أدوات صحية وسباكة', 'parent_id': null},
      {'id': 'cat_pipes', 'name': 'مواسير ولوازم', 'parent_id': 'cat_plumbing'},
      {'id': 'cat_mixers', 'name': 'خلاطات ودش', 'parent_id': 'cat_plumbing'},
      {'id': 'cat_ceramics', 'name': 'سيراميك وبورسلين', 'parent_id': null},
      {'id': 'cat_tools', 'name': 'عدد وأدوات تركيب', 'parent_id': null},
      {'id': 'cat_insulation', 'name': 'عوازل ومواد لاصقة', 'parent_id': null},
    ];

    for (final cat in categories) {
      await db.insert(
        'categories',
        cat,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// تضيف عموداً لجدول فقط إذا لم يكن موجوداً (ترقية idempotent آمنة).
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  // تجزئة كلمة المرور (SHA-256). مرجع موحّد لكل طبقات التطبيق.
  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  static Future<void> _seedDefaultOwner(Database db) async {
    await db.insert('users', {
      'id': 'user_owner',
      'name': 'المالك',
      'username': 'owner',
      'password_hash': hashPassword('owner123'),
      'role': 'owner',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
