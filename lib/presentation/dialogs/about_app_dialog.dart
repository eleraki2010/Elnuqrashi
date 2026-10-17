import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/license_provider.dart';
import '../screens/settings_screen.dart';

class AboutAppDialog extends ConsumerWidget {
  const AboutAppDialog({super.key});

  Future<void> _openWhatsApp(BuildContext context) async {
    const phone = AppStrings.DEVELOPER_WHATSAPP;
    final message = Uri.encodeComponent(
      'مرحباً م/ محمد، أتواصل معك بخصوص نظام دُكّان POS للحصول على الدعم الفني أو الاستفسار.',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$message');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          Clipboard.setData(const ClipboardData(text: AppStrings.DEVELOPER_PHONE));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم نسخ رقم الدعم الفني: ${AppStrings.DEVELOPER_PHONE}'),
              backgroundColor: AppColors.SUCCESS_GREEN,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        Clipboard.setData(const ClipboardData(text: AppStrings.DEVELOPER_PHONE));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم نسخ رقم الدعم الفني: ${AppStrings.DEVELOPER_PHONE}'),
            backgroundColor: AppColors.SUCCESS_GREEN,
          ),
        );
      }
    }
  }

  void _copyPhone(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: AppStrings.DEVELOPER_PHONE));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رقم هاتف المطور بنجاح'),
        backgroundColor: AppColors.SUCCESS_GREEN,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = ref.watch(storeNameProvider);
    final licenseAsync = ref.watch(licenseProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. رأس هوية التطبيق (App Software Brand)
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.15),
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.storefront_rounded,
                            color: AppColors.PRIMARY_BLUE,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          AppStrings.APP_NAME,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.2)),
                          ),
                          child: const Text(
                            AppStrings.APP_VERSION,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.PRIMARY_BLUE,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      AppStrings.APP_SLOGAN,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // 2. بطاقة هوية المحل والترخيص الحالي
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_BG,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store_outlined, size: 20, color: AppColors.PRIMARY_BLUE),
                        const SizedBox(width: 8),
                        const Text(
                          'المتجر المرخّص:',
                          style: TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
                        ),
                        const Spacer(),
                        Text(
                          storeName.isNotEmpty ? storeName : AppStrings.DEFAULT_STORE_NAME,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.TEXT_PRIMARY,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    licenseAsync.when(
                      data: (lic) => Row(
                        children: [
                          Icon(
                            lic.canPerformTransactions ? Icons.verified_rounded : Icons.lock_clock_rounded,
                            size: 18,
                            color: lic.canPerformTransactions ? AppColors.SUCCESS_GREEN : AppColors.DANGER_RED,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'حالة الترخيص:',
                            style: TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
                          ),
                          const Spacer(),
                          Text(
                            lic.statusDescription,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: lic.canPerformTransactions ? AppColors.SUCCESS_GREEN : AppColors.DANGER_RED,
                            ),
                          ),
                        ],
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 3. هوية المطور وجهة البرمجة (Developer Branding & Credits)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0F172A),
                      const Color(0xFF1E293B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.code_rounded, color: Colors.amberAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'هندسة وبرمجة النظام',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                AppStrings.DEVELOPER_NAME,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'لطلب الدعم الفني، تجديد التراخيص، أو إضافة ميزات مخصصة لمنشأتك:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _openWhatsApp(context),
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                            label: const Text(
                              'واتساب الدعم الفني',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF475569)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _copyPhone(context),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text(
                            AppStrings.DEVELOPER_PHONE,
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // حقوق النشر وتذييل الحوار
              const Center(
                child: Text(
                  AppStrings.DEVELOPER_RIGHTS,
                  style: TextStyle(fontSize: 11, color: AppColors.TEXT_SECONDARY),
                ),
              ),
              const SizedBox(height: 10),

              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
