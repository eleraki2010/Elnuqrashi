import 'purchase_invoice_item.dart';

class PurchaseInvoice {
  final String id;
  final String supplierId;
  final List<PurchaseInvoiceItem> items;
  final double total;
  final double tax;
  final double paidAmount;
  final DateTime createdAt;

  // Runtime helper
  final String? supplierName;

  PurchaseInvoice({
    required this.id,
    required this.supplierId,
    this.items = const [],
    required this.total,
    required this.tax,
    required this.paidAmount,
    required this.createdAt,
    this.supplierName,
  });

  double get remainingOwed => (total - paidAmount).clamp(0.0, double.infinity);
  bool get isFullyPaid => paidAmount >= total - 0.01;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'total': total,
      'tax': tax,
      'paid_amount': paidAmount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PurchaseInvoice.fromMap(Map<String, dynamic> map, {List<PurchaseInvoiceItem> items = const [], String? supplierName}) {
    return PurchaseInvoice(
      id: map['id'] as String,
      supplierId: map['supplier_id'] as String,
      items: items,
      total: (map['total'] as num).toDouble(),
      tax: (map['tax'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      supplierName: supplierName ?? (map['supplier_name'] as String?),
    );
  }

  PurchaseInvoice copyWith({
    String? id,
    String? supplierId,
    List<PurchaseInvoiceItem>? items,
    double? total,
    double? tax,
    double? paidAmount,
    DateTime? createdAt,
    String? supplierName,
  }) {
    return PurchaseInvoice(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      items: items ?? this.items,
      total: total ?? this.total,
      tax: tax ?? this.tax,
      paidAmount: paidAmount ?? this.paidAmount,
      createdAt: createdAt ?? this.createdAt,
      supplierName: supplierName ?? this.supplierName,
    );
  }
}
