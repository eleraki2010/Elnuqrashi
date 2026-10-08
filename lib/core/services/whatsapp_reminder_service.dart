import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';

/// إرسال تذكيرات الواتساب للعملاء (Phase 4).
///
/// يستخدم روابط `wa.me` التي تفتح واتساب (أو الويب) برسالة جاهزة،
/// ولا يتطلب أي اعتماد على خدمات خارجية أو مفاتيح API.
class WhatsAppReminderService {
  WhatsAppReminderService._();

  /// تنسيق رقم الهاتف ليبدأ بـ 2 (مصر) بدون + أو مسافات.
  /// الرقم المصري مثلاً 01012345678 يصبح 201012345678.
  static String normalizeEgyptianPhone(String phone) {
    var cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    // الأرقام المحلية المصرية تبدأ بـ 01 ويتوقعها واتساب بصيغة 201...
    if (cleaned.length == 11 && cleaned.startsWith('01')) {
      cleaned = '2$cleaned';
    }
    return cleaned;
  }

  static bool isValidWhatsAppNumber(String phone) {
    final normalized = normalizeEgyptianPhone(phone);
    return normalized.length >= 10 && normalized.length <= 15;
  }

  /// بناء نص رسالة التذكير بالدين.
  static String buildDebtReminderMessage({
    required String customerName,
    required double balanceDue,
  }) {
    return 'السلام عليكم $customerName 🌷\n'
        'نأمل أن تكون بخير.\n'
        'نذكّركم بوجود مبلغ مستحق على حسابكم لدى ${AppStrings.STORE_NAME} '
        'وقدره ${balanceDue.toStringAsFixed(0)} ${AppStrings.CURRENCY}.\n'
        'نرجو السداد في أقرب وقت ممكن، ويمكنكم زيارة المتجر أو التواصل معنا.\n'
        'شكراً لتعاملكم معنا 🙏';
  }

  /// فتح واتساب برسالة تذكير بالدين. يُرجع true إذا فُتح التطبيق بنجاح.
  static Future<bool> sendDebtReminder({
    required String customerName,
    required String phone,
    required double balanceDue,
  }) async {
    final normalized = normalizeEgyptianPhone(phone);
    if (!isValidWhatsAppNumber(normalized)) {
      throw ArgumentError('رقم الهاتف غير صالح لواتساب: $phone');
    }

    final message = buildDebtReminderMessage(
      customerName: customerName,
      balanceDue: balanceDue,
    );
    final encodedMessage = Uri.encodeComponent(message);

    // نجرّب تطبيق واتساب أولاً، ثم الويب كاحتياطي.
    final appUri = Uri.parse(
        'whatsapp://send?phone=$normalized&text=$encodedMessage');
    final webUri = Uri.parse('https://wa.me/$normalized?text=$encodedMessage');

    if (await canLaunchUrl(appUri)) {
      return launchUrl(appUri, mode: LaunchMode.externalApplication);
    }
    return launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}
