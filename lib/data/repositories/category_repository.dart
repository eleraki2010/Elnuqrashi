import 'package:sqflite/sqflite.dart';
import '../../core/database/app_database.dart';
import '../models/category.dart';

class CategoryRepository {
  Future<List<Category>> getAllCategories() async {
    final db = await AppDatabase.instance;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Category.fromMap(m)).toList();
  }

  Future<void> insertCategory(Category category) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCategory(Category category) async {
    final db = await AppDatabase.instance;
    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteCategory(String id) async {
    final db = await AppDatabase.instance;
    await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
