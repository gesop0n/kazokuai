import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';

import '../../support/layout_matrix.dart';

// 文字の幅で変わる値は、同梱のフォントを読み込んで測る。
// 読み込んだフォントはこのファイルのテストにだけ効く。
Future<void> _loadFonts() async {
  const families = {
    'ZenMaruGothic': [
      'ZenMaruGothic-Regular',
      'ZenMaruGothic-Medium',
      'ZenMaruGothic-Bold',
      'ZenMaruGothic-Black',
    ],
    'ShipporiMincho': ['ShipporiMincho-Medium'],
    'DMMono': ['DMMono-Regular', 'DMMono-Medium'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}

const _mockLayout = LayoutCase(393, 1.0);
const _message = '金曜の通院、10時に迎えに行くと伝えて';
const _suggestion = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';
const _footNote = '押すと、すぐにハナさんの固定電話にかけます';

// 指定のシミュレーター(iPhone 17 Pro)で測った値
const _deviceSize = Size(402, 874);
const _statusBar = 62.0;
const _keyboardHeight = 336.0;

Future<void> _pumpWithMessage(WidgetTester tester, LayoutCase layout) async {
  await pumpScreenInLayout(tester, layout, const AskScreen());
  await tester.enterText(find.byType(TextField), _message);
  await tester.pump();
}

void _expectChipsOnOneRow(WidgetTester tester, List<Finder> chips) {
  final tops = chips.map((chip) => tester.getTopLeft(chip).dy).toSet();
  expect(tops, hasLength(1));
}

void main() {
  setUpAll(_loadFonts);

  // docs/mock/ui.html を headless Chrome で開いて測った値
  group('モックと同じ値', () {
    testWidgets('チップの幅は 68.84、83.13、111.69 で、1 行に並ぶ', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      const expected = {'ふつう': 68.84, 'ゆっくり': 83.13, 'カスタマイズ': 111.69};
      for (final MapEntry(key: label, value: width) in expected.entries) {
        expect(
          tester.getSize(find.widgetWithText(AppChip, label).first).width,
          closeTo(width, .5),
          reason: label,
        );
      }
      _expectChipsOnOneRow(tester, [
        find.widgetWithText(AppChip, 'ふつう').first,
        find.widgetWithText(AppChip, 'ゆっくり'),
        find.widgetWithText(AppChip, 'カスタマイズ').first,
      ]);
    });

    testWidgets('チップの左端は 88 で、チップの間隔は 6', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      final normal = tester.getRect(find.widgetWithText(AppChip, 'ふつう').first);
      final slow = tester.getRect(find.widgetWithText(AppChip, 'ゆっくり'));

      expect(normal.left, 88);
      expect(slow.left - normal.right, 6);
    });

    testWidgets('入力欄の高さ 60、幅 361、上の見出しとの間隔 8', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      final field = tester.getRect(find.byType(AppTextField));
      expect(field.size, const Size(361, 60));
      expect(field.top - tester.getBottomLeft(find.text('伝えたいこと')).dy, 8);
    });

    testWidgets('案の文は 3 行で、説明は 2 行', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      // 行の高さ 28 と 20
      expect(tester.getSize(find.text(_suggestion)).height, 84);
      expect(
        tester.getSize(find.text('電話ではこの言い方で伝えます。聞き返されたら、同じ内容をくり返します。')).height,
        40,
      );
    });

    testWidgets('案のカードはモックの 214 より「なおす」の 12 だけ高い', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      // モックの「なおす」は高さ 32 で、44pt にした分だけ伸びる
      expect(tester.getSize(find.byType(AppCard)).height, 214 + 12);
    });

    testWidgets('文言は 1 行で、通話 56、予約 44', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      expect(tester.getSize(find.text(_footNote)).height, 20);
      expect(tester.getSize(find.widgetWithText(AppButton, '通話')).height, 56);
      expect(
        tester.getSize(find.widgetWithText(AppButton, '日時を決めて予約する')).height,
        44,
      );
    });
  });

  group('文字の幅', () {
    testEachLayout('「ボリューム」はラベルの列に収まり、1 行のまま', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      final label = tester.getRect(find.text('ボリューム'));
      final chipLeft = tester
          .getTopLeft(find.widgetWithText(AppChip, 'ふつう').last)
          .dx;
      // 列の右に 8 の間隔が残る
      expect(chipLeft - label.right, greaterThanOrEqualTo(8));

      // 折り返すと 2 行分の高さになる
      expect(label.height, closeTo(16 * layout.textScale, 1));
    });

    testWidgets('幅 360 ではチップが折り返す', (tester) async {
      await pumpScreenInLayout(
        tester,
        const LayoutCase(360, 1.0),
        const AskScreen(),
      );

      final first = tester.getTopLeft(
        find.widgetWithText(AppChip, 'ふつう').first,
      );
      final last = tester.getTopLeft(
        find.widgetWithText(AppChip, 'カスタマイズ').first,
      );
      expect(last.dy, greaterThan(first.dy));
    });
  });

  group('iPhone 17 Pro でキーボードを出したとき', () {
    Future<void> pumpOnDevice(WidgetTester tester, double textScale) async {
      await pumpScreenInLayout(
        tester,
        LayoutCase(_deviceSize.width, textScale),
        const AskScreen(),
      );
      tester.view
        ..physicalSize = _deviceSize
        ..padding = const FakeViewPadding(top: _statusBar)
        ..viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
      addTearDown(tester.view.reset);
      await tester.enterText(find.byType(TextField), _message);
      await tester.pumpAndSettle();
    }

    testWidgets('文字倍率 1.0 では、入力欄と案の文の全部がスクロールせずに見える', (tester) async {
      await pumpOnDevice(tester, 1.0);

      final footTop = tester.getTopLeft(find.text(_footNote)).dy;
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(footTop),
      );
      expect(
        tester.getBottomLeft(find.text(_suggestion)).dy,
        lessThanOrEqualTo(footTop),
      );
    });

    testWidgets('文字倍率 1.3 では、案の文はスクロールすれば全部見える', (tester) async {
      await pumpOnDevice(tester, 1.3);

      final footTop = tester.getTopLeft(find.text(_footNote)).dy;
      // 入力欄と案の見出しはスクロールしなくても見える
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(footTop),
      );
      expect(
        tester.getBottomLeft(find.text('Geminiの言い方の案')).dy,
        lessThan(footTop),
      );
      expect(
        tester.getBottomLeft(find.text(_suggestion)).dy,
        greaterThan(footTop),
      );

      await tester.ensureVisible(find.text(_suggestion));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.text(_suggestion)).dy,
        lessThanOrEqualTo(footTop),
      );
    });
  });
}
