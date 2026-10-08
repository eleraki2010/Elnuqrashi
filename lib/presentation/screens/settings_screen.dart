import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alnokrashy_pos/core/constants/app_constants.dart';
import '../../core/services/backup_service.dart';
import '../../data/repositories/shop_profile_repository.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';
import 'users_settings_screen.dart';

class _StoreNameNotifier extends Notifier<String> {
  @override
  String build() => AppStrings.STORE_NAME;

  void set(String value) => state = value;
}

class _StorePhoneNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

class _StoreAddressNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

class _StoreLogoNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final storeNameProvider = NotifierProvider<_StoreNameNotifier, String>(_StoreNameNotifier.new);
final storePhoneProvider = NotifierProvider<_StorePhoneNotifier, String?>(_StorePhoneNotifier.new);
final storeAddressProvider = NotifierProvider<_StoreAddressNotifier, String?>(_StoreAddressNotifier.new);
final storeLogoPathProvider = NotifierProvider<_StoreLogoNotifier, String?>(_StoreLogoNotifier.new);

Future<void> saveStoreSettings(BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final name = ref.read(storeNameProvider);
  final phone = ref.read(storePhoneProvider);
  final address = ref.read(storeAddressProvider);
  final vatEnabled = ref.read(vatEnabledProvider);

  await prefs.setString('store_name', name);
  if (phone != null && phone.isNotEmpty) {
    await prefs.setString('store_phone', phone);
  } else {
    await prefs.remove('store_phone');
  }
  if (address != null && address.isNotEmpty) {
    await prefs.setString('store_address', address);
  } else {
    await prefs.remove('store_address');
  }
  await prefs.setBool('vat_enabled', vatEnabled);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.SUCCESS_GREEN,
        content: Text('تم حفظ إعدادات المتجر بنجاح'),
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

    Future<void> _loadSettings() async {
      final prefs = await SharedPreferences.getInstance();
      ref.read(storeNameProvider.notifier).set(
          prefs.getString('store_name') ?? AppStrings.STORE_NAME);
      ref.read(storePhoneProvider.notifier).set(prefs.getString('store_phone'));
      ref.read(storeAddressProvider.notifier).set(prefs.getString('store_address'));

      // الشعار يُحفظ في قاعدة بيانات المحل (يظهر أعلى التطبيق وفي الطباعة).
      String? logoPath;
      try {
        logoPath = (await ShopProfileRepository().getProfile()).logoPath;
      } catch (_) {}
      ref.read(storeLogoPathProvider.notifier).set(logoPath);
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: SingleChildScrollView(
          child: MaxWidthContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إعدادات التطبيق',
                  style: TextStyle(
                    fontSize: AppTypography.HEADING_2,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'إدارة إعدادات المتجر، المستخدمين، والنسخ الاحتياطي',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
                const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.storefront,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                  title: const Text(
                    'معلومات المتجر',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('اسم المتجر، الهاتف، العنوان، الشعار'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                      child: StoreInfoForm(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.people_outline,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                  title: const Text(
                    'المستخدمين والصلاحيات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('إدارة الحسابات والأدوار (مالك / كاشير)'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                      child: UsersManagementContent(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.backup,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                  title: const Text(
                    'النسخ الاحتياطي والاستعادة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('حفظ واسترجاع بيانات المتجر بالكامل'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                      child: _BackupRestoreSection(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.SUCCESS_GREEN,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => saveStoreSettings(context, ref),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(
                    'حفظ جميع الإعدادات',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ),
              ],
            ),
          ), // MaxWidthContainer
        ),
      ),
    );
  }
}

class StoreInfoForm extends ConsumerWidget {
  const StoreInfoForm({super.key});

