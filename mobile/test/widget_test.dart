import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/features/home/home_screen.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_home_repository.dart';
import 'support/fake_watched_person_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('アプリが起動してロケールが ja になる', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInAuth(), registeredWatchedPerson(), sampleHome()],
        child: const KazokuAiApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    expect(Localizations.localeOf(context), const Locale('ja'));
  });

  testWidgets('文字倍率は 1.3 までしか追従しない', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [signedInAuth(), registeredWatchedPerson(), sampleHome()],
        child: const KazokuAiApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    expect(MediaQuery.textScalerOf(context).scale(10), 13);
  });

  test('AppIcons は23個ある', () {
    expect(AppIcons.values, hasLength(23));
  });

  for (final icon in AppIcons.values) {
    test('${icon.assetPath} を読める', () async {
      final bytes = await SvgAssetLoader(icon.assetPath).loadBytes(null);
      expect(bytes.lengthInBytes, greaterThan(0));
    });
  }
}
