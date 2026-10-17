import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/services/backup_service.dart';
import '../../providers/auth_provider.dart';
import 'main_layout_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: '1');
  final _passwordController = TextEditingController(text: '123');
  bool _isLoading = false;
  bool _obscurePassword = true;
  File? _detectedBackup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForExistingBackup();
    });
  }

  Future<void> _checkForExistingBackup() async {
    try {
      final isEmpty = await BackupService.isDatabaseEmpty();
      if (!isEmpty) return;
      final latest = await BackupService.findLatestBackupFile();
      if (mounted && latest != null) {
        setState(() => _detectedBackup = latest);
      }
    } catch (_) {}
  }

  Future<void> _restoreDetectedBackup(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore, color: AppColors.SUCCESS_GREEN),
            SizedBox(width: 8),
            Text('استعادة بيانات المحل'),
          ],
        ),
        content: Text(
          'سيتم استرجاع كافة المنتجات، الفواتير، والعملاء من النسخة الاحتياطية:\n(${p.basename(file.path)})\n\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.SUCCESS_GREEN,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await BackupService.restoreFromSpecificFile(file);
      if (mounted) {
        ref.invalidate(authProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            duration: Duration(seconds: 4),
            content: Text('تم استرجاع كافة بياناتك بنجاح! يمكنك الآن تسجيل الدخول.'),
          ),
        );
        setState(() => _detectedBackup = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('تعذر استعادة النسخة: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndRestoreFile() async {
    setState(() => _isLoading = true);
    try {
      final success = await BackupService.restoreFromBackupFile();
      if (mounted && success) {
        ref.invalidate(authProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم استعادة البيانات بنجاح! يمكنك الآن تسجيل الدخول.'),
          ),
        );
        setState(() => _detectedBackup = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشلت الاستعادة: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).login(
          _usernameController.text,
          _passwordController.text,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainLayoutScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.DANGER_RED,
          content: Text('اسم المستخدم أو كلمة المرور غير صحيحة'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS * 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.storefront,
                          color: AppColors.PRIMARY_BLUE,
                          size: 56,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.APP_TITLE,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTypography.HEADING_2,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE_DARK,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تسجيل الدخول للوصول إلى نقطة البيع',
                    style: TextStyle(color: AppColors.TEXT_SECONDARY),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'يرجى إدخال اسم المستخدم';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() {
                          _obscurePassword = !_obscurePassword;
                        }),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'يرجى إدخال كلمة المرور';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'تسجيل الدخول',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  if (_detectedBackup != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                        border: Border.all(color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.SUCCESS_GREEN.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.restore, color: AppColors.SUCCESS_GREEN, size: 24),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تم العثور على نسخة احتياطية سابقة!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.SUCCESS_GREEN,
                                      ),
                                    ),
                                    Text(
                                      'تم العثور على ملف بيانات على جهازك تلقائياً',
                                      style: TextStyle(fontSize: 11, color: AppColors.TEXT_SECONDARY),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.insert_drive_file_outlined, size: 16, color: AppColors.PRIMARY_BLUE),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.basename(_detectedBackup!.path),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.SUCCESS_GREEN,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 1,
                            ),
                            onPressed: _isLoading ? null : () => _restoreDetectedBackup(_detectedBackup!),
                            icon: const Icon(Icons.cloud_download_rounded, size: 20),
                            label: const Text(
                              'استعادة كافة بيانات المحل الآن',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                    ),
                    onPressed: _isLoading ? null : _pickAndRestoreFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 18, color: AppColors.PRIMARY_BLUE),
                    label: const Text(
                      'استعادة البيانات يدوياً من ملف (.json)',
                      style: TextStyle(fontSize: 13, color: AppColors.PRIMARY_BLUE_DARK),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.NEUTRAL_BG,
                      borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.PRIMARY_BLUE, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'الحساب الافتراضي للدخول:\nاسم المستخدم: 1\nكلمة المرور: 123\nيمكنك إضافة أو تغيير المستخدمين من شاشة الإعدادات بعد الدخول.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.TEXT_SECONDARY,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 13, color: AppColors.TEXT_SECONDARY),
                      const SizedBox(width: 4),
                      Text(
                        '${AppStrings.APP_NAME} (${AppStrings.APP_VERSION}) • تطوير: ${AppStrings.DEVELOPER_NAME}',
                        style: const TextStyle(fontSize: 11, color: AppColors.TEXT_SECONDARY),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
