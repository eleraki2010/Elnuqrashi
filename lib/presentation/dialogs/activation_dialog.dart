import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/license_service.dart';
import '../../providers/license_provider.dart';

class ActivationDialog extends ConsumerStatefulWidget {
  final LicenseInfo licenseInfo;
  final bool isDismissible;

  const ActivationDialog({
    super.key,
    required this.licenseInfo,
    this.isDismissible = true,
  });

  static Future<void> show(
    BuildContext context, {
    required LicenseInfo licenseInfo,
    bool isDismissible = true,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: isDismissible,
      builder: (_) => ActivationDialog(
        licenseInfo: licenseInfo,
        isDismissible: isDismissible,
      ),
    );
  }

  @override
  ConsumerState<ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends ConsumerState<ActivationDialog> {
  final _keyController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال مفتاح التفعيل أولاً';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await ref.read(licenseProvider.notifier).applyKey(key);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.success) {
        _successMessage = result.message;
        _errorMessage = null;
      } else {
        _errorMessage = result.message;
        _successMessage = null;
      }
    });

    if (result.success) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: widget.licenseInfo.deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ كود الجهاز بنجاح!'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.SUCCESS_GREEN,
      ),
    );
  }

  Future<void> _sendViaWhatsApp() async {
    final text = 'مرحباً، أود تفعيل نسختي من نظام ${AppStrings.APP_NAME}.%0Aكود جهازي هو: ${widget.licenseInfo.deviceId}';
    final url = Uri.parse('https://wa.me/${AppStrings.DEVELOPER_WHATSAPP}?text=$text');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.licenseInfo;
    final isExpired = info.status == LicenseStatus.trialExpired ||
        info.status == LicenseStatus.licenseExpired;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // رأس الحوار
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                          : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isExpired ? Icons.lock_clock_rounded : Icons.verified_user_rounded,
                      color: isExpired ? AppColors.DANGER_RED : AppColors.PRIMARY_BLUE,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isExpired ? 'تفعيل ترخيص التطبيق' : 'حالة ترخيص البرنامج',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.TEXT_PRIMARY,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.statusDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: isExpired ? AppColors.DANGER_RED : AppColors.TEXT_SECONDARY,
                            fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isDismissible)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.TEXT_SECONDARY),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const Divider(height: 28),

              // بطاقة كود الجهاز
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_BG,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كود جهازك الفريد (Hardware ID):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SelectableText(
                            info.deviceId,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppColors.PRIMARY_BLUE_DARK,
                              fontFamily: 'monospace',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.PRIMARY_BLUE),
                            tooltip: 'نسخ كود الجهاز',
                            onPressed: _copyDeviceId,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyDeviceId,
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('نسخ الكود', style: TextStyle(fontSize: 12.5)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _sendViaWhatsApp,
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('إرسال للمطور', style: TextStyle(fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.SUCCESS_GREEN,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // حقل إدخال مفتاح التفعيل
              const Text(
                'أدخل مفتاح التفعيل المستلم من المطور:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.TEXT_PRIMARY,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
                decoration: InputDecoration(
                  hintText: 'ACT-XXXX-YYYY-ZZZZ-WWWW',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Colors.black26,
                    letterSpacing: 1,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.PRIMARY_BLUE, width: 2),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste_rounded, size: 20),
                    tooltip: 'لصق',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _keyController.text = data!.text!.trim().toUpperCase();
                      }
                    },
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
              ),

              // رسائل الخطأ والنجاح
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.DANGER_RED.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.DANGER_RED, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.DANGER_RED, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppColors.SUCCESS_GREEN, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: AppColors.SUCCESS_GREEN, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // زر التفعيل
              ElevatedButton(
                onPressed: _isLoading ? null : _handleActivation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'تفعيل التطبيق الآن',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
              ),

              // زر المتابعة كقراءة فقط في حال انتهاء الصلاحية
              if (isExpired && widget.isDismissible) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'متابعة لاستعراض البيانات فقط (وضع القراءة)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
