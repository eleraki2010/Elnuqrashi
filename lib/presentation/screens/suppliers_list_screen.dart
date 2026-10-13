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
    final initialOwedController = TextEditingController(text: '');
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
              if (!isEdit) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: initialOwedController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'رصيد افتتاحي / مستحقات سابقة للمورد (ج.م)',
                    hintText: '0.00 (اختياري، إن كان للمورد دين سابق عليك)',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
              ],
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
                final initialOwed =
                    double.tryParse(initialOwedController.text.trim()) ?? 0.0;
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
                  balanceOwed: initialOwed,
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
                const Expanded(
                  child: Column(
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
                ),
                const SizedBox(width: 12),
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

                          return InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SupplierDetailScreen(
                                    supplierId: s.id,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth >= 720;

                                  if (isWide) {
                                    // صف واحد متناسق وأنيق للشاشات العريضة
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: hasOwed
                                              ? AppColors.WARNING_AMBER.withValues(alpha: 0.15)
                                              : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                                          child: Icon(
                                            Icons.local_shipping,
                                            size: 18,
                                            color: hasOwed
                                                ? AppColors.WARNING_AMBER
                                                : AppColors.PRIMARY_BLUE,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            s.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                              color: AppColors.PRIMARY_BLUE_DARK,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        if (s.phone != null && s.phone!.isNotEmpty) ...[
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.phone, size: 14, color: AppColors.TEXT_SECONDARY),
                                              const SizedBox(width: 4),
                                              Text(
                                                s.phone!,
                                                style: const TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        if (s.address != null && s.address!.isNotEmpty) ...[
                                          Flexible(
                                            flex: 2,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.TEXT_SECONDARY),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    s.address!,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        // شارة المستحق
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: hasOwed
                                                ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                                                : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            hasOwed
                                                ? 'مستحق: ${s.balanceOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}'
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
                                        // أزرار العمليات
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => SupplierDetailScreen(supplierId: s.id),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.receipt_long, size: 14),
                                          label: const Text('كشف الحساب', style: TextStyle(fontSize: 11.5)),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'تعديل',
                                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.PRIMARY_BLUE),
                                          onPressed: () => _showAddEditSupplierDialog(context, ref, s),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف',
                                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.DANGER_RED),
                                          onPressed: () => _confirmDeleteSupplier(context, ref, s),
                                        ),
                                      ],
                                    );
                                  }

                                  // عرض مدمج للشاشات المتوسطة والضيقة
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 15,
                                            backgroundColor: hasOwed
                                                ? AppColors.WARNING_AMBER.withValues(alpha: 0.15)
                                                : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                                            child: Icon(
                                              Icons.local_shipping,
                                              size: 16,
                                              color: hasOwed ? AppColors.WARNING_AMBER : AppColors.PRIMARY_BLUE,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              s.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppColors.PRIMARY_BLUE_DARK,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: hasOwed
                                                  ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                                                  : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              hasOwed
                                                  ? 'مستحق: ${s.balanceOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}'
                                                  : 'خالص (0.00)',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11.5,
                                                color: hasOwed ? AppColors.WARNING_AMBER : AppColors.SUCCESS_GREEN,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Wrap(
                                              spacing: 10,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                if (s.phone != null && s.phone!.isNotEmpty)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.phone, size: 13, color: AppColors.TEXT_SECONDARY),
                                                      const SizedBox(width: 3),
                                                      Text(s.phone!, style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY)),
                                                    ],
                                                  ),
                                                if (s.address != null && s.address!.isNotEmpty)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.location_on_outlined, size: 13, color: AppColors.TEXT_SECONDARY),
                                                      const SizedBox(width: 3),
                                                      Text(s.address!, style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY)),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              minimumSize: const Size(0, 30),
                                            ),
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => SupplierDetailScreen(supplierId: s.id),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.receipt_long, size: 13),
                                            label: const Text('كشف الحساب', style: TextStyle(fontSize: 11)),
                                          ),
                                          const SizedBox(width: 2),
                                          IconButton(
                                            tooltip: 'تعديل',
                                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.PRIMARY_BLUE),
                                            onPressed: () => _showAddEditSupplierDialog(context, ref, s),
                                          ),
                                          IconButton(
                                            tooltip: 'حذف',
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.DANGER_RED),
                                            onPressed: () => _confirmDeleteSupplier(context, ref, s),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
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
