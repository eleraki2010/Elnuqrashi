import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'license_device_service.dart';

/// حالة ترخيص التطبيق الحالية
enum LicenseStatus {
  /// فترة تجريبية مجانية نشطة (تعمل بكامل الكفاءة)
  trialActive,

  /// انتهت الفترة التجريبية (30 يوماً) ويلزم التفعيل
  trialExpired,

  /// مفعل بترخيص رسمي صالح (سنوي أو مدى الحياة)
  licensedActive,

  /// انتهت صلاحية الترخيص السنوي ويلزم التجديد
  licenseExpired,

  /// رصد تلاعب بساعة وتاريخ الجهاز
  clockTampered,
}

/// تفاصيل حالة الترخيص المتاحة للواجهات البرمجية
class LicenseInfo {
  final LicenseStatus status;
  final String deviceId;
  final int remainingDays;
  final DateTime? expiryDate;
  final bool isLifetime;
  final String? licenseKey;

  const LicenseInfo({
    required this.status,
    required this.deviceId,
    this.remainingDays = 0,
    this.expiryDate,
    this.isLifetime = false,
    this.licenseKey,
  });

  /// هل يُسمح للمستخدم بإجراء عمليات محاسبية جديدة (بيع، شراء، دفعات)؟
  bool get canPerformTransactions =>
      status == LicenseStatus.trialActive || status == LicenseStatus.licensedActive;

  /// هل التطبيق حالياً في فترة التجربة المجانية؟
  bool get isTrial => status == LicenseStatus.trialActive;

  /// هل النسخة مفعلة بترخيص دائم أو سنوي سارٍ؟
  bool get isLicensed => status == LicenseStatus.licensedActive;

  /// وصف مقروء للحالة
  String get statusDescription {
    switch (status) {
      case LicenseStatus.trialActive:
        return 'فترة تجريبية مجانية (متبقي $remainingDays يوم)';
      case LicenseStatus.trialExpired:
        return 'انتهت الفترة التجريبية المجانية (يلزم التفعيل)';
      case LicenseStatus.licensedActive:
        if (isLifetime) return 'نسخة مفعلة بصفة دائمة (مدى الحياة)';
        return 'نسخة مفعلة سارية حتى ${expiryDate?.toString().split(' ').first}';
      case LicenseStatus.licenseExpired:
        return 'انتهت مدة اشتراك الترخيص (يلزم التجديد)';
      case LicenseStatus.clockTampered:
        return 'تم رصد تغيير في ساعة النظام';
    }
  }
}

/// محرك التراخيص والتشفير وحماية التطبيق
class LicenseService {
  /// المفتاح السري المخصص لنظام دُكّان POS (لا يعرفه سوى المطور ومولد الأكواد)
  static const String _kSecretSalt =
      'ELNUQRASHI_POS_PROD_KEY_#2026_V1_SECRET_98b7f24a1e';

  // مفاتيح التخزين الآمن
  static const String _keyLicenseCode = 'alnokrashy_pos_lic_key';
  static const String _keyFirstRunDate = 'alnokrashy_pos_first_run_date';
  static const String _keyFirstRunSig = 'alnokrashy_pos_first_run_sig';
  static const String _keyLastKnownDate = 'alnokrashy_pos_last_known_date';

