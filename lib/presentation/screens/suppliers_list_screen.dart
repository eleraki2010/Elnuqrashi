import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/supplier.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import 'supplier_detail_screen.dart';

class SuppliersListScreen extends ConsumerWidget {
  const SuppliersListScreen({super.key});

  void _showAddEditSupplierDialog(
    BuildContext context,
    WidgetRef ref, [
    Supplier? supplier,
  ]) {
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final addressController = TextEditingController(
      text: supplier?.address ?? '',
    );
    final notesController = TextEditingController(text: supplier?.notes ?? '');
    final isEdit = supplier != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'تعديل بيانات المورد' : 'إضافة مورد جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد / الشركة *',
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات / أصناف التوريد',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('يرجى إدخال اسم المورد')),
                );
                return;
              }

              Navigator.of(ctx).pop();
              final repo = ref.read(supplierRepositoryProvider);
              final now = DateTime.now();

              if (isEdit) {
                final updated = supplier.copyWith(
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                  updatedAt: now,
                );
                await repo.updateSupplier(updated);
              } else {
                final newSupplier = Supplier(
                  id: const Uuid().v4(),
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                  balanceOwed: 0.0,
                  createdAt: now,
                  updatedAt: now,
                );
                await repo.insertSupplier(newSupplier);
              }

              ref.invalidate(suppliersListProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.SUCCESS_GREEN,
                    content: Text(
                      isEdit
                          ? 'تم تحديث بيانات المورد'
                          : 'تمت إضافة المورد بنجاح',
                    ),
                  ),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSupplier(
    BuildContext context,
    WidgetRef ref,
    Supplier supplier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المورد (${supplier.name})؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = ref.read(supplierRepositoryProvider);
              await repo.deleteSupplier(supplier.id);
              ref.invalidate(suppliersListProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف المورد بنجاح')),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إدارة الموردين والمستحقات',
                      style: TextStyle(
                        fontSize: AppTypography.HEADING_2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.PRIMARY_BLUE_DARK,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'متابعة فواتير التوريد، حسابات ومستحقات الموردين، ودفعات السداد',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditSupplierDialog(context, ref),
                  icon: const Icon(Icons.add_business),
                  label: const Text('إضافة مورد'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              onChanged: (val) {
                ref.read(supplierSearchProvider.notifier).setQuery(val);
              },
              decoration: InputDecoration(
                hintText: 'بحث باسم المورد أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ref.watch(supplierSearchProvider).isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          ref.read(supplierSearchProvider.notifier).clear();
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Suppliers Table / List
            Expanded(
              child: suppliersAsync.when(
                data: (suppliers) {
                  if (suppliers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: 64,
                            color: AppColors.TEXT_SECONDARY.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا يوجد موردين مسجلين',
                            style: TextStyle(
                              fontSize: AppTypography.HEADING_3,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showAddEditSupplierDialog(context, ref),
                            icon: const Icon(Icons.add_business),
                            label: const Text('إضافة أول مورد'),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.NEUTRAL_SURFACE,
                      borderRadius: BorderRadius.circular(
                        AppLayout.BORDER_RADIUS,
                      ),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppLayout.BORDER_RADIUS,
                      ),
                      child: ListView.separated(
                        itemCount: suppliers.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.8),
                        itemBuilder: (context, index) {
                          final s = suppliers[index];
                          final hasOwed = s.hasOwed;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: hasOwed
                                  ? AppColors.WARNING_AMBER.withValues(
                                      alpha: 0.15,
                                    )
                                  : AppColors.PRIMARY_BLUE.withValues(
                                      alpha: 0.12,
                                    ),
                              child: Icon(
                                Icons.local_shipping,
                                color: hasOwed
                                    ? AppColors.WARNING_AMBER
                                    : AppColors.PRIMARY_BLUE,
                              ),
                            ),
                             title: Text(
                               s.name,
                               maxLines: 1,
                               overflow: TextOverflow.ellipsis,
                               style: const TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 15,
                               ),
                             ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (s.phone != null &&
                                      s.phone!.isNotEmpty) ...[
                                    const Icon(
                                      Icons.phone,
                                      size: 14,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      s.phone!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.TEXT_SECONDARY,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  if (s.address != null &&
                                      s.address!.isNotEmpty) ...[
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      s.address!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.TEXT_SECONDARY,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Owed Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasOwed
                                        ? AppColors.WARNING_AMBER.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppColors.SUCCESS_GREEN.withValues(
                                            alpha: 0.12,
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    hasOwed
                                        ? 'مستحق له: ${s.balanceOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}'
                                        : 'خالص (0.00)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: hasOwed
                                          ? AppColors.WARNING_AMBER
                                          : AppColors.SUCCESS_GREEN,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 36),
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SupplierDetailScreen(
                                          supplierId: s.id,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'كشف الحساب',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: AppColors.PRIMARY_BLUE,
                                  ),
                                  onPressed: () => _showAddEditSupplierDialog(
                                    context,
                                    ref,
                                    s,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.DANGER_RED,
                                  ),
                                  onPressed: () =>
                                      _confirmDeleteSupplier(context, ref, s),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('خطأ: $err')),
              ),
            ),
          ],
        ),
      ), // MaxWidthContainer
      ),
    );
  }
}
