import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: KazokuAiApp()));
  await tester.pumpAndSettle();
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> tapAskField(WidgetTester tester) => tapText(tester, '伝えたいことを入力');

// カードの一番下にあるので、スクロールしてから押す
Future<void> tapCallLogButton(WidgetTester tester) async {
  final button = find.text('通話記録を見る');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(AppNavBar), matching: find.byType(InkWell)),
  );
  await tester.pumpAndSettle();
}

int currentTab(WidgetTester tester) =>
    tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex;

// 条件のチップも横に動くので、一番外側の Scrollable を選ぶ
ScrollPosition callsScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CallsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> scrollCalls(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('起動するとホームが開き、タブを切り替えられる', (tester) async {
    await pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(currentTab(tester), 0);

    await tapTab(tester, '通話記録');
    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(currentTab(tester), 1);

    await tapTab(tester, '予約電話');
    expect(find.byType(BookingScreen), findsOneWidget);
    expect(find.byType(CallsScreen), findsNothing);
    expect(currentTab(tester), 2);

    await tapTab(tester, 'ホーム');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BookingScreen), findsNothing);
    expect(currentTab(tester), 0);
  });

  testWidgets('01 を開くとタブバーが消え、戻るとタブバーが戻る', (tester) async {
    await pumpApp(tester);

    await tapAskField(tester);
    expect(find.byType(AskScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);

    await tapBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsOneWidget);
  });

  testWidgets('07 を開くとタブバーが消え、戻るとタブバーが戻る', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, '予約電話');

    await tapText(tester, 'かけなおしのルール');
    expect(find.byType(RetryRuleScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);

    await tapBack(tester);
    expect(find.byType(BookingScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(currentTab(tester), 2);
  });

  testWidgets('05 をホームから開くと、タブバーが消え、ホームに戻る', (tester) async {
    await pumpApp(tester);

    await tapText(tester, '会話を見る');
    expect(find.byType(CallDetailScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);

    await tapBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(currentTab(tester), 0);
  });

  testWidgets('05 を通話記録から開くと、タブバーが消え、通話記録に戻る', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, '通話記録');

    await tapText(tester, '朝食と薬は済み。膝を気にしている');
    expect(find.byType(CallDetailScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);

    await tapBack(tester);
    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(currentTab(tester), 1);
  });

  testWidgets('全画面の遷移は OS 標準の動きになる', (tester) async {
    await pumpApp(tester);

    await tapText(tester, '会話を見る');

    final route = ModalRoute.of(tester.element(find.byType(CallDetailScreen)));
    expect(route, isA<MaterialRouteTransitionMixin<void>>());
  });

  testWidgets('全画面の戻るボタンは「もどる」と読み上げる', (tester) async {
    await pumpApp(tester);

    await tapAskField(tester);
    expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    await tapBack(tester);

    await tapText(tester, '会話を見る');
    expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    await tapBack(tester);

    await tapTab(tester, '予約電話');
    await tapText(tester, 'かけなおしのルール');
    expect(find.bySemanticsLabel('もどる'), findsOneWidget);
  });

  testWidgets('「通話記録を見る」で通話記録タブに切り替わる', (tester) async {
    await pumpApp(tester);

    await tapCallLogButton(tester);

    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(currentTab(tester), 1);
  });

  testWidgets('通知のベルで「準備中です」と表示する', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('通知'));
    await tester.pumpAndSettle();
    expect(find.text('準備中です'), findsOneWidget);

    // 表示の時間は、出てくる動きが終わってから数える
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('準備中です'), findsNothing);
  });

  group('通話記録のスクロール位置', () {
    testWidgets('タブを切り替えて戻っても保たれる', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, '通話記録');
      await scrollCalls(tester, -300);
      final pixels = callsScrollPosition(tester).pixels;
      expect(pixels, greaterThan(0));

      await tapTab(tester, 'ホーム');
      await tapTab(tester, '通話記録');

      expect(callsScrollPosition(tester).pixels, pixels);
    });

    testWidgets('「通話記録を見る」で戻っても保たれる', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, '通話記録');
      await scrollCalls(tester, -300);
      final pixels = callsScrollPosition(tester).pixels;

      await tapTab(tester, 'ホーム');
      await tapCallLogButton(tester);

      expect(callsScrollPosition(tester).pixels, pixels);
    });

    testWidgets('05 を開いて戻っても保たれる', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, '通話記録');
      await scrollCalls(tester, -300);
      final pixels = callsScrollPosition(tester).pixels;

      await tapText(tester, 'お孫さんの運動会の話がはずんだ');
      expect(find.byType(CallDetailScreen), findsOneWidget);
      await tapBack(tester);

      expect(callsScrollPosition(tester).pixels, pixels);
    });
  });

  group('本文とタブバーの重なり', () {
    // モックと同じ画面。下の安全領域が 34 なので、タブバーは tabH と同じ 98 になる
    void useMockScreen(WidgetTester tester) {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.padding = const FakeViewPadding(top: 54 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
    }

    testWidgets('タブバーの高さは tabH と同じ 98 になる', (tester) async {
      useMockScreen(tester);
      await pumpApp(tester);

      expect(tester.getSize(find.byType(AppTabBar)).height, 98);
    });

    testWidgets('本文は画面の下端まで伸びる', (tester) async {
      useMockScreen(tester);
      await pumpApp(tester);
      await tapTab(tester, '通話記録');

      expect(tester.getBottomLeft(find.byType(CallsScreen)).dy, 852);
    });

    testWidgets('スクロールの最後はタブバーに隠れない', (tester) async {
      useMockScreen(tester);
      await pumpApp(tester);
      await tapTab(tester, '通話記録');

      await scrollCalls(tester, -100000);

      expect(
        tester.getBottomLeft(find.text('庭の菊が咲き始めた話をした')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppTabBar)).dy),
      );
    });
  });
}
