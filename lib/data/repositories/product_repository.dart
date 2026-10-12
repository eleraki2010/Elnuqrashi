import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../models/product.dart';

/// صف منتج في كشف خدمة المخزن: البضاعة + العدد + القيمة.
class StockSummaryItem {
  final String productId;
  final String name;
  final String? barcode;
  final String unit;
  final int quantity;
  final double purchasePrice;
  final double salePrice;

  StockSummaryItem({
    required this.productId,
    required this.name,
    this.barcode,
    required this.unit,
    required this.quantity,
    required this.purchasePrice,
    required this.salePrice,
  });

  /// قيمة البضاعة بسعر الشراء (التكلفة الحقيقية للمخزون).
  double get stockValue => quantity * purchasePrice;

  /// قيمة البضاعة بسعر البيع (القيمة المتوقعة عند بيع المخزون كاملاً).
  double get expectedSaleValue => quantity * salePrice;

  /// الربح المتوقع من المخزون الحالي.
  double get expectedProfit => expectedSaleValue - stockValue;

  factory StockSummaryItem.fromProduct(Product p) {
    return StockSummaryItem(
      productId: p.id,
      name: p.name,
      barcode: p.barcode,
      unit: p.unit,
      quantity: p.quantity,
      purchasePrice: p.purchasePrice,
      salePrice: p.salePrice,
    );
  }
}

/// كشف خدمة المخزن: ملخص حيّ للبضاعة الحالية بعد خصم المبيعات.
class StockSummary {
  final List<StockSummaryItem> items;

  StockSummary({required this.items});

  int get productsCount => items.length;

  /// إجمالي عدد القطع في المخزن.
  int get totalQuantity =>
      items.fold(0, (sum, i) => sum + i.quantity);

  /// إجمالي قيمة المخزون بسعر الشراء (أموال المحل في البضاعة).
  double get totalCostValue =>
      items.fold(0.0, (sum, i) => sum + i.stockValue);

  /// إجمالي قيمة المخزون بسعر البيع.
  double get totalSaleValue =>
      items.fold(0.0, (sum, i) => sum + i.expectedSaleValue);

  /// إجمالي الربح المتوقع من بيع المخزون الحالي.
  double get expectedProfit => totalSaleValue - totalCostValue;

  /// عدد الأصناف النافدة تماماً.
  int get outOfStockCount => items.where((i) => i.quantity <= 0).length;
}

class ProductRepository {
  Future<List<Product>> getAllProducts() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<Product?> getProductById(String id) async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  /// البحث عن منتج بباركود مطابق تمامًا (لمسح الباركود).
  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await AppDatabase.instance;
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  Future<List<Product>> searchProducts(String query, {String? categoryId}) async {
    final db = await AppDatabase.instance;
    final cleanQuery = query.trim();

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (cleanQuery.isNotEmpty) {
      whereClause = '(name LIKE ? OR barcode LIKE ?)';
      whereArgs.add('%$cleanQuery%');
      whereArgs.add('%$cleanQuery%');
    }

    if (categoryId != null && categoryId.isNotEmpty && categoryId != 'all') {
      if (whereClause.isNotEmpty) {
        whereClause += ' AND ';
      }
      whereClause += 'category_id = ?';
      whereArgs.add(categoryId);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'name ASC',
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<List<Product>> getStockAlertProducts() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM products
      WHERE quantity <= min_quantity_alert
      ORDER BY quantity ASC, name ASC
    ''');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<int> getLowStockCount() async {
    final db = await AppDatabase.instance;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM products
      WHERE quantity <= min_quantity_alert
    ''');
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// يُرجع الكمية المتاحة الحالية لمنتج (للتحقق قبل إتمام البيع).
  Future<int> getAvailableQuantity(String productId) async {
    final db = await AppDatabase.instance;
    final result = await db.rawQuery(
      'SELECT quantity as q FROM products WHERE id = ?',
      [productId],
    );
    if (result.isEmpty) return 0;
    return (result.first['q'] as num?)?.toInt() ?? 0;
  }

  Future<void> insertProduct(Product product) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateProduct(Product product) async {
    final db = await AppDatabase.instance;
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> deleteProduct(String id) async {
    final db = await AppDatabase.instance;
    await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// كشف حيّ لخدمة المخزن: البضاعة المتاحة فعلياً (الكمية الجارية في جدول
  /// products) مع قيمتها بسعر الشراء وسعر البيع. الكمية الجارية محدَّثة
  /// لحظياً عند كل بيع/شراء/مرتجع/جرد، فهي تعكس البضاعة بعد خصم المبيعات.
  Future<StockSummary> getStockSummary() async {
    final products = await getAllProducts();
    final items = products
        .map((p) => StockSummaryItem.fromProduct(p))
        .toList();
    return StockSummary(items: items);
  }

  /// تسجيل كسر أو توالف أو عجز مخزني:
  /// يخصم الكمية من المخزون، ويسجل حركة مخزنية من نوع 'damage'،
  /// ويسجل الخسارة كمصروف تشغيلي (توالف وكسر مخزون) لتدخل في قائمة الأرباح والخسائر بدقة.
  Future<void> recordStockDamage({
    required String productId,
    required int quantity,
    required String reason,
    bool recordAsExpense = true,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;
    final product = await getProductById(productId);
    if (product == null) throw StateError('المنتج غير موجود');
    if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من الصفر');
    if (quantity > product.quantity) {
      throw StateError(
        'الكمية التالفة ($quantity) أكبر من الرصيد المتاح بالمخزن (${product.quantity})',
      );
    }

    final now = DateTime.now();
    const uuid = Uuid();
    final movementId = uuid.v4();
    final totalLoss = quantity * product.purchasePrice;

    await db.transaction((txn) async {
      // 1. خصم الكمية من رصيد المنتج
      await txn.rawUpdate(
        'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
        [quantity, now.toIso8601String(), productId],
      );

      // 2. تسجيل حركة مخزنية سالبة من نوع damage
      await txn.insert('stock_movements', {
        'id': movementId,
        'product_id': productId,
        'type': 'damage',
        'quantity_change': -quantity,
        'reference_id': movementId,
        'note': 'كسر/تالف: $reason',
        'created_at': now.toIso8601String(),
      });

      // 3. تسجيل الخسارة كمصروف في الدفاتر إن طُلب ذلك
      if (recordAsExpense && totalLoss > 0) {
        await txn.insert('expenses', {
          'id': uuid.v4(),
          'amount': totalLoss,
          'category_id': 'توالف وكسر مخزون',
          'note':
              'خسارة كسر وتوالف: ${product.name} (عدد $quantity ${product.unit}) - $reason',
          'created_at': now.toIso8601String(),
        });
      }

      // 4. توثيق العملية في سجل التدقيق والرقابة
      await txn.insert('audit_logs', {
        'id': uuid.v4(),
        'table_name': 'products',
        'record_id': productId,
        'action': 'damage_write_off',
        'old_values': '{"quantity": ${product.quantity}}',
        'new_values':
            '{"damaged_qty": $quantity, "cost_loss": $totalLoss, "reason": "$reason"}',
        'user_id': userId,
        'note':
            'تسجيل كسر/توالف لصنف "${product.name}" بعدد $quantity ${product.unit} (خسارة ${totalLoss.toStringAsFixed(0)} ج.م)',
        'created_at': now.toIso8601String(),
      });
    });
  }
}
