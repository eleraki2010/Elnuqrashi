import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../models/stock_movement.dart';

class StockMovementRepository {
  final _uuid = const Uuid();

  Future<void> addMovement({
    required String productId,
    required String type,
    required int quantityChange,
    String? referenceId,
    String? note,
  }) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // 1. Insert stock movement
      final movement = StockMovement(
        id: _uuid.v4(),
        productId: productId,
        type: type,
        quantityChange: quantityChange,
        referenceId: referenceId,
        note: note,
        createdAt: DateTime.now(),
      );

      await txn.insert('stock_movements', movement.toMap());

      // 2. Update product quantity
      if (type == 'sale') {
        // Sale: decrease quantity
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
          [quantityChange.abs(), DateTime.now().toIso8601String(), productId],
        );
      } else if (type == 'purchase') {
        // Purchase: increase quantity
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [quantityChange, DateTime.now().toIso8601String(), productId],
        );
      } else if (type == 'count' || type == 'adjustment') {
        // Count/Adjustment: apply difference directly
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [quantityChange, DateTime.now().toIso8601String(), productId],
        );
      } else if (type == 'damage') {
        // Damage: decrease quantity
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity - ?, updated_at = ? WHERE id = ?',
          [quantityChange.abs(), DateTime.now().toIso8601String(), productId],
        );
      }
    });
  }

  Future<List<StockMovement>> getMovementsByProductId(String productId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => StockMovement.fromMap(m)).toList();
  }

  Future<List<StockMovement>> getMovementsByType(String type) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'stock_movements',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => StockMovement.fromMap(m)).toList();
  }

  Future<List<StockMovement>> getAllMovements() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'stock_movements',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => StockMovement.fromMap(m)).toList();
  }

  Future<List<StockMovement>> getMovementsInDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await AppDatabase.instance;
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    final maps = await db.query(
      'stock_movements',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => StockMovement.fromMap(m)).toList();
  }
}