  /// فحص حالة الترخيص الحالية للجهاز
  static Future<LicenseInfo> checkLicense({DateTime? customNow}) async {
    final deviceId = await LicenseDeviceService.getDeviceId();
    final prefs = await SharedPreferences.getInstance();
    final now = customNow ?? DateTime.now();

    // 1. التحقق من حماية ساعة النظام (Anti-Clock Tampering)
    final lastKnownEpoch = prefs.getInt(_keyLastKnownDate);
    final currentEpoch = now.millisecondsSinceEpoch;

    if (lastKnownEpoch != null) {
      // إذا كان التاريخ الحالي يسبق آخر تشغيل معروف بأكثر من 4 ساعات (محاولة إرجاع الساعة)
      if (currentEpoch < lastKnownEpoch - (4 * 3600 * 1000)) {
        return LicenseInfo(
          status: LicenseStatus.clockTampered,
          deviceId: deviceId,
        );
      }
    }
    // تحديث آخر وقت تشغيل معروف
    await prefs.setInt(_keyLastKnownDate, currentEpoch);

    // 2. فحص وجود كود تفعيل مسجل
    final savedKey = prefs.getString(_keyLicenseCode)?.trim();
    if (savedKey != null && savedKey.isNotEmpty) {
      final keyResult = verifyLicenseKey(
        deviceId: deviceId,
        licenseKey: savedKey,
        currentDate: now,
      );

      if (keyResult.isValid) {
        return LicenseInfo(
          status: LicenseStatus.licensedActive,
          deviceId: deviceId,
          remainingDays: keyResult.remainingDays,
          expiryDate: keyResult.expiryDate,
          isLifetime: keyResult.isLifetime,
          licenseKey: savedKey,
        );
      } else if (keyResult.isExpired) {
        return LicenseInfo(
          status: LicenseStatus.licenseExpired,
          deviceId: deviceId,
          remainingDays: 0,
          expiryDate: keyResult.expiryDate,
          licenseKey: savedKey,
        );
      }
      // إذا كان الكود المحفوظ غير صالح (تغيّر العتاد مثلاً)، نستمر لفحص الفترة التجريبية
    }

    // 3. إدارة الفترة التجريبية المجانية (30 يوماً)
    final firstRunIso = prefs.getString(_keyFirstRunDate);
    final firstRunSig = prefs.getString(_keyFirstRunSig);

    DateTime firstRun;
    if (firstRunIso == null || firstRunSig == null) {
      // أول تشغيل للتطبيق على هذا الجهاز
      firstRun = now;
      final iso = firstRun.toIso8601String();
      final sig = _hashData('$iso:$deviceId');
      await prefs.setString(_keyFirstRunDate, iso);
      await prefs.setString(_keyFirstRunSig, sig);
    } else {
      // التحقق من صحة تاريخ أول تشغيل
      final expectedSig = _hashData('$firstRunIso:$deviceId');
      if (firstRunSig != expectedSig) {
        // تم التلاعب ببيانات التثبيت
        return LicenseInfo(
          status: LicenseStatus.trialExpired,
          deviceId: deviceId,
        );
      }
      firstRun = DateTime.tryParse(firstRunIso) ?? now;
    }

    // حساب الأيام المنقضية من التجربة (30 يوماً)
    const int trialDurationDays = 30;
    final diffDays = now.difference(firstRun).inDays;
    final remainingTrial = trialDurationDays - diffDays;

    if (remainingTrial > 0) {
      return LicenseInfo(
        status: LicenseStatus.trialActive,
        deviceId: deviceId,
        remainingDays: remainingTrial,
        expiryDate: firstRun.add(const Duration(days: trialDurationDays)),
      );
    } else {
      return LicenseInfo(
        status: LicenseStatus.trialExpired,
        deviceId: deviceId,
        remainingDays: 0,
      );
    }
  }

  /// إدخال وتطبيق كود تفعيل جديد
  static Future<({bool success, String message, LicenseInfo info})> applyLicenseKey(
    String licenseKey,
  ) async {
    final deviceId = await LicenseDeviceService.getDeviceId();
    final now = DateTime.now();

    final validation = verifyLicenseKey(
      deviceId: deviceId,
      licenseKey: licenseKey,
      currentDate: now,
    );

    if (!validation.isValid) {
      if (validation.isExpired) {
        return (
          success: false,
          message: 'كود التفعيل منتهي الصلاحية!',
          info: await checkLicense(),
        );
      }
      return (
        success: false,
        message: 'كود التفعيل غير صالح لهذا الجهاز. تأكد من إدخال الكود الصحيح.',
        info: await checkLicense(),
      );
    }

    // حفظ الكود الصالح
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLicenseCode, licenseKey.trim().toUpperCase());

    final updatedInfo = await checkLicense();
    final durationDesc = validation.isLifetime
        ? 'مدى الحياة'
        : 'حتى تاريخ ${validation.expiryDate?.toString().split(' ').first}';

