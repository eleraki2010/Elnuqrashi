import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/audit_log_repository.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';

/// شاشة سجل العمليات: تعرض كل قرار مالي وإداري مع "من" اتخذه ومتى.
/// تُتيح للمالك متابعة من أنشأ الفاتورة أو سجّل سند القبض/الصرف أو الحذف.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _selectedUser;
  String? _selectedTable;

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل العمليات'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
      ),
      body: MaxWidthContainer(
        child: Padding(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
          child: logsAsync.when(
          data: (logs) {
            final users = _extractUsers(logs);
            final tables = _extractTables(logs);
            final filtered = _applyFilters(logs);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سجل العمليات والقرارات',
                      style: TextStyle(
                        fontSize: AppTypography.HEADING_2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.PRIMARY_BLUE_DARK,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'كل عملية (فاتورة، سند قبض/صرف، مصروف، مرتجع، حذف) مسجّلة باسم المستخدم الذي اتخذها',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // فلاتر المستخدم والجدول
                if (users.isNotEmpty || tables.isNotEmpty)
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (users.isNotEmpty)
                        _buildFilterDropdown<String>(
                          label: 'كل المستخدمين',
                          value: _selectedUser,
                          items: users,
                          onChanged: (val) =>
                              setState(() => _selectedUser = val),
                        ),
                      if (tables.isNotEmpty)
                        _buildFilterDropdown<String>(
                          label: 'كل أنواع العمليات',
                          value: _selectedTable,
                          items: tables,
                          onChanged: (val) =>
                              setState(() => _selectedTable = val),
                        ),
                    ],
                  ),
                if (users.isNotEmpty || tables.isNotEmpty)
                  const SizedBox(height: 16),

                // ملخص عددي
                Container(
                  padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
                  decoration: BoxDecoration(
                    color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    border: Border.all(
                      color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_edu, color: AppColors.PRIMARY_BLUE),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'عدد العمليات المعروضة: ${filtered.length}'
                          '${filtered.length != logs.length ? ' من ${logs.length}' : ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.PRIMARY_BLUE_DARK,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'تحديث',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => ref.invalidate(auditLogProvider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // قائمة العمليات
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(logs.isNotEmpty)
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.NEUTRAL_SURFACE,
                            borderRadius:
                                BorderRadius.circular(AppLayout.BORDER_RADIUS),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppLayout.BORDER_RADIUS,
                            ),
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, thickness: 0.8),
                              itemBuilder: (context, index) {
                                final entry = filtered[index];
                                final actionInfo = _actionInfo(entry.log.action);
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        actionInfo.color.withValues(alpha: 0.12),
                                    child: Icon(
                                      actionInfo.icon,
                                      color: actionInfo.color,
                                    ),
                                  ),
                                  title: Text(
                                    entry.log.note ??
                                        '${_tableArabic(entry.log.tableName)} — ${actionInfo.label}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: 13,
                                              color: AppColors.TEXT_SECONDARY,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              entry.userDisplayName,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppColors.PRIMARY_BLUE_DARK,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateFormat.format(entry.log.createdAt),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.TEXT_SECONDARY,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: actionInfo.color
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_tableArabic(entry.log.tableName)} • ${actionInfo.label}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: actionInfo.color,
                                      ),
                                    ),
                                  ),
                                  onTap: () => _showLogDetails(entry),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('خطأ: $err')),
        ),
        ),
      ),
    );
  }

  List<String> _extractUsers(List<DetailedAuditLog> logs) {
    final names = <String>{};
    for (final l in logs) {
      if (l.userName != null) names.add(l.userName!);
    }
    return names.toList()..sort();
  }

  List<String> _extractTables(List<DetailedAuditLog> logs) {
    return logs.map((l) => l.log.tableName).toSet().toList()..sort();
  }

  List<DetailedAuditLog> _applyFilters(List<DetailedAuditLog> logs) {
    return logs.where((l) {
      if (_selectedUser != null && l.userName != _selectedUser) return false;
      if (_selectedTable != null && l.log.tableName != _selectedTable) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        hint: Text(label),
        items: [
          DropdownMenuItem<T>(value: null, child: Text(label)),
          ...items.map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(item is String && _tableArabic(item) != item
                  ? _tableArabic(item)
                  : '$item'),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEmptyState(bool hasLogs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasLogs ? Icons.filter_alt_off : Icons.history,
            size: 64,
            color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasLogs ? 'لا توجد عمليات مطابقة للفلتر' : 'لا توجد عمليات مسجلة',
            style: const TextStyle(
              fontSize: AppTypography.HEADING_3,
              color: AppColors.TEXT_SECONDARY,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasLogs
                ? 'امسح الفلاتر لعرض كل العمليات'
                : 'ستُسجَّل هنا كل فاتورة أو سند أو حذف باسم المستخدم المسؤول',
            style: const TextStyle(color: AppColors.TEXT_SECONDARY),
            textAlign: TextAlign.center,
          ),
          if (hasLogs) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _selectedUser = null;
                _selectedTable = null;
              }),
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('مسح الفلاتر'),
            ),
          ],
        ],
      ),
    );
  }

  ({IconData icon, String label, Color color}) _actionInfo(String action) {
    switch (action) {
      case 'create':
        return (
          icon: Icons.add_circle_outline,
          label: 'إنشاء',
          color: AppColors.SUCCESS_GREEN,
        );
      case 'update':
        return (
          icon: Icons.edit_outlined,
          label: 'تعديل',
          color: AppColors.PRIMARY_BLUE,
        );
      case 'cancel':
        return (
          icon: Icons.cancel_outlined,
          label: 'إلغاء',
          color: AppColors.WARNING_AMBER,
        );
      case 'restore':
        return (
          icon: Icons.restore,
          label: 'استرجاع',
          color: AppColors.SUCCESS_GREEN,
        );
      case 'delete':
        return (
          icon: Icons.delete_outline,
          label: 'حذف',
          color: AppColors.DANGER_RED,
        );
      default:
        return (
          icon: Icons.info_outline,
          label: action,
          color: AppColors.TEXT_SECONDARY,
        );
    }
  }

  String _tableArabic(String tableName) {
    const map = {
      'sale_invoices': 'فاتورة مبيعات',
      'purchase_invoices': 'فاتورة شراء',
      'return_invoices': 'مرتجع',
      'payments': 'سند قبض/صرف',
      'expenses': 'مصروف',
      'customers': 'عميل',
      'suppliers': 'مورد',
      'products': 'منتج',
      'users': 'مستخدم',
    };
    return map[tableName] ?? tableName;
  }

  void _showLogDetails(DetailedAuditLog entry) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final actionInfo = _actionInfo(entry.log.action);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(actionInfo.icon, color: actionInfo.color),
            const SizedBox(width: 8),
            const Text('تفاصيل العملية'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('العملية', actionInfo.label),
              _detailRow('النوع', _tableArabic(entry.log.tableName)),
              _detailRow(
                'المستخدم',
                entry.userDisplayName,
              ),
              _detailRow('التاريخ', dateFormat.format(entry.log.createdAt)),
              if (entry.log.note != null && entry.log.note!.isNotEmpty)
                _detailRow('التفاصيل', entry.log.note!),
              if (entry.log.newValues != null &&
                  entry.log.newValues!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'القيم بعد العملية:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                ...entry.log.newValues!.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (entry.log.oldValues != null &&
                  entry.log.oldValues!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'القيم قبل العملية:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                ...entry.log.oldValues!.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${e.key}: ${e.value}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.TEXT_SECONDARY,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
