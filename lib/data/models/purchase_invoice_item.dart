class PurchaseInvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double lineTotal;

  // Runtime helper for UI
  final String? productName;

  PurchaseInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    this.productName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'line_total': lineTotal,
    };
  }

  factory PurchaseInvoiceItem.fromMap(Map<String, dynamic> map, {String? productName}) {
    return PurchaseInvoiceItem(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      productId: map['product_id'] as String,
      quantity: (map['quantity'] as num).toInt(),
      unitCost: (map['unit_cost'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
      productName: productName ?? (map['product_name'] as String?),
    );
  }

  PurchaseInvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    int? quantity,
    double? unitCost,
    double? lineTotal,
    String? productName,
  }) {
    return PurchaseInvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      lineTotal: lineTotal ?? this.lineTotal,
      productName: productName ?? this.productName,
    );
  }
}
