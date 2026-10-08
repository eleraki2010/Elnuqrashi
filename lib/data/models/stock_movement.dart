class StockMovement {
  final String id;
  final String productId;
  final String type; // sale, purchase, adjustment, damage, count
  final int quantityChange; // + in / - out
  final String? referenceId;
  final String? note;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantityChange,
    this.referenceId,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'type': type,
      'quantity_change': quantityChange,
      'reference_id': referenceId,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      type: map['type'] as String,
      quantityChange: (map['quantity_change'] as num).toInt(),
      referenceId: map['reference_id'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
