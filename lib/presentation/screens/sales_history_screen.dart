import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/sale_invoice.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../widgets/max_width_container.dart';
import '../widgets/receipt_dialog.dart';

class SalesHistoryScreen extends ConsumerWidget {
  final void Function(String route, {SaleInvoice? editInvoice})? onNavigate;

  const SalesHistoryScreen({super.key, this.onNavigate});

  void _showInvoiceDetails(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice invoice,
  ) async {
    final repo = ref.read(saleRepositoryProvider);
    final fullInvoice = await repo.getSaleInvoiceWithItems(invoice.id);
    if (fullInvoice != null && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => ReceiptDialog(invoice: fullInvoice),
      );
    }
  }

  void _confirmCancelInvoice(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice invoice,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء الفاتورة'),
        content: Text(
          'هل أنت متأكد من رغبتك في إلغاء الفاتورة رقم (${invoice.invoiceNumber})؟\nسيتم إعادة كميات المنتجات إلى المخزن تلقائيًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = ref.read(saleRepositoryProvider);
              final userId = ref.read(authProvider).user?.id;
              try {
                await repo.cancelSaleInvoice(invoice.id, userId: userId);
                refreshAfterSale(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم إلغاء الفاتورة وإعادة المخزون'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text(
                        e.toString().replaceFirst('StateError: ', ''),
                      ),
                      duration: const Duration(seconds: 7),
                    ),
                  );
                }
              }
            },
            child: const Text('إلغاء الفاتورة'),
          ),
        ],
      ),
    );
  }

  void _confirmRestoreInvoice(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice invoice,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع الفاتورة الملغاة'),
        content: Text(
          'هل تريد استرجاع الفاتورة رقم (${invoice.invoiceNumber})؟\n'
          'ستتحول إلى فاتورة "معلّقة"، ويمكنك تحريرها وإتمامها من زر '
          '"معلّقة" في شاشة نقطة البيع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.SUCCESS_GREEN,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = ref.read(saleRepositoryProvider);
              final userId = ref.read(authProvider).user?.id;
              try {
                await repo.restoreSaleInvoice(invoice.id, userId: userId);
                refreshAfterSale(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      content: Text(
                        '✓ تم استرجاع الفاتورة كمعلّقة — حرّرها من شاشة نقطة البيع',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text(
                        e.toString().replaceFirst('StateError: ', ''),
                      ),
                      duration: const Duration(seconds: 7),
                    ),
                  );
                }
              }
            },
            child: const Text('استرجاع الفاتورة'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteInvoice(
    BuildContext context,
    WidgetRef ref,
    SaleInvoice invoice,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف الفاتورة'),
        content: Text(
          invoice.status == 'held'
              ? 'هل أنت متأكد من حذف الفاتورة المعلّقة (${invoice.invoiceNumber})؟\n'
                    'الفاتورة المعلّقة لم تُؤثر على المخزن بعد، لكن أي دين أُضيف '
                    'للعميل عند تعليقها سيُعكس تلقائياً.'
              : 'هل أنت متأكد من حذف الفاتورة (${invoice.invoiceNumber})؟\n'
                    'سيتم إعادة كميات المنتجات إلى المخزن وعكس دين العميل. '
                    'لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = ref.read(saleRepositoryProvider);
              final userId = ref.read(authProvider).user?.id;
              try {
                await repo.deleteSaleInvoice(invoice.id, userId: userId);
                refreshAfterSale(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      content: Text('✓ تم حذف الفاتورة'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text(
                        e.toString().replaceFirst('StateError: ', ''),
                      ),
                      duration: const Duration(seconds: 7),
                    ),
                  );
                }
              }
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesHistoryProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    // عامل تكبير حسب عرض المحتوى: يكبّر السجلات على التابلت بوضوح.
    final scale = ResponsiveScope.scaleOf(context);

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سجل فواتير المبيعات',
                        style: TextStyle(
                          fontSize: AppTypography.HEADING_2 * scale,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE_DARK,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'عرض تفاصيل كل عمليات البيع السابقة، طرق الدفع، ومعاينة وطباعة الإيصالات',
                        style: TextStyle(
                          fontSize: 13 * scale,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ],
                  ),
                  IconButton.filledTonal(
                    onPressed: () => ref.invalidate(salesHistoryProvider),
                    tooltip: 'تحديث',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Expanded(
                child: salesAsync.when(
                  data: (invoices) {
                    if (invoices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: AppColors.TEXT_SECONDARY.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد فواتير مبيعات مسجلة حتى الآن',
                              style: TextStyle(
                                fontSize: AppTypography.HEADING_3,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'قم بإجراء عملية بيع جديدة من شاشة نقطة البيع (POS)',
                              style: TextStyle(color: AppColors.TEXT_SECONDARY),
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
                          itemCount: invoices.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.8),
                          itemBuilder: (context, index) {
                            final inv = invoices[index];
                            final isCompleted = inv.status == 'completed';
                            final isHeld = inv.status == 'held';
                            final statusColor = isCompleted
                                ? AppColors.SUCCESS_GREEN
                                : isHeld
                                ? AppColors.WARNING_AMBER
                                : AppColors.DANGER_RED;

                            return InkWell(
                              onTap: () => _showInvoiceDetails(context, ref, inv),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final customerText = inv.customerName?.isNotEmpty == true
                                        ? inv.customerName!
                                        : 'عميل نقدي';

                                    // عرض موحد موجز وأنيق في سطرين فقط
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // السطر 1: شارة الحالة + رقم الفاتورة + العميل | الإجمالي
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                inv.statusArabic,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: statusColor,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              inv.invoiceNumber,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: AppColors.PRIMARY_BLUE_DARK,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              '•',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.person_outline,
                                              size: 14,
                                              color: AppColors.TEXT_SECONDARY,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                customerText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppColors.TEXT_PRIMARY,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              AppStrings.money(inv.total),
                                              style: const TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.PRIMARY_BLUE,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // السطر 2: التاريخ والوقت + طريقة الدفع + المدفوع/المتبقي | أزرار الإجراءات السريعة
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.schedule,
                                              size: 13,
                                              color: AppColors.TEXT_SECONDARY,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              dateFormat.format(inv.createdAt),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.TEXT_SECONDARY,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              '•',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              inv.paymentMethodArabic,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.TEXT_SECONDARY,
                                              ),
                                            ),
                                            if (inv.remainingOnCustomer > 0.005) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '(متبقي: ${AppStrings.money(inv.remainingOnCustomer)})',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.DANGER_RED,
                                                ),
                                              ),
                                            ] else if (inv.paidAmount > 0.005 && inv.paidAmount != inv.total) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '(المدفوع: ${AppStrings.money(inv.paidAmount)})',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.TEXT_SECONDARY,
                                                ),
                                              ),
                                            ],
                                            const Spacer(),
                                            // أزرار العمليات المصغرة في نهاية السطر الثاني
                                            IconButton(
                                              tooltip: 'عرض الفاتورة والطباعة',
                                              icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(),
                                              onPressed: () => _showInvoiceDetails(context, ref, inv),
                                            ),
                                            if (isCompleted) ...[
                                              const SizedBox(width: 6),
                                              IconButton(
                                                tooltip: 'إلغاء الفاتورة',
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                  size: 18,
                                                  color: AppColors.DANGER_RED,
                                                ),
                                                visualDensity: VisualDensity.compact,
                                                padding: const EdgeInsets.all(4),
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _confirmCancelInvoice(context, ref, inv),
                                              ),
                                            ],
                                            if (inv.status == 'cancelled') ...[
                                              const SizedBox(width: 6),
                                              IconButton(
                                                tooltip: 'استرجاع الفاتورة الملغاة',
                                                icon: const Icon(
                                                  Icons.restore,
                                                  size: 18,
                                                  color: AppColors.SUCCESS_GREEN,
                                                ),
                                                visualDensity: VisualDensity.compact,
                                                padding: const EdgeInsets.all(4),
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _confirmRestoreInvoice(context, ref, inv),
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            IconButton(
                                              tooltip: inv.status == 'held'
                                                  ? 'حذف الفاتورة المعلّقة'
                                                  : 'حذف الفاتورة',
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.DANGER_RED,
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(),
                                              onPressed: () => _confirmDeleteInvoice(context, ref, inv),
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
