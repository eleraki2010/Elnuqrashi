import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/models/product.dart';
import '../data/models/sale_invoice.dart';
import '../data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/core/constants/app_constants.dart';
import 'app_providers.dart';

class CartItem {
  final Product product;
  int quantity;
  double unitPrice;

  CartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => quantity * unitPrice;
}

class CartState {
  final List<CartItem> items;
  final double discount;
  final double tax;
  final double paidAmount;
  final double splitCashAmount;
  final double splitWalletAmount;
  final String paymentMethod; // cash, wallet, split, credit
  final String? customerId;

  CartState({
    this.items = const [],
    this.discount = 0.0,
    this.tax = 0.0,
    this.paidAmount = 0.0,
    this.splitCashAmount = 0.0,
    this.splitWalletAmount = 0.0,
    this.paymentMethod = 'cash',
    this.customerId,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);
  double get total => (subtotal - discount + tax).clamp(0.0, double.infinity);
  double get changeDue {
    if (paymentMethod == 'split') {
      final totalPaid = splitCashAmount + splitWalletAmount;
      return totalPaid - total;
    }
    return paidAmount - total;
  }
  bool get isChangePositive => changeDue >= 0;
  double get remainingOnCustomer => changeDue < 0 ? (-changeDue) : 0.0;
  int get totalItemsCount => items.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({
    List<CartItem>? items,
    double? discount,
    double? tax,
    double? paidAmount,
    double? splitCashAmount,
    double? splitWalletAmount,
    String? paymentMethod,
    String? customerId,
  }) {
    return CartState(
      items: items ?? this.items,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      paidAmount: paidAmount ?? this.paidAmount,
      splitCashAmount: splitCashAmount ?? this.splitCashAmount,
      splitWalletAmount: splitWalletAmount ?? this.splitWalletAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      customerId: customerId ?? this.customerId,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  SaleInvoice? _latestSaleInvoice;

  @override
  CartState build() => CartState();

  SaleInvoice? get latestSaleInvoice => _latestSaleInvoice;

  /// يضيف منتجاً للسلة مع التحقق الصارم من توفر الرصيد بالمخزن.
  /// يعيد null في حال النجاح، أو رسالة التنبيه في حال عدم توفر الكمية.
  String? addProduct(Product product, {int quantity = 1}) {
    if (product.quantity <= 0) {
      return 'المنتج "${product.name}" نافد من المخزن تماماً (الرصيد: 0)';
    }

    final existingIndex =
        state.items.indexWhere((item) => item.product.id == product.id);

    if (existingIndex >= 0) {
      final updatedItems = List<CartItem>.from(state.items);
      final currentItem = updatedItems[existingIndex];
      final targetQty = currentItem.quantity + quantity;
      if (targetQty > product.quantity) {
        return 'الكمية المطلوبة ($targetQty) تتجاوز رصيد المخزن المتاح (${product.quantity} ${product.unit})';
      }
      currentItem.quantity = targetQty;
      state = state.copyWith(items: updatedItems);
      _updateTax();
    } else {
      if (quantity > product.quantity) {
        return 'الكمية المطلوبة ($quantity) تتجاوز رصيد المخزن المتاح (${product.quantity} ${product.unit})';
      }
      final newItem = CartItem(
        product: product,
        quantity: quantity,
        unitPrice: product.salePrice,
      );
      state = state.copyWith(items: [...state.items, newItem]);
      _updateTax();
    }
    return null;
  }

  /// يعدل كمية منتج بالسلة مع التحقق من عدم تجاوز الرصيد المتاح.
  String? updateQuantity(String productId, int newQuantity) {
    if (newQuantity <= 0) {
      removeProduct(productId);
      return null;
    }

    final existingItem =
        state.items.where((i) => i.product.id == productId).firstOrNull;
    if (existingItem != null && newQuantity > existingItem.product.quantity) {
      return 'الكمية المطلوبة ($newQuantity) تتجاوز رصيد المخزن المتاح (${existingItem.product.quantity} ${existingItem.product.unit})';
    }

    final updatedItems = state.items.map((item) {
      if (item.product.id == productId) {
        return CartItem(
          product: item.product,
          quantity: newQuantity,
          unitPrice: item.unitPrice,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
    _updateTax();
    return null;
  }

  void updateUnitPrice(String productId, double newPrice) {
    final updatedItems = state.items.map((item) {
      if (item.product.id == productId) {
        return CartItem(
          product: item.product,
          quantity: item.quantity,
          unitPrice: newPrice,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
    _updateTax();
  }

  void removeProduct(String productId) {
    final updatedItems = state.items.where((item) => item.product.id != productId).toList();
    state = state.copyWith(items: updatedItems);
    _updateTax();
  }

  void setDiscount(double discount) {
    state = state.copyWith(discount: discount);
    _updateTax();
  }

  void setTax(double tax) {
    state = state.copyWith(tax: tax);
  }

  void setPaidAmount(double paid) {
    state = state.copyWith(paidAmount: paid);
  }

  void setPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method);
  }

  void setSplitAmounts({required double cash, required double wallet}) {
    state = state.copyWith(
      splitCashAmount: cash,
      splitWalletAmount: wallet,
    );
  }

  void setCustomerId(String? customerId) {
    state = state.copyWith(customerId: customerId);
  }

   void clearCart() {
     state = CartState();
   }

  Future<void> completeSale() async {
    // التحقق النهائي من توفر رصيد المخزن لكافة الأصناف بالسلة
    final productRepo = ref.read(productRepositoryProvider);
    for (final item in state.items) {
      final latest = await productRepo.getProductById(item.product.id);
      final available = latest?.quantity ?? 0;
      if (item.quantity > available) {
        throw StateError(
          'لا يمكن إتمام البيع: الكمية المطلوبة للمنتج "${item.product.name}" هي ${item.quantity} بينما المتاح حالياً بالمخزن هو $available ${item.product.unit} فقط',
        );
      }
    }

    final invoiceNumber =
        await ref.read(saleRepositoryProvider).generateNextInvoiceNumber();
    final invoice = buildSaleInvoice(
      invoiceNumber: invoiceNumber,
      status: 'completed',
    );
    await ref.read(saleRepositoryProvider).createSaleInvoice(
      invoice: invoice,
      items: invoice.items,
    );
    _latestSaleInvoice = invoice;
  }

  void clear() => clearCart();

  SaleInvoice buildSaleInvoice({
    required String invoiceNumber,
    String? cashierId,
    String status = 'completed',
  }) {
    const uuid = Uuid();
    final invoiceId = uuid.v4();
    final now = DateTime.now();

    final invoiceItems = state.items.map((item) {
      return SaleInvoiceItem(
        id: uuid.v4(),
        invoiceId: invoiceId,
        productId: item.product.id,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
        unitCost: item.product.purchasePrice,
        productName: item.product.name,
      );
    }).toList();

    double actualPaid;
    if (state.paymentMethod == 'split') {
      final totalSplit = state.splitCashAmount + state.splitWalletAmount;
      actualPaid = totalSplit > 0 ? totalSplit : state.total;
    } else if ((state.paymentMethod == 'cash' || state.paymentMethod == 'wallet') && state.paidAmount <= 0.0) {
      actualPaid = state.total;
    } else {
      actualPaid = state.paidAmount;
    }
    final double actualChange = actualPaid - state.total;

    return SaleInvoice(
      id: invoiceId,
      invoiceNumber: invoiceNumber,
      customerId: state.customerId,
      cashierId: cashierId,
      items: invoiceItems,
      subtotal: state.subtotal,
      discount: state.discount,
      tax: state.tax,
      total: state.total,
      paidAmount: actualPaid,
      changeDue: actualChange,
      paymentMethod: state.paymentMethod,
      status: status,
      createdAt: now,
    );
  }

  void _updateTax() {
    final vatEnabled = ref.read(vatEnabledProvider);
    final tax = vatEnabled ? state.subtotal * AppStrings.TAX_RATE : 0.0;
    state = state.copyWith(tax: tax);
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);