import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// النسخ الاحتياطي والاسترجاع (Phase 3.15).
///
/// يصدّر كل الجداول كملف JSON قابل للنقل (يدويًا أو إلى التخزين السحابي)،
/// ويسترجعها في معاملة واحدة مع احترام ترتيب المفاتيح الأجنبية.
class BackupService {
  // الترتيب الصحيح للإدراج (الآباء قبل الأبناء).
  static const List<String> _insertOrder = [
    'categories',
    'users',
    'customers',
    'suppliers',
    'products',
    'sale_invoices',
    'sale_invoice_items',
    'purchase_invoices',
    'purchase_invoice_items',
    'payments',
    'stock_movements',
    'expenses',
    'audit_logs',
    'return_invoices',
    'return_invoice_items',
  ];

  /// إنشاء لقطة كاملة من قاعدة البيانات.
  static Future<Map<String, dynamic>> exportSnapshot() async {
    final db = await AppDatabase.instance;
    final data = <String, dynamic>{
      '_meta': {
        'app': 'alnokrashy_pos',
        'db_version': AppDatabase.dbVersion,
        'exported_at': DateTime.now().toIso8601String(),
      },
    };

    for (final table in _insertOrder) {
      data[table] = await db.query(table);
    }

    return data;
  }

  /// حفظ نسخة احتياطية في ملف يختاره المستخدم. يُرجع المسار أو null عند الإلغاء.
  static Future<String?> createBackupFile() async {
    final snapshot = await exportSnapshot();
    final json = const JsonEncoder.withIndent('  ').convert(snapshot);
    final now = DateTime.now();
    final fileName =
        'alnokrashy_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';

    // على المنصات التي تدعم saveFile نستخدمها، وإلا نحفظ في مجلد المستندات.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // تنبيه: saveFile في file_picker على Windows لا يكتب المحتوى بنفسه (يرجع المسار فقط).
      // لذلك نطلب المسار ثم نكتب الملف بأنفسنا لضمان وجوده فعلياً على القرص.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        lockParentWindow: true,
      );
      if (path == null) return null;

      // ضمان وجود امتداد .json حتى لو لم يكتبه المستخدم في المربع.
      String finalPath = path;
      if (!finalPath.toLowerCase().endsWith('.json')) {
        finalPath = '$finalPath.json';
      }

      final file = File(finalPath);
      await file.writeAsString(json, flush: true);

      // تحقق فعلي أن الملف كُتب وأنه غير فارغ.
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('تعذّر كتابة ملف النسخة الاحتياطية على القرص');
      }
      return finalPath;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(json, flush: true);
    return file.path;
  }

  /// استرجاع نسخة احتياطية من ملف يختاره المستخدم. يُرجع true عند النجاح.
  static Future<bool> restoreFromBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'اختر ملف النسخة الاحتياطية',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return false;

    final file = result.files.single;
    if (file.bytes == null && file.path == null) return false;

    List<int> bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else {
      bytes = await File(file.path!).readAsBytes();
    }

    if (bytes.isEmpty) {
      throw const FormatException('الملف المختار فارغ — ربما فشل حفظه مسبقاً.');
    }

    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح');
    }

    // التأكد من أن الملف نسخة احتياطية لتطبيقنا فعلاً قبل مسح البيانات الحالية.
    final meta = json['_meta'];
    if (meta is! Map || meta['app'] != 'alnokrashy_pos') {
      throw const FormatException(
          'الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي');
    }

    await _restoreFromSnapshot(json);
    return true;
  }

  static Future<void> _restoreFromSnapshot(Map<String, dynamic> snapshot) async {
    final db = await AppDatabase.instance;

    await db.transaction((txn) async {
      // حذف الأبناء قبل الآباء (عكس ترتيب الإدراج).
      for (final table in _insertOrder.reversed) {
        await txn.delete(table);
      }

      // إعادة الإدراج بالترتيب الصحيح.
      for (final table in _insertOrder) {
        final rows = snapshot[table];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is Map<String, dynamic>) {
            await txn.insert(table, row,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }
    });
  }
}
