import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../models/audit_log.dart';

/// سجل عملية مرفق باسم المستخدم المتخذ للقرار (يُعرض في شاشة سجل العمليات).
class DetailedAuditLog {
  final AuditLog log;
  final String? userName;
  final String? userUsername;
  final String? userRole;

  DetailedAuditLog({
    required this.log,
    this.userName,
    this.userUsername,
    this.userRole,
  });

  /// اسم المستخدم كما يُعرض للمالك (الاسم الكامل مع الدور بين قوسين).
  String get userDisplayName =>
      userName != null ? '$userName (${userRole == 'owner' || userRole == 'admin' ? 'أدمن' : 'كاشير'})' : 'غير مسجَّل';
}

class AuditLogRepository {
  final _uuid = const Uuid();

  Future<List<AuditLog>> getAllLogs({int limit = 100}) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'audit_logs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => AuditLog.fromMap(m)).toList();
  }

  /// سجل العمليات مفصّلاً مع اسم المستخدم الذي اتخذ كل قرار.
  Future<List<DetailedAuditLog>> getAllLogsDetailed({int limit = 200}) async {
    final db = await AppDatabase.instance;
    final maps = await db.rawQuery(
      '''
      SELECT al.*, u.name as user_name, u.username as user_username, u.role as user_role
      FROM audit_logs al
      LEFT JOIN users u ON u.id = al.user_id
      ORDER BY al.created_at DESC
      LIMIT ?
    ''',
      [limit],
    );
    return maps
        .map(
          (m) => DetailedAuditLog(
            log: AuditLog.fromMap(m),
            userName: m['user_name'] as String?,
            userUsername: m['user_username'] as String?,
            userRole: m['user_role'] as String?,
          ),
        )
        .toList();
  }

  Future<List<AuditLog>> getLogsForRecord(String tableName, String recordId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'audit_logs',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: [tableName, recordId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => AuditLog.fromMap(m)).toList();
  }

  Future<void> insertLog(AuditLog log) async {
    final db = await AppDatabase.instance;
    await db.insert('audit_logs', log.toMap());
  }

  Future<void> logAction({
    required String tableName,
    required String recordId,
    required String action,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    String? userId,
    String? note,
  }) async {
    final log = AuditLog(
      id: _uuid.v4(),
      tableName: tableName,
      recordId: recordId,
      action: action,
      oldValues: oldValues,
      newValues: newValues,
      userId: userId,
      note: note,
      createdAt: DateTime.now(),
    );
    await insertLog(log);
  }
}
