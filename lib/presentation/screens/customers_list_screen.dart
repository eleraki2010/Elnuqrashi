import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/customer.dart';
import '../../providers/app_providers.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import 'customer_detail_screen.dart';

class CustomersListScreen extends ConsumerWidget {
  const CustomersListScreen({super.key});

  void _showAddEditCustomerDialog(
    BuildContext context,
    WidgetRef ref, [
    Customer? customer,
  ]) {
    final nameController = TextEditingController(text: customer?.name ?? '');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final addressController = TextEditingController(
      text: customer?.address ?? '',
    );
    final notesController = TextEditingController(text: customer?.notes ?? '');
    final initialDebtController = TextEditingController(text: '');
    final isEdit = customer != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'تعديل بيانات العميل' : 'إضافة عميل جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل *',
                  prefixIcon: Icon(Icons.person),
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
                  controller: initialDebtController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'رصيد افتتاحي / ديون سابقة (ج.م)',
                    hintText: '0.00 (اختياري، إن وجد دين سابق للعميل)',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
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
                  const SnackBar(content: Text('يرجى إدخال اسم العميل')),
                );
                return;
              }

              Navigator.of(ctx).pop();
              final repo = ref.read(customerRepositoryProvider);
              final now = DateTime.now();

              if (isEdit) {
                final updated = customer.copyWith(
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
                await repo.updateCustomer(updated);
              } else {
                final initialDebt =
                    double.tryParse(initialDebtController.text.trim()) ?? 0.0;
                final newCustomer = Customer(
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
                  balanceDue: initialDebt,
                  createdAt: now,
                  updatedAt: now,
                );
                await repo.insertCustomer(newCustomer);
              }

              ref.invalidate(customersListProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.SUCCESS_GREEN,
                    content: Text(
                      isEdit
                          ? 'تم تحديث بيانات العميل'
                          : 'تمت إضافة العميل بنجاح',
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

  void _confirmDeleteCustomer(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العميل (${customer.name})؟'),
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
              final repo = ref.read(customerRepositoryProvider);
              try {
                await repo.deleteCustomer(customer.id);
                ref.invalidate(customersListProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف العميل بنجاح')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text(e.toString().replaceFirst(
                          'StateError: ', '')),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
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
    final customersAsync = ref.watch(customersListProvider);
    // عامل تكبير حسب عرض المحتوى: يكبّر الصفوف على التابلت بوضوح.
    final scale = ResponsiveScope.scaleOf(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة العملاء وحسابات الديون',
                        style: TextStyle(
                          fontSize: AppTypography.HEADING_2 * scale,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE_DARK,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مرتّبون تنازلياً حسب المديونية — كشف الحساب يجمع الفواتير والمرتجعات والدفعات برصيد جارٍ',
                        style: TextStyle(
                          fontSize: 13 * scale,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditCustomerDialog(context, ref),
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة عميل'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              onChanged: (val) {
                ref.read(customerSearchProvider.notifier).setQuery(val);
              },
              decoration: InputDecoration(
                hintText: 'بحث باسم العميل أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ref.watch(customerSearchProvider).isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          ref.read(customerSearchProvider.notifier).clear();
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Customers Table / List
            Expanded(
              child: customersAsync.when(
                data: (customers) {
                  if (customers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: AppColors.TEXT_SECONDARY.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا يوجد عملاء مسجلين',
                            style: TextStyle(
                              fontSize: AppTypography.HEADING_3,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showAddEditCustomerDialog(context, ref),
                            icon: const Icon(Icons.person_add),
                            label: const Text('إضافة أول عميل'),
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
                        itemCount: customers.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.8),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          final hasDebt = c.hasDebt;

                          return InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailScreen(
                                    customerId: c.id,
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
                                          backgroundColor: hasDebt
                                              ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                              : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                                          child: Icon(
                                            Icons.person,
                                            size: 18,
                                            color: hasDebt
                                                ? AppColors.DANGER_RED
                                                : AppColors.PRIMARY_BLUE,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            c.name,
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
                                        if (c.phone != null && c.phone!.isNotEmpty) ...[
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.phone, size: 14, color: AppColors.TEXT_SECONDARY),
                                              const SizedBox(width: 4),
                                              Text(
                                                c.phone!,
                                                style: const TextStyle(fontSize: 12.5, color: AppColors.TEXT_SECONDARY),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        if (c.address != null && c.address!.isNotEmpty) ...[
                                          Flexible(
                                            flex: 2,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.TEXT_SECONDARY),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    c.address!,
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
                                        if (c.isOverdue) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.DANGER_RED,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'متأخر',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10.5,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        // شارة المديونية
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: hasDebt
                                                ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                                : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            hasDebt
                                                ? 'مديونية: ${AppStrings.money(c.balanceDue)}'
                                                : 'خالص (0.00)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: hasDebt
                                                  ? AppColors.DANGER_RED
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
                                                builder: (_) => CustomerDetailScreen(customerId: c.id),
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
                                          onPressed: () => _showAddEditCustomerDialog(context, ref, c),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف',
                                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.DANGER_RED),
                                          onPressed: () => _confirmDeleteCustomer(context, ref, c),
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
                                            backgroundColor: hasDebt
                                                ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                                : AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                                            child: Icon(
                                              Icons.person,
                                              size: 16,
                                              color: hasDebt ? AppColors.DANGER_RED : AppColors.PRIMARY_BLUE,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              c.name,
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
                                              color: hasDebt
                                                  ? AppColors.DANGER_RED.withValues(alpha: 0.12)
                                                  : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              hasDebt
                                                  ? 'مديونية: ${AppStrings.money(c.balanceDue)}'
                                                  : 'خالص (0.00)',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11.5,
                                                color: hasDebt ? AppColors.DANGER_RED : AppColors.SUCCESS_GREEN,
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
                                                if (c.phone != null && c.phone!.isNotEmpty)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.phone, size: 13, color: AppColors.TEXT_SECONDARY),
                                                      const SizedBox(width: 3),
                                                      Text(c.phone!, style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY)),
                                                    ],
                                                  ),
                                                if (c.address != null && c.address!.isNotEmpty)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.location_on_outlined, size: 13, color: AppColors.TEXT_SECONDARY),
                                                      const SizedBox(width: 3),
                                                      Text(c.address!, style: const TextStyle(fontSize: 11.5, color: AppColors.TEXT_SECONDARY)),
                                                    ],
                                                  ),
                                                if (c.isOverdue)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.DANGER_RED,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text('متأخر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
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
                                                  builder: (_) => CustomerDetailScreen(customerId: c.id),
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
                                            onPressed: () => _showAddEditCustomerDialog(context, ref, c),
                                          ),
                                          IconButton(
                                            tooltip: 'حذف',
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.DANGER_RED),
                                            onPressed: () => _confirmDeleteCustomer(context, ref, c),
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