    return (
      success: true,
      message: 'تم تفعيل التطبيق بنجاح! نوع الترخيص: $durationDesc',
      info: updatedInfo,
    );
  }

  /// إزالة الترخيص الحالي (لأغراض الإدارة أو التجارب)
  static Future<void> removeLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLicenseCode);
  }

  // =========================================================================
  // خوارزمية التشفير والتحقق من المفاتيح (Mathematical HMAC-SHA256 Architecture)
  // =========================================================================

  /// التحقق من صحة كود تفعيل لجهاز محدد
  static ({
    bool isValid,
    bool isExpired,
    bool isLifetime,
    DateTime? expiryDate,
    int remainingDays,
  }) verifyLicenseKey({
    required String deviceId,
    required String licenseKey,
    required DateTime currentDate,
  }) {
    // تنظيف الكود
    final cleanKey = licenseKey.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    // الصيغة القياسية للأكواد: تبدأ بـ ACT ثم 16 حرفاً
    String payload = cleanKey;
    if (payload.startsWith('ACT')) {
      payload = payload.substring(3);
    }

    if (payload.length != 16) {
      return (
        isValid: false,
        isExpired: false,
        isLifetime: false,
        expiryDate: null,
        remainingDays: 0,
      );
    }

    try {
      // 1. استخراج نوع الترخيص (الحرف الأول)
      // '0' = شهر (30 يوم)
      // '1' = سنة (365 يوم)
      // '2' = سنتين (730 يوم)
      // '3' = 3 سنوات (1095 يوم)
      // '9' = مدى الحياة (Lifetime)
      final typeChar = payload.substring(0, 1);
      final isLifetime = typeChar == '9';

      // 2. استخراج تاريخ الإصدار (4 خانات Hex)
      final epochDaysHex = payload.substring(1, 5);
      final issuedEpochDays = int.parse(epochDaysHex, radix: 16);
      final issuedDate = DateTime.fromMillisecondsSinceEpoch(
        issuedEpochDays * 86400000,
        isUtc: true,
      );

      // 3. استخراج التوقيع الرقمي (11 خانة)
      final keySignature = payload.substring(5, 16);

      // 4. إعادة توليد التوقيع المتوقع لجهاز العميل والتحقق من التطابق
      final cleanDevId = deviceId.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final expectedSignature = _generateSignature(cleanDevId, typeChar, epochDaysHex);

      if (keySignature != expectedSignature) {
        return (
          isValid: false,
          isExpired: false,
          isLifetime: false,
          expiryDate: null,
          remainingDays: 0,
        );
      }

      // إذا كان مدى الحياة: صالح دائماً
      if (isLifetime) {
        return (
          isValid: true,
          isExpired: false,
          isLifetime: true,
          expiryDate: null,
          remainingDays: 99999,
        );
      }

      // 5. حساب تاريخ انتهاء الترخيص الزمني
      int durationDays = 365;
      if (typeChar == '0') durationDays = 30;
      if (typeChar == '1') durationDays = 365;
      if (typeChar == '2') durationDays = 730;
      if (typeChar == '3') durationDays = 1095;

      final expiryDate = issuedDate.add(Duration(days: durationDays));
      final remaining = expiryDate.difference(currentDate).inDays;

      if (remaining < 0) {
        return (
          isValid: false,
          isExpired: true,
          isLifetime: false,
          expiryDate: expiryDate,
          remainingDays: 0,
        );
      }

      return (
        isValid: true,
        isExpired: false,
        isLifetime: false,
        expiryDate: expiryDate,
        remainingDays: remaining,
      );
    } catch (_) {
      return (
        isValid: false,
        isExpired: false,
        isLifetime: false,
        expiryDate: null,
        remainingDays: 0,
      );
    }
  }

  /// توليد مفتاح ترخيص لجهاز محدد (تُستخدم داخل أداة التوليد الخاصة بك)
  ///
  /// [type]: '0'=شهر, '1'=سنة, '2'=سنتين, '3'=3 سنوات, '9'=مدى الحياة
  static String generateLicenseKey({
    required String deviceId,
    required String type,
    DateTime? issuedDate,
  }) {
    final now = issuedDate ?? DateTime.now();
    final cleanDevId = deviceId.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final epochDays = now.millisecondsSinceEpoch ~/ 86400000;
    final epochDaysHex = epochDays.toRadixString(16).toUpperCase().padLeft(4, '0');

    final signature = _generateSignature(cleanDevId, type, epochDaysHex);
    final rawKey = '$type$epochDaysHex$signature';

    // تنسيق المفتاح للشكل الرباعي الأنيق: XXXX-YYYY-ZZZZ-WWWW (16 خانة مقسمة على 4 خانات)
    return '${rawKey.substring(0, 4)}-${rawKey.substring(4, 8)}-${rawKey.substring(8, 12)}-${rawKey.substring(12, 16)}';
  }

  /// دالة التوقيع المشفر الداخلي عبر HMAC-SHA256
  static String _generateSignature(String cleanDeviceId, String type, String epochDaysHex) {
    final message = '$cleanDeviceId:$type:$epochDaysHex';
    final hmac = Hmac(sha256, utf8.encode(_kSecretSalt));
    final digest = hmac.convert(utf8.encode(message));
    final fullHex = digest.toString().toUpperCase();
    // نأخذ 11 خانة للتوقيع الرقمي لمنع التخمين
    return fullHex.substring(0, 11);
  }

  static String _hashData(String data) {
    final hmac = Hmac(sha256, utf8.encode(_kSecretSalt));
    return hmac.convert(utf8.encode(data)).toString();
  }
}
