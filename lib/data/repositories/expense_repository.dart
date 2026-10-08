import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/expense.dart';

class ExpenseRepository {
  final _uuid = const Uuid();

  /// الفئات الافتراضية للمصروفات التشغيلية للمحل
  /// (تُزروع في جدول expense_categories عند إنشاء القاعدة).
  static const List<String> defaultCategories = [
    'إيجار',
    'فواتير (كهرباء/مياه)',
    'رواتب',
    'صيانة',
    'شحن ونقل',
    'أخرى',
  ];

  /// كل فئات المصروفات (الافتراضية + المضافة من المستخدم).
  Future<List<String>> getCategories() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'expense_categories',
      orderBy: 'created_at ASC',
    );
    final names = maps.map((m) => m['name'] as String).toList();
    // سلامة: إذا كان الجدول فارغاً (قاعدة قديمة) نعود للقائمة الافتراضية.
    return names.isEmpty ? List.of(defaultCategories) : names;
  }

  /// إضافة فئة مصروفات مخصصة (تُضاف بجوار القائمة في شاشة المصروفات).
  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await AppDatabase.instance;
    await db.insert('expense_categories', {
      'id': trimmed,
      'name': trimmed,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertExpense(Expense expense, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      await txn.insert('expenses', expense.toMap());

      // سجل تدقيق لكل عملية مالية مع المستخدم المتخذ للقرار.
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': expense.id,
        'action': 'create',
        'old_values': null,
        'new_values':
            '{"title": "${expense.title}", "amount": ${expense.amount}, "category": "${expense.category}"}',
        'user_id': userId,
        'note': 'تسجيل مصروف: ${expense.title}',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// تعديل مصروف مسجل (البيان/المبلغ/الفئة) مع توثيق التغير في سجل العمليات.
  Future<void> updateExpense(Expense expense, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final maps = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expense.id],
        limit: 1,
      );
      if (maps.isEmpty) return;

      final old = Expense.fromMap(maps.first);

      await txn.update(
        'expenses',
        {
          'title': expense.title,
          'amount': expense.amount,
          'category': expense.category,
        },
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': expense.id,
        'action': 'update',
        'old_values':
            '{"title": "${old.title}", "amount": ${old.amount}, "category": "${old.category}"}',
        'new_values':
            '{"title": "${expense.title}", "amount": ${expense.amount}, "category": "${expense.category}"}',
        'user_id': userId,
        'note': 'تعديل مصروف: ${expense.title}',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> deleteExpense(String id, {String? userId}) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      final maps = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) return;

      await txn.delete('expenses', where: 'id = ?', whereArgs: [id]);

      final expense = Expense.fromMap(maps.first);
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': id,
        'action': 'delete',
        'old_values':
            '{"title": "${expense.title}", "amount": ${expense.amount}}',
        'new_values': null,
        'user_id': userId,
        'note': 'حذف مصروف: ${expense.title}',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Expense>> getAllExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;

    String where = '1=1';
    final args = <dynamic>[];

    if (startDate != null) {
      where += ' AND created_at >= ?';
      args.add(
        DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        ).toIso8601String(),
      );
    }
    if (endDate != null) {
      where += ' AND created_at <= ?';
      args.add(
        DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        ).toIso8601String(),
      );
    }

    final maps = await db.query(
      'expenses',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  /// إجمالي المصروفات خلال فترة (تُخصم من صافي الربح).
  Future<double> getTotalExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;

    String where = '1=1';
    final args = <dynamic>[];

    if (startDate != null) {
      where += ' AND created_at >= ?';
      args.add(
        DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        ).toIso8601String(),
      );
    }
    if (endDate != null) {
      where += ' AND created_at <= ?';
      args.add(
        DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        ).toIso8601String(),
      );
    }

    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0.0) as total FROM expenses WHERE $where',
      args,
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
