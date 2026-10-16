import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/repositories/shop_profile_repository.dart';
import '../database/app_database.dart';

/// النسخ الاحتياطي والاسترجاع (Phase 3.15).
///
/// يصدّر كل الجداول كملف JSON قابل للنقل (يدويًا أو إلى التخزين السحابي)،
/// ويسترجعها في معاملة واحدة مع احترام ترتيب المفاتيح الأجنبية.
class BackupService {
  // الترتيب الصحيح للإدراج (الآباء قبل الأبناء).
  static const List<String> _insertOrder = [
    'categories',
    'shop_profile',
    'expense_categories',
    'users',
    'customers',
    'suppliers',
    'products',
    'sale_invoices',
    'sale_invoice_items',
    'purchase_invoices',
    'purchase_invoice_items',
    'purchase_return_invoices',
    'purchase_return_invoice_items',
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

    // حفظ إعدادات المتجر (الاسم، الهاتف، العنوان، ضريبة القيمة المضافة)
    try {
      final prefs = await SharedPreferences.getInstance();
      data['_store_settings'] = {
        'store_name': prefs.getString('store_name'),
        'store_phone': prefs.getString('store_phone'),
        'store_address': prefs.getString('store_address'),
        'vat_enabled': prefs.getBool('vat_enabled'),
      };
    } catch (_) {}

    // حفظ ملف الشعار كبيانات Base64 لضمان نقله بين الأجهزة
    try {
      final profile = await ShopProfileRepository().getProfile();
      if (profile.logoPath != null) {
        final logoFile = File(profile.logoPath!);
        if (await logoFile.exists()) {
          final logoBytes = await logoFile.readAsBytes();
          data['_logo_base64'] = base64Encode(logoBytes);
        }
      }
    } catch (_) {}

    return data;
  }

  static const String keyCustomBackupDir = 'pref_custom_backup_directory';
  static const String defaultFolderName = 'Elnuqrashi_Backups';

