import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:alnokrashy_pos/core/constants/app_constants.dart';

import '../../data/models/product.dart';
import '../../data/models/purchase_invoice.dart';
import '../../data/models/purchase_invoice_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/product_search_dialog.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  String? _selectedSupplierId;
  final List<PurchaseInvoiceItem> _items = [];

  // Item inputs
  Product? _selectedProduct;
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController _unitCostController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    _unitCostController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (sum, item) => sum + item.lineTotal);
  double get _tax => _subtotal * AppStrings.TAX_RATE;
  double get _totalWithTax => _subtotal + _tax;
  double get _paidAmount =>
      double.tryParse(_paidAmountController.text.trim()) ?? 0.0;
  double get _remainingOwed =>
      (_totalWithTax - _paidAmount).clamp(0.0, double.infinity);

  void _addItem() {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار المنتج أولاً')));
      return;
    }

    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;
    final cost = double.tryParse(_unitCostController.text.trim()) ?? 0.0;

    if (qty <= 0 || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كمية وسعر شراء صحيحين')),
      );
      return;
    }

    setState(() {
      _items.add(
        PurchaseInvoiceItem(
          id: const Uuid().v4(),
          invoiceId: '', // set on save
          productId: _selectedProduct!.id,
          quantity: qty,
          unitCost: cost,
          lineTotal: qty * cost,
          productName: _selectedProduct!.name,
        ),
      );

      _selectedProduct = null;
      _quantityController.text = '1';
      _unitCostController.clear();
    });
  }

   void _removeItem(int index) {
     setState(() {
       _items.removeAt(index);
     });
   }

   Future<void> _showProductSearchDialog() async {
    final product = await ProductSearchDialog.show(context);
    if (product != null && mounted) {
      setState(() {
        _selectedProduct = product;
        _unitCostController.text = product.purchasePrice.toString();
        if (_quantityController.text.trim().isEmpty ||
            _quantityController.text.trim() == '0') {
          _quantityController.text = '1';
        }
      });
    }
  }

  Future<void> _savePurchase() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('يرجى اختيار المورد')));
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة صنف واحد على الأقل للفاتورة')),
      );
      return;
    }

    final repo = ref.read(purchaseRepositoryProvider);
    final invoiceId = const Uuid().v4();
    final now = DateTime.now();

    final preparedItems = _items.map((item) {
      return item.copyWith(invoiceId: invoiceId);
    }).toList();

    final invoice = PurchaseInvoice(
      id: invoiceId,
      supplierId: _selectedSupplierId!,
      items: preparedItems,
      total: _totalWithTax,
      tax: _tax,
      paidAmount: _paidAmount,
      createdAt: now,
    );

    await repo.createPurchaseInvoice(
      invoice: invoice,
      items: preparedItems,
      userId: ref.read(authProvider).user?.id,
    );

    // Refresh affected providers
    ref.invalidate(purchasesListProvider);
    ref.invalidate(productListProvider);
    ref.invalidate(stockAlertsProvider);
    ref.invalidate(lowStockCountProvider);
    ref.invalidate(suppliersListProvider);
    // الدفعة للمورد والبضاعة الواردة تظهر في لوحة القيادة وسجل المدفوعات.
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(paymentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.SUCCESS_GREEN,
          content: Text(
            'تم تسجيل فاتورة الشراء وتحديث كميات وأسعار المخزون بنجاح',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل فاتورة شراء وتوريد بضاعة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 840),
            padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
            decoration: BoxDecoration(
              color: AppColors.NEUTRAL_SURFACE,
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Supplier Selector
                const Text(
                  'بيانات المورد والفاتورة',
                  style: TextStyle(
                    fontSize: AppTypography.HEADING_3,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                const SizedBox(height: 16),

                suppliersAsync.when(
                  data: (suppliers) {
                    if (_selectedSupplierId == null && suppliers.isNotEmpty) {
                      _selectedSupplierId = suppliers.first.id;
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'المورد / الشركة *',
                        prefixIcon: Icon(Icons.business),
                      ),
                      items: suppliers.map((s) {
                        return DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.name} ${s.phone != null ? "(${s.phone})" : ""}',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedSupplierId = val);
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('تعذر تحميل قائمة الموردين'),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Add Items Section
                const Text(
                  'إضافة أصناف مشتراة للمخزن',
                  style: TextStyle(
                    fontSize: AppTypography.HEADING_3,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                const SizedBox(height: 14),

                // Product Selection Box
                if (_selectedProduct == null)
                  InkWell(
                    onTap: _showProductSearchDialog,
                    borderRadius:
                        BorderRadius.circular(AppLayout.BORDER_RADIUS),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.04),
                        borderRadius:
                            BorderRadius.circular(AppLayout.BORDER_RADIUS),
                        border: Border.all(
                          color:
                              AppColors.PRIMARY_BLUE.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            color: AppColors.PRIMARY_BLUE,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'اضغط للبحث عن صنف بالاسم، الباركود أو التصنيف...',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.PRIMARY_BLUE_DARK,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'يمكنك البحث في كامل المخزن أو إضافة صنف جديد على الفور',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.PRIMARY_BLUE,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            onPressed: _showProductSearchDialog,
                            icon: const Icon(Icons.manage_search, size: 20),
                            label: const Text('بحث واختيار'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      border: Border.all(
                        color: AppColors.PRIMARY_BLUE,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AppColors.PRIMARY_BLUE.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.inventory_2,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedProduct!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.5,
                                  color: AppColors.PRIMARY_BLUE_DARK,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 14,
                                runSpacing: 4,
                                children: [
                                  if (_selectedProduct!.barcode != null &&
                                      _selectedProduct!.barcode!.isNotEmpty)
                                    Text(
                                      'الباركود: ${_selectedProduct!.barcode}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.TEXT_SECONDARY,
                                      ),
                                    ),
                                  Text(
                                    'الرصيد الحالي: ${_selectedProduct!.quantity} ${_selectedProduct!.unit}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                  ),
                                  Text(
                                    'سعر الشراء المسجل: ${AppStrings.money(_selectedProduct!.purchasePrice)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.PRIMARY_BLUE,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: _showProductSearchDialog,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text(
                            'تغيير',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.DANGER_RED,
                          ),
                          tooltip: 'إلغاء التحديد',
                          onPressed: () {
                            setState(() {
                              _selectedProduct = null;
                              _unitCostController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // Row of Quantity, Unit Cost, and Add Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Quantity
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'الكمية الواردة *',
                          suffixText: _selectedProduct?.unit ?? 'وحدة',
                          prefixIcon: const Icon(Icons.numbers),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Unit Cost
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _unitCostController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سعر الشراء للوحدة *',
                          suffixText: AppStrings.CURRENCY,
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Add Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        backgroundColor: AppColors.SUCCESS_GREEN,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text(
                        'إضافة للفاتورة',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Items Table
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(
                      AppLayout.BORDER_RADIUS,
                    ),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: _items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'لم يتم إضافة أصناف حتى الآن. اختر منتجاً وأضفه للفاتورة أعلاه.',
                              style: TextStyle(color: AppColors.TEXT_SECONDARY),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.5),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              title: Text(
                                item.productName ?? 'منتج',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'الكمية: ${item.quantity} • سعر الوحدة: ${AppStrings.money(item.unitCost)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    AppStrings.money(item.lineTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.DANGER_RED,
                                    ),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Financial Summary
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            AppLayout.BORDER_RADIUS,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إجمالي الفاتورة',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppStrings.money(_totalWithTax),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.PRIMARY_BLUE,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Paid Amount
                    Expanded(
                      child: TextField(
                        controller: _paidAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المدفوع كاش للمورد',
                          suffixText: AppStrings.CURRENCY,
                          prefixIcon: Icon(Icons.payment),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Remaining to Supplier
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _remainingOwed > 0
                              ? AppColors.WARNING_AMBER.withValues(alpha: 0.12)
                              : AppColors.SUCCESS_GREEN.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppLayout.BORDER_RADIUS,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _remainingOwed > 0
                                  ? 'المتبقي للمورد (آجل)'
                                  : 'حالة السداد',
                              style: TextStyle(
                                fontSize: 13,
                                color: _remainingOwed > 0
                                    ? AppColors.WARNING_AMBER
                                    : AppColors.SUCCESS_GREEN,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _remainingOwed > 0
                                  ? AppStrings.money(_remainingOwed)
                                  : 'مدفوع بالكامل',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _remainingOwed > 0
                                    ? AppColors.WARNING_AMBER
                                    : AppColors.SUCCESS_GREEN,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Submit Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.SUCCESS_GREEN,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                      onPressed: _savePurchase,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text(
                        'حفظ الفاتورة وتحديث المخزون',
                        style: TextStyle(
                          fontSize: 16,
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
      ),
    );
  }
}
