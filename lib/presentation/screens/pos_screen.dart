import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/sale_invoice.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/phase2_providers.dart';
import '../../providers/pos_cart_provider.dart';
import '../widgets/receipt_dialog.dart';
import 'barcode_scanner_screen.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreenState> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    _paidController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() {});
  }

  Future<void> _completeSale() async {
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة منتجات إلى الفاتورة أولاً')),
      );
      return;
    }

    if (cart.paymentMethod == 'credit' && cart.customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار عميل للبيع الآجل')),
      );
      return;
    }

    final isPaidInFull = cart.paidAmount >= cart.totalAmount;
    if (!isPaidInFull && cart.paymentMethod == 'cash' && cart.customerId == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تحذير'),
          content: const Text(
              'المبلغ المدفوع أقل من الإجمالي. هل تريد متابعة البيع كآجل؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('لا')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('نعم')),
          ],
        ),
      );

      if (confirm == null || !confirm) return;
    }

    try {
      await cartNotifier.completeSale();
      if (!context.mounted) return;

      // Show receipt and reset cart
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => ReceiptDialog(
            saleInvoice: ref.read(cartProvider).latestSaleInvoice!,
            onNewSale: () {
              cartNotifier.clear();
              Navigator.of(context).pop();
            },
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    final isWide = ResponsiveScope.widthOf(context) >= 900;
    // عامل تكبير موحد لكل عناصر الشاشة حسب عرض المحتوى المتاح
    // (يكبر بوضوح على التابلت ليبقى كل شيء قابلاً والمس والقراءة).
    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);

    return Scaffold(
      body: Row(
        children: [
          // Left Pane (in RTL: Right Pane): Products Catalog & Search
          Expanded(
            flex: isWide ? 6 : 5,
            child: Padding(
              padding: EdgeInsets.all(
                  ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 2.0, contentWidth)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Box + Barcode Scan
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            ref
                                .read(searchQueryProvider.notifier)
                                .setQuery(val);
                            _onSearchChanged(val);
                          },
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم أو كود الباركود...',
                            prefixIcon: const Icon(Icons.search),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: ResponsiveUtils.scaledSpacing(12.0, contentWidth),
                              vertical: ResponsiveUtils.scaledSpacing(10.0, contentWidth),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref
                                          .read(searchQueryProvider.notifier)
                                          .clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.barcode_reader),
                                    onPressed: () async {
                                      final scannedBarcode =
                                          await Navigator.of(context).push<String>(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BarcodeScannerScreen(),
                                        ),
                                      );
                                      if (scannedBarcode != null) {
                                        _searchController.text = scannedBarcode;
                                        ref
                                            .read(searchQueryProvider.notifier)
                                            .setQuery(scannedBarcode);
                                        _onSearchChanged(scannedBarcode);
                                      }
                                    },
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: ResponsiveUtils.scaledSpacing(8.0, contentWidth),
                      ),
                      IconButton(
                        icon: const Icon(Icons.barcode_reader),
                        tooltip: 'مسح باركود',
                        onPressed: () async {
                          final scannedBarcode =
                              await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder: (context) => const BarcodeScannerScreen(),
                            ),
                          );
                          if (scannedBarcode != null) {
                            _searchController.text = scannedBarcode;
                            ref
                                .read(searchQueryProvider.notifier)
                                .setQuery(scannedBarcode);
                            _onSearchChanged(scannedBarcode);
                          }
                        },
                      ),
                    ],
                  ),
                  SizedBox(
                    height: ResponsiveUtils.scaledSpacing(8.0, contentWidth),
                  ),
                  // Products Grid
                  Expanded(
                    child: productsAsync.when(
                      data: (products) {
                        final filteredProducts = _selectedCategory == null
                            ? products
                            : products.where((p) =>
                                p.categoryId == _selectedCategory).toList();
                        return GridView.builder(
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: ResponsiveUtils.posGridColumns(
                                contentWidth),
                            crossAxisSpacing: ResponsiveUtils.scaledSpacing(
                                8.0, contentWidth),
                            mainAxisSpacing: ResponsiveUtils.scaledSpacing(
                                8.0, contentWidth),
                            childAspectRatio: 0.75,
                          ),
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            final isInCart = cart.items.any(
                                (item) => item.productId == product.id);
                            return GestureDetector(
                              onTap: () {
                                if (isInCart) {
                                  // Show quantity dialog
                                  _showQuantityDialog(context, product);
                                } else {
                                  // Add to cart with quantity 1
                                  cartNotifier.addItem(product.id, 1);
                                }
                              },
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppLayout.BORDER_RADIUS),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: product.imageUrl != null &&
                                              product.imageUrl!.isNotEmpty
                                          ? Image.network(
                                              product.imageUrl!,
                                              fit: BoxFit.cover,
                                              loadingBuilder:
                                                  (context, child, loadingProgress) {
                                                if (loadingProgress == null)
                                                  return child;
                                                return Center(
                                                  child: CircularProgressIndicator(
                                                    value: loadingProgress
                                                            .expectedTotalBytes !=
                                                        null
                                                        ? loadingProgress
                                                                .cumulativeBytesLoaded /
                                                            loadingProgress
                                                                .expectedTotalBytes
                                                        : null,
                                                  ),
                                                );
                                              },
                                              errorBuilder: (context, error,
                                                  stackTrace) =>
                                                  Icon(Icons.image,
                                                      size: 40 * scale),
                                            )
                                          : Container(
                                              color: AppColors.NEUTRAL_BG,
                                              child: Icon(
                                                  Icons.image_not_supported,
                                                  size: 40 * scale,
                                                  color: AppColors.TEXT_SECONDARY),
                                            ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(
                                          ResponsiveUtils.scaledSpacing(
                                              8.0, contentWidth)),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: TextStyle(
                                              fontSize:
                                                  ResponsiveUtils.scaledFont(
                                                      14.0, contentWidth),
                                              fontWeight: FontWeight.bold,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            maxLines: 2,
                                          ),
                                          SizedBox(
                                              height: ResponsiveUtils.scaledSpacing(
                                                  4.0, contentWidth)),
                                           Text(
                                             '${product.categoryId} • ${product.unit}',
                                             style: TextStyle(
                                               fontSize:
                                                   ResponsiveUtils.scaledFont(
                                                   12.0, contentWidth),
                                               color: AppColors.TEXT_SECONDARY),
                                             ),
                                        ],
                                      ),
                                    ),
                                    if (isInCart)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveUtils.scaledSpacing(
                                              4.0, contentWidth),
                                          vertical: ResponsiveUtils.scaledSpacing(
                                              2.0, contentWidth)),
                                        decoration: BoxDecoration(
                                          color: AppColors.PRIMARY_BLUE.withOpacity(
                                              0.1),
                                          borderRadius: BorderRadius.circular(
                                              4),
                                        ),
                                        child: Text(
                                          'في السلة',
                                          style: TextStyle(
                                            fontSize:
                                                ResponsiveUtils.scaledFont(
                                                    12.0, contentWidth),
                                            color: AppColors.PRIMARY_BLUE,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Text('خطأ في تحميل المنتجات: $e'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Vertical Divider
          VerticalDivider(
            width: 1,
            color: AppColors.NEUTRAL_BG.withOpacity(0.2),
          ),
          // Right Pane (in RTL: Left Pane): Cart & Actions
          Expanded(
            flex: isWide ? 4 : 5,
            child: Column(
              children: [
                // Cart Header
                Container(
                  padding: EdgeInsets.all(
                      ResponsiveUtils.scaledSpacing(AppLayout.SPACING_UNIT * 2.0, contentWidth)),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.NEUTRAL_BG.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'عربة التسوق',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(
                                  16.0, contentWidth),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep),
                        tooltip: 'تفريغ السلة',
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('تأكيد'),
                              content: const Text(
                                  'هل أنت متأكد من تفريغ سلة التسوق؟'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: const Text('إلغاء')),
                                TextButton(
                                  onPressed: () {
                                    cartNotifier.clear();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('تفريغ')),
                              ],
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
                // Cart Items
                Expanded(
                  child: cart.items.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد منتجات في السلة',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      14.0, contentWidth),
                              color: AppColors.TEXT_SECONDARY),
                          ),
                        )
                      : ListView.builder(
                          itemCount: cart.items.length,
                          itemBuilder: (context, index) {
                            final item = cart.items[index];
                            final product = item.product;
                            return Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: AppColors.DANGER_RED.withOpacity(
                                    0.2),
                                alignment: Alignment.centerRight,
                                padding: EdgeInsets.only(
                                    right: ResponsiveUtils.scaledSpacing(
                                        16.0, contentWidth)),
                                child: Icon(
                                  Icons.delete,
                                  color: AppColors.DANGER_RED,
                                  size: 24 * scale,
                                ),
                              ),
                              onDismissed: (direction) {
                                cartNotifier.removeItem(item.id);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${product.name} تم removal من السلة'),
                                  ),
                                );
                              },
                              child: Card(
                                margin: EdgeInsets.only(
                                  bottom: ResponsiveUtils.scaledSpacing(
                                      8.0, contentWidth)),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppLayout.BORDER_RADIUS),
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.all(
                                      ResponsiveUtils.scaledSpacing(
                                          12.0, contentWidth)),
                                  leading: product.imageUrl != null &&
                                          product.imageUrl!.isNotEmpty
                                      ? Image.network(
                                          product.imageUrl!,
                                          width: 50 * scale,
                                          height: 50 * scale,
                                          fit: BoxFit.cover,
                                        )
                                      : Icon(
                                          Icons.image_not_supported,
                                          size: 40 * scale,
                                          color: AppColors.TEXT_SECONDARY),
                                  title: Text(
                                    product.name,
                                    style: TextStyle(
                                      fontSize:
                                          ResponsiveUtils.scaledFont(
                                              14.0, contentWidth),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${product.categoryName} • ${item.quantity} وحدة',
                                    style: TextStyle(
                                      fontSize:
                                          ResponsiveUtils.scaledFont(
                                              12.0, contentWidth),
                                      color: AppColors.TEXT_SECONDARY),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${AppStrings.money(item.totalPrice)}',
                                        style: TextStyle(
                                          fontSize:
                                              ResponsiveUtils.scaledFont(
                                                  14.0, contentWidth),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(
                                          height: ResponsiveUtils.scaledSpacing(
                                              2.0, contentWidth)),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        tooltip: 'تقليل الكمية',
                                        onPressed: () {
                                          if (item.quantity > 1) {
                                            cartNotifier.updateQuantity(
                                                item.id, item.quantity - 1);
                                          } else {
                                            cartNotifier.removeItem(item.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Cart Summary
                Container(
                  padding: EdgeInsets.all(
                      ResponsiveUtils.scaledSpacing(
                          AppLayout.SPACING_UNIT * 2.0, contentWidth)),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.NEUTRAL_BG.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الإجمالي الفرعي:',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      14.0, contentWidth),
                            ),
                          ),
                          Text(
                            '${AppStrings.money(cart.subtotal)}',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      14.0, contentWidth),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: ResponsiveUtils.scaledSpacing(
                              4.0, contentWidth)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الضريبة (${(AppConstants.TAX_RATE * 100).toStringAsFixed(0)}%):',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      12.0, contentWidth),
                            ),
                          ),
                          Text(
                            '${AppStrings.money(cart.taxAmount)}',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      12.0, contentWidth),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: ResponsiveUtils.scaledSpacing(
                              4.0, contentWidth)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الإجمالي:',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      16.0, contentWidth),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${AppStrings.money(cart.totalAmount)}',
                            style: TextStyle(
                              fontSize:
                                  ResponsiveUtils.scaledFont(
                                      16.0, contentWidth),
                              fontWeight: FontWeight.bold,
                              color: AppColors.PRIMARY_BLUE),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Payment Section
                Container(
                  padding: EdgeInsets.all(
                      ResponsiveUtils.scaledSpacing(
                          AppLayout.SPACING_UNIT * 2.0, contentWidth)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'طريقة الدفع:',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(
                                  14.0, contentWidth),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(
                          height: ResponsiveUtils.scaledSpacing(
                              8.0, contentWidth)),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('نقدي'),
                              value: 'cash',
                              groupValue: cart.paymentMethod,
                              onChanged: (value) {
                                cartNotifier
                                    .updatePaymentMethod(value!);
                              },
                              activeColor: AppColors.PRIMARY_BLUE,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('آجل'),
                              value: 'credit',
                              groupValue: cart.paymentMethod,
                              onChanged: (value) {
                                cartNotifier
                                    .updatePaymentMethod(value!);
                              },
                              activeColor: AppColors.PRIMARY_BLUE,
                            ),
                          ),
                        ],
                      ),
                      if (cart.paymentMethod == 'credit')
                        Column(
                          children: [
                            SizedBox(
                                height: ResponsiveUtils.scaledSpacing(
                                    8.0, contentWidth)),
                            Text(
                              'اختر العميل:',
                              style: TextStyle(
                                fontSize:
                                    ResponsiveUtils.scaledFont(
                                        14.0, contentWidth),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(
                                height: ResponsiveUtils.scaledSpacing(
                                    4.0, contentWidth)),
                            ElevatedButton.icon(
                              onPressed: () {
                                // TODO: Implement customer selection
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'سيتم تنفيذ اختيار العميل في الإصدار القادم'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text('اختر عميل'),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveUtils.scaledSpacing(
                                      12.0, contentWidth)),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(
                          height: ResponsiveUtils.scaledSpacing(
                              12.0, contentWidth)),
                      if (cart.paymentMethod == 'cash')
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _paidController,
                                decoration: InputDecoration(
                                  labelText: 'المبلغ المدفوع',
                                  prefixIcon: const Icon(Icons.attach_money),
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (value) {
                                  // Update cart with paid amount
                                  final paid =
                                      double.tryParse(value) ?? 0.0;
                                  cartNotifier.updatePaidAmount(paid);
                                },
                              ),
                            ),
                            SizedBox(
                                width: ResponsiveUtils.scaledSpacing(
                                    8.0, contentWidth)),
                            Expanded(
                              child: TextField(
                                controller: _discountController,
                                decoration: InputDecoration(
                                  labelText: 'الخصم',
                                  prefixIcon: const Icon(Icons.percent),
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (value) {
                                  // Update cart with discount
                                  final discount =
                                      double.tryParse(value) ?? 0.0;
                                  cartNotifier.updateDiscount(discount);
                                },
                              ),
                            ),
                          ],
                        ),
                      SizedBox(
                          height: ResponsiveUtils.scaledSpacing(
                              12.0, contentWidth)),
                      ElevatedButton.icon(
                        onPressed: _completeSale,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('إتمام البيع'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.SUCCESS_GREEN,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveUtils.scaledSpacing(
                                14.0, contentWidth),
                          ),
                          textStyle: TextStyle(
                            fontSize:
                                ResponsiveUtils.scaledFont(
                                    16.0, contentWidth),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(
      BuildContext context, ProductModel product) {
    final cart = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final cartItem =
        cart.items.firstWhere((item) => item.productId == product.id,
            orElse: () => CartItemModel(
                  id: '',
                  productId: product.id,
                  quantity: 0,
                ));

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${product.name}',
          style: TextStyle(
            fontSize:
                ResponsiveUtils.scaledFont(16.0, contentWidth),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'الكمية',
                  prefixIcon: const Icon(Icons.numbers),
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: false),
                onChanged: (value) {
                  // Update quantity in real-time
                  final quantity = int.tryParse(value) ?? 0;
                  if (quantity > 0) {
                    cartNotifier.updateQuantity(product.id, quantity);
                  } else {
                    cartNotifier.removeItem(product.id);
                  }
                },
              ),
              SizedBox(
                  height: ResponsiveUtils.scaledSpacing(12.0, contentWidth)),
              Row(
                mainAxisAlignment: MainAxisSpaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.cancel),
                    label: const Text('إلغاء'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.DANGER_RED,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('تأكيد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}