import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnokrashy_pos/core/services/license_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LicenseService Cryptography & Validation Tests', () {
    const deviceA = 'ELN-8F42-99B1-K32A';
    const deviceB = 'ELN-1122-3344-5566';

    test('Lifetime License Generation and Validation', () {
      final key = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '9', // Lifetime
      );

      expect(key.startsWith('ACT-'), true);

      final result = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key,
        currentDate: DateTime.now(),
      );

      expect(result.isValid, true);
      expect(result.isLifetime, true);
      expect(result.isExpired, false);
    });

    test('1 Year License Validation active today', () {
      final now = DateTime.now();
      final key = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '1', // 1 Year
        issuedDate: now,
      );

      final result = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key,
        currentDate: now.add(const Duration(days: 100)),
      );

      expect(result.isValid, true);
      expect(result.isLifetime, false);
      expect(result.isExpired, false);
      expect(result.remainingDays, closeTo(265, 2));
    });

    test('1 Year License Expired after 366 days', () {
      final now = DateTime.now();
      final key = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '1', // 1 Year
        issuedDate: now,
      );

      final result = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key,
        currentDate: now.add(const Duration(days: 367)),
      );

      expect(result.isValid, false);
      expect(result.isExpired, true);
    });

    test('License generated for Device A is strictly REJECTED on Device B', () {
      final keyForA = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '9', // Lifetime
      );

      final resultOnB = LicenseService.verifyLicenseKey(
        deviceId: deviceB,
        licenseKey: keyForA,
        currentDate: DateTime.now(),
      );

      expect(resultOnB.isValid, false);
      expect(resultOnB.isExpired, false);
    });

    test('Multi-Year Licenses (2 Years and 3 Years)', () {
      final now = DateTime.now();
      final key2Y = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '2', // 2 Years
        issuedDate: now,
      );
      final key3Y = LicenseService.generateLicenseKey(
        deviceId: deviceA,
        type: '3', // 3 Years
        issuedDate: now,
      );

      // بعد 500 يوم: الـ 2Y صالحة والـ 3Y صالحة
      final res2Y = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key2Y,
        currentDate: now.add(const Duration(days: 500)),
      );
      expect(res2Y.isValid, true);

      // بعد 800 يوم: الـ 2Y انتهت (730 يوم) والـ 3Y ما زالت صالحة (1095 يوم)
      final res2YLater = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key2Y,
        currentDate: now.add(const Duration(days: 800)),
      );
      expect(res2YLater.isValid, false);
      expect(res2YLater.isExpired, true);

      final res3YLater = LicenseService.verifyLicenseKey(
        deviceId: deviceA,
        licenseKey: key3Y,
        currentDate: now.add(const Duration(days: 800)),
      );
      expect(res3YLater.isValid, true);
    });

    test('Trial Period active for 30 days and expires on day 31', () async {
      final baseDate = DateTime(2026, 1, 1);

      // اليوم الأول: التجربة صالحة (30 يوماً)
      final infoDay1 = await LicenseService.checkLicense(customNow: baseDate);
      expect(infoDay1.status, LicenseStatus.trialActive);
      expect(infoDay1.remainingDays, 30);
      expect(infoDay1.canPerformTransactions, true);

      // اليوم العشرين: متبقي 10 أيام
      final infoDay20 = await LicenseService.checkLicense(
        customNow: baseDate.add(const Duration(days: 20)),
      );
      expect(infoDay20.status, LicenseStatus.trialActive);
      expect(infoDay20.remainingDays, 10);
      expect(infoDay20.canPerformTransactions, true);

      // اليوم الحادي والثلاثين: انتهت التجربة
      final infoDay31 = await LicenseService.checkLicense(
        customNow: baseDate.add(const Duration(days: 31)),
      );
      expect(infoDay31.status, LicenseStatus.trialExpired);
      expect(infoDay31.canPerformTransactions, false);
    });
  });
}
