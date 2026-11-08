import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

final _sample = sampleHomeDataFor(HomeStatus.missedCall);

Future<void> _pumpView(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
  MissedCall? missedCall,
  VoidCallback? onOpenAsk,
}) => pumpInLayout(
  tester,
  layout,
  MissedCallView(
    missedCall: missedCall ?? _sample.missedCall,
    onOpenAsk: onOpenAsk ?? () {},
  ),
);

void main() {
  group('崩れない', () {
    testEachLayout('不在の表示', (tester, layout) async {
      await _pumpView(tester, layout: layout);

      expect(find.byType(MissedCallView), findsOneWidget);
    });

    testEachLayout('かけた回数が多いとき', (tester, layout) async {
      await _pumpView(
        tester,
        layout: layout,
        missedCall: MissedCall(
          attemptedAt: [
            for (var hour = 9; hour < 14; hour++) DateTime(2026, 11, 5, hour),
          ],
        ),
      );

      expect(find.textContaining('13:00にかけましたが'), findsOneWidget);
    });

    testEachLayout('押せる領域は 44 以上になる', (tester, layout) async {
      await _pumpView(tester, layout: layout);

      final size = tester.getSize(find.byType(InkWell));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('モックの内容', () {
    testWidgets('注意のカード、伝えるカード、今日の様子の順に並ぶ', (tester) async {
      await _pumpView(tester);

      final cards = tester.widgetList<AppCard>(find.byType(AppCard)).toList();
      expect(cards.map((card) => card.variant), [
        AppCardVariant.alert,
        AppCardVariant.paper,
      ]);
      final alert = tester.getRect(find.byType(AppCard).first);
      final ask = tester.getRect(find.byType(AskCard));
      final today = tester.getRect(find.byType(AppCard).last);
      expect(ask.top, greaterThanOrEqualTo(alert.bottom));
      expect(today.top, greaterThanOrEqualTo(ask.bottom));
    });

    testWidgets('alert のカードの文字', (tester) async {
      await _pumpView(tester);

      expect(find.text('確認をお願いします'), findsOneWidget);
      expect(find.text('電話に出ていません'), findsOneWidget);
      expect(find.text('朝の電話に出ていません'), findsNothing);
      expect(find.text('9:00、9:15、9:30にかけましたが、応答がありませんでした。'), findsOneWidget);
      expect(find.textContaining('外出中の可能性もあります'), findsNothing);
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon).first).icon,
        AppIcons.phoneMissed,
      );
    });

    testWidgets('今日の様子のカード', (tester) async {
      await _pumpView(tester);

      expect(find.text('今日の様子'), findsOneWidget);
      expect(find.text('今日はまだ話せていません。'), findsOneWidget);
      expect(find.text('今日はまだ話せていないので、様子は分かっていません。'), findsNothing);
    });

    testWidgets('もう一度電話すると最後に話したときは出ない', (tester) async {
      await _pumpView(tester);

      expect(find.text('もう一度電話する'), findsNothing);
      expect(find.text('最後に話したとき'), findsNothing);
      expect(find.byType(AppButton), findsNothing);
    });
  });

  group('データから文字を作る', () {
    testWidgets('かけた時刻は attemptedAt から作る', (tester) async {
      await _pumpView(
        tester,
        missedCall: MissedCall(
          attemptedAt: [
            DateTime(2026, 11, 5, 8, 5),
            DateTime(2026, 11, 5, 18, 40),
          ],
        ),
      );

      expect(find.text('8:05、18:40にかけましたが、応答がありませんでした。'), findsOneWidget);
    });
  });

  group('AIに伝えてもらう', () {
    testWidgets('押すと onOpenAsk を呼ぶ', (tester) async {
      var count = 0;
      await _pumpView(tester, onOpenAsk: () => count++);

      await tester.tap(find.text('AIに伝えてもらう'));

      expect(count, 1);
    });
  });

  group('読み上げ', () {
    testWidgets('伝えるカードは押せるものとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('AIに伝えてもらう')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('カードの文字をそのまま読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester);

      expect(find.bySemanticsLabel(RegExp('電話に出ていません')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('最後に話したとき')), findsNothing);
      handle.dispose();
    });
  });

  group('formatRelativeDay の「昨日」', () {
    test('前の日は昨日と書く', () {
      expect(
        formatRelativeDay(
          DateTime(2026, 11, 4, 19),
          DateTime(2026, 11, 5, 9, 31),
        ),
        '昨日',
      );
    });

    test('24 時間以上前でも、前の日なら昨日と書く', () {
      expect(
        formatRelativeDay(
          DateTime(2026, 11, 4, 0, 1),
          DateTime(2026, 11, 5, 23, 59),
        ),
        '昨日',
      );
    });

    test('24 時間以内でも、前の日なら昨日と書く', () {
      expect(
        formatRelativeDay(
          DateTime(2026, 11, 4, 23, 59),
          DateTime(2026, 11, 5, 0, 1),
        ),
        '昨日',
      );
    });

    test('月の境目でも昨日と書く', () {
      expect(
        formatRelativeDay(DateTime(2026, 11, 30), DateTime(2026, 12)),
        '昨日',
      );
    });

    test('年の境目でも昨日と書く', () {
      expect(formatRelativeDay(DateTime(2026, 12, 31), DateTime(2027)), '昨日');
    });

    test('2 日前は月日で書く', () {
      expect(
        formatRelativeDay(DateTime(2026, 11, 3), DateTime(2026, 11, 5)),
        '11月3日',
      );
    });

    test('次の日は月日で書く', () {
      expect(
        formatRelativeDay(DateTime(2026, 11, 6), DateTime(2026, 11, 5)),
        '11月6日',
      );
    });

    test('去年の同じ月の前の日は月日で書く', () {
      expect(
        formatRelativeDay(DateTime(2025, 11, 4), DateTime(2026, 11, 5)),
        '11月4日',
      );
    });

    test('同じ日は今日のまま', () {
      expect(
        formatRelativeDay(DateTime(2026, 11, 5, 9), DateTime(2026, 11, 5)),
        '今日',
      );
    });
  });
}
