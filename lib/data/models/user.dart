import '../../core/database/app_database.dart';

/// أدوار المستخدمين وفق SPECKIT Section 4 (Phase 3).
class User {
  final String id;
  final String name;
  final String username;
  final String passwordHash;
  final String role; // owner | cashier

  User({
    required this.id,
    required this.name,
    required this.username,
    required this.passwordHash,
    required this.role,
  });

  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isOwner => isAdmin; // للتوافق العكسي
  bool get isCashier => role == 'cashier';
  String get roleDisplayName => isAdmin ? 'أدمن' : 'كاشير';

  bool verifyPassword(String password) {
    return passwordHash == AppDatabase.hashPassword(password);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'password_hash': passwordHash,
      'role': role,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      username: map['username'] as String,
      passwordHash: map['password_hash'] as String,
      role: map['role'] as String,
    );
  }

  User copyWith({
    String? id,
    String? name,
    String? username,
    String? passwordHash,
    String? role,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
    );
  }
}
