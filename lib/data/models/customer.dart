class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final double balanceDue; // موجب = عليه دين، سالب = رصيد مسبق له
  final DateTime? paymentDueDate; // موعد سداد المديونية (اختياري)
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    this.balanceDue = 0.0,
    this.paymentDueDate,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasDebt => balanceDue > 0.01;

  bool get hasCredit => balanceDue < -0.01;

  /// متأخر عن موعد السداد: عليه دين ولم يسُدَّد قبل الموعد المحدد.
  bool get isOverdue {
    if (!hasDebt || paymentDueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(paymentDueDate!);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'balance_due': balanceDue,
      'payment_due_date':
          paymentDueDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    String? dueRaw = map['payment_due_date'] as String?;
    return Customer(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      balanceDue: (map['balance_due'] as num?)?.toDouble() ?? 0.0,
      paymentDueDate:
          dueRaw != null && dueRaw.isNotEmpty ? DateTime.parse(dueRaw) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    String? notes,
    double? balanceDue,
    DateTime? paymentDueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      balanceDue: balanceDue ?? this.balanceDue,
      paymentDueDate: paymentDueDate ?? this.paymentDueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
