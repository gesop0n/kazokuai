import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_card_heading.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

import '../../support/layout_matrix.dart';

// 高さと baseline は文字の幅とフォントの値で変わるので、同梱のフォントを読み込んで測る。
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

// モックの .hcol の幅 361 にするときの画面の幅
const _mockLayout = LayoutCase(393, 1.0);

double _baselineOf(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderBox>(find.text(text));
  // getDistanceToBaseline はレイアウト中にしか呼べない
  final baseline = paragraph.getDryBaseline(
    paragraph.constraints,
    TextBaseline.alphabetic,
  )!;
  return paragraph.localToGlobal(Offset(0, baseline)).dy;
}

void main() {
  setUpAll(_loadFonts);

  // docs/mock/ui.html を headless Chrome で開いて測った値
  group('カードの高さがモックと同じ', () {
    testWidgets('今日の様子は 393', (tester) async {
      await pumpInLayout(
        tester,
        _mockLayout,
        TodayCard(call: sampleHomeData.latestCall),
      );

      expect(tester.getSize(find.byType(TodayCard)), const Size(361, 393));
    });

    testWidgets('AIに伝えてもらうは 188', (tester) async {
      await pumpInLayout(tester, _mockLayout, AskCard(onOpenAsk: () {}));

      expect(tester.getSize(find.byType(AskCard)), const Size(361, 188));
    });

    testWidgets('この7日間の電話は 338', (tester) async {
      await pumpInLayout(
        tester,
        _mockLayout,
        WeekCard(week: sampleHomeData.week, onOpenCallLog: () {}),
      );

      expect(tester.getSize(find.byType(WeekCard)), const Size(361, 338));
    });
  });

  group('見出しとラベルの baseline が揃う', () {
    for (final textScale in [1.0, 1.3]) {
      for (final (name, title, label, card) in [
        (
          'AIに伝えてもらう',
          'AIに伝えてもらう',
          '予約もできます',
          (VoidCallback noop) => AskCard(onOpenAsk: noop),
        ),
        (
          '今日の様子',
          '今日の様子',
          '9:02の会話より',
          (VoidCallback noop) => TodayCard(call: sampleHomeData.latestCall),
        ),
        (
          'この7日間の電話',
          'この7日間の電話',
          '棒の数字は話した分数',
          (VoidCallback noop) =>
              WeekCard(week: sampleHomeData.week, onOpenCallLog: noop),
        ),
      ]) {
        // 幅 440 ならどの倍率でも 1 行に収まる
        testWidgets('$name(文字倍率 $textScale)', (tester) async {
          await pumpInLayout(tester, LayoutCase(440, textScale), card(() {}));

          expect(
            _baselineOf(tester, title),
            closeTo(_baselineOf(tester, label), .001),
          );
        });
      }
    }
  });

  group('幅 360、文字倍率 1.3', () {
    testWidgets('AIに伝えてもらうの見出しはラベルを次の行に送り、あふれない', (tester) async {
      await pumpInLayout(
        tester,
        const LayoutCase(360, 1.3),
        AskCard(onOpenAsk: () {}),
      );

      final heading = tester.getRect(find.byType(HomeCardHeading));
      expect(
        tester.getRect(find.text('予約もできます')).top,
        greaterThanOrEqualTo(tester.getRect(find.text('AIに伝えてもらう')).bottom),
      );
      expect(
        tester.getRect(find.text('予約もできます')).right,
        lessThan(heading.right),
      );
    });
  });
}
