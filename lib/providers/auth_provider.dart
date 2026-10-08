import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/user.dart';
import '../data/repositories/user_repository.dart';

const String _sessionKey = 'session_user_id';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

/// جسم الجلسة: المستخدم الحالي + جاهزية الاستعادة.
class AuthState {
  final User? user;
  final bool initialized;

  const AuthState({this.user, required this.initialized});

  bool get isLoggedIn => user != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(initialized: false);

  /// استعادة الجلسة المحفوظة عند بدء التطبيق.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_sessionKey);
    if (userId == null) {
      state = const AuthState(initialized: true);
      return;
    }

    final repo = ref.read(userRepositoryProvider);
    final user = await repo.getUserById(userId);
    state = AuthState(user: user, initialized: true);
  }

  /// تسجيل الدخول. يُرجع true عند النجاح.
  Future<bool> login(String username, String password) async {
    final repo = ref.read(userRepositoryProvider);
    final user = await repo.authenticate(username, password);
    if (user == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, user.id);
    state = AuthState(user: user, initialized: true);
    return true;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    state = const AuthState(initialized: true);
  }

  /// تحديث المستخدم الحالي (مثلاً بعد تغيير بياناته).
  Future<void> refreshCurrentUser() async {
    final current = state.user;
    if (current == null) return;
    final repo = ref.read(userRepositoryProvider);
    final updated = await repo.getUserById(current.id);
    state = AuthState(user: updated, initialized: true);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// اختصار للتحقق من صلاحية المالك.
final isOwnerProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).user?.isOwner ?? false;
});
