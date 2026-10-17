import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/services/backup_service.dart';
import '../../providers/data_refresh_service.dart';

/// مربع حوار تفاعلي لاختيار طريقة استرجاع النسخة الاحتياطية:
/// (استبدال شامل - دمج ذكي مع الحالي - تخصيص محتويات معينة)
Future<RestoreOptions?> showBackupRestoreDialog(
  BuildContext context, {
  required BackupInspection inspection,
  required String sourceTitle,
}) {
  return showDialog<RestoreOptions>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => BackupRestoreDialog(
      inspection: inspection,
      sourceTitle: sourceTitle,
    ),
  );
}

class BackupRestoreDialog extends StatefulWidget {
  final BackupInspection inspection;
  final String sourceTitle;

  const BackupRestoreDialog({
    super.key,
    required this.inspection,
    required this.sourceTitle,
  });

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  RestoreMode _selectedMode = RestoreMode.mergeAll;
  bool _updateStockInMerge = false;

  late RestoreCustomSelection _customSelection;

  @override
  void initState() {
    super.initState();
    _customSelection = const RestoreCustomSelection(
      includeCategoriesAndProducts: true,
      includeCustomers: true,
      includeSuppliers: true,
      includeSales: true,
      includePurchases: true,
      includePayments: true,
      includeExpenses: true,
      includeStockMovements: true,
      includeAuditLogs: true,
      includeShopSettings: true,
      includeUsers: false,
      mergeSelected: true,
      updateStockQuantities: false,
    );
  }

