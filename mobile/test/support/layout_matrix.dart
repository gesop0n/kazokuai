import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_theme.dart';

class LayoutCase {
  const LayoutCase(this.width, this.textScale);

  final double width;
  final double textScale;

  @override
  String toString() => '幅 ${width.toInt()}、文字倍率 $textScale';
}

// ADR の確認範囲
const layoutCases = [
  LayoutCase(360, 1.0),
  LayoutCase(360, 1.3),
  LayoutCase(393, 1.0),
  LayoutCase(393, 1.3),
  LayoutCase(440, 1.0),
  LayoutCase(440, 1.3),
];

// モックの画面の高さ
const _screenHeight = 852.0;

// 組み合わせごとに testWidgets を作る。
// overflow は pump の中で例外として報告されるので、ビルドするだけでテストが失敗する。
void testEachLayout(
  String description,
  Future<void> Function(WidgetTester tester, LayoutCase layout) body,
) {
  for (final layout in layoutCases) {
    testWidgets('$description($layout)', (tester) => body(tester, layout));
  }
}

// 部品やカードをビルドする。ホームの列と同じく、左右に 16 の余白を取って幅いっぱいに置く。
// 幅を決められると困る部品は、Align で包んで渡す。
Future<void> pumpInLayout(
  WidgetTester tester,
  LayoutCase layout,
  Widget child,
) {
  return pumpScreenInLayout(
    tester,
    layout,
    Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

// 画面全体をビルドする。ListView は画面外をビルドしないので、下まで確かめるときはスクロールする。
Future<void> pumpScreenInLayout(
  WidgetTester tester,
  LayoutCase layout,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(layout.width, _screenHeight);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = layout.textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme,
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: screen,
      ),
    ),
  );
}
