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

   void _showProductSearchDialog() {
     showDialog(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('بحث عن منتج'),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             TextField(
               decoration: const InputDecoration(
                 labelText: 'ابحث باسم المنتج',
                 prefixIcon: Icon(Icons.search),
               ),
               onChanged: (val) {
                 ref.read(searchQueryProvider.notifier).setQuery(val);
               },
             ),
             const SizedBox(height: 8),
             Expanded(
               child: ref.watch(productListProvider).when(
                 data: (products) {
                   final query = ref.watch(searchQueryProvider);
                   final filtered = query.isEmpty
                       ? products
                       : products.where((p) =>
                           p.name.toLowerCase().contains(query.toLowerCase())).toList();
                   return ListView.builder(
                     itemCount: filtered.length,
                     itemBuilder: (context, index) {
                       final product = filtered[index];
                       return ListTile(
                         title: Text(product.name),
                         subtitle: Text(
                             '${product.quantity} ${product.unit} • سعر الشراء: ${AppStrings.money(product.purchasePrice)}'),
                         onTap: () {
                           Navigator.of(ctx).pop();
                           setState(() {
                             _selectedProduct = product;
                             _unitCostController.text = product.purchasePrice.toString();
                           });
                         },
                       );
                     },
                   );
                 },
                 loading: () => const Center(child: CircularProgressIndicator()),
                 error: (e, _) => Center(child: Text('خطأ: $e')),
               ),
             ),
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
    final productsAsync = ref.watch(productListProvider);

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
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                     // Product Dropdown with Search Button
                     Expanded(
                       flex: 4,
                       child: Row(
                         children: [
                           Expanded(
                             child: productsAsync.when(
                               data: (products) {
                                 return DropdownButtonFormField<Product>(
                                   initialValue: _selectedProduct,
                                   decoration: const InputDecoration(
                                     labelText: 'اختر المنتج *',
                                     prefixIcon: Icon(Icons.inventory_2_outlined),
                                   ),
                                   items: products.map((p) {
                                     return DropdownMenuItem(
                                       value: p,
                                       child: Text(
                                         '${p.name} (حالي: ${p.quantity} ${p.unit})',
                                       ),
                                     );
                                   }).toList(),
                                   onChanged: (p) {
                                     setState(() {
                                       _selectedProduct = p;
                                       if (p != null) {
                                         _unitCostController.text = p.purchasePrice
                                             .toString();
                                       }
                                     });
                                   },
                                 );
                               },
                               loading: () => const SizedBox.shrink(),
                               error: (_, _) => const Text('تعذر تحميل المنتجات'),
                             ),
                           ),
                           const SizedBox(width: 8),
                           IconButton(
                             icon: const Icon(Icons.search),
                             tooltip: 'بحث عن منتج',
                             onPressed: _showProductSearchDialog,
                           ),
                         ],
                       ),
                     ),
                    const SizedBox(width: 12),

                    // Quantity
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الكمية *',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Unit Cost
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _unitCostController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سعر الشراء *',
                          suffixText: AppStrings.CURRENCY,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Add Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'),
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
