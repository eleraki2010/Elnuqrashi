import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/license_service.dart';

class LicenseNotifier extends AsyncNotifier<LicenseInfo> {
  @override
  Future<LicenseInfo> build() async {
    return LicenseService.checkLicense();
  }

  /// إعادة فحص الترخيص
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => LicenseService.checkLicense());
  }

  /// إدخال كود تفعيل
  Future<({bool success, String message})> applyKey(String key) async {
    final result = await LicenseService.applyLicenseKey(key);
    state = AsyncValue.data(result.info);
    return (success: result.success, message: result.message);
  }
}

final licenseProvider =
    AsyncNotifierProvider<LicenseNotifier, LicenseInfo>(LicenseNotifier.new);

/// هل يُسمح بإجراء عمليات جديدة (بيع، شراء، دفعات)؟
final isTransactionAllowedProvider = Provider<bool>((ref) {
  final license = ref.watch(licenseProvider).value;
  if (license == null) return true; // افتراضي أثناء التحميل السريع
  return license.canPerformTransactions;
});
