import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alnokrashy_pos/core/constants/app_constants.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/google_drive_backup_service.dart';
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
  bool _localBusy = false;
  bool _cloudBusy = false;
  bool _isLoadingBackups = false;
  GoogleSignInAccount? _googleUser;
  bool _autoBackupEnabled = true;
  String? _lastCloudBackupTime;
  List<drive.File> _cloudBackups = [];

  @override
  void initState() {
    super.initState();
    _initGoogleDriveState();
  }

  Future<void> _initGoogleDriveState() async {
    final prefs = await SharedPreferences.getInstance();
    _autoBackupEnabled =
        prefs.getBool(GoogleDriveBackupService.keyAutoBackupEnabled) ?? true;
    _lastCloudBackupTime =
        prefs.getString(GoogleDriveBackupService.keyLastBackupTime);

    final user = await GoogleDriveBackupService.signInSilently();
    if (mounted) {
      setState(() {
        _googleUser = user;
      });
      if (user != null) {
        _loadCloudBackups();
      }
    }
  }

  Future<void> _loadCloudBackups() async {
    setState(() => _isLoadingBackups = true);
    try {
      final list = await GoogleDriveBackupService.listBackups();
      if (mounted) {
        setState(() {
          _cloudBackups = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading cloud backups: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBackups = false);
    }
  }

  Future<void> _signInGoogle() async {
    setState(() => _cloudBusy = true);
    try {
      final user = await GoogleDriveBackupService.signIn();
      if (mounted) {
        setState(() {
          _googleUser = user;
        });
        if (user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.SUCCESS_GREEN,
              content: Text('تم ربط حساب Google بنجاح: ${user.email}'),
            ),
          );
          _loadCloudBackups();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل تسجيل الدخول بحساب Google: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _signOutGoogle() async {
    await GoogleDriveBackupService.signOut();
    if (mounted) {
      setState(() {
        _googleUser = null;
        _cloudBackups = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الخروج من Google Drive')),
      );
    }
  }

  Future<void> _toggleAutoBackup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GoogleDriveBackupService.keyAutoBackupEnabled, value);
    if (mounted) {
      setState(() {
        _autoBackupEnabled = value;
      });
    }
  }

  Future<void> _uploadCloudBackup() async {
    setState(() => _cloudBusy = true);
    try {
      final file = await GoogleDriveBackupService.uploadBackup();
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _lastCloudBackupTime = now.toIso8601String();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text(
                'تم رفع النسخة الاحتياطية بنجاح إلى Google Drive (${file.name ?? ""})'),
            duration: const Duration(seconds: 4),
          ),
        );
        _loadCloudBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل الرفع إلى Google Drive: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _restoreCloudBackup(drive.File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.DANGER_RED),
            SizedBox(width: 8),
            Text('استعادة نسخة سحابية'),
          ],
        ),
        content: Text(
          'سيتم استبدال جميع البيانات الحالية بالنسخة السحابية (${file.name ?? ""}).\n'
          'هذا الإجراء سيقوم بحذف أية بيانات غير محفوظة واسترجاع حالة المحل من تلك النسخة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cloudBusy = true);
    try {
      final success = await GoogleDriveBackupService.restoreBackup(file.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                success ? AppColors.SUCCESS_GREEN : AppColors.DANGER_RED,
            content: Text(success
                ? 'تم استعادة النسخة السحابية بنجاح! أعد تشغيل التطبيق لتحديث الشاشات.'
                : 'فشلت الاستعادة'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل استعادة النسخة السحابية: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _createLocalBackup() async {
    setState(() => _localBusy = true);
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
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _restoreLocalBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية محلية'),
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
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _localBusy = true);
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
      if (mounted) setState(() => _localBusy = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy-MM-dd • hh:mm a', 'ar').format(dt.toLocal());
  }

  String _formatSize(String? sizeStr) {
    if (sizeStr == null) return '';
    final bytes = int.tryParse(sizeStr) ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==================== 1. Google Drive Card ====================
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            side: BorderSide(color: Colors.blue.shade100),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.cloud_upload_outlined,
                        color: AppColors.PRIMARY_BLUE,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النسخ الاحتياطي السحابي (Google Drive)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'حفظ نسخة مشفرة تلقائياً كلما اتصل التابلت بالإنترنت',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Account Status
                if (_googleUser != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.PRIMARY_BLUE,
                          child: Text(
                            (_googleUser!.displayName?.isNotEmpty ?? false)
                                ? _googleUser!.displayName![0]
                                : 'G',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _googleUser!.displayName ?? 'حساب Google',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _googleUser!.email,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.TEXT_SECONDARY,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _cloudBusy ? null : _signOutGoogle,
                          child: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                                color: AppColors.DANGER_RED, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Auto backup toggle
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'النسخ التلقائي عند الاتصال بالإنترنت',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'يتم أخذ نسخة احتياطية في الخلفية كل 12 ساعة فور توفر شبكة',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    value: _autoBackupEnabled,
                    activeTrackColor: AppColors.PRIMARY_BLUE,
                    onChanged: _toggleAutoBackup,
                  ),

                  // Last cloud backup info
                  if (_lastCloudBackupTime != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.history,
                              size: 16, color: AppColors.TEXT_SECONDARY),
                          const SizedBox(width: 6),
                          Text(
                            'آخر نسخة سحابية: ${_formatDateTime(DateTime.parse(_lastCloudBackupTime!))}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.TEXT_SECONDARY,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Upload button
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: _cloudBusy ? null : _uploadCloudBackup,
                      icon: _cloudBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload, size: 20),
                      label: const Text(
                        'رفع نسخة احتياطية سحابية الآن',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.PRIMARY_BLUE,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                  // Cloud Backups List
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          const Text(
                            'النسخ السحابية السابقة',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.PRIMARY_BLUE,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_cloudBackups.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.PRIMARY_BLUE
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_cloudBackups.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.PRIMARY_BLUE,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: _isLoadingBackups
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        tooltip: 'تحديث القائمة',
                        onPressed:
                            _isLoadingBackups ? null : _loadCloudBackups,
                      ),
                      children: [
                        if (_cloudBackups.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'لا توجد نسخ سحابية محفوظة على Google Drive حتى الآن.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.TEXT_SECONDARY),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _cloudBackups.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _cloudBackups[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: AppColors.PRIMARY_BLUE,
                                  size: 20,
                                ),
                                title: Text(
                                  item.name ?? 'نسخة احتياطية',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.createdTime != null ? _formatDateTime(item.createdTime!) : ""}  •  ${_formatSize(item.size)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: OutlinedButton(
                                  onPressed: _cloudBusy
                                      ? null
                                      : () => _restoreCloudBackup(item),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.DANGER_RED,
                                    side: const BorderSide(
                                        color: AppColors.DANGER_RED),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                  ),
                                  child: const Text('استرجاع'),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Not logged in banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'اربط حساب Google Drive الخاص بك لحفظ نسخة سحابية مشفرة تلقائياً كلما اتصل التابلت بالإنترنت، مع إمكانية استرجاعها بضغطة زر على أي جهاز.',
                            style: TextStyle(fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _cloudBusy ? null : _signInGoogle,
                      icon: _cloudBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.account_circle, size: 20),
                      label: const Text(
                        'تسجيل الدخول وربط Google Drive',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.PRIMARY_BLUE,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ==================== 2. Local Backup Card ====================
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.save_alt_rounded,
                        color: AppColors.TEXT_PRIMARY,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النسخ الاحتياطي المحلي (ملف على الجهاز / فلاشة USB)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'تصدير أو استيراد ملف JSON يدوياً دون الحاجة للإنترنت',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _localBusy ? null : _createLocalBackup,
                        icon: _localBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download_outlined),
                        label: const Text('إنشاء نسخة محلية'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _localBusy ? null : _restoreLocalBackup,
                        icon: const Icon(Icons.restore),
                        label: const Text('استعادة نسخة من ملف'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
