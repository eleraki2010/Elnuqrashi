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

    // تصدير كافة الجداول الأساسية المعتمدة
    for (final table in _insertOrder) {
      data[table] = await db.query(table);
    }

    // فحص وتصدير أي جداول إضافية إن وجدت في قاعدة البيانات لضمان شمول 100%
    try {
      final extraTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      );
      for (final row in extraTables) {
        final tName = row['name'] as String?;
        if (tName != null && !_insertOrder.contains(tName) && !data.containsKey(tName)) {
          data[tName] = await db.query(tName);
        }
      }
    } catch (_) {}

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

    // حفظ جميع صور المنتجات المحلية كـ Base64 لضمان بقائها وانتقالها عند نقل النسخة أو إعادة التثبيت
    try {
      final productImages = <String, String>{};
      final productsRows = data['products'] as List?;
      if (productsRows != null) {
        for (final row in productsRows) {
          if (row is Map) {
            final imgPath = row['image_url']?.toString();
            if (imgPath != null && imgPath.isNotEmpty) {
              if (!imgPath.startsWith('http://') && !imgPath.startsWith('https://')) {
                final file = File(imgPath);
                if (await file.exists()) {
                  final fileName = p.basename(imgPath);
                  final len = await file.length();
                  // نقبل الصور حتى 10 ميجابايت
                  if (len > 0 && len < 10 * 1024 * 1024) {
                    final bytes = await file.readAsBytes();
                    productImages[fileName] = base64Encode(bytes);
                  }
                }
              }
            }
          }
        }
      }
      if (productImages.isNotEmpty) {
        data['_product_images_base64'] = productImages;
      }
    } catch (e) {
      debugPrint('تنبيه أثناء حفظ صور المنتجات في النسخة الاحتياطية: $e');
    }

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
            final isAppBackupDir = dirPath.contains(defaultFolderName);
            if (name.endsWith('.json')) {
              if (isAppBackupDir ||
                  name.contains('backup') ||
                  name.contains('alnokrashy') ||
                  name.contains('elnuqrashi') ||
                  name.contains('nakrashy') ||
                  name.contains('pos') ||
                  name.contains('bak') ||
                  name.contains('نقراشي') ||
                  name.contains('نوكراشي') ||
                  name.contains('احتياط') ||
                  name.contains('نسخة') ||
                  name.startsWith('202')) {
                foundFilesMap[e.path] = e;
              }
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

    var str = utf8.decode(bytes, allowMalformed: true);
    str = str.replaceAll(RegExp(r'^[\uFEFF\u200B\s]+'), '').trim();
    final dynamic json = jsonDecode(str);
    if (json is! Map) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح (ليس بتنسيق JSON صحيح)');
    }

    final meta = json['_meta'];
    final isValidApp = meta is Map &&
        (meta['app'] == 'alnokrashy_pos' || meta['app'] == 'elnuqrashi_pos');
    final hasStoreTables = json['products'] is List ||
        json['sale_invoices'] is List ||
        json['categories'] is List ||
        json['customers'] is List ||
        json['suppliers'] is List;

    if (!isValidApp && !hasStoreTables) {
      throw const FormatException(
          'الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي');
    }

    await restoreFromSnapshot(Map<String, dynamic>.from(json));
    return true;
  }

  /// استرجاع نسخة احتياطية من ملف يختاره المستخدم عبر متصفح الملفات.
  static Future<bool> restoreFromBackupFile({String? initialDirectory}) async {
    final initDir = initialDirectory ?? await getEffectiveBackupDirectoryPath();

    FilePickerResult? result;
    if (!kIsWeb && Platform.isAndroid) {
      // على أندرويد: استخدام FileType.any ضروري لعدم تعتيم ملفات .json من قِبل مديري الملفات بالنظام
      try {
        result = await FilePicker.platform.pickFiles(
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
          type: FileType.any,
          withData: true,
          withReadStream: true,
        );
      } catch (_) {
        result = await FilePicker.platform.pickFiles(
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: true,
          withReadStream: true,
        );
      }
    } else {
      // لأنظمة سطح المكتب (ويندوز / ماك / لينكس)
      try {
        result = await FilePicker.platform.pickFiles(
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
          type: FileType.custom,
          allowedExtensions: ['json'],
          initialDirectory: Directory(initDir).existsSync() ? initDir : null,
          withData: true,
          withReadStream: true,
          lockParentWindow: true,
        );
      } catch (_) {
        result = await FilePicker.platform.pickFiles(
          dialogTitle: 'اختر ملف النسخة الاحتياطية',
          type: FileType.any,
          withData: true,
          withReadStream: true,
          lockParentWindow: true,
        );
      }
    }

    if (result == null || result.files.isEmpty) return false;

    final file = result.files.single;
    List<int>? bytes = file.bytes;

    if ((bytes == null || bytes.isEmpty) && file.readStream != null) {
      try {
        final streamData = <int>[];
        await for (final chunk in file.readStream!) {
          streamData.addAll(chunk);
        }
        if (streamData.isNotEmpty) bytes = streamData;
      } catch (_) {}
    }

    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      try {
        final f = File(file.path!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      } catch (_) {}
    }

    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('تعذّر قراءة الملف المختار — تأكد من صحة الملف وصلاحيات الوصول.');
    }

    var str = utf8.decode(bytes, allowMalformed: true);
    str = str.replaceAll(RegExp(r'^[\uFEFF\u200B\s]+'), '').trim();
    final dynamic json = jsonDecode(str);
    if (json is! Map) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح (ليس بتنسيق JSON صحيح)');
    }

    final meta = json['_meta'];
    final isValidApp = meta is Map &&
        (meta['app'] == 'alnokrashy_pos' || meta['app'] == 'elnuqrashi_pos');
    final hasStoreTables = json['products'] is List ||
        json['sale_invoices'] is List ||
        json['categories'] is List ||
        json['customers'] is List ||
        json['suppliers'] is List;

    if (!isValidApp && !hasStoreTables) {
      throw const FormatException(
          'الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي');
    }

    await restoreFromSnapshot(Map<String, dynamic>.from(json));
    return true;
  }

  /// استعادة البيانات من كائن لقطة JSON تم التحقق منه بأعلى درجات الأمان والتوافق.
  static Future<void> restoreFromSnapshot(Map<String, dynamic> snapshot) async {
    final db = await AppDatabase.instance;

    // تعطيل فحص المفاتيح الأجنبية مؤقتاً أثناء عملية الاسترجاع لتفادي فشل المعاملة
    // بسبب سجلات قديمة أو اختلاف ترتيب العلاقات بين الإصدارات المختلفة.
    await db.execute('PRAGMA foreign_keys = OFF;');

    try {
      await db.transaction((txn) async {
        // 1. تفريغ الجداول الحالية بالترتيب العكسي
        for (final table in _insertOrder.reversed) {
          try {
            await txn.delete(table);
          } catch (e) {
            debugPrint('تنبيه: تعذر مسح الجدول $table أثناء الاسترجاع: $e');
          }
        }

        // 2. فحص وإدراج البيانات جدولاً بجدول مع مطابقة الأعمدة الحالية في قاعدة البيانات
        for (final table in _insertOrder) {
          final rows = snapshot[table];
          if (rows is! List) continue;

          // جلب الأعمدة الفعلية الموجودة في الجدول لتجنب خطأ (no such column)
          final colsInfo = await txn.rawQuery('PRAGMA table_info($table)');
          final validCols = <String>{};
          for (final col in colsInfo) {
            validCols.add(col['name'] as String);
          }

          for (final rawRow in rows) {
            if (rawRow is! Map) continue;
            final cleanRow = <String, dynamic>{};
            for (final entry in rawRow.entries) {
              final key = entry.key.toString();
              if (validCols.contains(key)) {
                cleanRow[key] = entry.value;
              }
            }

            // ضمان تعبئة الأعمدة الإجبارية التي لا تحتوي على قيم افتراضية
            _fillMissingRequiredValues(table, cleanRow);

            try {
              await txn.insert(
                table,
                cleanRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } catch (e) {
              debugPrint('خطأ في إدراج سطر بالجدول $table: $e');
            }
          }
        }

        // 3. فحص وإدراج أي جداول إضافية إن وجدت في النسخة الاحتياطية
        for (final entry in snapshot.entries) {
          final tName = entry.key;
          if (tName.startsWith('_') || _insertOrder.contains(tName)) continue;
          final rows = entry.value;
          if (rows is! List) continue;

          try {
            final colsInfo = await txn.rawQuery('PRAGMA table_info($tName)');
            if (colsInfo.isEmpty) continue;
            final validCols = colsInfo.map((c) => c['name'] as String).toSet();
            for (final rawRow in rows) {
              if (rawRow is! Map) continue;
              final cleanRow = <String, dynamic>{};
              for (final e in rawRow.entries) {
                if (validCols.contains(e.key.toString())) {
                  cleanRow[e.key.toString()] = e.value;
                }
              }
              if (cleanRow.isNotEmpty) {
                await txn.insert(tName, cleanRow, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          } catch (_) {}
        }

        // 4. التحقق من سلامة الجداول الأساسية وإعادة زرع البيانات الافتراضية إذا كانت فارغة
        await _ensureEssentialDefaults(txn);
      });
    } finally {
      // إعادة تفعيل فحص المفاتيح الأجنبية دائماً
      await db.execute('PRAGMA foreign_keys = ON;');
    }

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

    // استعادة صور المنتجات من Base64 وتحديث مساراتها على الجهاز الجديد
    if (snapshot['_product_images_base64'] is Map) {
      try {
        final productImages = snapshot['_product_images_base64'] as Map;
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(p.join(appDir.path, 'product_images'));
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }

        final fileNameToNewPath = <String, String>{};
        for (final entry in productImages.entries) {
          try {
            final fileName = entry.key.toString();
            final base64Str = entry.value.toString();
            if (base64Str.isNotEmpty) {
              final targetFile = File(p.join(imagesDir.path, fileName));
              await targetFile.writeAsBytes(base64Decode(base64Str));
              fileNameToNewPath[fileName] = targetFile.path;
            }
          } catch (_) {}
        }

        // تحديث مسارات الصور للمنتجات في قاعدة البيانات لتشير إلى مكان الملف الجديد على الجهاز
        if (fileNameToNewPath.isNotEmpty) {
          for (final entry in fileNameToNewPath.entries) {
            await db.rawUpdate(
              'UPDATE products SET image_url = ? WHERE image_url LIKE ?',
              [entry.value, '%${entry.key}'],
            );
          }
        }
      } catch (e) {
        debugPrint('تنبيه أثناء استعادة صور المنتجات: $e');
      }
    }
  }

  /// إكمال أي قيم إجبارية مفقودة من نسخ قديمة لتفادي أخطاء قيود NOT NULL
  static void _fillMissingRequiredValues(String table, Map<String, dynamic> row) {
    final now = DateTime.now().toIso8601String();
    switch (table) {
      case 'products':
        row['name'] ??= 'صنف غير مسمى';
        row['category_id'] ??= 'cat_plumbing';
        row['unit'] ??= 'قطعة';
        row['purchase_price'] ??= 0.0;
        row['sale_price'] ??= 0.0;
        row['quantity'] ??= 0;
        row['min_quantity_alert'] ??= 5;
        row['created_at'] ??= now;
        row['updated_at'] ??= now;
        break;
      case 'categories':
        row['name'] ??= 'تصنيف عام';
        break;
      case 'customers':
        row['name'] ??= 'عميل';
        row['balance_due'] ??= 0.0;
        row['created_at'] ??= now;
        row['updated_at'] ??= now;
        break;
      case 'suppliers':
        row['name'] ??= 'مورد';
        row['balance_owed'] ??= 0.0;
        row['created_at'] ??= now;
        row['updated_at'] ??= now;
        break;
      case 'sale_invoices':
        row['invoice_number'] ??= 'INV-${row['id'] ?? DateTime.now().millisecondsSinceEpoch}';
        row['subtotal'] ??= row['total'] ?? 0.0;
        row['discount'] ??= 0.0;
        row['tax'] ??= 0.0;
        row['total'] ??= 0.0;
        row['paid_amount'] ??= row['total'] ?? 0.0;
        row['change_due'] ??= 0.0;
        row['payment_method'] ??= 'cash';
        row['status'] ??= 'completed';
        row['created_at'] ??= now;
        break;
      case 'sale_invoice_items':
        row['quantity'] ??= 1;
        row['unit_price'] ??= 0.0;
        row['line_total'] ??= (row['quantity'] as num? ?? 1) * (row['unit_price'] as num? ?? 0.0);
        break;
      case 'purchase_invoices':
        row['total'] ??= 0.0;
        row['tax'] ??= 0.0;
        row['paid_amount'] ??= 0.0;
        row['created_at'] ??= now;
        break;
      case 'purchase_invoice_items':
        row['quantity'] ??= 1;
        row['unit_cost'] ??= 0.0;
        row['line_total'] ??= (row['quantity'] as num? ?? 1) * (row['unit_cost'] as num? ?? 0.0);
        break;
      case 'expenses':
        row['title'] ??= 'مصروف';
        row['amount'] ??= 0.0;
        row['category'] ??= 'أخرى';
        row['created_at'] ??= now;
        break;
      case 'users':
        row['name'] ??= 'مستخدم';
        row['username'] ??= 'user_${row['id'] ?? DateTime.now().millisecondsSinceEpoch}';
        row['password_hash'] ??= AppDatabase.hashPassword('123456');
        row['role'] ??= 'cashier';
        break;
    }
  }

  /// ضمان عدم ترك الجداول الحيوية فارغة بعد الاسترجاع حتى لو كانت النسخة خالية منها
  static Future<void> _ensureEssentialDefaults(Transaction txn) async {
    // 1. ضمان وجود حساب المالك على الأقل
    final userCount = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM users'),
        ) ?? 0;
    if (userCount == 0) {
      await txn.insert('users', {
        'id': 'user_owner',
        'name': 'المالك',
        'username': 'owner',
        'password_hash': AppDatabase.hashPassword('owner123'),
        'role': 'owner',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 2. ضمان وجود التصنيفات الافتراضية
    final catCount = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM categories'),
        ) ?? 0;
    if (catCount == 0) {
      final defaultCats = [
        {'id': 'cat_plumbing', 'name': 'أدوات صحية وسباكة', 'parent_id': null},
        {'id': 'cat_pipes', 'name': 'مواسير ولوازم', 'parent_id': 'cat_plumbing'},
        {'id': 'cat_mixers', 'name': 'خلاطات ودش', 'parent_id': 'cat_plumbing'},
        {'id': 'cat_ceramics', 'name': 'سيراميك وبورسلين', 'parent_id': null},
        {'id': 'cat_tools', 'name': 'عدد وأدوات تركيب', 'parent_id': null},
        {'id': 'cat_insulation', 'name': 'عوازل ومواد لاصقة', 'parent_id': null},
      ];
      for (final cat in defaultCats) {
        await txn.insert('categories', cat, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    // 3. ضمان وجود فئات المصروفات الافتراضية
    final expCatCount = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM expense_categories'),
        ) ?? 0;
    if (expCatCount == 0) {
      const defaults = [
        'إيجار',
        'فواتير (كهرباء/مياه)',
        'رواتب',
        'صيانة',
        'شحن ونقل',
        'توالف وكسر مخزون',
        'أخرى',
      ];
      final now = DateTime.now().toIso8601String();
      for (final name in defaults) {
        await txn.insert('expense_categories', {
          'id': name,
          'name': name,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }
}
