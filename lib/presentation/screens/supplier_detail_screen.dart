import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/payment.dart';
import '../../data/models/purchase_invoice.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/purchase_return_repository.dart';
import '../../data/repositories/shop_profile_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';
import '../widgets/supplier_statement_pdf.dart';
import 'purchase_form_screen.dart';

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
  bool _isFetching = false;
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

  Future<void> _loadStatement({bool showInitialSpinner = false}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (showInitialSpinner || _statement == null) {
      setState(() => _isLoading = true);
    }
    try {
      final repo = ref.read(supplierRepositoryProvider);
      final statement = await repo.getSupplierStatement(widget.supplierId);
      if (mounted) {
        setState(() {
          _statement = statement;
          _isLoading = false;
        });
      }
    } finally {
      _isFetching = false;
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

  Future<void> _shareStatement() async {
    final st = _statement;
    if (st == null) return;
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
            content: Text('تعذر مشاركة كشف الحساب: $e'),
          ),
        );
      }
    }
  }

  Future<void> _deletePurchaseFromStatement(PurchaseInvoice inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف فاتورة الشراء'),
        content: Text(
          'هل أنت متأكد من حذف فاتورة الشراء بقيمة ${AppStrings.money(inv.total)}؟\n\n'
          'تنبيه: سيتم عكس كميات الأصناف المضافة للمخزن وخصم مديونية الفاتورة من كشف حساب المورد فوراً.',
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

    if (confirmed == true && mounted) {
      final repo = ref.read(purchaseRepositoryProvider);
      await repo.deletePurchaseInvoice(
        inv.id,
        userId: ref.read(authProvider).user?.id,
      );
      refreshAfterPurchase(ref);
      await _loadStatement();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم حذف فاتورة الشراء وعكس المخزون ورصيد الحساب بنجاح'),
          ),
        );
      }
    }
  }

  Future<void> _editPurchaseFromStatement(PurchaseInvoice inv) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseFormScreen(purchaseToEdit: inv),
      ),
    );
    await _loadStatement();
  }

  /// فتح بيان فاتورة شراء: عرض أصنافها بالكامل وإتاحة التعديل والحذف للأدمن
  void _openPurchaseDetails(String purchaseInvoiceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل بيان: فاتورة شراء وتوريد'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<PurchaseInvoice?>(
            future: PurchaseRepository().getPurchaseInvoiceWithItems(
              purchaseInvoiceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(),
                  ),
                );
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
              final isAdmin = ref.read(isAdminProvider);

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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: inv.remainingOwed > 0
                              ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                              : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          inv.remainingOwed > 0
                              ? 'المتبقي: ${AppStrings.money(inv.remainingOwed)}'
                              : 'خالصة بالكامل',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: inv.remainingOwed > 0
                                ? AppColors.WARNING_AMBER
                                : AppColors.SUCCESS_GREEN,
                          ),
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
                      'الأصناف المشتراة:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    item.productName ?? 'منتج',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${item.quantity} × ${AppStrings.money(item.unitCost)}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    AppStrings.money(item.lineTotal),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.PRIMARY_BLUE_DARK,
                                    ),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'إجمالي الفاتورة (مجموع أسعار الشراء):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        Text(
                          AppStrings.money(inv.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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
                          'المسدد نقداً:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          AppStrings.money(inv.paidAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppColors.SUCCESS_GREEN,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (isAdmin) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.DANGER_RED,
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _deletePurchaseFromStatement(inv);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('حذف الفاتورة'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.PRIMARY_BLUE,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _editPurchaseFromStatement(inv);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('تعديل الفاتورة'),
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

  /// فتح بيان مرتجع مشتريات: عرض تفاصيل الأصناف المرتجعة والمبلغ.
  void _openReturnDetails(String returnId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل بيان: مرتجع مشتريات'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<DetailedPurchaseReturn?>(
            future: PurchaseReturnRepository().getPurchaseReturnWithItems(
              returnId,
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
              final ret = snapshot.data;
              if (ret == null) {
                return const Text('لم يتم العثور على المرتجع');
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
                        'التاريخ: ${dateFormat.format(ret.invoice.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                      Text(
                        'المبلغ: ${AppStrings.money(ret.invoice.returnAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.WARNING_AMBER,
                        ),
                      ),
                    ],
                  ),
                  if (ret.invoice.reason != null &&
                      ret.invoice.reason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'السبب: ${ret.invoice.reason}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (ret.items.isEmpty)
                    const Text(
                      'لا توجد أصناف مسجلة على هذا المرتجع',
                      style: TextStyle(color: AppColors.TEXT_SECONDARY),
                    )
                  else ...[
                    const Text(
                      'الأصناف المرتجعة:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: ret.items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
                          final item = ret.items[index];
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
                                  '${item.quantity} × ${item.unitCost.toStringAsFixed(0)}',
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

  void _showAddPaymentDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة سداد للمورد'),
        content: SingleChildScrollView(
          child: Column(
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

              refreshAfterPayment(ref);
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
    // استماع تلقائي لأي تحديث في الموردين أو المشتريات أو الدفعات لإعادة التحميل فوراً
    ref.listen(suppliersListProvider, (_, _) => _loadStatement());
    ref.listen(purchasesListProvider, (_, _) => _loadStatement());
    ref.listen(paymentsProvider, (_, _) => _loadStatement());

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
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. بطاقة معلومات المورد العلوية
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
                            Icons.local_shipping_rounded,
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
                              s.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.PRIMARY_BLUE_DARK,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                if (s.phone != null && s.phone!.isNotEmpty)
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
                                          s.phone!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.TEXT_SECONDARY,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (s.address != null && s.address!.isNotEmpty)
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
                                          s.address!,
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
                      ],
                    ),

                    // زر تسجيل سداد دفعة للمورد
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
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. بطاقات المؤشرات المالية الأربعة (KPIs) بشكل منسق ومستقل تماماً
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 720;
                  final cards = [
                    _buildKpiCard(
                      title: 'إجمالي المشتريات',
                      value: AppStrings.money(_statement!.totalPurchases),
                      icon: Icons.inventory_2_outlined,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                    _buildKpiCard(
                      title: 'إجمالي المسدد',
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
                      title: hasOwed ? 'الرصيد المستحق الحالي' : 'حالة الحساب',
                      value: hasOwed
                          ? AppStrings.money(s.balanceOwed)
                          : 'خالص (0.00)',
                      icon: Icons.account_balance_wallet_outlined,
                      color: hasOwed
                          ? AppColors.DANGER_RED
                          : AppColors.SUCCESS_GREEN,
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      children: cards
                          .map(
                            (c) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: c,
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
                        'كافة الفواتير والدفعات والمرتجعات مع الرصيد التراكمي المتبقي بعد كل حركة',
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
                      'لا توجد عمليات مسجلة لهذا المورد بعد',
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
                    return _buildLedgerCard(e, dateFormat);
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

  Widget _buildLedgerCard(StatementEntry e, DateFormat dateFormat) {
    final isPurchase = e.isPurchase;
    final isReturn = e.isReturn;
    final isOpening = e.referenceId == 'opening_balance';
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
      amountSign = isPurchase ? '+' : '−';
    } else if (isPurchase) {
      cardColor = AppColors.PRIMARY_BLUE;
      iconData = Icons.inventory_2_outlined;
      typeLabel = 'فاتورة شراء وتوريد';
      amountColor = AppColors.PRIMARY_BLUE_DARK;
      amountSign = '+';
    } else if (isReturn) {
      cardColor = AppColors.WARNING_AMBER;
      iconData = Icons.assignment_return_outlined;
      typeLabel = 'مرتجع مشتريات';
      amountColor = Colors.orange.shade800;
      amountSign = '−';
    } else {
      cardColor = AppColors.SUCCESS_GREEN;
      iconData = Icons.payments_outlined;
      typeLabel = 'سداد دفعة للمورد';
      amountColor = AppColors.SUCCESS_GREEN;
      amountSign = '−';
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
          // الصف العلوي: شارة نوع العملية + التاريخ + المبلغ كاملاً
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
                '$amountSign ${AppStrings.money(e.amount)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),

          // الوصف والملاحظات بدون اقتصاص
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              e.title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.TEXT_PRIMARY,
              ),
              softWrap: true,
            ),
          ),

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
                  color: e.runningBalance > 0.005
                      ? AppColors.WARNING_AMBER.withValues(alpha: 0.1)
                      : AppColors.SUCCESS_GREEN.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: e.runningBalance > 0.005
                        ? AppColors.WARNING_AMBER.withValues(alpha: 0.3)
                        : AppColors.SUCCESS_GREEN.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'الرصيد بعد الحركة: ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    Text(
                      AppStrings.money(e.runningBalance),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: e.runningBalance > 0.005
                            ? AppColors.WARNING_AMBER
                            : AppColors.SUCCESS_GREEN,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isPurchase) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _openPurchaseDetails(e.referenceId),
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: const Text(
                    'تفاصيل الفاتورة',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'تعديل الفاتورة (للأدمن)',
                    onPressed: () async {
                      final repo = ref.read(purchaseRepositoryProvider);
                      final inv =
                          await repo.getPurchaseInvoiceWithItems(e.referenceId);
                      if (inv != null && mounted) {
                        _editPurchaseFromStatement(inv);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.DANGER_RED,
                      size: 18,
                    ),
                    tooltip: 'حذف الفاتورة (للأدمن)',
                    onPressed: () async {
                      final repo = ref.read(purchaseRepositoryProvider);
                      final inv =
                          await repo.getPurchaseInvoiceWithItems(e.referenceId);
                      if (inv != null && mounted) {
                        _deletePurchaseFromStatement(inv);
                      }
                    },
                  ),
                ],
              ] else if (isReturn) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _openReturnDetails(e.referenceId),
                  icon: const Icon(Icons.assignment_return_outlined, size: 15),
                  label: const Text(
                    'تفاصيل المرتجع',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else if (!isOpening) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => _openPaymentDetails(e.referenceId),
                  icon: const Icon(Icons.payments_outlined, size: 15),
                  label: const Text(
                    'تفاصيل السداد',
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
