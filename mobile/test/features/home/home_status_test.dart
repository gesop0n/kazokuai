import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/calling_banner.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

import '../../support/fake_auth_repository.dart';
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
  const Scaffold(body: HomeScreen()),
  overrides: _startingAt(status),
);

void main() {
  group('homeStatusFromDefine', () {
    test('空の文字は normal', () {
      expect(homeStatusFromDefine(''), HomeStatus.normal);
    });

    test('calling と missedCall を読める', () {
      expect(homeStatusFromDefine('calling'), HomeStatus.calling);
      expect(homeStatusFromDefine('missedCall'), HomeStatus.missedCall);
      expect(homeStatusFromDefine('normal'), HomeStatus.normal);
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

    for (final status in HomeStatus.values) {
      test('${status.name} から startCall で calling になる', () {
        final container = ProviderContainer.test(
          overrides: _startingAt(status),
        );

        container.read(homeStatusProvider.notifier).startCall();

        expect(container.read(homeStatusProvider), HomeStatus.calling);
      });
    }
  });

  group('sampleHomeDataFor', () {
    test('状態ごとの基準日時はモックの hhead の文字と同じ', () {
      expect(
        sampleHomeDataFor(HomeStatus.normal).now,
        DateTime(2026, 11, 5, 10, 24),
      );
      expect(
        sampleHomeDataFor(HomeStatus.calling).now,
        DateTime(2026, 11, 5, 10, 27),
      );
      expect(
        sampleHomeDataFor(HomeStatus.missedCall).now,
        DateTime(2026, 11, 5, 9, 31),
      );
    });

    test('sampleHomeData は normal と同じ', () {
      expect(sampleHomeData.now, sampleHomeDataFor(HomeStatus.normal).now);
    });

    test('不在のデータはモックの 07b と同じ', () {
      final missedCall = sampleHomeDataFor(HomeStatus.missedCall).missedCall;
      expect(missedCall.attemptedAt, [
        DateTime(2026, 11, 5, 9, 0),
        DateTime(2026, 11, 5, 9, 15),
        DateTime(2026, 11, 5, 9, 30),
      ]);
      expect(missedCall.lastTalk.startedAt, DateTime(2026, 11, 4, 19, 0));
      expect(missedCall.lastTalk.duration, const Duration(minutes: 3));
      expect(missedCall.lastTalk.quote, '「さっき飲んだよ。膝が少し痛むけど、大丈夫。」');
    });
  });

  group('overflow', () {
    for (final status in HomeStatus.values) {
      testEachLayout('ホーム画面(${status.name})', (tester, layout) async {
        await _pumpHome(tester, status, layout: layout);

        expect(find.byType(HomeHeader), findsOneWidget);
      });
    }

    testEachLayout('通話中の帯', (tester, layout) async {
      await pumpInLayout(tester, layout, const CallingBanner());

      expect(find.byType(CallingBanner), findsOneWidget);
    });

    testEachLayout('不在の表示', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        MissedCallView(
          missedCall: sampleHomeData.missedCall,
          now: sampleHomeData.now,
          onCallAgain: () {},
        ),
      );

      expect(find.byType(MissedCallView), findsOneWidget);
    });
  });

  group('表示の分岐', () {
    testWidgets('normal は 4 枚のカードで、帯も不在の表示も出さない', (tester) async {
      await _pumpHome(tester, HomeStatus.normal);

      expect(find.text('11月5日(木) 10:24 時点'), findsOneWidget);
      expect(find.byType(RecentCallCard), findsOneWidget);
      expect(tester.widget<AskCard>(find.byType(AskCard)).isCalling, isFalse);
      expect(find.byType(TodayCard), findsOneWidget);
      expect(find.byType(WeekCard), findsOneWidget);
      expect(find.byType(CallingBanner), findsNothing);
      expect(find.byType(MissedCallView), findsNothing);
    });

    testWidgets('calling は帯を足し、カードは normal と同じで AskCard に isCalling を渡す', (
      tester,
    ) async {
      await _pumpHome(tester, HomeStatus.calling);

      expect(find.text('11月5日(木) 10:27 時点'), findsOneWidget);
      expect(find.byType(CallingBanner), findsOneWidget);
      expect(find.byType(RecentCallCard), findsOneWidget);
      expect(tester.widget<AskCard>(find.byType(AskCard)).isCalling, isTrue);
      expect(find.byType(TodayCard), findsOneWidget);
      expect(find.byType(WeekCard), findsOneWidget);
      expect(find.byType(MissedCallView), findsNothing);
    });

    testWidgets('missedCall はヘッダーの下を MissedCallView に置き換える', (tester) async {
      await _pumpHome(tester, HomeStatus.missedCall);

      expect(find.text('11月5日(木) 9:31 時点'), findsOneWidget);
      expect(find.byType(MissedCallView), findsOneWidget);
      expect(find.byType(RecentCallCard), findsNothing);
      expect(find.byType(AskCard), findsNothing);
      expect(find.byType(TodayCard), findsNothing);
      expect(find.byType(WeekCard), findsNothing);
      expect(find.byType(CallingBanner), findsNothing);
      expect(
        tester.getTopLeft(find.byType(MissedCallView)).dy,
        tester.getBottomLeft(find.byType(HomeHeader)).dy,
      );
    });

    testWidgets('「もう一度電話する」を押すと通話中の表示になる', (tester) async {
      await _pumpHome(tester, HomeStatus.missedCall);

      await tester.tap(find.text('もう一度電話する'));
      await tester.pump();

      expect(find.byType(CallingBanner), findsOneWidget);
      expect(find.byType(MissedCallView), findsNothing);
      expect(find.text('11月5日(木) 10:27 時点'), findsOneWidget);
      expect(tester.widget<AskCard>(find.byType(AskCard)).isCalling, isTrue);
    });

    testWidgets('通話中は時間が経っても終わらない', (tester) async {
      await _pumpHome(tester, HomeStatus.calling);

      await tester.pump(const Duration(hours: 1));

      expect(find.byType(CallingBanner), findsOneWidget);
    });

    testWidgets('状態が変わると表示も変わる', (tester) async {
      await _pumpHome(tester, HomeStatus.normal);
      expect(find.byType(CallingBanner), findsNothing);

      tester.container().read(homeStatusProvider.notifier).startCall();
      await tester.pump();

      expect(find.byType(CallingBanner), findsOneWidget);
    });
  });

  group('状態バーの裏', () {
    const statusBar = 54.0;

    void setStatusBar(WidgetTester tester) {
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPadding);
    }

    testWidgets('calling の帯は画面の一番上から伸び、ヘッダーはモックと同じ位置に来る', (tester) async {
      setStatusBar(tester);
      await _pumpHome(tester, HomeStatus.calling);

      final banner = tester.getRect(find.byType(CallingBanner));
      expect(banner.top, 0);
      expect(banner.left, 0);
      expect(banner.width, _standardLayout.width);
      // モックの height:94px
      expect(banner.height, 94);
      expect(tester.getTopLeft(find.byType(HomeHeader)).dy, 94);
    });

    testWidgets('normal と missedCall のヘッダーは状態バーの下から始まる', (tester) async {
      setStatusBar(tester);
      for (final status in [HomeStatus.normal, HomeStatus.missedCall]) {
        await _pumpHome(tester, status);

        expect(tester.getTopLeft(find.byType(HomeHeader)).dy, statusBar);
      }
    });

    testWidgets('帯の文字はモックと同じく下から 10 の位置に出す', (tester) async {
      setStatusBar(tester);
      await _pumpHome(tester, HomeStatus.calling);

      expect(
        tester.getBottomLeft(find.text('通話中')).dy,
        tester.getBottomLeft(find.byType(CallingBanner)).dy - 10,
      );
      expect(
        tester.widget<Text>(find.text('通話中')).style?.color,
        AppColors.onStateOk,
      );
    });

    testWidgets('通話中は状態バーの文字が明るくなり、ほかの画面では暗い文字に戻る', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._startingAt(HomeStatus.calling),
            signedInAuth(),
            registeredWatchedPerson(),
          ],
          child: const KazokuAiApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);

      await tester.tap(find.text('通話記録').last);
      await tester.pumpAndSettle();

      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
    });
  });

  group('不在の表示', () {
    testWidgets('濃い赤のカードに白いボタンを置き、押すと onCallAgain を呼ぶ', (tester) async {
      var callCount = 0;
      await pumpInLayout(
        tester,
        _standardLayout,
        MissedCallView(
          missedCall: sampleHomeData.missedCall,
          now: sampleHomeData.now,
          onCallAgain: () => callCount++,
        ),
      );

      expect(
        tester.widget<AppCard>(find.byType(AppCard).first).variant,
        AppCardVariant.alert,
      );
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).variant,
        AppButtonVariant.white,
      );

      await tester.tap(find.text('もう一度電話する'));
      expect(callCount, 1);
    });
  });
}
