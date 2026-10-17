import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/purchase_invoice.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import 'purchase_form_screen.dart';

class PurchasesHistoryScreen extends ConsumerWidget {
  const PurchasesHistoryScreen({super.key});

  Future<void> _editPurchase(
    BuildContext context,
    WidgetRef ref,
    String invoiceId,
  ) async {
    final repo = ref.read(purchaseRepositoryProvider);
    final fullInvoice = await repo.getPurchaseInvoiceWithItems(invoiceId);
    if (fullInvoice == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(purchaseToEdit: fullInvoice),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PurchaseInvoice invoice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف فاتورة الشراء'),
        content: Text(
          'هل أنت متأكد من حذف فاتورة الشراء للمورد "${invoice.supplierName ?? "المورد"}" بقيمة ${AppStrings.money(invoice.total)}؟\n\n'
          'تنبيه: سيتم عكس كميات الأصناف المضافة للمخزن وخصم المديونية من رصيد المورد تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('نعم، حذف الفاتورة'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final repo = ref.read(purchaseRepositoryProvider);
      await repo.deletePurchaseInvoice(
        invoice.id,
        userId: ref.read(authProvider).user?.id,
      );
      refreshAfterPurchase(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم حذف فاتورة الشراء وعكس المخزون ورصيد المورد بنجاح'),
          ),
        );
      }
    }
  }

  void _showPurchaseDetails(
    BuildContext context,
    WidgetRef ref,
    PurchaseInvoice invoice,
  ) async {
    final repo = ref.read(purchaseRepositoryProvider);
    final fullInvoice = await repo.getPurchaseInvoiceWithItems(invoice.id);
    if (fullInvoice == null || !context.mounted) return;

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final isAdmin = ref.read(isAdminProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'تفاصيل فاتورة التوريد (${fullInvoice.supplierName ?? "مورد"})',
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'التاريخ: ${dateFormat.format(fullInvoice.createdAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: fullInvoice.items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final item = fullInvoice.items[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        item.productName ?? 'منتج',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${item.quantity} × ${AppStrings.money(item.unitCost)}',
                      ),
                      trailing: Text(
                        AppStrings.money(item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إجمالي الفاتورة:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    AppStrings.money(fullInvoice.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المدفوع كاش:'),
                  Text(
                    AppStrings.money(fullInvoice.paidAmount),
                    style: const TextStyle(
                      color: AppColors.SUCCESS_GREEN,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (fullInvoice.remainingOwed > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المتبقي للمورد:'),
                    Text(
                      AppStrings.money(fullInvoice.remainingOwed),
                      style: const TextStyle(
                        color: AppColors.WARNING_AMBER,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          if (isAdmin) ...[
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.DANGER_RED),
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmDelete(context, ref, fullInvoice);
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('حذف الفاتورة'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.PRIMARY_BLUE,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _editPurchase(context, ref, fullInvoice.id);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('تعديل الفاتورة'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchasesListProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

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
                        'سجل فواتير المشتريات والتوريد',
                        style: TextStyle(
                          fontSize: AppTypography.HEADING_2,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE_DARK,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'متابعة فواتير شراء البضائع من الموردين، تفاصيل الأسعار، وتحديثات المخزون',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PurchaseFormScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('تسجيل فاتورة شراء'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Expanded(
                child: purchasesAsync.when(
                  data: (purchases) {
                    if (purchases.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              size: 64,
                              color: AppColors.TEXT_SECONDARY.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد فواتير مشتريات مسجلة حتى الآن',
                              style: TextStyle(
                                fontSize: AppTypography.HEADING_3,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PurchaseFormScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('تسجيل أول فاتورة توريد'),
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
                          itemCount: purchases.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.8),
                          itemBuilder: (context, index) {
                            final p = purchases[index];
                            final isFullyPaid = p.isFullyPaid;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.PRIMARY_BLUE
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  '#${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.PRIMARY_BLUE,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                'المورد: ${p.supplierName ?? "مورد"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${dateFormat.format(p.createdAt)} • المدفوع: ${AppStrings.money(p.paidAmount)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        AppStrings.money(p.total),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.PRIMARY_BLUE_DARK,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isFullyPaid
                                              ? AppColors.SUCCESS_GREEN
                                                    .withValues(alpha: 0.12)
                                              : AppColors.WARNING_AMBER
                                                    .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          isFullyPaid
                                              ? 'خالص'
                                              : 'آجل (متبقي: ${AppStrings.money(p.remainingOwed)})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isFullyPaid
                                                ? AppColors.SUCCESS_GREEN
                                                : AppColors.WARNING_AMBER,
                                          ),
                                        ),
                                      ),
                                    ],
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
                                    onPressed: () =>
                                        _showPurchaseDetails(context, ref, p),
                                    icon: const Icon(
                                      Icons.receipt_long,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'الأصناف',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (ref.watch(isAdminProvider)) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      tooltip: 'تعديل الفاتورة (للأدمن)',
                                      onPressed: () => _editPurchase(context, ref, p.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: AppColors.DANGER_RED,
                                        size: 18,
                                      ),
                                      tooltip: 'حذف الفاتورة (للأدمن)',
                                      onPressed: () => _confirmDelete(context, ref, p),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
