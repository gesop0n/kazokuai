import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('アプリが起動してロケールが ja になる', (tester) async {
    await tester.pumpWidget(const KazokuAiApp());
    await tester.pump();

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('ja'));
  });

  test('AppIcons は22個ある', () {
    expect(AppIcons.values, hasLength(22));
  });

  for (final icon in AppIcons.values) {
    test('${icon.assetPath} を読める', () async {
      final bytes = await SvgAssetLoader(icon.assetPath).loadBytes(null);
      expect(bytes.lengthInBytes, greaterThan(0));
    });
  }
}
