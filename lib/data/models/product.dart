class Product {
  final String id;
  final String name;
  final String? barcode;
  final String categoryId;
  final String unit;
  final double purchasePrice;
  final double salePrice;
  final int quantity;
  final int minQuantityAlert;
  final String? imageUrl;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.categoryId,
    required this.unit,
    required this.purchasePrice,
    required this.salePrice,
    required this.quantity,
    required this.minQuantityAlert,
    this.imageUrl,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOutOfStock => quantity <= 0;
  bool get isLowStock => quantity > 0 && quantity <= minQuantityAlert;
  bool get hasStockAlert => quantity <= minQuantityAlert;
  double get profitMargin => salePrice - purchasePrice;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'category_id': categoryId,
      'unit': unit,
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'quantity': quantity,
      'min_quantity_alert': minQuantityAlert,
      'image_url': imageUrl,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      barcode: map['barcode'] as String?,
      categoryId: map['category_id'] as String,
      unit: map['unit'] as String,
      purchasePrice: (map['purchase_price'] as num).toDouble(),
      salePrice: (map['sale_price'] as num).toDouble(),
      quantity: (map['quantity'] as num).toInt(),
      minQuantityAlert: (map['min_quantity_alert'] as num).toInt(),
      imageUrl: map['image_url'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    String? categoryId,
    String? unit,
    double? purchasePrice,
    double? salePrice,
    int? quantity,
    int? minQuantityAlert,
    String? imageUrl,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      quantity: quantity ?? this.quantity,
      minQuantityAlert: minQuantityAlert ?? this.minQuantityAlert,
      imageUrl: imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
