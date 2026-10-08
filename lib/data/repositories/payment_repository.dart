import '../../core/database/app_database.dart';
import '../models/payment.dart';

/// دفعة مرتبطة باسم الطرف (عميل/مورد) لعرضها مباشرة في القوائم.
class PaymentWithParty {
  final Payment payment;
  final String partyName;

  PaymentWithParty({required this.payment, required this.partyName});
}

class PaymentRepository {
  /// كل المدفوعات مع اسم الطرف، يُمكن فلترتها بنطاق تاريخي.
  Future<List<PaymentWithParty>> getAllPaymentsWithParty({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;

    String query = '''
      SELECT pay.*,
             c.name as customer_name,
             s.name as supplier_name
      FROM payments pay
      LEFT JOIN customers c
        ON pay.party_type = 'customer' AND pay.party_id = c.id
      LEFT JOIN suppliers s
        ON pay.party_type = 'supplier' AND pay.party_id = s.id
      WHERE 1=1
    ''';
    final args = <dynamic>[];

    if (startDate != null) {
      query += ' AND pay.created_at >= ?';
      args.add(DateTime(startDate.year, startDate.month, startDate.day)
          .toIso8601String());
    }
    if (endDate != null) {
      query += ' AND pay.created_at <= ?';
      args.add(
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
            .toIso8601String(),
      );
    }

    query += ' ORDER BY pay.created_at DESC';

    final maps = await db.rawQuery(query, args);

    return maps.map((m) {
      final payment = Payment.fromMap(m);
      final name = (m['customer_name'] as String?) ??
          (m['supplier_name'] as String?) ??
          'طرف محذوف';
      return PaymentWithParty(payment: payment, partyName: name);
    }).toList();
  }

  /// إجمالي تحصيلات العملاء (داخل) خلال فترة.
  Future<double> getTotalCollections({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;
    final args = <dynamic>[];
    String query = '''
      SELECT COALESCE(SUM(amount), 0.0) as total
      FROM payments
      WHERE direction = 'in'
    ''';

    if (startDate != null) {
      query += ' AND created_at >= ?';
      args.add(DateTime(startDate.year, startDate.month, startDate.day)
          .toIso8601String());
    }
    if (endDate != null) {
      query += ' AND created_at <= ?';
      args.add(
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
            .toIso8601String(),
      );
    }

    final result = await db.rawQuery(query, args);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// إجمالي المدفوعات للموردين (خارج) خلال فترة.
  Future<double> getTotalSupplierPayments({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await AppDatabase.instance;
    final args = <dynamic>[];
    String query = '''
      SELECT COALESCE(SUM(amount), 0.0) as total
      FROM payments
      WHERE direction = 'out'
    ''';

    if (startDate != null) {
      query += ' AND created_at >= ?';
      args.add(DateTime(startDate.year, startDate.month, startDate.day)
          .toIso8601String());
    }
    if (endDate != null) {
      query += ' AND created_at <= ?';
      args.add(
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
            .toIso8601String(),
      );
    }

    final result = await db.rawQuery(query, args);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
