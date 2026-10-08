class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final double balanceOwed; // موجب = مستحق له
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    this.balanceOwed = 0.0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasOwed => balanceOwed > 0.01;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'balance_owed': balanceOwed,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      balanceOwed: (map['balance_owed'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Supplier copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    String? notes,
    double? balanceOwed,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      balanceOwed: balanceOwed ?? this.balanceOwed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
