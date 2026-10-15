import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';

/// إرسال تذكيرات الواتساب للعملاء (Phase 4).
///
/// يستخدم روابط `wa.me` التي تفتح واتساب (أو الويب) برسالة جاهزة،
/// ولا يتطلب أي اعتماد على خدمات خارجية أو مفاتيح API.
class WhatsAppReminderService {
  WhatsAppReminderService._();

  /// تحويل الأرقام المشرقية والفارسية (٠-٩) إلى أرقام غربية (0-9)
  static String convertIndicDigits(String input) {
    const easternArabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(easternArabic[i], western[i]);
      result = result.replaceAll(persian[i], western[i]);
    }
    return result;
  }

  /// تنسيق رقم الهاتف ليبدأ بـ 2 (مصر) بدون + أو مسافات، مع دعم الأرقام المكتوبة بلوحة مفاتيح عربية.
  /// الرقم المصري مثلاً 01012345678 أو ٠١٠١٢٣٤٥٦٧٨ يصبح 201012345678.
  static String normalizeEgyptianPhone(String phone) {
    var cleaned = convertIndicDigits(phone).replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }
    // الأرقام المحلية المصرية تبدأ بـ 01 ويتوقعها واتساب بصيغة 201...
    if (cleaned.length == 11 && cleaned.startsWith('01')) {
      cleaned = '2$cleaned';
    } else if (cleaned.length == 10 && cleaned.startsWith('1')) {
      cleaned = '20$cleaned';
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

  /// فتح واتساب برسالة تذكير بالدين. يُرجع true إذا فُتح التطبيق أو الرابط بنجاح.
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

    // الروابط المختلفة بترتيب الأفضلية: التطبيق المباشر -> wa.me -> api.whatsapp.com
    final appUri = Uri.parse(
        'whatsapp://send?phone=$normalized&text=$encodedMessage');
    final webUri = Uri.parse('https://wa.me/$normalized?text=$encodedMessage');
    final apiUri = Uri.parse(
        'https://api.whatsapp.com/send?phone=$normalized&text=$encodedMessage');

    try {
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    try {
      if (await canLaunchUrl(webUri)) {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    try {
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        try {
          return await launchUrl(apiUri, mode: LaunchMode.externalApplication);
        } catch (_) {
          return false;
        }
      }
    }
  }
}
