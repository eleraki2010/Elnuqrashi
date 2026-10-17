import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/customer.dart';
import '../../data/models/product.dart';
import '../../providers/app_providers.dart';
import '../../providers/phase2_providers.dart';
import '../../providers/pos_cart_provider.dart';
import '../../providers/license_provider.dart';
import '../dialogs/activation_dialog.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/product_image_view.dart';
import 'barcode_scanner_screen.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _splitCashController = TextEditingController();
  final TextEditingController _splitWalletController = TextEditingController();
  String? _selectedCategory;
  int _activeTab = 0; // 0: Catalog, 1: Invoice & Checkout

  @override
  void dispose() {
    _searchController.dispose();
    _paidController.dispose();
    _discountController.dispose();
    _splitCashController.dispose();
    _splitWalletController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() {});
  }

  Future<void> _completeSale() async {
    final canTransact = ref.read(isTransactionAllowedProvider);
    if (!canTransact) {
      final licenseInfo = ref.read(licenseProvider).value;
      if (licenseInfo != null && mounted) {
        ActivationDialog.show(context, licenseInfo: licenseInfo);
      }
      return;
    }

    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة منتجات إلى الفاتورة أولاً'),
          backgroundColor: AppColors.WARNING_AMBER,
        ),
      );
      return;
    }

    if (cart.paymentMethod == 'credit' && cart.customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد العميل لإتمام الفاتورة الآجلة وتسجيلها على حسابه'),
          backgroundColor: AppColors.DANGER_RED,
        ),
      );
      _showCustomerSelectionDialog(context);
      return;
    }

    double effectivePaid;
    if (cart.paymentMethod == 'split') {
      final totalSplit = cart.splitCashAmount + cart.splitWalletAmount;
      effectivePaid = totalSplit > 0 ? totalSplit : cart.total;
    } else if ((cart.paymentMethod == 'cash' || cart.paymentMethod == 'wallet') && cart.paidAmount <= 0.0) {
      effectivePaid = cart.total;
    } else {
      effectivePaid = cart.paidAmount;
    }

    final isPaidInFull = effectivePaid >= cart.total;
    if (!isPaidInFull && (cart.paymentMethod == 'cash' || cart.paymentMethod == 'split') && cart.customerId == null) {
      final chooseCustomer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.WARNING_AMBER),
              SizedBox(width: 8),
              Text('المبلغ المدفوع غير مكتمل'),
            ],
          ),
          content: Text(
            'المبلغ المدفوع (${AppStrings.money(effectivePaid)}) أقل من إجمالي الفاتورة (${AppStrings.money(cart.total)}).\nلتسجيل المتبقي كدين آجل، يرجى اختيار العميل أولاً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.PRIMARY_BLUE,
                foregroundColor: Colors.white,
              ),
              child: const Text('اختيار عميل'),
            ),
          ],
        ),
      );

      if (chooseCustomer == true && mounted) {
        _showCustomerSelectionDialog(context);
      }
      return;
    }

    try {
      await cartNotifier.completeSale();
      if (!mounted) return;

      final latestInvoice = ref.read(cartProvider.notifier).latestSaleInvoice;
      if (latestInvoice != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ReceiptDialog(
            invoice: latestInvoice,
          ),
        );
      }

      if (!mounted) return;
      cartNotifier.clear();
      _paidController.clear();
      _discountController.clear();
      _splitCashController.clear();
      _splitWalletController.clear();
      setState(() {
        _activeTab = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.TOAST_SALE_SUCCESS),
          backgroundColor: AppColors.SUCCESS_GREEN,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء إتمام البيع: $e'),
          backgroundColor: AppColors.DANGER_RED,
        ),
      );
    }
  }

  void _showClearCartDialog(BuildContext context) {
    final cartNotifier = ref.read(cartProvider.notifier);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_outlined, color: AppColors.DANGER_RED),
            SizedBox(width: 8),
            Text('تأكيد تفريغ السلة'),
          ],
        ),
        content: const Text('هل أنت متأكد من تفريغ كافة المنتجات من السلة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              cartNotifier.clear();
              _paidController.clear();
              _discountController.clear();
              _splitCashController.clear();
              _splitWalletController.clear();
              Navigator.of(context).pop();
              setState(() {
                _activeTab = 0;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
              foregroundColor: Colors.white,
            ),
            child: const Text('تفريغ'),
          ),
        ],
      ),
    );
  }

  void _showCustomerSelectionDialog(BuildContext context) {
    final customersAsync = ref.read(customersListProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final currentCustomerId = ref.read(cartProvider).customerId;

    final searchController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_search, color: AppColors.PRIMARY_BLUE),
                SizedBox(width: 8),
                Text('اختر عميلاً للفاتورة'),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 440,
              child: customersAsync.when(
                data: (allCustomers) {
                  final query = searchController.text.trim().toLowerCase();
                  final customers = query.isEmpty
                      ? allCustomers
                      : allCustomers.where((c) {
                          final matchName =
                              c.name.toLowerCase().contains(query);
                          final matchPhone =
                              c.phone?.toLowerCase().contains(query) ?? false;
                          return matchName || matchPhone;
                        }).toList();

                  return Column(
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم العميل أو رقم الهاتف...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: customers.isEmpty
                            ? Center(
                                child: Text(
                                  query.isEmpty
                                      ? 'لا يوجد عملاء مسجلون حالياً.'
                                      : 'لا يوجد عميل يطابق بحثك.',
                                  style: const TextStyle(
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: customers.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  final isSelected =
                                      customer.id == currentCustomerId;
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isSelected
                                          ? AppColors.PRIMARY_BLUE
                                          : AppColors.NEUTRAL_BG,
                                      child: Icon(
                                        Icons.person,
                                        size: 18,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.TEXT_PRIMARY,
                                      ),
                                    ),
                                    title: Text(
                                      customer.name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      customer.phone ?? 'بدون هاتف',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: customer.hasDebt
                                        ? Text(
                                            'مديونية: ${AppStrings.money(customer.balanceDue)}',
                                            style: const TextStyle(
                                              color: AppColors.DANGER_RED,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : const Text(
                                            'لا توجد ديون',
                                            style: TextStyle(
                                              color: AppColors.SUCCESS_GREEN,
                                              fontSize: 12,
                                            ),
                                          ),
                                    onTap: () {
                                      cartNotifier.setCustomerId(customer.id,
                                          customerName: customer.name);
                                      Navigator.of(ctx).pop();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
              ),
            ),
            actions: [
              if (currentCustomerId != null)
                TextButton(
                  onPressed: () {
                    cartNotifier.setCustomerId(null, customerName: null);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text(
                    'إلغاء التحديد',
                    style: TextStyle(color: AppColors.DANGER_RED),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaymentMethodButton({
    required String id,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.PRIMARY_BLUE
              : AppColors.PRIMARY_BLUE.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.PRIMARY_BLUE : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.PRIMARY_BLUE,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.TEXT_PRIMARY,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final customersAsync = ref.watch(customersListProvider);
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    final contentWidth = ResponsiveScope.widthOf(context);
    final isWide = contentWidth >= 1050;
    final scale = ResponsiveScope.scaleOf(context);

    Customer? selectedCustomer;
    if (cart.customerId != null) {
      selectedCustomer = customersAsync.asData?.value
          .where((c) => c.id == cart.customerId)
          .firstOrNull;
    }

    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.NEUTRAL_BG,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Pane: Catalog
            Expanded(
              flex: 6,
              child: _buildProductCatalog(
                context,
                productsAsync,
                categoriesAsync,
                cart,
                cartNotifier,
                contentWidth,
                scale,
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Right Pane: Cart & Checkout
            Expanded(
              flex: 5,
              child: Container(
                color: Colors.white,
                child: _buildInvoiceSplitContent(
                  context,
                  cart,
                  cartNotifier,
                  selectedCustomer,
                  scale,
                  isWide: true,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tablet Portrait / Standard Screen Layout (Adaptive Professional Dual-Mode)
    return Scaffold(
      backgroundColor: AppColors.NEUTRAL_BG,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: _buildSegmentedHeader(context, cart),
      ),
      body: _activeTab == 0
          ? _buildProductCatalog(
              context,
              productsAsync,
              categoriesAsync,
              cart,
              cartNotifier,
              contentWidth,
              scale,
            )
          : _buildInvoiceView(
              context,
              cart,
              cartNotifier,
              selectedCustomer,
              contentWidth,
              scale,
            ),
      bottomNavigationBar: _activeTab == 0 && cart.items.isNotEmpty
          ? _buildFloatingCartBar(context, cart)
          : null,
    );
  }

  // ==========================================
  // 1. Tablet Portrait Segmented Header
  // ==========================================
  Widget _buildSegmentedHeader(BuildContext context, CartState cart) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Tab 0: Product Catalog
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _activeTab = 0),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _activeTab == 0
                        ? AppColors.PRIMARY_BLUE
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 19,
                        color: _activeTab == 0 ? Colors.white : AppColors.TEXT_PRIMARY,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'الأصناف والمنتجات',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 0
                              ? Colors.white
                              : AppColors.TEXT_PRIMARY,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Tab 1: Invoice & Checkout
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _activeTab = 1),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _activeTab == 1
                        ? AppColors.PRIMARY_BLUE
                        : (_cartHasItems(cart)
                            ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.08)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _activeTab == 1
                          ? AppColors.PRIMARY_BLUE
                          : (_cartHasItems(cart)
                              ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.3)
                              : Colors.transparent),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: cart.items.isNotEmpty,
                        label: Text(
                          '${cart.totalItemsCount}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: AppColors.DANGER_RED,
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 19,
                          color: _activeTab == 1
                              ? Colors.white
                              : (_cartHasItems(cart)
                                  ? AppColors.PRIMARY_BLUE
                                  : AppColors.TEXT_PRIMARY),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        cart.items.isEmpty
                            ? 'الفاتورة والسداد'
                            : 'الفاتورة (${AppStrings.money(cart.total)})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 1
                              ? Colors.white
                              : (_cartHasItems(cart)
                                  ? AppColors.PRIMARY_BLUE
                                  : AppColors.TEXT_PRIMARY),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _cartHasItems(CartState cart) => cart.items.isNotEmpty;

  // ==========================================
  // 2. Floating Cart Bar (Bottom of Catalog)
  // ==========================================
  Widget _buildFloatingCartBar(BuildContext context, CartState cart) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Items Count Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: AppColors.PRIMARY_BLUE,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${cart.totalItemsCount} أصناف',
                    style: const TextStyle(
                      color: AppColors.PRIMARY_BLUE,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Total Due Preview
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إجمالي الفاتورة',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                  Text(
                    AppStrings.money(cart.total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Button to jump straight to Invoice & Checkout
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _activeTab = 1;
                });
              },
              icon: const Icon(Icons.receipt_long, size: 19),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'عرض الفاتورة والدفع',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 13),
                ],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.SUCCESS_GREEN,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 3. Product Catalog Pane
  // ==========================================
  Widget _buildProductCatalog(
    BuildContext context,
    AsyncValue<List<Product>> productsAsync,
    AsyncValue<List<dynamic>> categoriesAsync,
    CartState cart,
    CartNotifier cartNotifier,
    double contentWidth,
    double scale,
  ) {
    return Padding(
      padding: EdgeInsets.all(
        ResponsiveUtils.scaledSpacing(12.0, contentWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search & Barcode Scan Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).setQuery(val);
                    _onSearchChanged(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المنتج أو كود الباركود...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            tooltip: 'مسح البحث',
                            onPressed: () {
                              _searchController.clear();
                              ref.read(searchQueryProvider.notifier).clear();
                              _onSearchChanged('');
                            },
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.barcode_reader,
                            size: 22,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                          tooltip: 'مسح باركود بالكاميرا',
                          onPressed: () async {
                            final scannedBarcode = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (context) => const BarcodeScannerScreen(),
                              ),
                            );
                            if (scannedBarcode != null) {
                              _searchController.text = scannedBarcode;
                              ref.read(searchQueryProvider.notifier).setQuery(scannedBarcode);
                              _onSearchChanged(scannedBarcode);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Category Filter Chips
          categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = _selectedCategory == null;
                      return ChoiceChip(
                        label: const Text('الكل'),
                        selected: isSelected,
                        selectedColor: AppColors.PRIMARY_BLUE,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.TEXT_PRIMARY,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        onSelected: (_) {
                          setState(() => _selectedCategory = null);
                        },
                      );
                    }
                    final cat = categories[index - 1];
                    final isSelected = _selectedCategory == cat.id;
                    return ChoiceChip(
                      label: Text(cat.name),
                      selected: isSelected,
                      selectedColor: AppColors.PRIMARY_BLUE,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.TEXT_PRIMARY,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedCategory = cat.id);
                      },
                    );
                  },
                ),
              );
            },
            loading: () => const SizedBox(height: 38),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 10),

          // Products Grid
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filteredProducts = _selectedCategory == null
                    ? products
                    : products.where((p) => p.categoryId == _selectedCategory).toList();

                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48 * scale,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد منتجات مطابقة للبحث أو القسم',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.TEXT_SECONDARY,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final paneWidth = constraints.maxWidth;
                    final cols = (paneWidth / 150).floor().clamp(2, 6);

                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 10.0,
                        mainAxisSpacing: 10.0,
                        childAspectRatio: 0.74,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final cartItem = cart.items
                            .where((item) => item.product.id == product.id)
                            .firstOrNull;
                        final isInCart = cartItem != null;

                        return Card(
                          elevation: isInCart ? 3 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                            side: BorderSide(
                              color: isInCart ? AppColors.PRIMARY_BLUE : Colors.transparent,
                              width: isInCart ? 2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (isInCart) {
                                _showQuantityDialog(context, product);
                              } else {
                                final err = cartNotifier.addProduct(product);
                                if (err != null && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.DANGER_RED,
                                      content: Text(err),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Thumbnail
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ProductImageView(
                                        imageUrl: product.imageUrl,
                                        iconSize: 32,
                                      ),
                                      if (isInCart)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.PRIMARY_BLUE,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.2),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              '${cartItem.quantity} في السلة',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Details (Name, Price, Stock)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              AppStrings.money(product.salePrice),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.PRIMARY_BLUE,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${product.quantity} ${product.unit}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: product.isOutOfStock
                                                  ? AppColors.DANGER_RED
                                                  : product.isLowStock
                                                      ? AppColors.WARNING_AMBER
                                                      : AppColors.TEXT_SECONDARY,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'خطأ في تحميل المنتجات: $e',
                  style: const TextStyle(color: AppColors.DANGER_RED),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 4. Dedicated Invoice & Payment View (Tablet Portrait)
  // ==========================================
  Widget _buildInvoiceView(
    BuildContext context,
    CartState cart,
    CartNotifier cartNotifier,
    Customer? selectedCustomer,
    double contentWidth,
    double scale,
  ) {
    if (cart.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.remove_shopping_cart_outlined,
              size: 56 * scale,
              color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'الفاتورة فارغة حالياً',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.TEXT_PRIMARY,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'يرجى الانتقال لتصفح الأصناف وإضافتها إلى الفاتورة',
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.TEXT_SECONDARY,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => setState(() => _activeTab = 0),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('تصفح الأصناف والمنتجات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.PRIMARY_BLUE,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Top action bar inside the invoice view
    final invoiceTopBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _activeTab = 0),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('➕ إضافة المزيد من الأصناف'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.PRIMARY_BLUE,
              side: const BorderSide(color: AppColors.PRIMARY_BLUE),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'بنود الفاتورة (${cart.totalItemsCount} أصناف)',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.DANGER_RED),
            tooltip: 'تفريغ السلة',
            onPressed: () => _showClearCartDialog(context),
          ),
        ],
      ),
    );

    // On standard tablet portrait width (>= 680), show spacious 2-column layout!
    if (contentWidth >= 680) {
      return Column(
        children: [
          invoiceTopBar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Items List (full height)
                Expanded(
                  flex: 6,
                  child: Container(
                    color: Colors.white,
                    child: _buildCartItemsList(context, cart, cartNotifier, scale),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                // Right Column: Checkout & Payment (full height scrollable)
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.grey.shade50,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: _buildCheckoutPanel(
                        context,
                        cart,
                        cartNotifier,
                        selectedCustomer,
                        scale,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // On very compact screens (< 680), vertical stack with top items and bottom checkout
    return Column(
      children: [
        invoiceTopBar,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _buildCartItemsList(context, cart, cartNotifier, scale, shrinkWrap: true),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(14),
                child: _buildCheckoutPanel(
                  context,
                  cart,
                  cartNotifier,
                  selectedCustomer,
                  scale,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 5. Shared Cart Items List
  // ==========================================
  Widget _buildCartItemsList(
    BuildContext context,
    CartState cart,
    CartNotifier cartNotifier,
    double scale, {
    bool shrinkWrap = false,
  }) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: cart.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = cart.items[index];
        final product = item.product;

        return Dismissible(
          key: ValueKey(item.product.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: AppColors.DANGER_RED.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
            ),
            child: const Icon(Icons.delete, color: AppColors.DANGER_RED),
          ),
          onDismissed: (_) {
            cartNotifier.removeProduct(item.product.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم حذف ${product.name} من الفاتورة'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Card(
            elevation: 0.5,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  // Product Thumbnail
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ProductImageView(
                      imageUrl: product.imageUrl,
                      iconSize: 22,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Product Info & Price
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${AppStrings.money(item.unitPrice)} × ${item.quantity}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            Text(
                              '= ${AppStrings.money(item.lineTotal)}',
                              style: const TextStyle(
                                fontSize: 13,
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

                  // Stepper Buttons [-] [qty] [+]
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            if (item.quantity > 1) {
                              cartNotifier.updateQuantity(
                                item.product.id,
                                item.quantity - 1,
                              );
                            } else {
                              cartNotifier.removeProduct(item.product.id);
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Icon(Icons.remove, size: 16),
                          ),
                        ),
                        InkWell(
                          onTap: () => _showQuantityDialog(context, product),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            final err =
                                cartNotifier.addProduct(product, quantity: 1);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.DANGER_RED,
                                  content: Text(err),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Icon(Icons.add, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    tooltip: 'حذف',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      cartNotifier.removeProduct(item.product.id);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 6. Checkout & Payment Details Panel
  // ==========================================
  Widget _buildCheckoutPanel(
    BuildContext context,
    CartState cart,
    CartNotifier cartNotifier,
    Customer? selectedCustomer,
    double scale,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Customer Selection Card
        InkWell(
          onTap: () => _showCustomerSelectionDialog(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selectedCustomer != null
                  ? AppColors.PRIMARY_BLUE.withValues(alpha: 0.08)
                  : (cart.paymentMethod == 'credit' ? Colors.amber.shade50 : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selectedCustomer != null
                    ? AppColors.PRIMARY_BLUE
                    : (cart.paymentMethod == 'credit'
                        ? Colors.amber.shade400
                        : Colors.grey.shade300),
                width: cart.paymentMethod == 'credit' ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selectedCustomer != null ? Icons.person : Icons.person_add_alt,
                  color: selectedCustomer != null
                      ? AppColors.PRIMARY_BLUE
                      : (cart.paymentMethod == 'credit'
                          ? Colors.amber.shade800
                          : AppColors.TEXT_SECONDARY),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedCustomer != null
                            ? 'العميل: ${selectedCustomer.name}'
                            : (cart.paymentMethod == 'credit'
                                ? 'اضغط لاختيار العميل (مطلوب للآجل)'
                                : 'تحديد عميل للفاتورة (اختياري)'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selectedCustomer != null
                              ? AppColors.PRIMARY_BLUE
                              : (cart.paymentMethod == 'credit'
                                  ? Colors.amber.shade900
                                  : AppColors.TEXT_PRIMARY),
                        ),
                      ),
                      if (selectedCustomer != null && selectedCustomer.hasDebt)
                        Text(
                          'مديونية سابقة: ${AppStrings.money(selectedCustomer.balanceDue)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.DANGER_RED,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Financial Summary Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الإجمالي الفرعي:',
                    style: TextStyle(fontSize: 13, color: AppColors.TEXT_SECONDARY),
                  ),
                  Text(
                    AppStrings.money(cart.subtotal),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الضريبة (${(AppStrings.TAX_RATE * 100).toStringAsFixed(0)}%):',
                    style: const TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
                  ),
                  Text(
                    AppStrings.money(cart.tax),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (cart.discount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الخصم:',
                      style: TextStyle(fontSize: 12, color: AppColors.DANGER_RED),
                    ),
                    Text(
                      '- ${AppStrings.money(cart.discount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.DANGER_RED,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المبلغ المستحق:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    AppStrings.money(cart.total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Payment Method Selector (2x2 Grid)
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildPaymentMethodButton(
                    id: 'cash',
                    label: 'نقدي',
                    icon: Icons.payments_outlined,
                    isSelected: cart.paymentMethod == 'cash',
                    onTap: () => cartNotifier.setPaymentMethod('cash'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPaymentMethodButton(
                    id: 'wallet',
                    label: 'إلكتروني',
                    icon: Icons.account_balance_wallet_outlined,
                    isSelected: cart.paymentMethod == 'wallet',
                    onTap: () => cartNotifier.setPaymentMethod('wallet'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildPaymentMethodButton(
                    id: 'split',
                    label: 'مشترك',
                    icon: Icons.call_split,
                    isSelected: cart.paymentMethod == 'split',
                    onTap: () => cartNotifier.setPaymentMethod('split'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPaymentMethodButton(
                    id: 'credit',
                    label: 'آجل',
                    icon: Icons.credit_card_outlined,
                    isSelected: cart.paymentMethod == 'credit',
                    onTap: () {
                      cartNotifier.setPaymentMethod('credit');
                      if (cart.customerId == null) {
                        _showCustomerSelectionDialog(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4. Method-specific Controls
        if (cart.paymentMethod == 'wallet') ...[
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone_android, size: 20, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'دفع إلكتروني (إنستاباي / فودافون كاش / فيزا)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _discountController,
                  decoration: const InputDecoration(
                    labelText: 'الخصم',
                    prefixIcon: Icon(Icons.percent_outlined, size: 16),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final discount = double.tryParse(value) ?? 0.0;
                    cartNotifier.setDiscount(discount);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        if (cart.paymentMethod == 'split') ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.call_split, size: 18, color: AppColors.PRIMARY_BLUE),
                    const SizedBox(width: 6),
                    const Text(
                      'توزيع الدفع (نقدي + إلكتروني)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      'الإجمالي: ${AppStrings.money(cart.total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _splitCashController,
                        decoration: const InputDecoration(
                          labelText: 'المبلغ النقدي',
                          prefixIcon: Icon(Icons.payments_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          final cash = double.tryParse(value) ?? 0.0;
                          final wallet = double.tryParse(_splitWalletController.text) ?? 0.0;
                          cartNotifier.setSplitAmounts(cash: cash, wallet: wallet);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _splitWalletController,
                        decoration: const InputDecoration(
                          labelText: 'المحفظة / إلكتروني',
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          final wallet = double.tryParse(value) ?? 0.0;
                          final cash = double.tryParse(_splitCashController.text) ?? 0.0;
                          cartNotifier.setSplitAmounts(cash: cash, wallet: wallet);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('الباقي على المحفظة', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        final cash = double.tryParse(_splitCashController.text) ?? 0.0;
                        final remaining = (cart.total - cash).clamp(0.0, double.infinity);
                        _splitWalletController.text = remaining.toStringAsFixed(2);
                        cartNotifier.setSplitAmounts(cash: cash, wallet: remaining);
                      },
                    ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('الباقي نقدي', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        final wallet = double.tryParse(_splitWalletController.text) ?? 0.0;
                        final remaining = (cart.total - wallet).clamp(0.0, double.infinity);
                        _splitCashController.text = remaining.toStringAsFixed(2);
                        cartNotifier.setSplitAmounts(cash: remaining, wallet: wallet);
                      },
                    ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('مناصفة (50%)', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        final half = cart.total / 2;
                        _splitCashController.text = half.toStringAsFixed(2);
                        _splitWalletController.text = half.toStringAsFixed(2);
                        cartNotifier.setSplitAmounts(cash: half, wallet: half);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (cart.paymentMethod == 'cash') ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _paidController,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المدفوع',
                    prefixIcon: const Icon(Icons.attach_money, size: 18),
                    suffixIcon: Tooltip(
                      message: 'دفع بالكامل',
                      child: IconButton(
                        icon: const Icon(Icons.done_all, size: 18, color: AppColors.PRIMARY_BLUE),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _paidController.text = cart.total.toStringAsFixed(2);
                          cartNotifier.setPaidAmount(cart.total);
                        },
                      ),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final paid = double.tryParse(value) ?? 0.0;
                    cartNotifier.setPaidAmount(paid);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _discountController,
                  decoration: const InputDecoration(
                    labelText: 'الخصم',
                    prefixIcon: Icon(Icons.percent_outlined, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final discount = double.tryParse(value) ?? 0.0;
                    cartNotifier.setDiscount(discount);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.check_circle_outline, size: 14, color: AppColors.PRIMARY_BLUE),
              label: const Text('دفع بالكامل', style: TextStyle(fontSize: 11)),
              onPressed: () {
                _paidController.text = cart.total.toStringAsFixed(2);
                cartNotifier.setPaidAmount(cart.total);
              },
            ),
          ),
          if (cart.paidAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cart.isChangePositive ? 'الباقي للعميل:' : 'المتبقي على العميل:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: cart.isChangePositive
                        ? AppColors.SUCCESS_GREEN
                        : AppColors.DANGER_RED,
                  ),
                ),
                Text(
                  AppStrings.money(cart.isChangePositive ? cart.changeDue : cart.remainingOnCustomer),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cart.isChangePositive
                        ? AppColors.SUCCESS_GREEN
                        : AppColors.DANGER_RED,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
        ],

        // 5. Complete Sale Action Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: cart.items.isEmpty ? null : _completeSale,
            icon: const Icon(Icons.check_circle_outline, size: 22),
            label: const Text(
              'إتمام عملية البيع وطباعة الفاتورة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.SUCCESS_GREEN,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 7. Wide Screen Split Cart & Checkout Content
  // ==========================================
  Widget _buildInvoiceSplitContent(
    BuildContext context,
    CartState cart,
    CartNotifier cartNotifier,
    Customer? selectedCustomer,
    double scale, {
    required bool isWide,
  }) {
    return Column(
      children: [
        // Cart Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, color: AppColors.PRIMARY_BLUE),
                  const SizedBox(width: 8),
                  const Text(
                    'سلة المبيعات والفاتورة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  if (cart.items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${cart.totalItemsCount} صنف',
                        style: const TextStyle(
                          color: AppColors.PRIMARY_BLUE,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.DANGER_RED),
                  tooltip: 'تفريغ السلة',
                  onPressed: () => _showClearCartDialog(context),
                ),
            ],
          ),
        ),

        // Cart Items List
        Expanded(
          child: cart.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.remove_shopping_cart_outlined,
                        size: 44 * scale,
                        color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'السلة فارغة حالياً',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.TEXT_SECONDARY,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اضغط على أي منتج لإضافته',
                        style: TextStyle(fontSize: 12, color: AppColors.TEXT_SECONDARY),
                      ),
                    ],
                  ),
                )
              : _buildCartItemsList(context, cart, cartNotifier, scale),
        ),

        // Bottom Checkout & Payment Panel
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                offset: const Offset(0, -2),
                blurRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: _buildCheckoutPanel(
            context,
            cart,
            cartNotifier,
            selectedCustomer,
            scale,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 8. Product Quantity Adjustment Dialog
  // ==========================================
  void _showQuantityDialog(BuildContext context, Product product) {
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final existingItem = cart.items
        .where((item) => item.product.id == product.id)
        .firstOrNull;
    final int currentQty = existingItem?.quantity ?? 1;

    final TextEditingController quantityController =
        TextEditingController(text: currentQty.toString());

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          int qty = int.tryParse(quantityController.text) ?? currentQty;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_note, color: AppColors.PRIMARY_BLUE),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'سعر الوحدة: ${AppStrings.money(product.salePrice)}  •  المتاح بالمخزن: ${product.quantity} ${product.unit}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stepper Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () {
                          if (qty > 1) {
                            qty--;
                            quantityController.text = qty.toString();
                            setDialogState(() {});
                          }
                        },
                        icon: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: quantityController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 8,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val) ?? 0;
                            setDialogState(() => qty = parsed);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: () {
                          if (qty < product.quantity) {
                            qty++;
                            quantityController.text = qty.toString();
                            setDialogState(() {});
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.WARNING_AMBER,
                                content: Text(
                                  'تم الوصول للحد الأقصى المتاح بالمخزن (${product.quantity} ${product.unit})',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Quick presets (+1, +5, +10, +20)
                  Wrap(
                    spacing: 8,
                    children: [1, 5, 10, 20].map((preset) {
                      return ActionChip(
                        label: Text('+$preset'),
                        onPressed: () {
                          final target = qty + preset;
                          qty = target <= product.quantity
                              ? target
                              : product.quantity;
                          quantityController.text = qty.toString();
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Total for this item
                  Text(
                    'إجمالي الصنف: ${AppStrings.money(qty * product.salePrice)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cartNotifier.removeProduct(product.id);
                  Navigator.of(ctx).pop();
                },
                child: const Text(
                  'حذف من السلة',
                  style: TextStyle(color: AppColors.DANGER_RED),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final finalQty = int.tryParse(quantityController.text) ?? 0;
                  if (finalQty > product.quantity) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.DANGER_RED,
                        content: Text(
                          'الكمية المطلوبة ($finalQty) تتجاوز رصيد المخزن المتاح (${product.quantity} ${product.unit})',
                        ),
                      ),
                    );
                    return;
                  }
                  if (finalQty > 0) {
                    final err =
                        cartNotifier.updateQuantity(product.id, finalQty);
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.DANGER_RED,
                          content: Text(err),
                        ),
                      );
                      return;
                    }
                  } else {
                    cartNotifier.removeProduct(product.id);
                  }
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );
  }
}