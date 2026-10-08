import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../models/shop_profile.dart';

/// يدير صف بيانات المحل (حالياً: مسار الشعار).
class ShopProfileRepository {
  Future<ShopProfile> getProfile() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'shop_profile',
      where: 'id = ?',
      whereArgs: ['shop'],
      limit: 1,
    );
    if (maps.isEmpty) return const ShopProfile();
    final m = maps.first;
    return ShopProfile(
      logoPath: m['logo_path'] as String?,
      updatedAt: m['updated_at'] != null
          ? DateTime.parse(m['updated_at'] as String)
          : null,
    );
  }

  /// يحفظ/يحدّث مسار الشعار (null = إزالة الشعار).
  Future<void> saveLogoPath(String? logoPath) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'shop_profile',
      {
        'id': 'shop',
        'logo_path': logoPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
