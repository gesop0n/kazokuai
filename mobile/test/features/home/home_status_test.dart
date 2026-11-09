import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

List<Override> _startingAt(HomeStatus status) => [
  homeStatusProvider.overrideWithBuild((ref, self) => status),
];

Future<void> _pumpHome(
  WidgetTester tester,
  HomeStatus status, {
  LayoutCase layout = _standardLayout,
}) => pumpScreenInLayout(
  tester,
  layout,
  Scaffold(body: HomeScreen(data: sampleHomeDataFor(status))),
  overrides: _startingAt(status),
);

void main() {
  group('homeStatusFromDefine', () {
    test('空の文字は normal', () {
      expect(homeStatusFromDefine(''), HomeStatus.normal);
    });

    test('missedCall を読め、calling はもう状態ではない', () {
      expect(homeStatusFromDefine('missedCall'), HomeStatus.missedCall);
      expect(homeStatusFromDefine('normal'), HomeStatus.normal);
      expect(homeStatusFromDefine('calling'), HomeStatus.normal);
    });

    test('不明な値は normal', () {
      expect(homeStatusFromDefine('Calling'), HomeStatus.normal);
      expect(homeStatusFromDefine('unknown'), HomeStatus.normal);
    });
  });

  group('HomeStatusNotifier', () {
    test('--dart-define を渡さないと normal から始まる', () {
      final container = ProviderContainer.test();

      expect(container.read(homeStatusProvider), HomeStatus.normal);
    });
  });

  group('sampleHomeDataFor', () {
    test('状態ごとの基準日時はモックの hhead の文字と同じ', () {
      expect(
        sampleHomeDataFor(HomeStatus.normal).now,
        DateTime(2026, 11, 5, 10, 24),
      );
      expect(
        sampleHomeDataFor(HomeStatus.missedCall).now,
        DateTime(2026, 11, 5, 9, 31),
      );
    });

    test('sampleHomeData は normal と同じ', () {
      expect(sampleHomeData.now, sampleHomeDataFor(HomeStatus.normal).now);
    });

    test('不在の時刻はかけなおしの既定の 15 分おき', () {
      final missedCall = sampleHomeDataFor(HomeStatus.missedCall).missedCall;
      expect(missedCall.attemptedAt, [
        DateTime(2026, 11, 5, 9, 0),
        DateTime(2026, 11, 5, 9, 15),
        DateTime(2026, 11, 5, 9, 30),
      ]);
    });
  });

  group('overflow', () {
    for (final status in HomeStatus.values) {
      testEachLayout('ホーム画面(${status.name})', (tester, layout) async {
        await _pumpHome(tester, status, layout: layout);

        expect(find.byType(HomeHeader), findsOneWidget);
      });
    }

    testEachLayout('不在の表示', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        MissedCallView(missedCall: sampleHomeData.missedCall, onOpenAsk: () {}),
      );

      expect(find.byType(MissedCallView), findsOneWidget);
    });
  });

  group('表示の分岐', () {
    testWidgets('normal は 3 枚のカードで、帯も不在の表示も 7 日間も出さない', (tester) async {
      await _pumpHome(tester, HomeStatus.normal);

      expect(find.text('11月5日(木) 10:24 時点'), findsOneWidget);
      expect(find.byType(RecentCallCard), findsOneWidget);
      expect(find.byType(AskCard), findsOneWidget);
      expect(find.byType(TodayCard), findsOneWidget);
      expect(find.text('7日間の電話'), findsNothing);
      expect(find.text('通話中'), findsNothing);
      expect(find.byType(MissedCallView), findsNothing);
    });

    testWidgets('missedCall はヘッダーの下を MissedCallView に置き換える', (tester) async {
      await _pumpHome(tester, HomeStatus.missedCall);

      expect(find.text('11月5日(木) 9:31 時点'), findsOneWidget);
      expect(find.byType(MissedCallView), findsOneWidget);
      expect(find.byType(AskCard), findsOneWidget);
      expect(find.text('電話に出ていません'), findsOneWidget);
      expect(find.text('もう一度電話する'), findsNothing);
      expect(find.text('最後に話したとき'), findsNothing);
      expect(find.byType(RecentCallCard), findsNothing);
      expect(find.byType(TodayCard), findsNothing);
      expect(find.text('通話中'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(MissedCallView)).dy,
        tester.getBottomLeft(find.byType(HomeHeader)).dy,
      );
    });

    testWidgets('07b のカードを押すと 01 が開く', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._startingAt(HomeStatus.missedCall),
            signedInAuth(),
            registeredWatchedPerson(),
            sampleCalls(),
          ],
          child: const KazokuAiApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('AIに伝えてもらう'));
      await tester.pumpAndSettle();

      expect(find.byType(AskScreen), findsOneWidget);
      expect(find.byType(MissedCallView), findsNothing);
    });
  });

  group('状態バーの裏', () {
    const statusBar = 54.0;

    void setStatusBar(WidgetTester tester) {
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPadding);
    }

    testWidgets('normal と missedCall のヘッダーは状態バーの下から始まる', (tester) async {
      setStatusBar(tester);
      for (final status in [HomeStatus.normal, HomeStatus.missedCall]) {
        await _pumpHome(tester, status);

        expect(tester.getTopLeft(find.byType(HomeHeader)).dy, statusBar);
      }
    });
  });
}
