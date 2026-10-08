class ReturnInvoice {
  final String id;
  final String originalSaleInvoiceId;
  final String? customerId;
  final List<ReturnInvoiceItem> items;
  final double returnAmount;

  /// الجزء الذي خُصم فعلياً من دين العميل عند المرتجع (الزائد عن الدين
  /// سُلِّم للعميل نقداً من الصندوق ويُحسب في `cashRefundOut`).
  /// محفوظ في DB ليظل كشف الحساب والخزينة متسقين حتى بعد سداد العميل لاحقاً.
  final double debtReduction;
  final String? reason;
  final DateTime createdAt;

  ReturnInvoice({
    required this.id,
    required this.originalSaleInvoiceId,
    this.customerId,
    this.items = const [],
    required this.returnAmount,
    this.debtReduction = 0.0,
    this.reason,
    required this.createdAt,
  });

  /// الجزء الذي سُلِّم للعميل نقداً من الصندوق (خارج الدين).
  double get cashRefundOut =>
      (returnAmount - debtReduction).clamp(0.0, double.infinity);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_sale_invoice_id': originalSaleInvoiceId,
      'customer_id': customerId,
      'return_amount': returnAmount,
      'debt_reduction': debtReduction,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ReturnInvoice.fromMap(Map<String, dynamic> map) {
    return ReturnInvoice(
      id: map['id'] as String,
      originalSaleInvoiceId: map['original_sale_invoice_id'] as String,
      customerId: map['customer_id'] as String?,
      returnAmount: (map['return_amount'] as num?)?.toDouble() ?? 0.0,
      debtReduction: (map['debt_reduction'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  ReturnInvoice copyWith({
    String? id,
    String? originalSaleInvoiceId,
    String? customerId,
    List<ReturnInvoiceItem>? items,
    double? returnAmount,
    double? debtReduction,
    String? reason,
    DateTime? createdAt,
  }) {
    return ReturnInvoice(
      id: id ?? this.id,
      originalSaleInvoiceId: originalSaleInvoiceId ?? this.originalSaleInvoiceId,
      customerId: customerId ?? this.customerId,
      items: items ?? this.items,
      returnAmount: returnAmount ?? this.returnAmount,
      debtReduction: debtReduction ?? this.debtReduction,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'ReturnInvoice(id: $id, originalSaleInvoiceId: $originalSaleInvoiceId, returnAmount: $returnAmount, debtReduction: $debtReduction, reason: $reason)';
}

class ReturnInvoiceItem {
  final String id;
  String returnInvoiceId;
  final String productId;
  final int quantity;
  final double unitPrice;

  /// تكلفة الصنف وقت البيع الأصلي (لخصم ربح المرتجع من الأرباح).
  /// تملأها المستودع من عنصر الفاتورة الأصلية قبل الإدراج (كـ returnInvoiceId).
  double? unitCost;
  final double lineTotal;
  final String productName;
  final DateTime createdAt;

  ReturnInvoiceItem({
    required this.id,
    required this.returnInvoiceId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.unitCost,
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
      'unit_price': unitPrice,
      'unit_cost': unitCost,
      'line_total': lineTotal,
      'product_name': productName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ReturnInvoiceItem.fromMap(Map<String, dynamic> map) {
    return ReturnInvoiceItem(
      id: map['id'] as String,
      returnInvoiceId: map['return_invoice_id'] as String,
      productId: map['product_id'] as String,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      unitCost: (map['unit_cost'] as num?)?.toDouble(),
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0.0,
      productName: map['product_name'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  String toString() =>
      'ReturnInvoiceItem(id: $id, productId: $productId, quantity: $quantity, lineTotal: $lineTotal)';
}
