import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/payment.dart';
import '../../data/models/purchase_invoice.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/shop_profile_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import '../widgets/supplier_statement_pdf.dart';

class SupplierDetailScreen extends ConsumerStatefulWidget {
  final String supplierId;

  const SupplierDetailScreen({super.key, required this.supplierId});

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen> {
  SupplierStatement? _statement;
  bool _isLoading = true;
  String? _storeName;
  String? _storeLogoPath;

  @override
  void initState() {
    super.initState();
    _loadStatement();
    _loadStoreInfo();
  }

  /// اسم المحل والشعار (لرويسة كشف الحساب المطبوع).
  Future<void> _loadStoreInfo() async {
    String? name;
    try {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('store_name');
    } catch (_) {
      name = null;
    }
    String? logoPath;
    try {
      logoPath = (await ShopProfileRepository().getProfile()).logoPath;
    } catch (_) {
      logoPath = null;
    }
    if (mounted) {
      setState(() {
        _storeName = name;
        _storeLogoPath = logoPath;
      });
    }
  }

  Future<void> _loadStatement() async {
    setState(() => _isLoading = true);
    final repo = ref.read(supplierRepositoryProvider);
    final statement = await repo.getSupplierStatement(widget.supplierId);
    if (mounted) {
      setState(() {
        _statement = statement;
        _isLoading = false;
      });
    }
  }

  /// طباعة كشف الحساب (بديل: مشاركة PDF إذا تعذرت الطباعة المباشرة).
  Future<void> _printStatement() async {
    final st = _statement;
    if (st == null) return;
    try {
      await SupplierStatementPdf.printStatement(
        statement: st,
        storeName: _storeName,
        storeLogoPath: _storeLogoPath,
      );
    } catch (_) {
      if (!mounted) return;
      try {
        await SupplierStatementPdf.shareStatement(
          statement: st,
          storeName: _storeName,
          storeLogoPath: _storeLogoPath,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.DANGER_RED,
              content: Text('تعذر إنشاء ملف كشف الحساب: $e'),
            ),
          );
        }
      }
    }
  }

  /// فتح بيان فاتورة شراء: عرض أصنافها بالكامل.
  void _openPurchaseDetails(String purchaseInvoiceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل بيان: فاتورة شراء'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<PurchaseInvoice?>(
            future: PurchaseRepository().getPurchaseInvoiceWithItems(
              purchaseInvoiceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text(
                  'حدث خطأ أثناء تحميل التفاصيل: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.DANGER_RED),
                );
              }
              final inv = snapshot.data;
              if (inv == null) {
                return const Text('لم يتم العثور على الفاتورة');
              }
              final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'التاريخ: ${dateFormat.format(inv.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                      Text(
                        'المتبقي على الفاتورة: ${inv.remainingOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.DANGER_RED,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (inv.items.isEmpty)
                    const Text(
                      'لا توجد أصناف مسجلة على هذه الفاتورة',
                      style: TextStyle(color: AppColors.TEXT_SECONDARY),
                    )
                  else ...[
                    const Text(
                      'الأصناف:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: inv.items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
                          final item = inv.items[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName ?? 'منتج',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '${item.quantity} × ${item.unitCost.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${item.lineTotal.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الإجمالي:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${inv.total.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المدفوع:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${inv.paidAmount.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.SUCCESS_GREEN,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
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

  /// فتح بيان دفعة سداد: المبلغ والتاريخ والملاحظة.
  void _openPaymentDetails(String paymentId) {
    final st = _statement;
    if (st == null) return;
    Payment? payment;
    for (final p in st.payments) {
      if (p.id == paymentId) {
        payment = p;
        break;
      }
    }
    if (payment == null) return;
    final p = payment;
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل بيان: دفعة سداد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المبلغ:', style: TextStyle(fontSize: 13)),
                Text(
                  '${p.amount.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.SUCCESS_GREEN,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'التاريخ: ${dateFormat.format(p.createdAt)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.TEXT_SECONDARY,
              ),
            ),
            if (p.note != null && p.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'الملاحظة: ${p.note}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
            ],
          ],
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

  void _showAddPaymentDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة سداد للمورد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المورد: ${_statement?.supplier.name ?? ""}'),
            const SizedBox(height: 8),
            Text(
              'إجمالي المستحق للمورد: ${_statement?.supplier.balanceOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.WARNING_AMBER,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع *',
                suffixText: AppStrings.CURRENCY,
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount =
                  double.tryParse(amountController.text.trim()) ?? 0.0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر'),
                  ),
                );
                return;
              }

              Navigator.of(ctx).pop();
              final repo = ref.read(supplierRepositoryProvider);
              await repo.addSupplierPayment(
                supplierId: widget.supplierId,
                amount: amount,
                note: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
                userId: ref.read(authProvider).user?.id,
              );

              ref.invalidate(suppliersListProvider);
              ref.invalidate(paymentsProvider);
              ref.invalidate(dashboardStatsProvider);
              await _loadStatement();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.SUCCESS_GREEN,
                    content: Text(
                      'تم تسجيل دفعة السداد وتحديث رصيد المورد بنجاح',
                    ),
                  ),
                );
              }
            },
            child: const Text('تسجيل السداد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('كشف حساب المورد')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_statement == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('كشف حساب المورد')),
        body: const Center(child: Text('المورد غير موجود')),
      );
    }

    final s = _statement!.supplier;
    final hasOwed = s.hasOwed;
    // كشف الحساب الموحد: كل العمليات (شراء + دفعات) مرتبة زمنياً برصيد دائري.
    final entries = _statement!.buildEntries();

    return Scaffold(
     appBar: AppBar(
         title: Text(
           'كشف حساب المورد: ${s.name}',
           maxLines: 1,
           overflow: TextOverflow.ellipsis,
         ),
         actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printStatement,
            tooltip: 'طباعة كشف الحساب',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatement,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: MaxWidthContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Supplier Header Card
              Container(
                padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.PRIMARY_BLUE.withValues(
                        alpha: 0.12,
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        size: 36,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                    ),
                    const SizedBox(width: 20),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             s.name,
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                             style: const TextStyle(
                               fontSize: AppTypography.HEADING_2,
                               fontWeight: FontWeight.bold,
                               color: AppColors.PRIMARY_BLUE_DARK,
                             ),
                           ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (s.phone != null && s.phone!.isNotEmpty) ...[
                                const Icon(
                                  Icons.phone,
                                  size: 16,
                                  color: AppColors.TEXT_SECONDARY,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  s.phone!,
                                  style: const TextStyle(
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                              if (s.address != null &&
                                  s.address!.isNotEmpty) ...[
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: AppColors.TEXT_SECONDARY,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  s.address!,
                                  style: const TextStyle(
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (s.notes != null && s.notes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ملاحظات: ${s.notes!}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Balance Owed Card & Pay Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: hasOwed
                            ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                            : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppLayout.BORDER_RADIUS,
                        ),
                        border: Border.all(
                          color: hasOwed
                              ? AppColors.WARNING_AMBER
                              : AppColors.SUCCESS_GREEN,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hasOwed ? 'إجمالي المستحق للمورد' : 'حالة الحساب',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: hasOwed
                                  ? AppColors.WARNING_AMBER
                                  : AppColors.SUCCESS_GREEN,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasOwed
                                ? '${s.balanceOwed.toStringAsFixed(0)} ${AppStrings.CURRENCY}'
                                : 'خالص (0.00)',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: hasOwed
                                  ? AppColors.WARNING_AMBER
                                  : AppColors.SUCCESS_GREEN,
                            ),
                          ),
                          if (hasOwed) ...[
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.PRIMARY_BLUE,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              onPressed: _showAddPaymentDialog,
                              icon: const Icon(Icons.payment, size: 16),
                              label: const Text(
                                'سداد دفعة',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Ledger header with totals
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'كشف الحساب — كل عمليات المورد',
                    style: TextStyle(
                      fontSize: AppTypography.HEADING_3,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE_DARK,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                         'إجمالي المشتريات: ${AppStrings.money(_statement!.totalPurchases)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'إجمالي الدفعات: ${_statement!.totalPayments.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.SUCCESS_GREEN,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'اضغط على أي بيان لعرض محتواه بالكامل',
                style: TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
              ),
              const SizedBox(height: 12),

              // Unified transaction ledger
              Container(
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'لا توجد عمليات مسجلة لهذا المورد بعد',
                            style: TextStyle(color: AppColors.TEXT_SECONDARY),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
                          final e = entries[index];
                          final isPurchase = e.isPurchase;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            onTap: () => isPurchase
                                ? _openPurchaseDetails(e.referenceId)
                                : _openPaymentDetails(e.referenceId),
                            leading: CircleAvatar(
                              backgroundColor: isPurchase
                                  ? AppColors.PRIMARY_BLUE.withValues(
                                      alpha: 0.12,
                                    )
                                  : AppColors.SUCCESS_GREEN.withValues(
                                      alpha: 0.12,
                                    ),
                              child: Icon(
                                isPurchase
                                    ? Icons.inventory_2_outlined
                                    : Icons.payments_outlined,
                                color: isPurchase
                                    ? AppColors.PRIMARY_BLUE
                                    : AppColors.SUCCESS_GREEN,
                              ),
                            ),
                            title: Text(
                              e.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              dateFormat.format(e.date),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isPurchase
                                      ? '+${e.amount.toStringAsFixed(0)}'
                                      : '−${e.amount.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPurchase
                                        ? AppColors.PRIMARY_BLUE
                                        : AppColors.SUCCESS_GREEN,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'الرصيد: ${e.runningBalance.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: e.runningBalance > 0.005
                                        ? AppColors.WARNING_AMBER
                                        : AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_left,
                                  size: 18,
                                  color: AppColors.TEXT_SECONDARY,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
