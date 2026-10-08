import 'dart:io';

import 'package:alnokrashy_pos/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory testSupportDir = Directory.systemTemp;

  setUpAll(() async {
    testSupportDir =
        await Directory.systemTemp.createTemp('alnokrashy_probe_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return testSupportDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (await testSupportDir.exists()) {
        await testSupportDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('probe: FFI query completes outside widget', (tester) async {
    final rows = await tester.runAsync<List<Map<String, dynamic>>>(
      () async {
        final db = await AppDatabase.instance;
        return db.query('products');
      },
    );
    expect(rows, isNotNull);
    // DB init seed: default categories exist, products may be empty.
    print('products rows: ${rows!.length}');
  });

  testWidgets('probe: future created in fake zone completes via runAsync',
      (tester) async {
    // future مهيّأ قبل الـ widget (في fake zone) — هل يكتمل؟
    final probe = <Future<int>>[];
    await tester.runAsync(() async {
      final db = await AppDatabase.instance;
      probe.add(db.query('products').then((m) => m.length));
    });

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    int value = -1;
    await tester.runAsync(() async {
      value = await probe.first.timeout(
        const Duration(seconds: 5),
      );
    });
    expect(value, greaterThanOrEqualTo(0));
    print('probe value: $value');
  });

  testWidgets('probe: query future created in FAKE zone completes?',
      (tester) async {
    // init القاعدة في zone حقيقي أولاً.
    await tester.runAsync(() async {
      await AppDatabase.instance;
    });

    // future يُنشأ في الـ fake zone (مثل FutureBuilder أثناء البناء)
    // ثم ننتظر اكتماله من الـ zone الحقيقي.
    final captured = <Future<List<Map<String, dynamic>>>>[];
    Future<List<Map<String, dynamic>>> fakeZoneQuery() async {
      final db = await AppDatabase.instance;
      final rows = db.query('products');
      captured.add(rows);
      return rows;
    }

    await tester.pumpWidget(
      FutureBuilder(
        future: fakeZoneQuery(),
        builder: (_, _) => const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    int outcome = -1;
    await tester.runAsync(() async {
      try {
        final rows = await captured.first.timeout(
          const Duration(seconds: 4),
        );
        outcome = rows.length;
      } catch (e) {
        print('fake-zone future FAILED: $e');
      }
    });
    print('fake-zone future outcome: $outcome');
    expect(outcome, isNonNegative);
  });
}
