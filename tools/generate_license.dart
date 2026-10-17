import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const String _kSecretSalt =
    'ELNUQRASHI_POS_PROD_KEY_#2026_V1_SECRET_98b7f24a1e';

void main(List<String> args) {
  if (args.isEmpty) {
    stdout.writeln('======================================================');
    stdout.writeln('  أداة توليد تراخيص النقراشي POS (Elnuqrashi POS Keygen)');
    stdout.writeln('======================================================');
    stdout.writeln('الاستخدام:');
    stdout.writeln('  dart run tools/generate_license.dart <DEVICE_ID> [TYPE]');
    stdout.writeln('');
    stdout.writeln('خيارات النوع [TYPE]:');
    stdout.writeln('  9 : مدى الحياة (Lifetime) [الافتراضي]');
    stdout.writeln('  1 : سنة واحدة (1 Year)');
    stdout.writeln('  2 : سنتان (2 Years)');
    stdout.writeln('  3 : ثلاث سنوات (3 Years)');
    stdout.writeln('  0 : شهر واحد (1 Month)');
    stdout.writeln('');
    stdout.writeln('مثال:');
    stdout.writeln('  dart run tools/generate_license.dart ELN-8F42-99B1-K32A 1');
    stdout.writeln('======================================================');
    return;
  }

  final deviceId = args[0].trim().toUpperCase();
  final type = args.length > 1 ? args[1].trim() : '9';

  final key = generateLicenseKey(
    deviceId: deviceId,
    type: type,
  );

  String desc = 'مدى الحياة (Lifetime)';
  if (type == '1') desc = 'سنة واحدة (1 Year)';
  if (type == '2') desc = 'سنتان (2 Years)';
  if (type == '3') desc = 'ثلاث سنوات (3 Years)';
  if (type == '0') desc = 'شهر واحد (1 Month)';

  stdout.writeln('');
  stdout.writeln('✅ تم توليد مفتاح التفعيل بنجاح:');
  stdout.writeln('------------------------------------------------------');
  stdout.writeln('كود الجهاز:    $deviceId');
  stdout.writeln('نوع الترخيص:   $desc');
  stdout.writeln('مفتاح التفعيل: $key');
  stdout.writeln('------------------------------------------------------');
  stdout.writeln('');
}

String generateLicenseKey({
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

  return 'ACT-${rawKey.substring(0, 4)}-${rawKey.substring(4, 8)}-${rawKey.substring(8, 12)}-${rawKey.substring(12, 16)}';
}

String _generateSignature(String cleanDeviceId, String type, String epochDaysHex) {
  final message = '$cleanDeviceId:$type:$epochDaysHex';
  final hmac = Hmac(sha256, utf8.encode(_kSecretSalt));
  final digest = hmac.convert(utf8.encode(message));
  final fullHex = digest.toString().toUpperCase();
  return fullHex.substring(0, 11);
}
