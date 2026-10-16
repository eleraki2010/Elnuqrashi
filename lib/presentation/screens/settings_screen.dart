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
import '../../core/services/printer_settings_service.dart';
import 'package:printing/printing.dart';
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
                    Icons.print_outlined,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                  title: const Text(
                    'إعدادات الطابعات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('تحديد الطابعة، مقاس الورق، والطباعة المباشرة للتابلت'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                      child: _PrinterSettingsSection(),
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

/// قسم إعدادات الطابعات والطباعة الحرارية لأجهزة التابلت (Tablet POS Printing).
class _PrinterSettingsSection extends StatefulWidget {
  const _PrinterSettingsSection();

  @override
  State<_PrinterSettingsSection> createState() => _PrinterSettingsSectionState();
}

class _PrinterSettingsSectionState extends State<_PrinterSettingsSection> {
  Printer? _savedPrinter;
  String _paperSize = '80mm';
  bool _directPrint = false;
  bool _isLoading = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final printer = await PrinterSettingsService.getSavedPrinter();
      final size = await PrinterSettingsService.getPaperSize();
      final direct = await PrinterSettingsService.isDirectPrint();
      if (mounted) {
        setState(() {
          _savedPrinter = printer;
          _paperSize = size;
          _directPrint = direct;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanAndSelectPrinter() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري فحص الطابعات المتوفرة (بلوتوث / شبكة / USB)...'),
              ],
            ),
          ),
        ),
      ),
    );

    List<Printer> printers = [];
    try {
      printers = await PrinterSettingsService.discoverPrinters();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.print, color: AppColors.PRIMARY_BLUE),
              SizedBox(width: 8),
              Text('اختيار طابعة'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: printers.isEmpty
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_disabled,
                          size: 48, color: AppColors.TEXT_SECONDARY),
                      SizedBox(height: 12),
                      Text(
                        'لم يتم العثور على طابعات متصلة مباشرة.\nتأكد من اقتران طابعة البلوتوث مع التابلت أو اتصال طابعة الشبكة بنفس الراوتر، أو أضفها يدوياً برقم IP.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.TEXT_SECONDARY),
                      ),
                    ],
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: printers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final p = printers[index];
                      final isSelected = _savedPrinter?.url == p.url;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.print_outlined,
                          color: isSelected
                              ? AppColors.SUCCESS_GREEN
                              : AppColors.PRIMARY_BLUE,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          p.model ?? p.url,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogCtx);
                          await PrinterSettingsService.savePrinter(p);
                          if (!mounted) return;
                          setState(() => _savedPrinter = p);
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.SUCCESS_GREEN,
                              content: Text(
                                  'تم تعيين الطابعة الافتراضية: ${p.name}'),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addManualPrinterDialog() async {
    final nameCtrl = TextEditingController(text: 'طابعة الفواتير');
    final urlCtrl = TextEditingController(text: 'tcp://192.168.1.');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة طابعة شبكة يدوياً (IP)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'أدخل اسم الطابعة وعنوان IP الخاص بها على الشبكة المحلية (مثل 192.168.1.100 أو tcp://192.168.1.100:9100):',
                style: TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الطابعة *',
                  hintText: 'مثال: طابعة كاشير 1',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'عنوان IP أو مسار الطابعة *',
                  hintText: 'مثال: tcp://192.168.1.100:9100',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.DANGER_RED,
                    content: Text('يرجى ملء جميع الحقول المطلوبة'),
                  ),
                );
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(ctx);
              await PrinterSettingsService.saveCustomPrinter(
                  name: name, url: url);
              if (!mounted) return;
              setState(() {
                _savedPrinter = Printer(url: url, name: name);
              });
              nav.pop();
              messenger.showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.SUCCESS_GREEN,
                  content: Text('تم حفظ وتعيين الطابعة: $name'),
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearPrinter() async {
    await PrinterSettingsService.clearSavedPrinter();
    if (mounted) {
      setState(() => _savedPrinter = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت العودة لطابعة النظام الافتراضية'),
        ),
      );
    }
  }

  Future<void> _runTestPrint() async {
    setState(() => _isTesting = true);
    try {
      final success = await PrinterSettingsService.printTestReceipt(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                success ? AppColors.SUCCESS_GREEN : AppColors.NEUTRAL_BG,
            content: Text(success
                ? 'تم إرسال صفحة الاختبار للطابعة بنجاح'
                : 'تم إلغاء أمر الطباعة التجريبية'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشلت الطباعة التجريبية: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. حالة الطابعة الحالية
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _savedPrinter != null
                ? AppColors.SUCCESS_GREEN.withValues(alpha: 0.06)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            border: Border.all(
              color: _savedPrinter != null
                  ? AppColors.SUCCESS_GREEN.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _savedPrinter != null
                      ? AppColors.SUCCESS_GREEN.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _savedPrinter != null
                      ? Icons.print
                      : Icons.print_outlined,
                  color: _savedPrinter != null
                      ? AppColors.SUCCESS_GREEN
                      : AppColors.TEXT_SECONDARY,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _savedPrinter != null
                              ? _savedPrinter!.name
                              : 'طابعة النظام الافتراضية',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _savedPrinter != null
                                ? AppColors.SUCCESS_GREEN
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _savedPrinter != null ? 'معتمدة' : 'افتراضية',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _savedPrinter != null
                          ? (_savedPrinter!.model ?? _savedPrinter!.url)
                          : 'يتم إرسال أي مستند أو فاتورة إلى طابعة النظام أو نافذة الاختيار.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // أزرار التحكم في الطابعة
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _scanAndSelectPrinter,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('بحث عن طابعات متصلة'),
            ),
            OutlinedButton.icon(
              onPressed: _addManualPrinterDialog,
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('إضافة طابعة شبكة (IP)'),
            ),
            if (_savedPrinter != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.DANGER_RED,
                  side: BorderSide(
                    color: AppColors.DANGER_RED.withValues(alpha: 0.5),
                  ),
                ),
                onPressed: _clearPrinter,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('إلغاء التعيين'),
              ),
          ],
        ),

        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // 2. مقاس الورق الافتراضي
        const Text(
          'مقاس ورق الطباعة الافتراضي',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'اختر المقاس المناسب للمطبعة المستخدمة مع التابلت لضبط الفواتير والإيصالات بدقة.',
          style: TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: '80mm',
              label: Text('80 مم (حراري قياسي)'),
              icon: Icon(Icons.receipt_long),
            ),
            ButtonSegment(
              value: '58mm',
              label: Text('58 مم (حراري صغير)'),
              icon: Icon(Icons.receipt),
            ),
            ButtonSegment(
              value: 'a4',
              label: Text('A4 (عادي / ليزر)'),
              icon: Icon(Icons.description),
            ),
          ],
          selected: {_paperSize},
          onSelectionChanged: (newSelection) async {
            final val = newSelection.first;
            setState(() => _paperSize = val);
            await PrinterSettingsService.setPaperSize(val);
          },
        ),

        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 8),

        // 3. خيار الطباعة المباشرة السريعة للتابلت
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'الطباعة المباشرة السريعة (بدون نافذة معاينة)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          subtitle: const Text(
            'إرسال الفاتورة فوراً وبأقصى سرعة للطابعة عند الضغط على "طباعة" دون فتح شاشات إضافية. مثالي لأجهزة التابلت لتسريع إنهاء عمليات البيع.',
            style: TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
          ),
          value: _directPrint,
          activeTrackColor: AppColors.PRIMARY_BLUE,
          onChanged: (val) async {
            setState(() => _directPrint = val);
            await PrinterSettingsService.setDirectPrint(val);
          },
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // 4. زر الطباعة التجريبية
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            border: Border.all(
              color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.PRIMARY_BLUE,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اختبار وتأكيد عمل الطابعة',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'طباعة صفحة تجريبية تحتوي على اسم المحل والشعار ورقم الفاتورة والباركود للتأكد من جاهزية الطباعة.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onPressed: _isTesting ? null : _runTestPrint,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print, size: 18),
                label: const Text(
                  'طباعة تجريبية',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
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

  // حالة النسخ الاحتياطي المحلي على التابلت
  String _backupDirPath = '';
  bool _isCustomBackupDir = false;
  List<File> _localBackups = [];
  bool _isLoadingLocalBackups = false;

  @override
  void initState() {
    super.initState();
    _initGoogleDriveState();
    _loadLocalBackupInfo();
  }

  Future<void> _loadLocalBackupInfo() async {
    setState(() => _isLoadingLocalBackups = true);
    try {
      final effectivePath =
          await BackupService.getEffectiveBackupDirectoryPath();
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(BackupService.keyCustomBackupDir);
      final files = await BackupService.listLocalBackupFiles();
      if (mounted) {
        setState(() {
          _backupDirPath = effectivePath;
          _isCustomBackupDir = custom != null && custom.trim().isNotEmpty;
          _localBackups = files;
        });
      }
    } catch (e) {
      debugPrint('Error loading local backup info: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocalBackups = false);
    }
  }

  Future<void> _changeBackupDirectory() async {
    final pickedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد حفظ واسترجاع النسخ الاحتياطية للتابلت',
      lockParentWindow: true,
    );
    if (pickedPath != null && pickedPath.trim().isNotEmpty) {
      await BackupService.setCustomBackupDirectory(pickedPath);
      await _loadLocalBackupInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم تعيين مجلد النسخ الاحتياطي:\n$pickedPath'),
          ),
        );
      }
    }
  }

  Future<void> _resetBackupDirectory() async {
    await BackupService.resetBackupDirectory();
    await _loadLocalBackupInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.SUCCESS_GREEN,
          content: Text('تمت استعادة المجلد الافتراضي العام للتابلت بنجاح'),
        ),
      );
    }
  }

  Future<void> _restoreSpecificLocalBackup(File file) async {
    final fileName = p.basename(file.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.DANGER_RED),
            SizedBox(width: 8),
            Text('استعادة نسخة احتياطية محلية'),
          ],
        ),
        content: Text(
          'سيتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية ($fileName).\n'
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

    setState(() => _localBusy = true);
    try {
      final success = await BackupService.restoreFromSpecificFile(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                success ? AppColors.SUCCESS_GREEN : AppColors.DANGER_RED,
            content: Text(success
                ? 'تم استعادة النسخة الاحتياطية ($fileName) بنجاح! أعد تشغيل التطبيق لتحديث الشاشات.'
                : 'فشلت الاستعادة'),
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

  Future<void> _createLocalBackup({bool pickCustomLocation = false}) async {
    setState(() => _localBusy = true);
    try {
      final path = await BackupService.createBackupFile(
        pickCustomLocation: pickCustomLocation,
      );
      if (mounted) {
        if (path == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء النسخ الاحتياطي')),
          );
        } else {
          await _loadLocalBackupInfo();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.SUCCESS_GREEN,
              content: Text(
                  'تم حفظ النسخة الاحتياطية بنجاح في:\n$path\n(مجلد آمن لا يُحذف عند إزالة التطبيق)'),
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
      final success = await BackupService.restoreFromBackupFile(
        initialDirectory: _backupDirPath.isNotEmpty ? _backupDirPath : null,
      );
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
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.save_alt_rounded,
                        color: AppColors.SUCCESS_GREEN,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النسخ الاحتياطي المحلي على التابلت والكمبيوتر',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'يُحفظ في مجلد عام ظاهر على التابلت ولا يُحذف إطلاقاً عند إزالة التطبيق بالخطأ',
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

                // عرض مجلد الحفظ المعتمد وأزرار التحكم
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'مجلد الحفظ والاسترجاع للتابلت:',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isCustomBackupDir
                                  ? Colors.blue.shade100
                                  : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isCustomBackupDir
                                  ? 'مجلد مخصص'
                                  : 'مجلد عام محمي ضد الحذف',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: _isCustomBackupDir
                                    ? Colors.blue.shade900
                                    : Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _backupDirPath.isEmpty
                            ? 'جاري تحديد المجلد...'
                            : _backupDirPath,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppColors.TEXT_PRIMARY,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            ),
                            onPressed:
                                _localBusy ? null : _changeBackupDirectory,
                            icon: const Icon(Icons.drive_file_move_outlined,
                                size: 16),
                            label: const Text('تغيير المجلد'),
                          ),
                          if (_isCustomBackupDir)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                              onPressed:
                                  _localBusy ? null : _resetBackupDirectory,
                              icon: const Icon(Icons.restore, size: 16),
                              label:
                                  const Text('استعادة المجلد الافتراضي العام'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // أزرار إنشاء النسخ الاحتياطية
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.SUCCESS_GREEN,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _localBusy
                            ? null
                            : () =>
                                _createLocalBackup(pickCustomLocation: false),
                        icon: _localBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.file_download_outlined,
                                size: 20),
                        label: const Text(
                          'إنشاء نسخة في المجلد',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _localBusy
                            ? null
                            : () =>
                                _createLocalBackup(pickCustomLocation: true),
                        icon: const Icon(Icons.save_as_outlined, size: 18),
                        label: const Text('حفظ في فلاشة USB'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // قائمة النسخ المتوفرة في المجلد الحالي
                Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.history,
                                size: 18, color: AppColors.PRIMARY_BLUE),
                            const SizedBox(width: 8),
                            Text(
                              'النسخ المتوفرة في المجلد (${_localBackups.length})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: _isLoadingLocalBackups
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh, size: 18),
                              tooltip: 'تحديث قائمة النسخ',
                              onPressed: _isLoadingLocalBackups
                                  ? null
                                  : _loadLocalBackupInfo,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (_localBackups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'لا توجد نسخ احتياطية في هذا المجلد بعد. انقر على "إنشاء نسخة في المجلد" لحفظ أول نسخة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _localBackups.length > 5
                              ? 5
                              : _localBackups.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final file = _localBackups[index];
                            final fileName = p.basename(file.path);
                            DateTime? modTime;
                            int? fileLen;
                            try {
                              modTime = file.lastModifiedSync();
                              fileLen = file.lengthSync();
                            } catch (_) {}

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 2),
                              leading: const Icon(
                                Icons.insert_drive_file_outlined,
                                color: AppColors.SUCCESS_GREEN,
                                size: 20,
                              ),
                              title: Text(
                                fileName,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${modTime != null ? _formatDateTime(modTime) : ""}  •  ${fileLen != null ? _formatSize(fileLen.toString()) : ""}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.DANGER_RED,
                                  side: const BorderSide(
                                      color: AppColors.DANGER_RED),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                ),
                                onPressed: _localBusy
                                    ? null
                                    : () => _restoreSpecificLocalBackup(file),
                                child: const Text('استرجاع'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // زر استعادة من ملف خارجي (فلاشة أو مكان آخر)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _localBusy ? null : _restoreLocalBackup,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('اختيار ملف من مكان آخر أو فلاشة USB'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
