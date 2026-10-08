class SaleInvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  /// سعر شراء المنتج لحظة إتمام البيع (يُجمّد لحساب أرباح تاريخية دقيقة).
  final double? unitCost;

  // Runtime helper field for UI displays
  final String? productName;

  SaleInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.unitCost,
    this.productName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'unit_cost': unitCost,
    };
  }

  factory SaleInvoiceItem.fromMap(Map<String, dynamic> map, {String? productName}) {
    return SaleInvoiceItem(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      productId: map['product_id'] as String,
      quantity: (map['quantity'] as num).toInt(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
      unitCost: (map['unit_cost'] as num?)?.toDouble(),
      productName: productName ?? (map['product_name'] as String?),
    );
  }

  SaleInvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    int? quantity,
    double? unitPrice,
    double? lineTotal,
    double? unitCost,
    String? productName,
  }) {
    return SaleInvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      unitCost: unitCost ?? this.unitCost,
      productName: productName ?? this.productName,
    );
  }
}
