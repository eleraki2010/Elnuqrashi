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
  // أربع خانات مستقلة لإدخال كود التفعيل بسهولة وسرعة
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _c3 = TextEditingController();
  final _c4 = TextEditingController();

  final _f1 = FocusNode();
  final _f2 = FocusNode();
  final _f3 = FocusNode();
  final _f4 = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    _c4.dispose();
    _f1.dispose();
    _f2.dispose();
    _f3.dispose();
    _f4.dispose();
    super.dispose();
  }

  /// تفريغ وتوزيع الكود الكامل (سواء منسوخ أو ملصوق) عبر الخانات الأربع
  void _distributeCode(String input) {
    String clean = input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.startsWith('ACT')) {
      clean = clean.substring(3);
    }

    if (clean.isEmpty) return;

    setState(() {
      _c1.text = clean.length >= 4 ? clean.substring(0, 4) : clean;
      _c2.text = clean.length >= 8 ? clean.substring(4, 8) : (clean.length > 4 ? clean.substring(4) : '');
      _c3.text = clean.length >= 12 ? clean.substring(8, 12) : (clean.length > 8 ? clean.substring(8) : '');
      _c4.text = clean.length >= 16 ? clean.substring(12, 16) : (clean.length > 12 ? clean.substring(12) : '');
      _errorMessage = null;
    });

    if (clean.length >= 16) {
      _f4.requestFocus();
    } else if (clean.length >= 12) {
      _f4.requestFocus();
    } else if (clean.length >= 8) {
      _f3.requestFocus();
    } else if (clean.length >= 4) {
      _f2.requestFocus();
    }
  }

  /// لصق الكود مباشرة من الحافظة
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _distributeCode(data.text!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الحافظة فارغة أو لا تحتوي على نص'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleActivation() async {
    final k1 = _c1.text.trim();
    final k2 = _c2.text.trim();
    final k3 = _c3.text.trim();
    final k4 = _c4.text.trim();

    final fullKey = '$k1$k2$k3$k4';

    if (fullKey.length != 16) {
      setState(() {
        _errorMessage = 'يرجى إكمال الخانات الأربع (كل خانة تحتوي على 4 أحرف أو أرقام)';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await ref.read(licenseProvider.notifier).applyKey(fullKey);

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
      await Future.delayed(const Duration(milliseconds: 1400));
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
    final text = 'مرحباً م/ محمد، أود تفعيل نسختي من نظام ${AppStrings.APP_NAME}.%0Aكود جهازي هو: ${widget.licenseInfo.deviceId}';
    final url = Uri.parse('https://wa.me/${AppStrings.DEVELOPER_WHATSAPP}?text=$text');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Widget _buildCodeBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    FocusNode? prevFocus,
    required String hint,
  }) {
    return Expanded(
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty &&
              prevFocus != null) {
            prevFocus.requestFocus();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          maxLength: 4,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontFamily: 'monospace',
            color: AppColors.PRIMARY_BLUE_DARK,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 12,
              color: Colors.black26,
              letterSpacing: 1.5,
              fontWeight: FontWeight.normal,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.PRIMARY_BLUE, width: 2),
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
          ],
          onChanged: (val) {
            if (val.length > 4 || val.contains('-')) {
              _distributeCode(val);
              return;
            }
            if (val.length == 4 && nextFocus != null) {
              nextFocus.requestFocus();
            }
            if (val.isEmpty && prevFocus != null) {
              prevFocus.requestFocus();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.licenseInfo;
    final isExpired = info.status == LicenseStatus.trialExpired ||
        info.status == LicenseStatus.licenseExpired;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                          isExpired ? 'تفعيل ترخيص نظام دُكّان' : 'حالة ترخيص دُكّان POS',
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
              const Divider(height: 26),

              // بطاقة كود الجهاز
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_BG,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
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

              // حقول إدخال مفتاح التفعيل (4 خانات مستقلة)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'أدخل مفتاح التفعيل (4 خانات):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.TEXT_PRIMARY,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.paste_rounded, size: 15),
                    label: const Text('لصق الكود كاملاً', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // صف الخانات الأربع المستقلة
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    _buildCodeBox(
                      controller: _c1,
                      focusNode: _f1,
                      nextFocus: _f2,
                      hint: 'XXXX',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    _buildCodeBox(
                      controller: _c2,
                      focusNode: _f2,
                      prevFocus: _f1,
                      nextFocus: _f3,
                      hint: 'YYYY',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    _buildCodeBox(
                      controller: _c3,
                      focusNode: _f3,
                      prevFocus: _f2,
                      nextFocus: _f4,
                      hint: 'ZZZZ',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    _buildCodeBox(
                      controller: _c4,
                      focusNode: _f4,
                      prevFocus: _c4.text.isEmpty ? _f3 : null,
                      hint: 'WWWW',
                    ),
                  ],
                ),
              ),

              // رسائل الخطأ والنجاح
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.DANGER_RED.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.DANGER_RED.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.DANGER_RED, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.DANGER_RED, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppColors.SUCCESS_GREEN, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: AppColors.SUCCESS_GREEN, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // زر التفعيل
              ElevatedButton(
                onPressed: _isLoading ? null : _handleActivation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
