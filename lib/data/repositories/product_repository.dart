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
          'title':
              'خسارة كسر وتوالف: ${product.name} (عدد $quantity ${product.unit}) - $reason',
          'amount': totalLoss,
          'category': 'توالف وكسر مخزون',
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

  /// تطبيق جرد المخزون الفعلي محاسبياً بصورة دقيقة وموحدة:
  /// 1. تحديث أرصدة المنتجات في جدول products لتطابق الكمية الفعلية.
  /// 2. تسجيل حركة مخزنية رسمية (stock_movement) لكل صنف تغير رصيده بنوع 'count'.
  /// 3. في حال وجود عجز (الفعلي أقل من المسجل): احتساب قيمة خسارة العجز بسعر الشراء
  ///    وإثباتها كمصروف تشغيلي في جدول expenses تحت فئة 'عجز وفروقات جرد' لضمان دقة الأرباح والميزانية.
  /// 4. توثيق كافة التعديلات في سجل الرقابة والتدقيق (audit_logs).
  /// 5. كل هذه العمليات تُنفذ داخل معاملة ذرية موحدة (Database Transaction) لضمان سلامة الدفاتر.
  Future<InventoryCountResult> applyInventoryCount({
    required List<InventoryCountEntry> entries,
    bool recordShortageAsExpense = true,
    String? userId,
  }) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now();
    const uuid = Uuid();
    final batchId = uuid.v4();

    int adjustedCount = 0;
    int shortageItemsCount = 0;
    int surplusItemsCount = 0;
    int totalShortageQty = 0;
    int totalSurplusQty = 0;
    double totalShortageValue = 0.0;
    double totalSurplusValue = 0.0;

    await db.transaction((txn) async {
      for (final entry in entries) {
        final productMaps = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [entry.productId],
          limit: 1,
        );
        if (productMaps.isEmpty) continue;
        final product = Product.fromMap(productMaps.first);
        final diff = entry.actualQuantity - product.quantity;
        if (diff == 0) continue;

        adjustedCount++;
        if (diff < 0) {
          final shortageQty = diff.abs();
          final shortageCost = shortageQty * product.purchasePrice;
          shortageItemsCount++;
          totalShortageQty += shortageQty;
          totalShortageValue += shortageCost;

          // 1. تحديث رصيد الصنف الفعلي
          await txn.rawUpdate(
            'UPDATE products SET quantity = ?, updated_at = ? WHERE id = ?',
            [entry.actualQuantity, now.toIso8601String(), product.id],
          );

          // 2. حركة مخزنية سالبة للجرد
          await txn.insert('stock_movements', {
            'id': uuid.v4(),
            'product_id': product.id,
            'type': 'count',
            'quantity_change': diff,
            'reference_id': batchId,
            'note':
                'عجز جرد مخزني: مسجل ${product.quantity} فعلي ${entry.actualQuantity} (عجز $shortageQty ${product.unit}) بتكلفة ${shortageCost.toStringAsFixed(2)} ج.م',
            'created_at': now.toIso8601String(),
          });

          // 3. سجل تدقيق
          await txn.insert('audit_logs', {
            'id': uuid.v4(),
            'table_name': 'products',
            'record_id': product.id,
            'action': 'inventory_count_shortage',
            'old_values': '{"quantity": ${product.quantity}}',
            'new_values':
                '{"actual_quantity": ${entry.actualQuantity}, "difference": $diff, "shortage_cost": $shortageCost}',
            'user_id': userId,
            'note':
                'تسوية عجز جرد لصنف "${product.name}" بنقص $shortageQty ${product.unit} (تكلفة $shortageCost ج.م)',
            'created_at': now.toIso8601String(),
          });
        } else {
          final surplusQty = diff;
          final surplusCost = surplusQty * product.purchasePrice;
          surplusItemsCount++;
          totalSurplusQty += surplusQty;
          totalSurplusValue += surplusCost;

          // 1. تحديث رصيد الصنف الفعلي
          await txn.rawUpdate(
            'UPDATE products SET quantity = ?, updated_at = ? WHERE id = ?',
            [entry.actualQuantity, now.toIso8601String(), product.id],
          );

          // 2. حركة مخزنية موجبة للجرد
          await txn.insert('stock_movements', {
            'id': uuid.v4(),
            'product_id': product.id,
            'type': 'count',
            'quantity_change': diff,
            'reference_id': batchId,
            'note':
                'فائض جرد مخزني: مسجل ${product.quantity} فعلي ${entry.actualQuantity} (زيادة $surplusQty ${product.unit}) بقيمة ${surplusCost.toStringAsFixed(2)} ج.م',
            'created_at': now.toIso8601String(),
          });

          // 3. سجل تدقيق
          await txn.insert('audit_logs', {
            'id': uuid.v4(),
            'table_name': 'products',
            'record_id': product.id,
            'action': 'inventory_count_surplus',
            'old_values': '{"quantity": ${product.quantity}}',
            'new_values':
                '{"actual_quantity": ${entry.actualQuantity}, "difference": $diff, "surplus_value": $surplusCost}',
            'user_id': userId,
            'note':
                'تسوية زيادة وفائض جرد لصنف "${product.name}" بزيادة $surplusQty ${product.unit}',
            'created_at': now.toIso8601String(),
          });
        }
      }

      // 4. إثبات محاسبي إجمالي للعجز كمصروف تشغيلي (عجز وفروقات جرد)
      if (recordShortageAsExpense && totalShortageValue > 0) {
        final expenseId = uuid.v4();
        await txn.insert('expenses', {
          'id': expenseId,
          'title':
              'تسوية عجز جرد مخزني ($shortageItemsCount أصناف - عجز $totalShortageQty قطعة)',
          'amount': totalShortageValue,
          'category': 'عجز وفروقات جرد',
          'created_at': now.toIso8601String(),
        });

        await txn.insert('audit_logs', {
          'id': uuid.v4(),
          'table_name': 'expenses',
          'record_id': expenseId,
          'action': 'create',
          'old_values': null,
          'new_values':
              '{"title": "تسوية عجز جرد مخزني", "amount": $totalShortageValue, "category": "عجز وفروقات جرد"}',
          'user_id': userId,
          'note':
              'إثبات مصروف عجز جرد مخزني بقيمة ${totalShortageValue.toStringAsFixed(2)} ج.م',
          'created_at': now.toIso8601String(),
        });
      }
    });

    return InventoryCountResult(
      adjustedItemsCount: adjustedCount,
      shortageItemsCount: shortageItemsCount,
      surplusItemsCount: surplusItemsCount,
      totalShortageQty: totalShortageQty,
      totalSurplusQty: totalSurplusQty,
      totalShortageValue: totalShortageValue,
      totalSurplusValue: totalSurplusValue,
    );
  }
}

/// مدخل جرد لصنف فردي
class InventoryCountEntry {
  final String productId;
  final int actualQuantity;

  InventoryCountEntry({
    required this.productId,
    required this.actualQuantity,
  });
}

/// نتيجة تسوية الجرد المخزني محاسبياً
class InventoryCountResult {
  final int adjustedItemsCount;
  final int shortageItemsCount;
  final int surplusItemsCount;
  final int totalShortageQty;
  final int totalSurplusQty;
  final double totalShortageValue;
  final double totalSurplusValue;

  InventoryCountResult({
    required this.adjustedItemsCount,
    required this.shortageItemsCount,
    required this.surplusItemsCount,
    required this.totalShortageQty,
    required this.totalSurplusQty,
    required this.totalShortageValue,
    required this.totalSurplusValue,
  });
}
