import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/calling_banner.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';
import 'package:kazokuai/features/home/home_screen.dart';
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
  DateTime? now,
  VoidCallback? onCallAgain,
}) => pumpInLayout(
  tester,
  layout,
  MissedCallView(
    missedCall: missedCall ?? _sample.missedCall,
    now: now ?? _sample.now,
    onCallAgain: onCallAgain ?? () {},
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
          lastTalk: _sample.missedCall.lastTalk,
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
    testWidgets('alert のカードと 2 枚のカードが順に並ぶ', (tester) async {
      await _pumpView(tester);

      final cards = tester.widgetList<AppCard>(find.byType(AppCard)).toList();
      expect(cards.map((card) => card.variant), [
        AppCardVariant.alert,
        AppCardVariant.paper,
        AppCardVariant.paper,
      ]);
    });

    testWidgets('alert のカードの文字', (tester) async {
      await _pumpView(tester);

      expect(find.text('確認をお願いします'), findsOneWidget);
      expect(find.text('朝の電話に出ていません'), findsOneWidget);
      expect(find.text('9:00、9:10、9:20にかけましたが、応答がありません。'), findsOneWidget);
      expect(find.textContaining('外出中の可能性もあります'), findsNothing);
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon).first).icon,
        AppIcons.phoneMissed,
      );
    });

    testWidgets('今日の様子のカード', (tester) async {
      await _pumpView(tester);

      expect(find.text('今日の様子'), findsOneWidget);
      expect(find.text('今日はまだ話せていないので、様子は分かっていません。'), findsOneWidget);
    });

    testWidgets('最後に話したときのカード', (tester) async {
      await _pumpView(tester);

      expect(find.text('最後に話したとき'), findsOneWidget);
      expect(find.text('昨日 19:00 ・ 3分'), findsOneWidget);
      expect(find.text('「さっき飲んだよ。膝が少し痛むけど、大丈夫。」'), findsOneWidget);
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
          lastTalk: _sample.missedCall.lastTalk,
        ),
      );

      expect(find.text('8:05、18:40にかけましたが、応答がありません。'), findsOneWidget);
    });

    testWidgets('最後に話したときの時刻と長さは lastTalk から作る', (tester) async {
      await _pumpView(
        tester,
        missedCall: MissedCall(
          attemptedAt: _sample.missedCall.attemptedAt,
          lastTalk: LastTalk(
            startedAt: DateTime(2026, 11, 2, 7, 5),
            duration: const Duration(minutes: 12),
            quote: '「元気だよ」',
          ),
        ),
      );

      expect(find.text('11月2日 7:05 ・ 12分'), findsOneWidget);
      expect(find.text('「元気だよ」'), findsOneWidget);
    });

    testWidgets('「昨日」は now をもとに決める', (tester) async {
      await _pumpView(tester, now: DateTime(2026, 11, 6, 9));

      expect(find.text('11月4日 19:00 ・ 3分'), findsOneWidget);
    });
  });

  group('もう一度電話する', () {
    testWidgets('ボタンは white の L が 1 つだけ', (tester) async {
      await _pumpView(tester);

      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.label, 'もう一度電話する');
      expect(button.variant, AppButtonVariant.white);
      expect(button.size, AppButtonSize.l);
      expect(button.leadingIcon, AppIcons.phone);
    });

    testWidgets('押すと onCallAgain を呼ぶ', (tester) async {
      var callCount = 0;
      await _pumpView(tester, onCallAgain: () => callCount++);

      await tester.tap(find.text('もう一度電話する'));

      expect(callCount, 1);
    });

    testWidgets('ホーム画面で押すと通話中の表示になる', (tester) async {
      await pumpScreenInLayout(
        tester,
        _standardLayout,
        const Scaffold(body: HomeScreen()),
        overrides: [
          homeStatusProvider.overrideWithBuild(
            (ref, self) => HomeStatus.missedCall,
          ),
        ],
      );
      expect(find.text('昨日 19:00 ・ 3分'), findsOneWidget);

      await tester.tap(find.text('もう一度電話する'));
      await tester.pump();

      expect(find.byType(CallingBanner), findsOneWidget);
      expect(find.byType(MissedCallView), findsNothing);
    });
  });

  group('読み上げ', () {
    testWidgets('ボタンは押せるものとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('もう一度電話する')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('カードの文字をそのまま読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester);

      expect(find.bySemanticsLabel(RegExp('朝の電話に出ていません')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('昨日 19:00 ・ 3分')), findsOneWidget);
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