  void _selectAllCustom(bool select) {
    setState(() {
      _customSelection = _customSelection.copyWith(
        includeCategoriesAndProducts: select,
        includeCustomers: select,
        includeSuppliers: select,
        includeSales: select,
        includePurchases: select,
        includePayments: select,
        includeExpenses: select,
        includeStockMovements: select,
        includeAuditLogs: select,
        includeShopSettings: select,
        includeUsers: select,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final insp = widget.inspection;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. الترويسة الرئيسية
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.settings_backup_restore_rounded,
                      color: AppColors.PRIMARY_BLUE,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'خيارات استرجاع النسخة الاحتياطية',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'حدد طريقة الاسترجاع ومحتوياتها المطلوبة بأمان تام',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.TEXT_SECONDARY,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // 2. المحتوى القابل للتمرير
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // بطاقة ملخص النسخة المختارة
                      _buildInspectionSummaryCard(insp, dateFormat),
                      const SizedBox(height: 18),

                      const Text(
                        'اختر طريقة الاسترجاع:',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.TEXT_PRIMARY,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // الخيار 1: الدمج الذكي مع الحالي (مستحسن)
                      _buildModeCard(
                        mode: RestoreMode.mergeAll,
                        title: 'الدمج مع البيانات الحالية (مستحسن)',
                        badgeText: 'حماية المبيعات الحالية',
                        badgeColor: AppColors.SUCCESS_GREEN,
                        icon: Icons.merge_type_rounded,
                        description:
                            'يحافظ على جميع بياناتك وفواتيرك الحالية دون مسح، ويضيف البيانات الجديدة ويحدث تفاصيل الأصناف.',
                        extraWidget: _selectedMode == RestoreMode.mergeAll
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: AppColors.SUCCESS_GREEN,
                                  title: const Text(
                                    'تحديث كميات المخزون من النسخة أيضاً',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'اتركه غير محدد للحفاظ على الجرد الفعلي للمحل حالياً',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                  ),
                                  value: _updateStockInMerge,
                                  onChanged: (val) {
                                    setState(() {
                                      _updateStockInMerge = val ?? false;
                                    });
                                  },
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),

                      // الخيار 2: تخصيص محتويات النسخة
                      _buildModeCard(
                        mode: RestoreMode.custom,
                        title: 'تخصيص محتويات النسخة',
                        badgeText: 'تحكم كامل',
                        badgeColor: Colors.orange.shade700,
                        icon: Icons.checklist_rounded,
                        description:
                            'اختيار أقسام محددة لاسترجاعها (مثل: الأصناف والعملاء فقط، أو الفواتير والمصروفات).',
                        extraWidget: _selectedMode == RestoreMode.custom
                            ? _buildCustomChecklistSection(insp)
                            : null,
                      ),
                      const SizedBox(height: 10),

                      // الخيار 3: استبدال شامل لكافة البيانات
                      _buildModeCard(
                        mode: RestoreMode.replaceAll,
                        title: 'استبدال شامل لكافة البيانات الحالية',
                        badgeText: 'مسح واستبدال كامل',
                        badgeColor: AppColors.DANGER_RED,
                        icon: Icons.delete_sweep_rounded,
                        description:
                            'مسح كافة البيانات الحالية وتنزيل النسخة الاحتياطية كبديل كامل للنظام.',
                        extraWidget: _selectedMode == RestoreMode.replaceAll
                            ? Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.DANGER_RED
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.DANGER_RED
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: AppColors.DANGER_RED,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'سيتم أخذ نسخة أمان احترازية صامتة تلقائياً للبيانات الحالية قبل الاستبدال.',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.DANGER_RED,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),
              const SizedBox(height: 14),

              // 3. أزرار الإجراءات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedMode == RestoreMode.replaceAll
                          ? AppColors.DANGER_RED
                          : AppColors.PRIMARY_BLUE,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _onConfirm,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      _selectedMode == RestoreMode.replaceAll
                          ? 'تأكيد واستبدال شامل'
                          : _selectedMode == RestoreMode.mergeAll
                              ? 'بدء الدمج مع الحالي'
                              : 'استرجاع الأقسام المختارة',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectionSummaryCard(
    BackupInspection insp,
    DateFormat dateFormat,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_zip_outlined,
                size: 20,
                color: AppColors.PRIMARY_BLUE,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.sourceTitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.TEXT_PRIMARY,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (insp.exportedAt != null)
                Text(
                  dateFormat.format(insp.exportedAt!),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
            ],
          ),
          if (insp.storeName != null && insp.storeName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'المتجر: ${insp.storeName}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.TEXT_SECONDARY,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildCountBadge('📦 الأصناف', insp.productsCount, AppColors.PRIMARY_BLUE),
              _buildCountBadge('🏷️ التصنيفات', insp.categoriesCount, Colors.indigo),
              _buildCountBadge('👥 العملاء', insp.customersCount, AppColors.SUCCESS_GREEN),
              _buildCountBadge('🚚 الموردون', insp.suppliersCount, Colors.teal),
              _buildCountBadge('🧾 فواتير البيع', insp.salesCount, Colors.purple),
              if (insp.saleReturnsCount > 0)
                _buildCountBadge('🔄 مرتجع بيع', insp.saleReturnsCount, Colors.orange),
              _buildCountBadge('🛒 فواتير الشراء', insp.purchasesCount, Colors.blueGrey),
              _buildCountBadge('💵 السندات', insp.paymentsCount, Colors.green.shade800),
              _buildCountBadge('📉 المصروفات', insp.expensesCount, Colors.amber.shade900),
              if (insp.productImagesCount > 0)
                _buildCountBadge('🖼️ صور منتجات', insp.productImagesCount, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required RestoreMode mode,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required String description,
    Widget? extraWidget,
  }) {
    final isSelected = _selectedMode == mode;

    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? badgeColor.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? badgeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? badgeColor : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Icon(icon, color: badgeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppColors.TEXT_PRIMARY
                          : AppColors.TEXT_PRIMARY,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 32, top: 4),
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                  height: 1.35,
                ),
              ),
            ),
            ?extraWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildCustomChecklistSection(BackupInspection insp) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'اختر الأقسام المطلوبة:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _selectAllCustom(true),
                    child: const Text('تحديد الكل', style: TextStyle(fontSize: 11.5)),
                  ),
                  TextButton(
                    onPressed: () => _selectAllCustom(false),
                    child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 1),

          _buildCheckItem(
            '📦 الأصناف والتصنيفات',
            '${insp.productsCount} صنف • ${insp.categoriesCount} تصنيف',
            _customSelection.includeCategoriesAndProducts,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeCategoriesAndProducts: v)),
          ),
          _buildCheckItem(
            '👥 سجل العملاء',
            '${insp.customersCount} عميل',
            _customSelection.includeCustomers,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeCustomers: v)),
          ),
          _buildCheckItem(
            '🚚 سجل الموردين',
            '${insp.suppliersCount} مورد',
            _customSelection.includeSuppliers,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeSuppliers: v)),
          ),
          _buildCheckItem(
            '🧾 فواتير وحركات المبيعات',
            '${insp.salesCount} فاتورة بيع • ${insp.saleReturnsCount} مرتجع',
            _customSelection.includeSales,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeSales: v)),
          ),
          _buildCheckItem(
            '🛒 فواتير وحركات المشتريات',
            '${insp.purchasesCount} فاتورة شراء • ${insp.purchaseReturnsCount} مرتجع',
            _customSelection.includePurchases,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includePurchases: v)),
          ),
          _buildCheckItem(
            '💵 سندات القبض والدفع المالية',
            '${insp.paymentsCount} سند مالي',
            _customSelection.includePayments,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includePayments: v)),
          ),
          _buildCheckItem(
            '📉 المصروفات التشغيلية',
            '${insp.expensesCount} مصروف وفئاتها',
            _customSelection.includeExpenses,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeExpenses: v)),
          ),
          _buildCheckItem(
            '🔄 سجل حركات المخزون والعمليات',
            '${insp.stockMovementsCount + insp.auditLogsCount} حركة وسجل رقابة',
            _customSelection.includeStockMovements,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(
                  includeStockMovements: v,
                  includeAuditLogs: v,
                )),
          ),
          _buildCheckItem(
            '⚙️ إعدادات المتجر والشعار',
            insp.hasLogo ? 'مع شعار المتجر' : 'بيانات المتجر والضريبة',
            _customSelection.includeShopSettings,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeShopSettings: v)),
          ),
          _buildCheckItem(
            '👤 حسابات وصلاحيات المستخدمين',
            '${insp.usersCount} مستخدم',
            _customSelection.includeUsers,
            (v) => setState(() => _customSelection =
                _customSelection.copyWith(includeUsers: v)),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // خيار طريقة التطبيق للأقسام المختارة
          const Text(
            'طريقة تطبيق الأقسام المختارة:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.TEXT_PRIMARY,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _customSelection =
                        _customSelection.copyWith(mergeSelected: true));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _customSelection.mergeSelected
                          ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _customSelection.mergeSelected
                            ? AppColors.PRIMARY_BLUE
                            : Colors.grey.shade300,
                        width: _customSelection.mergeSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _customSelection.mergeSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                          color: _customSelection.mergeSelected
                              ? AppColors.PRIMARY_BLUE
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'دمج مع الحالي (مستحسن)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _customSelection =
                        _customSelection.copyWith(mergeSelected: false));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: !_customSelection.mergeSelected
                          ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !_customSelection.mergeSelected
                            ? AppColors.PRIMARY_BLUE
                            : Colors.grey.shade300,
                        width: !_customSelection.mergeSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          !_customSelection.mergeSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                          color: !_customSelection.mergeSelected
                              ? AppColors.PRIMARY_BLUE
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'استبدال الأقسام المختارة فقط',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: Colors.orange.shade800,
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.TEXT_SECONDARY),
      ),
    );
  }

  void _onConfirm() {
    if (_selectedMode == RestoreMode.custom &&
        !_customSelection.hasAnySelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.DANGER_RED,
          content: Text('يرجى تحديد قسم واحد على الأقل للاسترجاع'),
        ),
      );
      return;
    }

    final options = RestoreOptions(
      mode: _selectedMode,
      customSelection: _customSelection,
      updateStockQuantitiesInMerge: _selectedMode == RestoreMode.custom
          ? _customSelection.updateStockQuantities
          : _updateStockInMerge,
    );

    Navigator.pop(context, options);
  }
}

