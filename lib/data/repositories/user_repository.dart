import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/user.dart';

class UserRepository {
  final _uuid = const Uuid();

  Future<Database> _db() => AppDatabase.instance;

  /// التحقق من اسم المستخدم وكلمة المرور. يُرجع المستخدم عند النجاح أو null.
  Future<User?> authenticate(String username, String password) async {
    final db = await _db();
    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (maps.isEmpty) return null;

    final user = User.fromMap(maps.first);
    return user.verifyPassword(password) ? user : null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await _db();
    final maps = await db.query('users', orderBy: 'name ASC');
    return maps.map((m) => User.fromMap(m)).toList();
  }

  Future<User?> getUserById(String id) async {
    final db = await _db();
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return User.fromMap(maps.first);
  }

  Future<void> insertUser({
    required String name,
    required String username,
    required String password,
    required String role,
  }) async {
    final db = await _db();
    await db.insert('users', {
      'id': _uuid.v4(),
      'name': name.trim(),
      'username': username.trim(),
      'password_hash': AppDatabase.hashPassword(password),
      'role': role,
    });
  }

  Future<void> updateUser(User user, {String? newPassword}) async {
    final db = await _db();
    await db.update(
      'users',
      {
        'name': user.name,
        'username': user.username,
        'role': user.role,
        if (newPassword != null)
          'password_hash': AppDatabase.hashPassword(newPassword),
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> deleteUser(String id) async {
    final db = await _db();
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }
}
