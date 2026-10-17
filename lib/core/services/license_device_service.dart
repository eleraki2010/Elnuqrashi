import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة استخراج بصمة العتاد الفريدة للجهاز (Hardware Fingerprint).
///
/// تضمن استخراج معرّف عتاد ثابت وفريد للجهاز لا يتكرر:
/// - على Windows: MachineGuid من الـ Registry + UUID العتاد.
/// - على Android / المنصات الأخرى: معرّف مشفر ومخزن في مسار التطبيق الآمن.
class LicenseDeviceService {
  static String? _cachedDeviceId;

  /// الحصول على معرّف الجهاز بصيغة سهلة القراءة (مثال: ELN-8F42-99B1-K32A).
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    String rawHardwareInfo = '';

    try {
      if (Platform.isWindows) {
        rawHardwareInfo = await _getWindowsHardwareId();
      } else {
        rawHardwareInfo = await _getFallbackHardwareId();
      }
    } catch (_) {
      rawHardwareInfo = await _getFallbackHardwareId();
    }

    if (rawHardwareInfo.trim().isEmpty) {
      rawHardwareInfo = await _getFallbackHardwareId();
    }

    // تشفير البصمة لإنتاج كود موحد من 12 حرفاً سهلاً للمحادثة الهاتفية أو واتساب
    final hash = sha256.convert(utf8.encode(rawHardwareInfo)).toString().toUpperCase();
    final clean = hash.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final p1 = clean.substring(0, 4);
    final p2 = clean.substring(4, 8);
    final p3 = clean.substring(8, 12);

    _cachedDeviceId = 'ELN-$p1-$p2-$p3';
    return _cachedDeviceId!;
  }

  /// استخراج بصمة عتاد ويندوز من سجل النظام (Registry MachineGuid) ومعرّف اللوحة الأم
  static Future<String> _getWindowsHardwareId() async {
    String guid = '';
    String sysUuid = '';

    try {
      // 1. قراءة MachineGuid من سجل الويندوز الرسمي
      final regResult = await Process.run(
        'reg',
        ['query', r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid'],
      );
      if (regResult.exitCode == 0) {
        final match = RegExp(r'MachineGuid\s+REG_SZ\s+([a-zA-Z0-9\-]+)')
            .firstMatch(regResult.stdout.toString());
        if (match != null) {
          guid = match.group(1) ?? '';
        }
      }
    } catch (_) {}

    try {
      // 2. قراءة UUID العتاد من النظام
      final wmicResult = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', '(Get-CimInstance -Class Win32_ComputerSystemProduct).UUID'],
      );
      if (wmicResult.exitCode == 0) {
        sysUuid = wmicResult.stdout.toString().trim();
      }
    } catch (_) {}

    if (guid.isNotEmpty || sysUuid.isNotEmpty) {
      return 'WIN_${guid}_$sysUuid';
    }

    return _getFallbackHardwareId();
  }

  /// بديل احتياطي دائم في حال تعذر قراءة العتاد المباشر
  static Future<String> _getFallbackHardwareId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'alnokrashy_pos_device_seed';
    String? seed = prefs.getString(key);

    if (seed == null || seed.isEmpty) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        final seedFile = File('${supportDir.path}/.device_seed');
        if (await seedFile.exists()) {
          seed = (await seedFile.readAsString()).trim();
        }
      } catch (_) {}
    }

    if (seed == null || seed.isEmpty) {
      final now = DateTime.now().toIso8601String();
      final rand = DateTime.now().microsecondsSinceEpoch.toString();
      final envUser = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'u';
      seed = 'SEED_${now}_${rand}_$envUser';

      await prefs.setString(key, seed);
      try {
        final supportDir = await getApplicationSupportDirectory();
        final seedFile = File('${supportDir.path}/.device_seed');
        await seedFile.writeAsString(seed);
      } catch (_) {}
    }

    return seed;
  }
}
