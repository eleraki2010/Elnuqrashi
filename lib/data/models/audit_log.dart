import 'dart:convert';

class AuditLog {
  final String id;
  final String tableName;
  final String recordId;
  final String action; // insert, update, delete, cancel
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? userId;
  final String? note;
  final DateTime createdAt;

  AuditLog({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.oldValues,
    this.newValues,
    this.userId,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'old_values': oldValues != null ? _encodeMap(oldValues!) : null,
      'new_values': newValues != null ? _encodeMap(newValues!) : null,
      'user_id': userId,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      tableName: map['table_name'] as String,
      recordId: map['record_id'] as String,
      action: map['action'] as String,
      oldValues: _decodeMap(map['old_values'] as String?),
      newValues: _decodeMap(map['new_values'] as String?),
      userId: map['user_id'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static String? _encodeMap(Map<String, dynamic> map) {
    try {
      return Uri.encodeComponent(_simpleEncode(map));
    } catch (_) {
      return null;
    }
  }

  static String _simpleEncode(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    bool first = true;
    for (final entry in map.entries) {
      if (!first) {
        buffer.write('&');
      }
      first = false;
      buffer.write('${entry.key}=${entry.value}');
    }
    return buffer.toString();
  }

  static Map<String, dynamic>? _decodeMap(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;

    // المستودعات تخزّن JSON نصي في new_values/old_values، لذا نحاول فكه أولاً.
    final json = _tryParseJson(encoded);
    if (json != null) return json;

    // التوافق مع الصيغة القديمة (key=value&key2=value2).
    final result = <String, dynamic>{};
    final decoded = Uri.decodeFull(encoded);
    for (final pair in decoded.split('&')) {
      final idx = pair.indexOf('=');
      if (idx > 0) {
        result[pair.substring(0, idx)] = pair.substring(idx + 1);
      }
    }
    return result;
  }

  static Map<String, dynamic>? _tryParseJson(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ليس JSON صالح — نتركها للمُفكّك القديم.
    }
    return null;
  }
}
