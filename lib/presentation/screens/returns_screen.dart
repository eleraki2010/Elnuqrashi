import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/purchase_invoice.dart';
import '../../data/models/purchase_invoice_item.dart';
import '../../data/models/purchase_return_invoice.dart';
import '../../data/models/return_invoice.dart';
import '../../data/models/sale_invoice.dart';
import '../../data/models/sale_invoice_item.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/purchase_return_repository.dart';
import '../../data/repositories/return_repository.dart';
import '../../data/repositories/sale_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends ConsumerState<ReturnsScreen> {
  // Sales Return State
  String? _selectedSaleInvoiceId;
  final Map<String, int> _selectedItems = {};
  final TextEditingController _reasonController = TextEditingController();

  // Purchase Return State
  String? _selectedPurchaseInvoiceId;
  final Map<String, int> _selectedPurchaseItems = {};
  final TextEditingController _purchaseReasonController = TextEditingController();

  // History Tab Filter ('sales' or 'purchases')
  String _historyFilter = 'sales';

  @override
  void dispose() {
    _reasonController.dispose();
    _purchaseReasonController.dispose();
    super.dispose();
  }

  /// ضبط كمية مرتجع المبيعات لصنف مع حصرها بين 1 وأقصى كمية قابلة للإرجاع.
  void _setReturnQty(String productId, int qty, int max) {
    setState(() {
      _selectedItems[productId] = qty.clamp(1, max);
    });
  }

  /// ضبط كمية مرتجع المشتريات لصنف مع حصرها بين 1 وأقصى كمية قابلة للإرجاع.
  void _setPurchaseReturnQty(String productId, int qty, int max) {
    setState(() {
      _selectedPurchaseItems[productId] = qty.clamp(1, max);
    });
  }

  /// زر خطوة كمية (−/+) مفعّل ضمن الحدود فقط.
  Widget _qtyStepButton(
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: enabled
            ? AppColors.PRIMARY_BLUE
            : AppColors.TEXT_SECONDARY.withValues(alpha: 0.35),
      ),
    );
  }

  /// الكميات المرتجعة سابقاً لفاتورة البيع المحددة (لمنع الإفراط في الإرجاع).
  Future<Map<String, int>?> _loadReturnedQuantities() async {
    if (_selectedSaleInvoiceId == null) return null;
    final returnRepo = ref.read(returnRepositoryProvider);
    return returnRepo.getReturnedQuantitiesBySaleInvoice(
      _selectedSaleInvoiceId!,
    );
  }

  /// الكميات المرتجعة سابقاً لفاتورة الشراء المحددة.
  Future<Map<String, int>?> _loadPurchaseReturnedQuantities() async {
    if (_selectedPurchaseInvoiceId == null) return null;
    final purchaseReturnRepo = ref.read(purchaseReturnRepositoryProvider);
    return purchaseReturnRepo.getReturnedQuantitiesByPurchaseInvoice(
      _selectedPurchaseInvoiceId!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final saleRepo = ref.read(saleRepositoryProvider);
    final purchaseRepo = ref.read(purchaseRepositoryProvider);
    // عامل تكبير حسب عرض المحتوى: يكبّر الخطوات والسجلات على التابلت بوضوح.
    final scale = ResponsiveScope.scaleOf(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المرتجعات'),
          backgroundColor: AppColors.PRIMARY_BLUE,
          centerTitle: true,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: TextStyle(
              fontFamily: AppTypography.FONT_FAMILY,
              fontWeight: FontWeight.bold,
              fontSize: 14 * scale,
            ),
            tabs: const [
              Tab(text: 'مرتجع مبيعات (عميل)'),
              Tab(text: 'مرتجع مشتريات (مورد)'),
              Tab(text: 'سجل المرتجعات'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Sales Return
            MaxWidthContainer(child: _buildNewReturnTab(saleRepo, scale)),
            // Tab 2: Purchase Return
            MaxWidthContainer(child: _buildNewPurchaseReturnTab(purchaseRepo, scale)),
            // Tab 3: Returns History
            MaxWidthContainer(child: _buildReturnsHistoryTab(scale)),
          ],
        ),
      ),
    );
  }

  Widget _buildNewReturnTab(SaleRepository saleRepo, double scale) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: Select Sale Invoice
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الخطوة 1: اختر الفاتورة الأصلية',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15 * scale,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ref.watch(salesHistoryProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Text(
                      'حدث خطأ أثناء تحميل الفواتير: $error',
                      style: const TextStyle(color: AppColors.DANGER_RED),
                    ),
                    data: (invoices) {
                      final completedInvoices = invoices
                          .where((i) => i.status == 'completed')
                          .toList();

                      if (completedInvoices.isEmpty) {
                        return const Text(
                          'لا توجد فواتير مكتملة قابلة للإرجاع بعد.',
                          style: TextStyle(color: AppColors.TEXT_SECONDARY),
                        );
                      }

                      return DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('اختر فاتورة...'),
                        value: _selectedSaleInvoiceId,
                        items: completedInvoices.map<DropdownMenuItem<String>>((
                          invoice,
                        ) {
                          return DropdownMenuItem<String>(
                            value: invoice.id,
                            child: Text(
                              'الفاتورة #${invoice.invoiceNumber} - ${AppStrings.money(invoice.total)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedSaleInvoiceId = value;
                            _selectedItems.clear();
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Step 2: Select Items to Return
          if (_selectedSaleInvoiceId != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الخطوة 2: اختر الأصناف وحدد كمياتها',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15 * scale,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يمكن الإرجاع الجزئي: اختر الصنف وحدد كميتة بالأزرار (مثلاً 3 من 5)',
                      style: TextStyle(
                        fontSize: 12 * scale,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<Map<String, int>?>(
                      future: _loadReturnedQuantities(),
                      builder: (context, returnedSnapshot) {
                        return FutureBuilder<SaleInvoice?>(
                          future: saleRepo.getSaleInvoiceById(
                            _selectedSaleInvoiceId!,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const CircularProgressIndicator();
                            }

                            final invoice = snapshot.data;
                            if (invoice == null) {
                              return const Text('لم يتم العثور على الفاتورة');
                            }

                            final items = invoice.items;
                            final returnedQty = returnedSnapshot.data ?? {};

                            return Column(
                              children: items.map((item) {
                                final productId = item.productId;
                                final soldQty = item.quantity;
                                final alreadyReturned =
                                    returnedQty[productId] ?? 0;
                                final returnable = soldQty - alreadyReturned;

                                if (returnable <= 0) {
                                  // تمت إرجاع الكمية بالكامل سابقاً.
                                  return Tooltip(
                                    message: 'تمت إرجاع هذا الصنف بالكامل',
                                    child: CheckboxListTile(
                                      title: Text(
                                        item.productName ?? 'صنف',
                                        style: const TextStyle(
                                          color: AppColors.TEXT_SECONDARY,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      subtitle: const Text(
                                        'تمت إرجاع الكمية بالكامل سابقاً',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.TEXT_SECONDARY,
                                        ),
                                      ),
                                      value: false,
                                      onChanged: null,
                                    ),
                                  );
                                }

                                final checked = _selectedItems.containsKey(
                                  productId,
                                );
                                final selectedQty =
                                    _selectedItems[productId] ?? 0;

                                // صنف قابل للإرجاع جزئياً:علامة اختيار +
                                // تحديد الكمية (مثلاً 3 من 5) عبر أزرار +/-
                                // مع القيمة النقدية للمبلغ المرتجع.
                                return Material(
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: checked,
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                // افتراض: إرجاع كل ما تبقى
                                                // القابل للإرجاع، ويُعدَّل
                                                // بالأزرار إن كان جزئياً.
                                                _selectedItems[productId] =
                                                    returnable;
                                              } else {
                                                _selectedItems.remove(
                                                  productId,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.productName ?? 'صنف',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'في الفاتورة: $soldQty • السعر: ${AppStrings.money(item.unitPrice)}'
                                                '${alreadyReturned > 0 ? ' • المرتجع سابقاً: $alreadyReturned' : ''}',
                                                style: TextStyle(
                                                  fontSize: 12 * scale,
                                                  color:
                                                      AppColors.TEXT_SECONDARY,
                                                ),
                                              ),
                                              if (checked) ...[
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Text(
                                                      'الكمية المرتجعة:',
                                                      style: TextStyle(
                                                        fontSize: 12 * scale,
                                                        color: AppColors
                                                            .TEXT_SECONDARY,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    _qtyStepButton(
                                                      Icons
                                                          .remove_circle_outline,
                                                      enabled: selectedQty > 1,
                                                      onTap: () =>
                                                          _setReturnQty(
                                                            productId,
                                                            selectedQty - 1,
                                                            returnable,
                                                          ),
                                                    ),
                                                    Container(
                                                      width: 40,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        '$selectedQty',
                                                        style: TextStyle(
                                                          fontSize: 14 * scale,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppColors
                                                              .PRIMARY_BLUE,
                                                        ),
                                                      ),
                                                    ),
                                                    _qtyStepButton(
                                                      Icons.add_circle_outline,
                                                      enabled:
                                                          selectedQty <
                                                          returnable,
                                                      onTap: () =>
                                                          _setReturnQty(
                                                            productId,
                                                            selectedQty + 1,
                                                            returnable,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      '= ${AppStrings.money(selectedQty * item.unitPrice)}',
                                                      style: TextStyle(
                                                        fontSize: 13 * scale,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppColors
                                                            .PRIMARY_BLUE,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Step 3: Reason and Confirmation
          if (_selectedItems.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الخطوة 3: سبب المرتجع (اختياري)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15 * scale,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonController,
                      decoration: InputDecoration(
                        hintText: 'مثال: تالف، غير مطابق، ...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _submitReturn(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.SUCCESS_GREEN,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('تأكيد المرتجع'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNewPurchaseReturnTab(PurchaseRepository purchaseRepo, double scale) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: Select Purchase Invoice
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الخطوة 1: اختر فاتورة الشراء الأصلية (المورد)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15 * scale,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ref.watch(purchasesListProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Text(
                      'حدث خطأ أثناء تحميل فواتير الشراء: $error',
                      style: const TextStyle(color: AppColors.DANGER_RED),
                    ),
                    data: (invoices) {
                      if (invoices.isEmpty) {
                        return const Text(
                          'لا توجد فواتير شراء مسجلة بعد.',
                          style: TextStyle(color: AppColors.TEXT_SECONDARY),
                        );
                      }

                      return DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('اختر فاتورة توريد...'),
                        value: _selectedPurchaseInvoiceId,
                        items: invoices.map<DropdownMenuItem<String>>((invoice) {
                          final shortId = invoice.id.length > 8
                              ? invoice.id.substring(0, 8)
                              : invoice.id;
                          return DropdownMenuItem<String>(
                            value: invoice.id,
                            child: Text(
                              'فاتورة #$shortId • المورد: ${invoice.supplierName ?? "عام"} • ${AppStrings.money(invoice.total)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPurchaseInvoiceId = value;
                            _selectedPurchaseItems.clear();
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Step 2: Select Items to Return to Supplier
          if (_selectedPurchaseInvoiceId != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الخطوة 2: اختر الأصناف المراد إرجاعها للمورد',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15 * scale,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'حدد الكميات المرتجعة بالأزرار (+ / −). سيتم خصم الكمية من المخزن وتسوية حساب المورد/الخزينة.',
                      style: TextStyle(
                        fontSize: 12 * scale,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<Map<String, int>?>(
                      future: _loadPurchaseReturnedQuantities(),
                      builder: (context, returnedSnapshot) {
                        return FutureBuilder<PurchaseInvoice?>(
                          future: purchaseRepo.getPurchaseInvoiceWithItems(
                            _selectedPurchaseInvoiceId!,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final invoice = snapshot.data;
                            if (invoice == null) {
                              return const Text('لم يتم العثور على الفاتورة');
                            }

                            final items = invoice.items;
                            final returnedQty = returnedSnapshot.data ?? {};

                            return Column(
                              children: items.map((item) {
                                final productId = item.productId;
                                final purchasedQty = item.quantity;
                                final alreadyReturned = returnedQty[productId] ?? 0;
                                final returnable = purchasedQty - alreadyReturned;

                                if (returnable <= 0) {
                                  return Tooltip(
                                    message: 'تم إرجاع هذا الصنف بالكامل للمورد',
                                    child: CheckboxListTile(
                                      title: Text(
                                        item.productName ?? 'صنف',
                                        style: const TextStyle(
                                          color: AppColors.TEXT_SECONDARY,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                      subtitle: const Text(
                                        'تم إرجاع كامل الكمية المشتراة',
                                        style: TextStyle(
                                          color: AppColors.TEXT_SECONDARY,
                                          fontSize: 12,
                                        ),
                                      ),
                                      value: false,
                                      onChanged: null,
                                    ),
                                  );
                                }

                                final isSelected = _selectedPurchaseItems.containsKey(productId);
                                final selectedQty = _selectedPurchaseItems[productId] ?? 1;

                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  elevation: isSelected ? 1 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isSelected
                                          ? AppColors.PRIMARY_BLUE
                                          : AppColors.NEUTRAL_SURFACE,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                    child: Column(
                                      children: [
                                        CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            item.productName ?? 'صنف',
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 14 * scale,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'سعر الشراء: ${AppStrings.money(item.unitCost)} • قابل للإرجاع: $returnable من $purchasedQty'
                                            '${alreadyReturned > 0 ? " (أُرجع سابقاً: $alreadyReturned)" : ""}',
                                            style: TextStyle(fontSize: 12 * scale),
                                          ),
                                          value: isSelected,
                                          onChanged: (selected) {
                                            setState(() {
                                              if (selected == true) {
                                                _selectedPurchaseItems[productId] = 1;
                                              } else {
                                                _selectedPurchaseItems.remove(productId);
                                              }
                                            });
                                          },
                                        ),
                                        if (isSelected) ...[
                                          const Divider(height: 1),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'الكمية المرتجعة للمورد:',
                                                  style: TextStyle(fontSize: 12.5 * scale, color: AppColors.TEXT_SECONDARY),
                                                ),
                                                Row(
                                                  children: [
                                                    _qtyStepButton(
                                                      Icons.remove_circle_outline,
                                                      enabled: selectedQty > 1,
                                                      onTap: () => _setPurchaseReturnQty(productId, selectedQty - 1, returnable),
                                                    ),
                                                    Container(
                                                      constraints: const BoxConstraints(minWidth: 36),
                                                      alignment: Alignment.center,
                                                      child: Text(
                                                        '$selectedQty',
                                                        style: TextStyle(
                                                          fontSize: 14 * scale,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppColors.PRIMARY_BLUE,
                                                        ),
                                                      ),
                                                    ),
                                                    _qtyStepButton(
                                                      Icons.add_circle_outline,
                                                      enabled: selectedQty < returnable,
                                                      onTap: () => _setPurchaseReturnQty(productId, selectedQty + 1, returnable),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      '= ${AppStrings.money(selectedQty * item.unitCost)}',
                                                      style: TextStyle(
                                                        fontSize: 13 * scale,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppColors.PRIMARY_BLUE,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Step 3: Purchase Return Reason & Confirmation
          if (_selectedPurchaseItems.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الخطوة 3: سبب إرجاع البضاعة للمورد (اختياري)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15 * scale,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _purchaseReasonController,
                      decoration: InputDecoration(
                        hintText: 'مثال: عيوب تصنيع، شحنة تالفة، غير مطابق للمواصفات...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _submitPurchaseReturn(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.PRIMARY_BLUE,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('تأكيد إرجاع البضاعة للمورد وتسوية الحساب'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReturnsHistoryTab(double scale) {
    final returnRepo = ref.read(returnRepositoryProvider);
    final purchaseReturnRepo = ref.read(purchaseReturnRepositoryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'sales',
                  label: Text('مرتجعات المبيعات (العملاء)'),
                  icon: Icon(Icons.person_outline, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'purchases',
                  label: Text('مرتجعات المشتريات (الموردين)'),
                  icon: Icon(Icons.local_shipping_outlined, size: 18),
                ),
              ],
              selected: {_historyFilter},
              onSelectionChanged: (newVal) {
                setState(() => _historyFilter = newVal.first);
              },
            ),
          ),
        ),
        Expanded(
          child: _historyFilter == 'sales'
              ? _buildSalesReturnsList(returnRepo, scale)
              : _buildPurchaseReturnsList(purchaseReturnRepo, scale),
        ),
      ],
    );
  }

  Widget _buildSalesReturnsList(ReturnRepository returnRepo, double scale) {
    return FutureBuilder<List<DetailedReturn>>(
      future: returnRepo.getAllReturnsDetailed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final returns = snapshot.data ?? [];

        if (returns.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text('لا توجد مرتجعات مبيعات'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: returns.length,
          itemBuilder: (context, index) {
            final ret = returns[index];
            final itemsSummary = ret.items.isEmpty
                ? 'لا توجد أصناف'
                : ret.items
                    .map((i) => '${i.productName} (${i.quantity})')
                    .join('، ');

            return Card(
              child: ListTile(
                onTap: () => _showReturnDetails(context, ret),
                title: Text(
                  'مرتجع مبيعات #${ret.originalInvoiceNumber}'
                  '${ret.customerName != null ? ' • ${ret.customerName}' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5 * scale,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.money(ret.invoice.returnAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5 * scale,
                        color: AppColors.WARNING_AMBER,
                      ),
                    ),
                    Text(
                      'الأصناف: $itemsSummary',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5 * scale),
                    ),
                    if (ret.invoice.reason != null &&
                        ret.invoice.reason!.isNotEmpty)
                      Text(
                        'السبب: ${ret.invoice.reason}',
                        style: TextStyle(fontSize: 12.5 * scale),
                      ),
                    Text(
                      'التاريخ: ${ret.invoice.createdAt.toString().split('.')[0]}',
                      style: TextStyle(
                        fontSize: 12.5 * scale,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                trailing: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.WARNING_AMBER.withValues(
                    alpha: 0.12,
                  ),
                  child: Text(
                    '${ret.items.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5 * scale,
                      color: AppColors.WARNING_AMBER,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPurchaseReturnsList(PurchaseReturnRepository repo, double scale) {
    return FutureBuilder<List<DetailedPurchaseReturn>>(
      future: repo.getAllPurchaseReturnsDetailed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final returns = snapshot.data ?? [];

        if (returns.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 64,
                  color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text('لا توجد مرتجعات مشتريات للموردين'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: returns.length,
          itemBuilder: (context, index) {
            final ret = returns[index];
            final itemsSummary = ret.items.isEmpty
                ? 'لا توجد أصناف'
                : ret.items
                    .map((i) => '${i.productName} (${i.quantity})')
                    .join('، ');

            return Card(
              child: ListTile(
                onTap: () => _showPurchaseReturnDetails(context, ret),
                title: Text(
                  'مرتجع لمورد: ${ret.supplierName}'
                  '${ret.originalInvoiceNumber != null ? ' • فاتورة #${ret.originalInvoiceNumber}' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5 * scale,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.money(ret.invoice.returnAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5 * scale,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                    ),
                    Text(
                      'الأصناف: $itemsSummary',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5 * scale),
                    ),
                    if (ret.invoice.reason != null &&
                        ret.invoice.reason!.isNotEmpty)
                      Text(
                        'السبب: ${ret.invoice.reason}',
                        style: TextStyle(fontSize: 12.5 * scale),
                      ),
                    Text(
                      'التسوية: ${ret.invoice.debtReduction > 0 ? "خصم دين: ${AppStrings.money(ret.invoice.debtReduction)} " : ""}${ret.invoice.cashRefundIn > 0 ? "استرداد نقدي: ${AppStrings.money(ret.invoice.cashRefundIn)}" : ""}',
                      style: TextStyle(
                        fontSize: 12 * scale,
                        color: AppColors.SUCCESS_GREEN,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'التاريخ: ${ret.invoice.createdAt.toString().split('.')[0]}',
                      style: TextStyle(
                        fontSize: 12.5 * scale,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                  ],
                ),
                trailing: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.PRIMARY_BLUE.withValues(
                    alpha: 0.12,
                  ),
                  child: Text(
                    '${ret.items.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5 * scale,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// عرض أصناف مرتجع المبيعات بالكامل عند الضغط عليه.
  void _showReturnDetails(BuildContext context, DetailedReturn ret) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'مرتجع من فاتورة #${ret.originalInvoiceNumber}'
          '${ret.customerName != null ? '\n${ret.customerName}' : ''}',
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'القيمة الإجمالية: ${AppStrings.money(ret.invoice.returnAmount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.WARNING_AMBER,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'التاريخ: ${ret.invoice.createdAt.toString().split('.')[0]}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
              if (ret.invoice.reason != null &&
                  ret.invoice.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
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
              const Text(
                'الأصناف المرتجعة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (ret.items.isEmpty)
                const Text(
                  'لا توجد أصناف مسجلة',
                  style: TextStyle(color: AppColors.TEXT_SECONDARY),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
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

  /// عرض أصناف مرتجع المشتريات بالكامل عند الضغط عليه.
  void _showPurchaseReturnDetails(BuildContext context, DetailedPurchaseReturn ret) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'مرتجع مشتريات للمورد: ${ret.supplierName}',
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'القيمة الإجمالية: ${AppStrings.money(ret.invoice.returnAmount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.PRIMARY_BLUE,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'التسوية المحاسبية: '
                '${ret.invoice.debtReduction > 0 ? "خصم دين ${AppStrings.money(ret.invoice.debtReduction)} " : ""}'
                '${ret.invoice.cashRefundIn > 0 ? "استرداد نقدي ${AppStrings.money(ret.invoice.cashRefundIn)}" : ""}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.SUCCESS_GREEN,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'التاريخ: ${ret.invoice.createdAt.toString().split('.')[0]}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
              if (ret.invoice.reason != null &&
                  ret.invoice.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
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
              const Text(
                'الأصناف المرتجعة للمورد:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (ret.items.isEmpty)
                const Text(
                  'لا توجد أصناف مسجلة',
                  style: TextStyle(color: AppColors.TEXT_SECONDARY),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
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
                              '${item.quantity} × ${AppStrings.money(item.unitCost)}',
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

  Future<void> _submitReturn() async {
    if (_selectedSaleInvoiceId == null || _selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار فاتورة ومنتجات')),
      );
      return;
    }

    try {
      final saleRepo = ref.read(saleRepositoryProvider);
      final returnRepo = ref.read(returnRepositoryProvider);

      final saleInvoice = await saleRepo.getSaleInvoiceById(
        _selectedSaleInvoiceId!,
      );
      if (saleInvoice == null) throw Exception('فاتورة غير موجودة');

      // حماية نهائية: التأكد من أن الكميات المختارة لا تتجاوز القابل للإرجاع.
      final alreadyReturned = await returnRepo
          .getReturnedQuantitiesBySaleInvoice(_selectedSaleInvoiceId!);
      for (final entry in _selectedItems.entries) {
        SaleInvoiceItem? soldItem;
        for (final i in saleInvoice.items) {
          if (i.productId == entry.key) {
            soldItem = i;
            break;
          }
        }
        if (soldItem == null) {
          throw Exception('الصنف غير موجود في الفاتورة الأصلية');
        }
        final returnable =
            soldItem.quantity - (alreadyReturned[entry.key] ?? 0);
        if (entry.value <= 0 || entry.value > returnable) {
          throw Exception(
            'الكمية المرتجعة من "${soldItem.productName ?? "الصنف"}" تتجاوز الكمية القابلة للإرجاع ($returnable)',
          );
        }
      }

      double totalReturn = 0.0;
      final returnItems = <ReturnInvoiceItem>[];

      for (final item in saleInvoice.items) {
        if (_selectedItems.containsKey(item.productId)) {
          final qty = _selectedItems[item.productId]!;
          final lineTotal = item.unitPrice * qty;
          totalReturn += lineTotal;

          returnItems.add(
            ReturnInvoiceItem(
              id: const Uuid().v4(),
              returnInvoiceId: '',
              productId: item.productId,
              quantity: qty,
              unitPrice: item.unitPrice,
              lineTotal: lineTotal,
              productName: item.productName ?? '',
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      final returnInvoiceId = const Uuid().v4();
      final returnInvoice = ReturnInvoice(
        id: returnInvoiceId,
        originalSaleInvoiceId: _selectedSaleInvoiceId!,
        customerId: saleInvoice.customerId,
        items: returnItems,
        returnAmount: totalReturn,
        reason: _reasonController.text.isNotEmpty
            ? _reasonController.text
            : null,
        createdAt: DateTime.now(),
      );

      await returnRepo.createReturnInvoice(
        invoice: returnInvoice,
        items: returnItems,
        userId: ref.read(authProvider).user?.id,
      );

      // Refresh all related providers
      refreshAfterReturn(ref);

      if (mounted) {
        _reasonController.clear();
        setState(() {
          _selectedSaleInvoiceId = null;
          _selectedItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text(
              '✓ تم إنشاء المرتجع بنجاح (${AppStrings.money(totalReturn)})',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }

  Future<void> _submitPurchaseReturn() async {
    if (_selectedPurchaseInvoiceId == null || _selectedPurchaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار فاتورة شراء وأصناف للإرجاع')),
      );
      return;
    }

    try {
      final purchaseRepo = ref.read(purchaseRepositoryProvider);
      final purchaseReturnRepo = ref.read(purchaseReturnRepositoryProvider);

      final purchaseInvoice = await purchaseRepo.getPurchaseInvoiceWithItems(
        _selectedPurchaseInvoiceId!,
      );
      if (purchaseInvoice == null) throw Exception('فاتورة الشراء غير موجودة');

      final alreadyReturned = await purchaseReturnRepo
          .getReturnedQuantitiesByPurchaseInvoice(_selectedPurchaseInvoiceId!);

      for (final entry in _selectedPurchaseItems.entries) {
        PurchaseInvoiceItem? item;
        for (final i in purchaseInvoice.items) {
          if (i.productId == entry.key) {
            item = i;
            break;
          }
        }
        if (item == null) {
          throw Exception('الصنف غير موجود في فاتورة الشراء الأصلية');
        }
        final returnable = item.quantity - (alreadyReturned[entry.key] ?? 0);
        if (entry.value <= 0 || entry.value > returnable) {
          throw Exception(
            'الكمية المرتجعة من "${item.productName ?? "الصنف"}" تتجاوز الكمية القابلة للإرجاع ($returnable)',
          );
        }
      }

      double totalReturn = 0.0;
      final returnItems = <PurchaseReturnInvoiceItem>[];
      const uuid = Uuid();
      final returnInvoiceId = uuid.v4();

      for (final item in purchaseInvoice.items) {
        if (_selectedPurchaseItems.containsKey(item.productId)) {
          final qty = _selectedPurchaseItems[item.productId]!;
          final lineTotal = item.unitCost * qty;
          totalReturn += lineTotal;

          returnItems.add(
            PurchaseReturnInvoiceItem(
              id: uuid.v4(),
              returnInvoiceId: returnInvoiceId,
              productId: item.productId,
              quantity: qty,
              unitCost: item.unitCost,
              lineTotal: lineTotal,
              productName: item.productName ?? '',
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      final returnInvoice = PurchaseReturnInvoice(
        id: returnInvoiceId,
        originalPurchaseInvoiceId: _selectedPurchaseInvoiceId,
        supplierId: purchaseInvoice.supplierId,
        items: returnItems,
        returnAmount: totalReturn,
        reason: _purchaseReasonController.text.trim().isNotEmpty
            ? _purchaseReasonController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );

      await purchaseReturnRepo.createPurchaseReturn(
        invoice: returnInvoice,
        items: returnItems,
        userId: ref.read(authProvider).user?.id,
      );

      // Refresh all related providers
      refreshAfterReturn(ref);

      if (mounted) {
        _purchaseReasonController.clear();
        setState(() {
          _selectedPurchaseInvoiceId = null;
          _selectedPurchaseItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text(
              '✓ تم تسجيل مرتجع المشتريات للمورد بنجاح (${AppStrings.money(totalReturn)})',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }
}
