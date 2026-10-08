import 'sale_invoice_item.dart';

/// قيمة تمييزية للتفريق بين تمرير `null` صراحةً وعدم تمرير `customerName`
/// في `copyWith` (حتى لا يُمحى اسم العميل عند التحديثات الجزئية).
const Object _sentinel = Object();

class SaleInvoice {
  final String id;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? cashierId;
  final List<SaleInvoiceItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paidAmount;
  final double changeDue;
  final String paymentMethod; // cash, wallet, credit
  final String status; // completed, held, returned, cancelled
  final DateTime createdAt;

  SaleInvoice({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.cashierId,
    this.items = const [],
    required this.subtotal,
    this.discount = 0.0,
    this.tax = 0.0,
    required this.total,
    required this.paidAmount,
    required this.changeDue,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
  });

  bool get isChangePositive => changeDue >= 0;
  double get remainingOnCustomer => changeDue < 0 ? (-changeDue) : 0.0;

  String get paymentMethodArabic {
    switch (paymentMethod) {
      case 'cash':
        return 'نقدي';
      case 'wallet':
        return 'محفظة إلكترونية';
      case 'credit':
        return 'آجل (على الحساب)';
      default:
        return paymentMethod;
    }
  }

  String get statusArabic {
    switch (status) {
      case 'completed':
        return 'مكتملة';
      case 'held':
        return 'معلقة';
      case 'returned':
        return 'مرتجع';
      case 'cancelled':
        return 'ملغاة';
      default:
        return status;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'cashier_id': cashierId,
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'paid_amount': paidAmount,
      'change_due': changeDue,
      'payment_method': paymentMethod,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SaleInvoice.fromMap(Map<String, dynamic> map, {List<SaleInvoiceItem> items = const []}) {
    return SaleInvoice(
      id: map['id'] as String,
      invoiceNumber: map['invoice_number'] as String,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String?,
      cashierId: map['cashier_id'] as String?,
      items: items,
      subtotal: (map['subtotal'] as num).toDouble(),
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      changeDue: (map['change_due'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  SaleInvoice copyWith({
    String? id,
    String? invoiceNumber,
    String? customerId,
    Object? customerName = _sentinel,
    String? cashierId,
    List<SaleInvoiceItem>? items,
    double? subtotal,
    double? discount,
    double? tax,
    double? total,
    double? paidAmount,
    double? changeDue,
    String? paymentMethod,
    String? status,
    DateTime? createdAt,
  }) {
    return SaleInvoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: identical(customerName, _sentinel)
          ? this.customerName
          : customerName as String?,
      cashierId: cashierId ?? this.cashierId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      changeDue: changeDue ?? this.changeDue,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
