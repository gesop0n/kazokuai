import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';

import '../../support/layout_matrix.dart';

// 文字の幅で変わる値は、同梱のフォントを読み込んで測る。
// 読み込んだフォントはこのファイルのテストにだけ効く。
Future<void> _loadFonts() async {
  const families = {
    'BIZUDPGothic': ['BIZUDPGothic-Regular', 'BIZUDPGothic-Bold'],
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
const _script = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';
const _removedNote = '電話ではこの言い方で伝えます。聞き返されたら、同じ内容をくり返します。';
const _removedFootNote = '押すと、すぐにハナさんの固定電話にかけます';

// 指定のシミュレーター(iPhone 17 Pro)で測った値
const _deviceSize = Size(402, 874);
const _statusBar = 62.0;
const _keyboardHeight = 336.0;

Future<void> _pumpWithMessage(WidgetTester tester, LayoutCase layout) async {
  await pumpScreenInLayout(tester, layout, const AskScreen());
  await tester.enterText(find.byType(TextField), _message);
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);

  // docs/mock/ui.html の 01 を headless Chrome で、BIZ UDPゴシックを読み込んで測った値。
  // 画面の上の状態バー 54 は引いてある。
  group('モックと同じ値', () {
    testWidgets('入力欄の高さ 60、幅 361、上の見出しとの間隔 8', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      final field = tester.getRect(find.byType(AppTextField));
      expect(field.size, const Size(361, 60));
      expect(field.top - tester.getBottomLeft(find.text('伝えたいこと')).dy, 8);
    });

    testWidgets('通話内容の文は 3 行で、削った説明はない', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      // 行の高さ 28
      expect(tester.getSize(find.text(_script)).height, 84);
      expect(find.text(_removedNote), findsNothing);
      expect(find.text('話し方'), findsNothing);
    });

    testWidgets('通話内容のカードはモックの 162 より「なおす」の 12 だけ高い', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      // モックの「なおす」は高さ 32 で、44pt にした分だけ伸びる
      expect(tester.getSize(find.byType(AppCard)).height, 162 + 12);
    });

    testWidgets('日付と時刻の欄は高さ 56、幅 176.5 で、間は 8', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      final date = tester.getRect(find.text('11/6(金)'));
      final time = tester.getRect(find.text('08:30'));
      // 文字の箱ではなく、欄の面を測る
      final dateField = tester.getRect(
        find.ancestor(of: find.text('11/6(金)'), matching: find.byType(InkWell)),
      );
      final timeField = tester.getRect(
        find.ancestor(of: find.text('08:30'), matching: find.byType(InkWell)),
      );

      expect(dateField.size, const Size(176.5, 56));
      expect(timeField.size, const Size(176.5, 56));
      expect(timeField.left - dateField.right, 8);
      expect(date.top, time.top);
      expect(
        tester.getTopLeft(find.text('日付')).dy -
            tester.getBottomLeft(find.byType(AppCard)).dy,
        16,
      );
    });

    testWidgets('予約は 56、今すぐ通話は 44 で、削った文言はない', (tester) async {
      await _pumpWithMessage(tester, _mockLayout);

      expect(find.text(_removedFootNote), findsNothing);
      expect(
        tester.getSize(find.widgetWithText(AppButton, 'この日時で予約する')),
        const Size(361, 56),
      );
      expect(
        tester.getSize(find.widgetWithText(AppButton, '今すぐ通話')).height,
        44,
      );
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

      final footTop = tester
          .getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する'))
          .dy;
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(footTop),
      );
      expect(
        tester.getBottomLeft(find.text(_script)).dy,
        lessThanOrEqualTo(footTop),
      );
    });

    testWidgets('文字倍率 1.3 では、通話内容の文はスクロールすれば全部見える', (tester) async {
      await pumpOnDevice(tester, 1.3);

      final footTop = tester
          .getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する'))
          .dy;
      // 入力欄と通話内容の見出しはスクロールしなくても見える
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(footTop),
      );
      expect(tester.getBottomLeft(find.text('通話内容')).dy, lessThan(footTop));
      expect(tester.getBottomLeft(find.text(_script)).dy, greaterThan(footTop));

      await tester.ensureVisible(find.text(_script));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.text(_script)).dy,
        lessThanOrEqualTo(footTop),
      );
    });
  });
}
