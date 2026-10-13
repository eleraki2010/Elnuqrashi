import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// عميل HTTP مخصص لتمرير ترويسات مصادقة Google إلى DriveApi
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

/// خدمة إدارة النسخ الاحتياطي السحابي عبر Google Drive
class GoogleDriveBackupService {
  static const String _folderName = 'Alnokrashy_POS_Backups';
  static const String keyLastBackupTime = 'gdrive_last_backup_time';
  static const String keyAutoBackupEnabled = 'gdrive_auto_backup_enabled';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
  );

  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// تسجيل الدخول التفاعلي
  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// محاولة تسجيل الدخول الصامت لاستعادة الجلسة
  static Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      debugPrint('Google Sign-In Silently Error: $e');
      return null;
    }
  }

  /// تسجيل الخروج
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google Sign-Out Error: $e');
    }
  }

  /// التحقق من حالة تسجيل الدخول
  static Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  /// إنشاء كائن DriveApi معتمد
  static Future<drive.DriveApi?> _getDriveApi() async {
    var account = currentUser;
    account ??= await signInSilently();
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    return drive.DriveApi(authenticateClient);
  }

  /// البحث عن مجلد النسخ الاحتياطي أو إنشائه
  static Future<String> _getOrCreateBackupFolder(drive.DriveApi driveApi) async {
    final query =
        "mimeType = 'application/vnd.google-apps.folder' and name = '$_folderName' and trashed = false";
    final fileList = await driveApi.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      return fileList.files!.first.id!;
    }

    final folder = drive.File()
      ..name = _folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await driveApi.files.create(
      folder,
      $fields: 'id',
    );
    return created.id!;
  }

  /// رفع نسخة احتياطية جديدة إلى Google Drive
  static Future<drive.File> uploadBackup() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('يرجى تسجيل الدخول بحساب Google أولاً.');
    }

    final folderId = await _getOrCreateBackupFolder(driveApi);
    final snapshot = await BackupService.exportSnapshot();
    final jsonString = jsonEncode(snapshot);
    final bytes = utf8.encode(jsonString);

    final now = DateTime.now();
    final fileName =
        'alnokrashy_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';

    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folderId]
      ..description = 'نسخة احتياطية لنظام النقراشي POS'
      ..mimeType = 'application/json';

    final uploaded = await driveApi.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id, name, size, createdTime',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastBackupTime, now.toIso8601String());

    return uploaded;
  }

  /// استعراض النسخ الاحتياطية المتاحة على Google Drive
  static Future<List<drive.File>> listBackups() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return [];
    }

    final folderId = await _getOrCreateBackupFolder(driveApi);
    final query =
        "'$folderId' in parents and trashed = false and mimeType = 'application/json'";
    final fileList = await driveApi.files.list(
      q: query,
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, size, createdTime)',
    );

    return fileList.files ?? [];
  }

  /// استعادة البيانات من ملف محدد على Google Drive
  static Future<bool> restoreBackup(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('يرجى تسجيل الدخول بحساب Google أولاً.');
    }

    final response = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw Exception('تعذر تنزيل ملف النسخة الاحتياطية.');
    }

    final List<int> dataStore = [];
    await for (final chunk in response.stream) {
      dataStore.addAll(chunk);
    }

    if (dataStore.isEmpty) {
      throw Exception('ملف النسخة الاحتياطية فارغ.');
    }

    final json = jsonDecode(utf8.decode(dataStore));
    if (json is! Map<String, dynamic>) {
      throw Exception('بيانات النسخة الاحتياطية غير صالحة.');
    }

    final meta = json['_meta'];
    if (meta is! Map || meta['app'] != 'alnokrashy_pos') {
      throw Exception('الملف المختار ليس نسخة احتياطية صالحة لتطبيق النقراشي.');
    }

    await BackupService.restoreFromSnapshot(json);
    return true;
  }

  /// فحص شروط وتفعيل النسخ التلقائي في الخلفية
  static Future<bool> checkAndTriggerAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool(keyAutoBackupEnabled) ?? true;
      if (!isEnabled) return false;

      // فحص وجود اتصال بالإنترنت
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any((c) =>
          c == ConnectivityResult.wifi ||
          c == ConnectivityResult.mobile ||
          c == ConnectivityResult.ethernet);

      if (!hasConnection) return false;

      // فحص موعد آخر نسخة (ألا يقل الفارق عن 12 ساعة لتوفير البيانات)
      final lastBackupStr = prefs.getString(keyLastBackupTime);
      if (lastBackupStr != null) {
        final lastBackup = DateTime.tryParse(lastBackupStr);
        if (lastBackup != null) {
          final diff = DateTime.now().difference(lastBackup);
          if (diff.inHours < 12) {
            return false;
          }
        }
      }

      // محاولة تسجيل الدخول الصامت إذا لم يكن مسجلاً
      final user = await signInSilently();
      if (user == null) return false;

      await uploadBackup();
      debugPrint('Auto backup completed successfully to Google Drive.');
      return true;
    } catch (e) {
      debugPrint('Auto backup failed: $e');
      return false;
    }
  }

  /// تفعيل الاستماع لتغيرات الشبكة لبدء النسخ التلقائي فور الاتصال
  static void initializeAutoBackupListener() {
    Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((c) =>
          c == ConnectivityResult.wifi ||
          c == ConnectivityResult.mobile ||
          c == ConnectivityResult.ethernet);
      if (hasConnection) {
        checkAndTriggerAutoBackup();
      }
    });
  }
}