  /// اختيار شعار صورة للمحل من الجهاز ونسخه لمدى تطبيقه الداعم
  /// (حتى لا يعتمد عرض الشعار على مسار مؤقت)، ثم حفظ المسار في قاعدة بيانات المحل.
  Future<void> _pickLogo(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withReadStream: false);
    if (result == null || result.files.isEmpty) return;
    final srcPath = result.files.single.path;
    if (srcPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الوصول إلى الصورة. جرّب اختيار ملف من الحاسوب.')),
        );
      }
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final fileName = p.basename(srcPath);
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
          : 'png';
      final dest = p.join(dir.path, 'shop_logo.$ext');
      await File(srcPath).copy(dest);

      await ShopProfileRepository().saveLogoPath(dest);
      ref.read(storeLogoPathProvider.notifier).set(dest);
      ref.invalidate(shopProfileProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم حفظ الشعار وسيظهر أعلى التطبيق وفي الفواتير والطباعة'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل حفظ الشعار: $e'),
          ),
        );
      }
    }
  }

  Future<void> _removeLogo(BuildContext context, WidgetRef ref) async {
    try {
      await ShopProfileRepository().saveLogoPath(null);
      ref.read(storeLogoPathProvider.notifier).set(null);
      ref.invalidate(shopProfileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إزالة شعار المحل')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل إزالة الشعار: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(storeNameProvider);
    final phone = ref.watch(storePhoneProvider) ?? '';
    final address = ref.watch(storeAddressProvider) ?? '';
    final logo = ref.watch(storeLogoPathProvider);
    final hasLogo =
        logo != null && logo.isNotEmpty && File(logo).existsSync();
    final vatEnabled = ref.watch(vatEnabledProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // شعار المحل
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.NEUTRAL_BG,
                borderRadius: BorderRadius.circular(
                  AppLayout.BORDER_RADIUS,
                ),
                border: Border.all(
                  color: hasLogo
                      ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.4)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: hasLogo
                  ? ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      child: Image.file(
                        File(logo),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: AppColors.TEXT_SECONDARY,
                          ),
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 32,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'شعار المحل',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'يظهر أعلى التطبيق بجوار اسم المحل وفي ترويسة كل الفواتير والطباعة والتقارير.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.TEXT_SECONDARY,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickLogo(context, ref),
                        icon: const Icon(Icons.image, size: 18),
                        label: const Text('اختيار شعار'),
                      ),
                      if (hasLogo) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.DANGER_RED,
                            side: BorderSide(
                              color: AppColors.DANGER_RED.withValues(alpha: 0.5),
                            ),
                          ),
                          onPressed: () => _removeLogo(context, ref),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('إزالة'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 20),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: name,
          decoration: const InputDecoration(
            labelText: 'اسم المتجر *',
            prefixIcon: Icon(Icons.storefront),
          ),
          onChanged: (val) => ref.read(storeNameProvider.notifier).set(val),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            prefixIcon: Icon(Icons.phone),
          ),
          onChanged: (val) =>
              ref.read(storePhoneProvider.notifier).set(
                  val.trim().isEmpty ? null : val),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: address,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'العنوان',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          onChanged: (val) =>
              ref.read(storeAddressProvider.notifier).set(
                  val.trim().isEmpty ? null : val),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('تفعيل القيمة المضافة (VAT)'),
          subtitle: const Text('عند التفعيل، سيتم حساب الضريبة على الفواتير والمشتريات'),
          value: vatEnabled,
           onChanged: (value) => ref.read(vatEnabledProvider.notifier).setEnabled(value),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => saveStoreSettings(context, ref),
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ إعدادات المتجر'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: name));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ اسم المتجر')),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('نسخ اسم المتجر'),
            style: OutlinedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

/// قسم النسخ الاحتياطي والاستعادة (Phase 3.15).
class _BackupRestoreSection extends ConsumerStatefulWidget {
  const _BackupRestoreSection();

  @override
  ConsumerState<_BackupRestoreSection> createState() =>
      _BackupRestoreSectionState();
}

class _BackupRestoreSectionState extends ConsumerState<_BackupRestoreSection> {
  bool _busy = false;

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.createBackupFile();
      if (mounted) {
        if (path == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء النسخ الاحتياطي')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.SUCCESS_GREEN,
              content: Text('تم حفظ النسخة الاحتياطية في:\n$path'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل النسخ الاحتياطي: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: const Text(
          'سيتم استبدال جميع البيانات الحالية بمحتوى النسخة الاحتياطية. '
          'هذا الإجراء لا يمكن التراجع عنه. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final success = await BackupService.restoreFromBackupFile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                success ? AppColors.SUCCESS_GREEN : AppColors.NEUTRAL_BG,
            content: Text(success
                ? 'تم استعادة النسخة الاحتياطية بنجاح. أعد تشغيل التطبيق لتحديث الشاشات.'
                : 'تم إلغاء الاستعادة'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل الاستعادة: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'احفظ نسخة كاملة من المنتجات والمبيعات والعملاء وكل بيانات المتجر '
          'في ملف JSON آمن، واستعدها على أي جهاز.',
          style: TextStyle(color: AppColors.TEXT_SECONDARY, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _createBackup,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_outlined),
                label: const Text('إنشاء نسخة احتياطية'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restoreBackup,
                icon: const Icon(Icons.restore),
                label: const Text('استعادة نسخة'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
