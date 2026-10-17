import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../models/user.dart';

class UserRepository {
  final _uuid = const Uuid();

  Future<Database> _db() => AppDatabase.instance;

  static String _normalize(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var res = input.trim();
    for (int i = 0; i < arabic.length; i++) {
      res = res.replaceAll(arabic[i], '$i');
    }
    return res;
  }

  /// التحقق من اسم المستخدم وكلمة المرور. يُرجع المستخدم عند النجاح أو null.
  Future<User?> authenticate(String username, String password) async {
    final cleanUsername = _normalize(username);
    final cleanPassword = _normalize(password);

    final db = await _db();

    // التحقق من الحساب الافتراضي (1 / 123) بكل الصيغ
    if (cleanUsername == '1' && cleanPassword == '123') {
      final maps = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['1'],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        final u = User.fromMap(maps.first);
        if (u.verifyPassword('123')) return u;
      }
      // ضمان حفظه في قاعدة البيانات فورياً
      await db.insert('users', {
        'id': 'user_owner_default',
        'name': 'أدمن',
        'username': '1',
        'password_hash': AppDatabase.hashPassword('123'),
        'role': 'admin',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return User(
        id: 'user_owner_default',
        name: 'أدمن',
        username: '1',
        passwordHash: AppDatabase.hashPassword('123'),
        role: 'admin',
      );
    }

    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [cleanUsername],
      limit: 1,
    );
    if (maps.isEmpty) return null;

    final user = User.fromMap(maps.first);
    return user.verifyPassword(cleanPassword) ? user : null;
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
