import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../core/services/whatsapp_reminder_service.dart';
import '../../data/models/payment.dart';
import '../../data/models/sale_invoice.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/shop_profile_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/customer_statement_pdf.dart';
import '../widgets/max_width_container.dart';
import '../widgets/receipt_dialog.dart';

/// حركة موحّدة في كشف الحساب: فاتورة بيع / مرتجع / دفعة سداد،
/// مع أثرها على دين العميل (delta) وتاريخها لعرض الرصيد الجاري.
class _StatementEntry {
  final DateTime date;
  final int typeOrder; // عند تسابيق التاريخ: فاتورة ← مرتجع ← تحصيل
  final String typeLabel;
  final String? refLabel;
  final String? subtitle;
  final double delta; // موجب يزيد الدين، سالب يخفّضه
  final double displayAmount; // المبلغ الظاهر (إجمالي الفاتورة/قيمة الدفعة)
  final bool isHeld;
  final SaleInvoice? invoice;
  final Payment? payment;
  final StatementReturn? ret;

  const _StatementEntry({
    required this.date,
    required this.typeOrder,
    required this.typeLabel,
    required this.delta,
    required this.displayAmount,
    this.refLabel,
    this.subtitle,
    this.isHeld = false,
    this.invoice,
    this.payment,
    this.ret,
  });
}

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  CustomerStatement? _statement;
  bool _isLoading = true;
  bool _isFetching = false;
  String? _errorMessage;
  String? _storeName;
  String? _storeLogoPath;

  @override
  void initState() {
    super.initState();
    _loadStatement(showInitialSpinner: true);
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

  /// طباعة كشف حساب العميل (بديل: مشاركة PDF إذا تعذرت الطباعة).
  Future<void> _printStatement() async {
    final st = _statement;
    if (st == null) return;
    try {
      await CustomerStatementPdf.printStatement(
        statement: st,
        storeName: _storeName,
        storeLogoPath: _storeLogoPath,
      );
    } catch (_) {
      if (!mounted) return;
      try {
        await CustomerStatementPdf.shareStatement(
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

  Future<void> _shareStatement() async {
    final st = _statement;
    if (st == null) return;
    try {
      await CustomerStatementPdf.shareStatement(
        statement: st,
        storeName: _storeName,
        storeLogoPath: _storeLogoPath,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('تعذر مشاركة كشف الحساب: $e'),
          ),
        );
      }
    }
  }

  Future<void> _loadStatement({bool showInitialSpinner = false}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (showInitialSpinner || _statement == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final repo = ref.read(customerRepositoryProvider);
      final statement = await repo.getCustomerStatement(widget.customerId);
      if (mounted) {
        setState(() {
          _statement = statement;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading customer statement: $e\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      _isFetching = false;
    }
  }

  /// يبني الحركات الموحّدة مرتبة زمنياً (الأقدم أول) ويحسب الرصيد الجاري،
  /// مطابقاً لقواعد الديون:
  /// - أي فاتورة (آجلة أو نقدية بدفع جزئي) يُضاف للمتبقي غير المسدد (total − paid).
  /// - تحصيل: يخصم المبلغ.
  /// - مرتجع: يخصم فقط ما خُصم فعلياً من دين العميل (debt_reduction)؛
  ///   الزائد سُلِّم نقداً ولا يؤثر على الحساب.
  List<_StatementEntry> _buildEntries() {
    final s = _statement!;
    final entries = <_StatementEntry>[];

    for (final inv in s.invoices) {
      final remaining = (inv.total - inv.paidAmount).clamp(
        0.0,
        double.infinity,
      );
      entries.add(
        _StatementEntry(
          date: inv.createdAt,
          typeOrder: 0,
          typeLabel: inv.status == 'held' ? 'فاتورة معلّقة' : 'فاتورة بيع',
          refLabel: inv.invoiceNumber,
          subtitle:
              'طريقة الدفع: ${inv.paymentMethodArabic}'
              '${inv.paidAmount > 0 ? ' • مدفوع: ${AppStrings.money(inv.paidAmount)}' : ''}',
          delta: remaining,
          displayAmount: inv.total,
          isHeld: inv.status == 'held',
          invoice: inv,
        ),
      );
    }

    for (final p in s.payments) {
      entries.add(
        _StatementEntry(
          date: p.createdAt,
          typeOrder: 2,
          typeLabel: 'تحصيل (دفعة)',
          subtitle: p.note != null && p.note!.isNotEmpty ? p.note : null,
          delta: -p.amount,
          displayAmount: p.amount,
          payment: p,
        ),
      );
    }

    for (final r in s.returns) {
      final isCashRefund = r.invoice.cashRefundOut > 0.001 && r.invoice.debtReduction <= 0.001;
      final returnVal = isCashRefund ? 0.0 : (r.invoice.debtReduction > 0.001 ? r.invoice.debtReduction : r.invoice.returnAmount);
      entries.add(
        _StatementEntry(
          date: r.invoice.createdAt,
          typeOrder: 1,
          typeLabel: 'مرتجع',
          subtitle: isCashRefund
              ? 'استرداد نقدي من الخزينة${r.invoice.reason != null && r.invoice.reason!.isNotEmpty ? " • ${r.invoice.reason}" : ""}'
              : r.invoice.reason,
          delta: -returnVal,
          displayAmount: r.invoice.returnAmount,
          ret: r,
        ),
      );
    }

    // الأقدم أول؛ وعند التسابيق الزمني: الفاتورة قبل المرتجع وقبل التحصيل
    // (لكي يُنشأ الدين قبل أن يُخصم).
    entries.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.typeOrder.compareTo(b.typeOrder);
    });

    final sumDeltas = entries.fold(0.0, (acc, e) => acc + e.delta);
    final openingBalance = s.customer.balanceDue - sumDeltas;
    if (openingBalance.abs() > 0.01) {
      entries.insert(
        0,
        _StatementEntry(
          date: s.customer.createdAt,
          typeOrder: -1,
          typeLabel: 'رصيد سابق / افتتاحي',
          refLabel: 'رصيد سابق',
          subtitle: 'ديون أو رصيد مدور سابق لتاريخ المعاملات المسجلة',
          delta: openingBalance,
          displayAmount: openingBalance.abs(),
        ),
      );
    }

    return entries;
  }

  void _showAddPaymentDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة سداد على الحساب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('العميل: ${_statement?.customer.name ?? ""}'),
              const SizedBox(height: 8),
              Text(
                'إجمالي الدين المستحق: ${AppStrings.money(_statement?.customer.balanceDue ?? 0.0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.DANGER_RED,
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
                  labelText: 'المبلغ المحصّل *',
                  suffixText: AppStrings.CURRENCY,
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  hintText: 'مثال: تحصيل من فاتورة...',
                ),
                maxLines: 2,
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
              final note = noteController.text.trim();

              Navigator.of(ctx).pop();
              final repo = ref.read(customerRepositoryProvider);
              try {
                await repo.addCustomerPayment(
                  customerId: widget.customerId,
                  amount: amount,
                  note: note.isEmpty ? null : note,
                  userId: ref.read(authProvider).user?.id,
                );

                // تحديث القوائم والإحصائيات لتنعكس الدفعة فوراً في كل الشاشات.
                refreshAfterPayment(ref);
                await _loadStatement();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      content: Text(
                        'تم تسجيل الدفعة وتخفيض رصيد المديونية بنجاح',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text('فشل تسجيل الدفعة: $e'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('تسجيل التحصيل'),
          ),
        ],
      ),
    );
  }

  /// إدارة موعد سداد المديونية: تحديد أو إزالة (لتنبيه تأخر السداد).
  Future<void> _manageDueDate() async {
    final c = _statement?.customer;
    if (c == null) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('موعد سداد المديونية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.hasDebt
                  ? 'المستحق على العميل حالياً: ${AppStrings.money(c.balanceDue)}'
                  : 'لا توجد مديونية مستحقة حالياً.',
            ),
            const SizedBox(height: 8),
            if (c.paymentDueDate != null)
              Text(
                'الموعد الحالي: ${DateFormat('d MMMM yyyy', 'ar').format(c.paymentDueDate!)}',
                style: const TextStyle(
                  color: AppColors.TEXT_SECONDARY,
                  fontSize: 13,
                ),
              )
            else
              const Text(
                'لم يُحدد موعد بعد. سيُنبّه التطبيق عند تأخر العميل عن الموعد.',
                style: TextStyle(color: AppColors.TEXT_SECONDARY, fontSize: 13),
              ),
          ],
        ),
        actions: [
          if (c.paymentDueDate != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('clear'),
              child: const Text('إزالة الموعد'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('pick'),
            child: const Text('تحديد موعد'),
          ),
        ],
      ),
    );

    if (action == 'clear') {
      await _applyDueDate(null);
      return;
    }
    if (action != 'pick' || !mounted) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          c.paymentDueDate ?? DateTime(now.year, now.month, now.day + 7),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      helpText: 'اختر موعد السداد',
      cancelText: 'إلغاء',
      confirmText: 'حفظ',
    );
    if (picked != null) {
      await _applyDueDate(picked);
    }
  }

  Future<void> _applyDueDate(DateTime? dueDate) async {
    try {
      await ref
          .read(customerRepositoryProvider)
          .updateCustomerPaymentDueDate(widget.customerId, dueDate);
      refreshAfterCustomerChange(ref);
      await _loadStatement();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.SUCCESS_GREEN,
          content: Text(
            dueDate == null
                ? 'تمت إزالة موعد السداد'
                : 'تم تحديد موعد السداد: ${DateFormat('d MMMM yyyy', 'ar').format(dueDate)}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل التحديث: $e'),
          ),
        );
      }
    }
  }

  Future<void> _sendWhatsAppReminder() async {
    final c = _statement?.customer;
    if (c == null) return;
    if (c.phone == null || c.phone!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف مسجل لهذا العميل لإرسال تذكير عبر واتساب'),
        ),
      );
      return;
    }

    try {
      final opened = await WhatsAppReminderService.sendDebtReminder(
        customerName: c.name,
        phone: c.phone!,
        balanceDue: c.balanceDue,
      );
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر فتح تطبيق واتساب. تأكد من تثبيت التطبيق أو توفر متصفح.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  /// عرض تفاصيل الفاتورة الكاملة (الأصناف، الكميات، الإجمالي، الطباعة) عند الضغط.
  Future<void> _showInvoiceDetails(SaleInvoice invoice) async {
    final repo = ref.read(saleRepositoryProvider);
    final fullInvoice = await repo.getSaleInvoiceWithItems(invoice.id);
    if (!mounted) return;

    if (fullInvoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على تفاصيل الفاتورة')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => ReceiptDialog(invoice: fullInvoice),
    );
  }

  /// تأكيد وإلغاء فاتورة بيع من كشف الحساب للأدمن
  void _confirmCancelSaleFromStatement(SaleInvoice invoice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء الفاتورة'),
        content: Text(
          'هل أنت متأكد من رغبتك في إلغاء الفاتورة رقم (${invoice.invoiceNumber})؟\nسيتم إعادة كميات المنتجات إلى المخزن وتحديث رصيد العميل تلقائيًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final repo = ref.read(saleRepositoryProvider);
              final userId = ref.read(authProvider).user?.id;
              try {
                await repo.cancelSaleInvoice(invoice.id, userId: userId);
                refreshAfterSale(ref);
                await _loadStatement();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      content: Text('تم إلغاء الفاتورة وتحديث رصيد العميل بنجاح'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
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

  /// عرض دفعة تحصيل عند الضغط عليها من كشف الحساب.
  void _showPaymentDetails(Payment p) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل الدفعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المبلغ: ${AppStrings.money(p.amount)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.SUCCESS_GREEN,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'التاريخ: ${dateFormat.format(p.createdAt)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.TEXT_SECONDARY,
              ),
            ),
            if (p.note != null && p.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'ملاحظة: ${p.note}',
                style: const TextStyle(
                  fontSize: 13,
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

  /// عرض أصناف المرتجع عند الضغط عليه من كشف الحساب.
  Future<void> _showReturnDetails(StatementReturn r) async {
    final ret = r.invoice;
    final repo = ref.read(returnRepositoryProvider);
    final items = await repo.getReturnItems(ret.id);
    if (!mounted) return;

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل المرتجع'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'القيمة الإجمالية: ${AppStrings.money(ret.returnAmount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.WARNING_AMBER,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'التاريخ: ${dateFormat.format(ret.createdAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
              if (r.invoice.debtReduction > 0.01 ||
                  r.invoice.cashRefundOut > 0.01) ...[
                const SizedBox(height: 4),
                Text(
                  'التسوية: ${AppStrings.money(r.invoice.debtReduction)} خصم من الحساب'
                  '${r.invoice.cashRefundOut > 0.01 ? ' + ${AppStrings.money(r.invoice.cashRefundOut)} سُلِّمت نقداً' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
              if (ret.reason != null && ret.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'السبب: ${ret.reason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'الأصناف المرتجعة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text(
                  'لا توجد أصناف مسجلة لهذا المرتجع',
                  style: TextStyle(color: AppColors.TEXT_SECONDARY),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, thickness: 0.5),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.productName,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${item.quantity} × ${AppStrings.money(item.unitPrice)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppStrings.money(item.lineTotal),
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

  @override
  Widget build(BuildContext context) {
    // استماع تلقائي لأي تغيير في بيانات العملاء أو المبيعات أو الدفعات لإعادة التحميل فوراً
    ref.listen(customersListProvider, (_, _) => _loadStatement());
    ref.listen(salesHistoryProvider, (_, _) => _loadStatement());
    ref.listen(paymentsProvider, (_, _) => _loadStatement());

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('كشف حساب العميل')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('كشف حساب العميل')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.DANGER_RED),
              const SizedBox(height: 12),
              const Text(
                'تعذر تحميل كشف الحساب',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStatement,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_statement == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('كشف حساب العميل')),
        body: const Center(child: Text('العميل غير موجود')),
      );
    }

    final c = _statement!.customer;
    final hasDebt = c.hasDebt;
    final hasCredit = c.hasCredit;
    // عامل تكبير حسب عرض المحتوى: يكبّر كشف الحساب على التابلت بوضوح.
    final scale = ResponsiveScope.scaleOf(context);

    // الحركات الموحّدة والرصيد الجاري (يُعاد البناء عند كل تحميل).
    final entries = _buildEntries();
    var running = 0.0;
    final runningBalances = <double>[
      for (final e in entries) (running += e.delta),
    ];

    return Scaffold(
       appBar: AppBar(
         title: Text(
           'كشف حساب: ${c.name}',
         ),
         actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareStatement,
            tooltip: 'مشاركة كشف الحساب كصورة',
          ),
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
              // 1. بطاقة العميل ومعلومات الاتصال والإجراءات المنسقة
              Container(
                padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor:
                              AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
                          child: const Icon(
                            Icons.person,
                            size: 32,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.name,
                              style: TextStyle(
                                fontSize: 20 * scale,
                                fontWeight: FontWeight.bold,
                                color: AppColors.PRIMARY_BLUE_DARK,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (c.phone != null && c.phone!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.phone,
                                          size: 14,
                                          color: AppColors.TEXT_SECONDARY,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          c.phone!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.TEXT_SECONDARY,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (c.address != null && c.address!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          size: 14,
                                          color: AppColors.TEXT_SECONDARY,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          c.address!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.TEXT_SECONDARY,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (c.paymentDueDate != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.isOverdue
                                          ? AppColors.DANGER_RED.withValues(alpha: 0.1)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: c.isOverdue
                                          ? Border.all(
                                              color: AppColors.DANGER_RED.withValues(alpha: 0.4),
                                              width: 0.8,
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.event,
                                          size: 14,
                                          color: c.isOverdue
                                              ? AppColors.DANGER_RED
                                              : AppColors.TEXT_SECONDARY,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'موعد السداد: ${DateFormat('d MMMM yyyy', 'ar').format(c.paymentDueDate!)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.isOverdue
                                                ? AppColors.DANGER_RED
                                                : AppColors.TEXT_SECONDARY,
                                            fontWeight: c.isOverdue
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (c.isOverdue)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.DANGER_RED.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'متأخر عن السداد',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.DANGER_RED,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (c.notes != null && c.notes!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'ملاحظات: ${c.notes!}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.TEXT_SECONDARY,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                    // أزرار الإجراءات للعميل
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.PRIMARY_BLUE,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _showAddPaymentDialog,
                          icon: const Icon(Icons.payment, size: 18),
                          label: const Text(
                            'تسجيل دفعة سداد',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.PRIMARY_BLUE,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: BorderSide(
                              color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.5),
                            ),
                          ),
                          onPressed: _manageDueDate,
                          icon: const Icon(Icons.event, size: 18),
                          label: const Text(
                            'موعد السداد',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (hasDebt && c.phone != null && c.phone!.isNotEmpty)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF25D366),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              side: const BorderSide(
                                color: Color(0xFF25D366),
                                width: 1.2,
                              ),
                            ),
                            onPressed: _sendWhatsAppReminder,
                            icon: const Icon(Icons.chat_outlined, size: 18),
                            label: const Text(
                              'تذكير واتساب',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // لافتة التنبيه عند التأخر عن موعد السداد
              if (c.isOverdue) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.DANGER_RED.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    border: Border.all(
                      color: AppColors.DANGER_RED.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.DANGER_RED,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'تنبيه: العميل متأخر عن موعد السداد (${DateFormat('d MMMM yyyy', 'ar').format(c.paymentDueDate!)}) والمستحق عليه حالياً: ${AppStrings.money(c.balanceDue)}.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.DANGER_RED,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // 2. بطاقات المؤشرات المالية الأربعة (KPIs)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 720;
                  final cards = [
                    _buildKpiCard(
                      title: 'إجمالي المبيعات',
                      value: AppStrings.money(_statement!.totalSales),
                      icon: Icons.point_of_sale_rounded,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                    _buildKpiCard(
                      title: 'إجمالي التحصيلات (المسدد)',
                      value: AppStrings.money(_statement!.totalPayments),
                      icon: Icons.payments_outlined,
                      color: AppColors.SUCCESS_GREEN,
                    ),
                    _buildKpiCard(
                      title: 'إجمالي المرتجعات',
                      value: AppStrings.money(_statement!.totalReturns),
                      icon: Icons.assignment_return_outlined,
                      color: AppColors.WARNING_AMBER,
                    ),
                    _buildKpiCard(
                      title: hasDebt
                          ? 'الرصيد المستحق (المديونية)'
                          : hasCredit
                          ? 'رصيد مسبق للعميل'
                          : 'حالة الحساب',
                      value: hasDebt
                          ? AppStrings.money(c.balanceDue)
                          : hasCredit
                          ? AppStrings.money(-c.balanceDue)
                          : 'خالص (0.00)',
                      icon: Icons.account_balance_wallet_outlined,
                      color: hasDebt
                          ? AppColors.DANGER_RED
                          : hasCredit
                          ? AppColors.WARNING_AMBER
                          : AppColors.SUCCESS_GREEN,
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      children: cards
                          .map(
                            (card) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: card,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  } else {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 8),
                            Expanded(child: cards[1]),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: cards[2]),
                            const SizedBox(width: 8),
                            Expanded(child: cards[3]),
                          ],
                        ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 22),

              // 3. ترويسة سجل كشف الحساب
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سجل المعاملات وحركات الحساب (${entries.length})',
                        style: const TextStyle(
                          fontSize: AppTypography.HEADING_3,
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE_DARK,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'كافة الفواتير والتحصيلات والمرتجعات مع الرصيد التراكمي المتبقي بعد كل حركة',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 4. قائمة بطاقات الحركات المنفصلة (بدون أي اقتصاص للكلمات أو الأرقام)
              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Center(
                    child: Text(
                      'لا توجد حركات مسجلة لهذا العميل بعد',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    final balanceAfter = runningBalances[index];
                    return _buildLedgerCard(e, balanceAfter, dateFormat);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerCard(
    _StatementEntry e,
    double balanceAfter,
    DateFormat dateFormat,
  ) {
    final isInvoice = e.invoice != null;
    final isPayment = e.payment != null;
    final isReturn = e.ret != null;
    final isOpening = e.typeOrder == -1;
    final isAdmin = ref.watch(isAdminProvider);

    Color cardColor;
    IconData iconData;
    String typeLabel;
    Color amountColor;
    String amountSign;

    if (isOpening) {
      cardColor = Colors.purple;
      iconData = Icons.account_balance_outlined;
      typeLabel = 'رصيد سابق / افتتاحي';
      amountColor = Colors.purple.shade700;
      amountSign = e.delta >= 0 ? '+' : '−';
    } else if (isInvoice) {
      cardColor = AppColors.PRIMARY_BLUE;
      iconData = e.isHeld ? Icons.schedule_rounded : Icons.receipt_long_outlined;
      typeLabel = e.isHeld ? 'فاتورة بيع معلّقة' : 'فاتورة مبيعات';
      amountColor = AppColors.PRIMARY_BLUE_DARK;
      amountSign = '+';
    } else if (isPayment) {
      cardColor = AppColors.SUCCESS_GREEN;
      iconData = Icons.payments_outlined;
      typeLabel = 'تحصيل دفعة سداد';
      amountColor = AppColors.SUCCESS_GREEN;
      amountSign = '−';
    } else if (isReturn) {
      cardColor = AppColors.WARNING_AMBER;
      iconData = Icons.assignment_return_outlined;
      typeLabel = 'مرتجع مبيعات';
      amountColor = Colors.orange.shade800;
      amountSign = '−';
    } else {
      cardColor = AppColors.TEXT_SECONDARY;
      iconData = Icons.swap_horiz;
      typeLabel = e.typeLabel;
      amountColor = AppColors.TEXT_PRIMARY;
      amountSign = e.delta >= 0 ? '+' : '−';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(
          color: cardColor.withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف العلوي: شارة نوع الحركة + رقم المرجع + التاريخ + المبلغ كاملاً
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconData, size: 14, color: cardColor),
                    const SizedBox(width: 5),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (e.refLabel != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '#${e.refLabel}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Text(
                dateFormat.format(e.date),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
              const Spacer(),
              Text(
                '$amountSign ${AppStrings.money(e.displayAmount)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),

          // الوصف والملاحظات بدون اقتصاص
          if (e.subtitle != null && e.subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                e.subtitle!,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.TEXT_PRIMARY,
                ),
                softWrap: true,
              ),
            )
          else
            const SizedBox(height: 8),

          const Divider(height: 1, thickness: 0.6),
          const SizedBox(height: 8),

          // الصف السفلي: الرصيد التراكمي + أزرار الإجراءات
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: balanceAfter > 0.005
                      ? AppColors.DANGER_RED.withValues(alpha: 0.08)
                      : balanceAfter < -0.005
                      ? AppColors.WARNING_AMBER.withValues(alpha: 0.1)
                      : AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: balanceAfter > 0.005
                        ? AppColors.DANGER_RED.withValues(alpha: 0.25)
                        : balanceAfter < -0.005
                        ? AppColors.WARNING_AMBER.withValues(alpha: 0.3)
                        : AppColors.SUCCESS_GREEN.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      balanceAfter > 0.005
                          ? 'الرصيد بعد الحركة (مديونية): '
                          : balanceAfter < -0.005
                          ? 'الرصيد بعد الحركة (دائن): '
                          : 'الرصيد بعد الحركة: ',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    Text(
                      AppStrings.money(balanceAfter.abs()),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: balanceAfter > 0.005
                            ? AppColors.DANGER_RED
                            : balanceAfter < -0.005
                            ? AppColors.WARNING_AMBER
                            : AppColors.SUCCESS_GREEN,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isInvoice && e.invoice != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _showInvoiceDetails(e.invoice!),
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: const Text(
                    'تفاصيل الفاتورة',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (isAdmin && e.invoice!.status != 'cancelled') ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.DANGER_RED,
                      size: 18,
                    ),
                    tooltip: 'إلغاء الفاتورة (للأدمن)',
                    onPressed: () =>
                        _confirmCancelSaleFromStatement(e.invoice!),
                  ),
                ],
              ] else if (isPayment && e.payment != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _showPaymentDetails(e.payment!),
                  icon: const Icon(Icons.info_outline, size: 15),
                  label: const Text(
                    'تفاصيل الدفعة',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else if (isReturn && e.ret != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _showReturnDetails(e.ret!),
                  icon: const Icon(Icons.assignment_return_outlined, size: 15),
                  label: const Text(
                    'تفاصيل المرتجع',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
