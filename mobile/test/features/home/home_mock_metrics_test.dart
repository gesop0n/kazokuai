import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

import '../../support/layout_matrix.dart';

// 高さと baseline は文字の幅とフォントの値で変わるので、同梱のフォントを読み込んで測る。
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
    testWidgets('今日の様子は 341', (tester) async {
      await pumpInLayout(
        tester,
        _mockLayout,
        TodayCard(call: sampleHomeData.latestCall),
      );

      expect(tester.getSize(find.byType(TodayCard)), const Size(361, 341));
    });

    testWidgets('AIに伝えてもらうは 188', (tester) async {
      await pumpInLayout(tester, _mockLayout, AskCard(onOpenAsk: () {}));

      expect(tester.getSize(find.byType(AskCard)), const Size(361, 188));
    });

    testWidgets('7日間の電話は 338', (tester) async {
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
      // 幅 440 ならどの倍率でも 1 行に収まる。右のラベルが残るのは今日の様子だけ
      testWidgets('今日の様子(文字倍率 $textScale)', (tester) async {
        await pumpInLayout(
          tester,
          LayoutCase(440, textScale),
          TodayCard(call: sampleHomeData.latestCall),
        );

        expect(
          _baselineOf(tester, '今日の様子'),
          closeTo(_baselineOf(tester, '9:02の会話より'), .001),
        );
      });
    }
  });
}