  /// المجلد الافتراضي الظاهر للنسخ الاحتياطي على أجهزة التابلت والكمبيوتر.
  /// يتميز بأنه:
  /// 1. ظاهر للمستخدم في تطبيق "ملفاتي" أو مستكشف الملفات (مجلد Download أو Documents العام).
  /// 2. لا يُحذف إطلاقاً عند إزالة أو تحديث التطبيق بالخطأ من التابلت.
  static Future<String> getDefaultBackupDirectoryPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      // 1. فحص مجلد التنزيلات العام المتاح لجميع التطبيقات والمستخدمين
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        final appBackupDir =
            Directory(p.join(downloadDir.path, defaultFolderName));
        if (!appBackupDir.existsSync()) {
          try {
            await appBackupDir.create(recursive: true);
          } catch (_) {}
        }
        if (appBackupDir.existsSync()) {
          return appBackupDir.path;
        }
      }

      // 2. فحص مجلد المستندات العام
      final docsDir = Directory('/storage/emulated/0/Documents');
      if (docsDir.existsSync()) {
        final appBackupDir =
            Directory(p.join(docsDir.path, defaultFolderName));
        if (!appBackupDir.existsSync()) {
          try {
            await appBackupDir.create(recursive: true);
          } catch (_) {}
        }
        if (appBackupDir.existsSync()) {
          return appBackupDir.path;
        }
      }

      // 3. مسار التخزين الخارجي البديل
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final parts = ext.path.split('/Android');
          if (parts.isNotEmpty) {
            final rootPublic =
                Directory(p.join(parts[0], 'Download', defaultFolderName));
            if (!rootPublic.existsSync()) {
              try {
                await rootPublic.create(recursive: true);
              } catch (_) {}
            }
            if (rootPublic.existsSync()) return rootPublic.path;
          }
          final fallback = Directory(p.join(ext.path, defaultFolderName));
          if (!fallback.existsSync()) await fallback.create(recursive: true);
          return fallback.path;
        }
      } catch (_) {}
    }

    // لأنظمة سطح المكتب (Windows / Linux / macOS)
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final appBackupDir =
            Directory(p.join(downloads.path, defaultFolderName));
        if (!appBackupDir.existsSync()) await appBackupDir.create(recursive: true);
        return appBackupDir.path;
      }
    } catch (_) {}

    // ملجأ أخير: مجلد المستندات
    final docDir = await getApplicationDocumentsDirectory();
    final fallback = Directory(p.join(docDir.path, defaultFolderName));
    if (!fallback.existsSync()) await fallback.create(recursive: true);
    return fallback.path;
  }

  /// الحصول على المجلد الفعلي المعتمد للنسخ الاحتياطي (المخصص إن وجد، أو الافتراضي).
  static Future<String> getEffectiveBackupDirectoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(keyCustomBackupDir);
    if (custom != null && custom.trim().isNotEmpty) {
      final dir = Directory(custom.trim());
      if (dir.existsSync()) {
        return dir.path;
      }
    }
    return await getDefaultBackupDirectoryPath();
  }

  /// تعيين مجلد مخصص لحفظ واسترجاع النسخ الاحتياطية.
  static Future<void> setCustomBackupDirectory(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(keyCustomBackupDir);
    } else {
      await prefs.setString(keyCustomBackupDir, path.trim());
    }
  }

  /// إعادة تعيين مجلد النسخ الاحتياطي إلى المجلد الافتراضي الظاهر.
  static Future<void> resetBackupDirectory() async {
    await setCustomBackupDirectory(null);
  }

  /// قائمة بجميع المجلدات المحتملة التي قد تحتوي على نسخ احتياطية على التابلت أو الكمبيوتر
  static Future<List<String>> getAllCandidateBackupDirectories() async {
    final dirs = <String>{};

    // 1. المجلد المخصص أو الافتراضي المعتمد
    try {
      final effective = await getEffectiveBackupDirectoryPath();
      dirs.add(effective);
    } catch (_) {}

    if (!kIsWeb && Platform.isAndroid) {
      // 2. مجلدات التنزيلات العامة الشائعة على أندرويد
      final downloadPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/sdcard/Download',
        '/sdcard/Downloads',
      ];
      for (final dp in downloadPaths) {
        dirs.add(p.join(dp, defaultFolderName));
        dirs.add(dp);
      }

      // 3. مجلدات المستندات العامة الشائعة
      final docPaths = [
        '/storage/emulated/0/Documents',
        '/sdcard/Documents',
      ];
      for (final dp in docPaths) {
        dirs.add(p.join(dp, defaultFolderName));
        dirs.add(dp);
      }

      // 4. مسار الـ External Storage
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          dirs.add(p.join(ext.path, defaultFolderName));
          dirs.add(ext.path);
          final parts = ext.path.split('/Android');
          if (parts.isNotEmpty) {
            dirs.add(p.join(parts[0], 'Download', defaultFolderName));
            dirs.add(p.join(parts[0], 'Documents', defaultFolderName));
            dirs.add(p.join(parts[0], 'Download'));
            dirs.add(p.join(parts[0], 'Documents'));
          }
        }
      } catch (_) {}
    }

    // 5. مجلد المستندات والتنزيلات لنظام التشغيل
    try {
      final docDir = await getApplicationDocumentsDirectory();
      dirs.add(p.join(docDir.path, defaultFolderName));
      dirs.add(docDir.path);
    } catch (_) {}

    try {
      final dlDir = await getDownloadsDirectory();
      if (dlDir != null) {
        dirs.add(p.join(dlDir.path, defaultFolderName));
        dirs.add(dlDir.path);
      }
    } catch (_) {}

    return dirs.toList();
  }

  /// عرض قائمة ملفات النسخ الاحتياطي الموجودة بجميع المجلدات المحتملة مرتبة من الأحدث للأقدم.
  static Future<List<File>> listLocalBackupFiles() async {
    final candidateDirs = await getAllCandidateBackupDirectories();
    final foundFilesMap = <String, File>{};

    for (final dirPath in candidateDirs) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await for (final e in dir.list()) {
          if (e is File) {
            final name = p.basename(e.path).toLowerCase();
            if (name.endsWith('.json') &&
                (name.contains('backup') ||
                    name.contains('alnokrashy') ||
                    name.contains('elnuqrashi') ||
                    name.startsWith('202') ||
                    name.startsWith('bak_'))) {
              foundFilesMap[e.path] = e;
            }
          }
        }
      } catch (e) {
        debugPrint('Skip inaccessible dir $dirPath: $e');
      }
    }

    final files = foundFilesMap.values.toList();
    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return files;
  }

  /// البحث عن أحدث ملف نسخة احتياطية صالح على التابلت عبر كافة المجلدات
  static Future<File?> findLatestBackupFile() async {
    final files = await listLocalBackupFiles();
    for (final file in files) {
      try {
        if (!await file.exists() || await file.length() == 0) continue;
        return file;
      } catch (_) {}
    }
    return null;
  }

  /// فحص ما إذا كانت قاعدة البيانات الحالية فارغة (تثبيت جديد أو بعد إعادة التهيئة)
  static Future<bool> isDatabaseEmpty() async {
    try {
      final db = await AppDatabase.instance;
      final total = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT (SELECT COUNT(*) FROM products) + '
              '(SELECT COUNT(*) FROM sale_invoices) + '
              '(SELECT COUNT(*) FROM customers) AS total_count',
            ),
          ) ?? 0;
      return total == 0;
    } catch (_) {
      return false;
    }
  }

  /// حفظ نسخة احتياطية في المجلد المعتمد للتابلت (أو باختيار مكان مخصص عند الطلب).
  static Future<String?> createBackupFile({bool pickCustomLocation = false}) async {
    final snapshot = await exportSnapshot();
    final json = const JsonEncoder.withIndent('  ').convert(snapshot);
    final now = DateTime.now();
    final fileName =
        'alnokrashy_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';

    if (pickCustomLocation) {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          lockParentWindow: true,
        );
        if (path == null) return null;

        String finalPath = path;
        if (!finalPath.toLowerCase().endsWith('.json')) {
          finalPath = '$finalPath.json';
        }

        final file = File(finalPath);
        await file.writeAsString(json, flush: true);

        if (!await file.exists() || await file.length() == 0) {
          throw Exception('تعذّر كتابة ملف النسخة الاحتياطية على القرص');
        }
        return finalPath;
      }
    }

    // حفظ في المجلد الظاهر المعتمد (الذي يبقى حتى بعد حذف التطبيق)
    final dirPath = await getEffectiveBackupDirectoryPath();
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(json, flush: true);

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('تعذّر كتابة ملف النسخة الاحتياطية في المجلد: $dirPath');
    }
    return file.path;
  }

  /// استرجاع نسخة احتياطية من ملف محدد مسبقاً (دون فتح حوار البحث).
  static Future<bool> restoreFromSpecificFile(File file) async {
    if (!await file.exists()) {
      throw const FormatException('ملف النسخة الاحتياطية المحدد غير موجود');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('الملف المحدد فارغ — ربما تعذر حفظه مسبقاً.');
    }

    var str = utf8.decode(bytes);
    if (str.startsWith('\uFEFF')) {
      str = str.substring(1);
    }
    final json = jsonDecode(str);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح');
    }

    final meta = json['_meta'];
    final isValidApp = meta is Map &&
        (meta['app'] == 'alnokrashy_pos' || meta['app'] == 'elnuqrashi_pos');
    final hasStoreTables = json['products'] is List ||
        json['sale_invoices'] is List ||
        json['categories'] is List;

    if (!isValidApp && !hasStoreTables) {
      throw const FormatException(
          'الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي');
    }

    await restoreFromSnapshot(json);
    return true;
  }

  /// استرجاع نسخة احتياطية من ملف يختاره المستخدم عبر متصفح الملفات.
  static Future<bool> restoreFromBackupFile({String? initialDirectory}) async {
    final initDir = initialDirectory ?? await getEffectiveBackupDirectoryPath();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة الاحتياطية',
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: Directory(initDir).existsSync() ? initDir : null,
        withData: true,
        lockParentWindow: true,
      );
    } catch (_) {
      // بديل إذا لم يدعم نظام أندرويد نوع الملف المخصص
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة الاحتياطية',
        type: FileType.any,
        withData: true,
        lockParentWindow: true,
      );
    }

    if (result == null || result.files.isEmpty) return false;

    final file = result.files.single;
    List<int>? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {}
    }

    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('تعذّر قراءة الملف المختار — تأكد من صحة الملف.');
    }

    var str = utf8.decode(bytes);
    if (str.startsWith('\uFEFF')) {
      str = str.substring(1);
    }
    final json = jsonDecode(str);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح');
    }

    final meta = json['_meta'];
    final isValidApp = meta is Map &&
        (meta['app'] == 'alnokrashy_pos' || meta['app'] == 'elnuqrashi_pos');
    final hasStoreTables = json['products'] is List ||
        json['sale_invoices'] is List ||
        json['categories'] is List;

    if (!isValidApp && !hasStoreTables) {
      throw const FormatException(
          'الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي');
    }

    await restoreFromSnapshot(json);
    return true;
  }

  /// استعادة البيانات من كائن لقطة JSON تم التحقق منه.
  static Future<void> restoreFromSnapshot(Map<String, dynamic> snapshot) async {
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

    // استعادة إعدادات المتجر إلى SharedPreferences
    if (snapshot['_store_settings'] is Map) {
      try {
        final settings = snapshot['_store_settings'] as Map;
        final prefs = await SharedPreferences.getInstance();
        if (settings['store_name'] != null) {
          await prefs.setString('store_name', settings['store_name'].toString());
        }
        if (settings['store_phone'] != null) {
          await prefs.setString('store_phone', settings['store_phone'].toString());
        }
        if (settings['store_address'] != null) {
          await prefs.setString('store_address', settings['store_address'].toString());
        }
        if (settings['vat_enabled'] != null) {
          await prefs.setBool('vat_enabled', settings['vat_enabled'] == true);
        }
      } catch (_) {}
    }

    // استعادة ملف الشعار من Base64 وحفظه في مجلد المستندات
    if (snapshot['_logo_base64'] is String && (snapshot['_logo_base64'] as String).isNotEmpty) {
      try {
        final logoBytes = base64Decode(snapshot['_logo_base64'] as String);
        final dir = await getApplicationDocumentsDirectory();
        final logoFile = File(p.join(dir.path, 'shop_logo.png'));
        await logoFile.writeAsBytes(logoBytes);
        await ShopProfileRepository().saveLogoPath(logoFile.path);
      } catch (_) {}
    }
  }
}