/// مساعد تنفيذ الاسترجاع عبر النافذة التفاعلية
class BackupRestoreWorkflow {
  static Future<bool> startRestore(
    BuildContext context,
    WidgetRef ref, {
    File? file,
    Map<String, dynamic>? snapshot,
    String? sourceTitle,
  }) async {
    Map<String, dynamic>? dataSnapshot = snapshot;
    String title = sourceTitle ?? 'نسخة احتياطية';

    if (file != null) {
      title = p.basename(file.path);
      try {
        dataSnapshot = await BackupService.readSnapshotFromFile(file);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.DANGER_RED,
              content: Text('تعذر قراءة ملف النسخة الاحتياطية: $e'),
            ),
          );
        }
        return false;
      }
    }

    if (dataSnapshot == null) return false;

    // 1. فحص محتويات النسخة
    final inspection = BackupInspection.fromSnapshot(dataSnapshot);

    // 2. عرض نافذة الاختيارات
    if (!context.mounted) return false;
    final options = await showBackupRestoreDialog(
      context,
      inspection: inspection,
      sourceTitle: title,
    );

    if (options == null) return false; // إلغاء المستخدم

    // 3. عرض نافذة التقدم
    if (!context.mounted) return false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'جارٍ استرجاع وتحديث البيانات بأمان...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 4. تنفيذ الاسترجاع
    try {
      await BackupService.restoreFromSnapshot(dataSnapshot, options: options);

      // إغلاق نافذة التقدم
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      // تحديث كافة المزودات والواجهات فورياً
      refreshAfterRestore(ref);

      String modeArabic = 'دمج مع الحالي';
      if (options.mode == RestoreMode.replaceAll) {
        modeArabic = 'استبدال شامل';
      } else if (options.mode == RestoreMode.custom) {
        modeArabic = 'استرجاع مخصص';
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            duration: const Duration(seconds: 5),
            content: Text(
              'تم استرجاع البيانات بنجاح ($modeArabic). تم حفظ نسخة أمان احترازية تلقائياً.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            duration: const Duration(seconds: 7),
            content: Text('فشلت الاستعادة: $e'),
          ),
        );
      }
      return false;
    }
  }
}
