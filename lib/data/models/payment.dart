class Payment {
  final String id;
  final String partyType; // 'customer' or 'supplier'
  final String partyId;
  final double amount;
  final String direction; // 'in' (received from customer) or 'out' (paid to supplier)
  final String? note;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.partyType,
    required this.partyId,
    required this.amount,
    required this.direction,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'party_type': partyType,
      'party_id': partyId,
      'amount': amount,
      'direction': direction,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as String,
      partyType: map['party_type'] as String,
      partyId: map['party_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      direction: map['direction'] as String,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
