import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/license_service.dart';
import '../../providers/license_provider.dart';
import '../dialogs/activation_dialog.dart';

class LicenseBanner extends ConsumerWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseAsync = ref.watch(licenseProvider);

    return licenseAsync.when(
      data: (info) {
        if (info.status == LicenseStatus.licensedActive) {
          return const SizedBox.shrink(); // مفعل رسمياً -> لا داعي لإظهار أي شريط
        }

        final isExpired = info.status == LicenseStatus.trialExpired ||
            info.status == LicenseStatus.licenseExpired ||
            info.status == LicenseStatus.clockTampered;

        final bgColor = isExpired
            ? AppColors.DANGER_RED.withValues(alpha: 0.12)
            : AppColors.WARNING_AMBER.withValues(alpha: 0.15);
        final borderColor = isExpired
            ? AppColors.DANGER_RED.withValues(alpha: 0.3)
            : AppColors.WARNING_AMBER.withValues(alpha: 0.4);
        final textColor = isExpired ? AppColors.DANGER_RED : const Color(0xFFB45309);
        final icon = isExpired ? Icons.lock_clock_rounded : Icons.timer_outlined;

        final message = isExpired
            ? 'انتهت الفترة التجريبية المجانية — يرجى تفعيل النسخة لمتابعة حفظ العمليات اليومية.'
            : 'نسخة تجريبية مجانية — متبقي ${info.remainingDays} يوماً على التفعيل.';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => ActivationDialog.show(context, licenseInfo: info),
                style: ElevatedButton.styleFrom(
                  backgroundColor: textColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('تفعيل النسخة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
