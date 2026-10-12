class PurchaseReturnInvoice {
  final String id;
  final String? originalPurchaseInvoiceId;
  final String supplierId;
  final List<PurchaseReturnInvoiceItem> items;
  final double returnAmount;

  /// الجزء الذي خُصم من مديونية المورد للمحل
  final double debtReduction;

  /// الجزء الذي استُرد نقداً من المورد إلى الخزينة
  final double cashRefundIn;
  final String? reason;
  final DateTime createdAt;

  PurchaseReturnInvoice({
    required this.id,
    this.originalPurchaseInvoiceId,
    required this.supplierId,
    this.items = const [],
    required this.returnAmount,
    this.debtReduction = 0.0,
    this.cashRefundIn = 0.0,
    this.reason,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_purchase_invoice_id': originalPurchaseInvoiceId,
      'supplier_id': supplierId,
      'return_amount': returnAmount,
      'debt_reduction': debtReduction,
      'cash_refund_in': cashRefundIn,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PurchaseReturnInvoice.fromMap(Map<String, dynamic> map) {
    return PurchaseReturnInvoice(
      id: map['id'] as String,
      originalPurchaseInvoiceId:
          map['original_purchase_invoice_id'] as String?,
      supplierId: map['supplier_id'] as String,
      returnAmount: (map['return_amount'] as num?)?.toDouble() ?? 0.0,
      debtReduction: (map['debt_reduction'] as num?)?.toDouble() ?? 0.0,
      cashRefundIn: (map['cash_refund_in'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  PurchaseReturnInvoice copyWith({
    String? id,
    String? originalPurchaseInvoiceId,
    String? supplierId,
    List<PurchaseReturnInvoiceItem>? items,
    double? returnAmount,
    double? debtReduction,
    double? cashRefundIn,
    String? reason,
    DateTime? createdAt,
  }) {
    return PurchaseReturnInvoice(
      id: id ?? this.id,
      originalPurchaseInvoiceId:
          originalPurchaseInvoiceId ?? this.originalPurchaseInvoiceId,
      supplierId: supplierId ?? this.supplierId,
      items: items ?? this.items,
      returnAmount: returnAmount ?? this.returnAmount,
      debtReduction: debtReduction ?? this.debtReduction,
      cashRefundIn: cashRefundIn ?? this.cashRefundIn,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class PurchaseReturnInvoiceItem {
  final String id;
  String returnInvoiceId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double lineTotal;
  final String productName;
  final DateTime createdAt;

  PurchaseReturnInvoiceItem({
    required this.id,
    required this.returnInvoiceId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    required this.productName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'return_invoice_id': returnInvoiceId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'line_total': lineTotal,
      'product_name': productName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PurchaseReturnInvoiceItem.fromMap(Map<String, dynamic> map) {
    return PurchaseReturnInvoiceItem(
      id: map['id'] as String,
      returnInvoiceId: map['return_invoice_id'] as String,
      productId: map['product_id'] as String,
      quantity: (map['quantity'] as num).toInt(),
      unitCost: (map['unit_cost'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
      productName: (map['product_name'] as String?) ?? 'صنف',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
