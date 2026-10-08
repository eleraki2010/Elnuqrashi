import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alnokrashy_pos/main.dart';
import 'package:alnokrashy_pos/core/constants/app_constants.dart';

void main() {
  testWidgets(
    'App smoke test - verifies store title',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: AlnokrashyPOSApp(),
        ),
      );

      expect(find.text(AppStrings.STORE_NAME), findsWidgets);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    },
    skip: true,
  );
}
