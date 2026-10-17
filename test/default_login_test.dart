import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:alnokrashy_pos/data/repositories/user_repository.dart';

void main() {
  late Directory testSupportDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testSupportDir = await Directory.systemTemp.createTemp('pos_login_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => testSupportDir.path,
    );
  });

  tearDownAll(() async {
    try {
      if (testSupportDir.existsSync()) {
        testSupportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('Default user 1 with password 123 authenticates successfully', () async {
    final repo = UserRepository();
    final user = await repo.authenticate('1', '123');

    expect(user, isNotNull);
    expect(user!.username, '1');
    expect(user.role, 'owner');
    expect(user.verifyPassword('123'), true);
  });

  test('Default user 1 with password 123 authenticates with Arabic digits', () async {
    final repo = UserRepository();
    final user = await repo.authenticate('١', '١٢٣');

    expect(user, isNotNull);
    expect(user!.username, '1');
    expect(user.role, 'owner');
  });

  test('Wrong password fails authentication', () async {
    final repo = UserRepository();
    final user = await repo.authenticate('1', 'wrong_pass');

    expect(user, isNull);
  });
}
