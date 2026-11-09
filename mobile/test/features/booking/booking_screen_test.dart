import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

Future<void> _pumpBooking(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
}) => pumpScreenInLayout(tester, layout, const Scaffold(body: BookingScreen()));

// 画面の外にあっても押せるように、スクロールしてから押す
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('崩れない', () {
    testEachLayout('一番下までスクロールできる', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      await tester.ensureVisible(find.text('かけなおしのルール'));
      await tester.pumpAndSettle();

      expect(find.text('かけなおしのルール'), findsOneWidget);
    });

    testEachLayout('伝えたいことが長い予約を足しても', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      tester
          .container()
          .read(bookedCallsProvider.notifier)
          .add(
            at: DateTime(2026, 11, 8, 9),
            message: 'とても長い内容です。' * 8,
            script: '「長い通話内容です。」',
          );
      await tester.pump();

      await tester.ensureVisible(find.textContaining('とても長い内容です。'));
      await tester.pumpAndSettle();
      expect(find.textContaining('とても長い内容です。'), findsOneWidget);
    });

    testEachLayout('押せる領域はどれも 44 以上になる', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      final pressables = find.descendant(
        of: find.byType(BookingScreen),
        matching: find.byType(InkWell),
      );
      expect(pressables, findsWidgets);
      for (final element in pressables.evaluate()) {
        final size = (element.renderObject! as RenderBox).size;
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });
  });

  group('一覧', () {
    testWidgets('フォームは出ず、一覧と新しい予約とかけなおしのルールが出る', (tester) async {
      await _pumpBooking(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.text('この内容で予約する'), findsNothing);
      expect(find.text('伝える内容'), findsNothing);
      expect(find.text('11/6(金)'), findsNothing);
      expect(find.text('予約している電話'), findsOneWidget);
      expect(find.text('新しい予約'), findsOneWidget);
      expect(find.text('かけなおしのルール'), findsOneWidget);

      final list = tester.getTopLeft(find.text('予約している電話')).dy;
      final button = tester.getTopLeft(find.text('新しい予約')).dy;
      final rule = tester.getTopLeft(find.text('かけなおしのルール')).dy;
      expect(list, lessThan(button));
      expect(button, lessThan(rule));
    });

    testWidgets('「新しい予約」はプラスの付いた主ボタン', (tester) async {
      await _pumpBooking(tester);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, '新しい予約'),
      );
      expect(button.variant, AppButtonVariant.primary);
      expect(button.size, AppButtonSize.l);
      expect(button.leadingIcon, AppIcons.plus);
      expect(
        tester.getSize(find.widgetWithText(AppButton, '新しい予約')).height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('予約している電話はモックの 3 件で、題も繰り返しもない', (tester) async {
      await _pumpBooking(tester);

      expect(find.text('今日 12:00'), findsOneWidget);
      expect(find.text('話し相手'), findsOneWidget);
      expect(find.text('今日 19:00'), findsOneWidget);
      expect(find.text('薬と戸締まりの確認'), findsOneWidget);
      expect(find.text('11/7 10:00'), findsOneWidget);
      expect(find.text('週末に帰ると伝える'), findsOneWidget);
      expect(find.text('昼の電話'), findsNothing);
      expect(find.text('夜の電話'), findsNothing);
      expect(find.text('1回だけ'), findsNothing);
      expect(find.textContaining('毎日'), findsNothing);
    });

    testWidgets('一覧とかけなおしのルールの間は 12', (tester) async {
      await _pumpBooking(tester);

      final card = tester.getRect(find.byType(AppCard));
      final button = tester.getRect(find.widgetWithText(AppButton, '新しい予約'));
      final rule = tester.getRect(
        find.ancestor(
          of: find.text('かけなおしのルール'),
          matching: find.byType(InkWell),
        ),
      );

      expect(button.top - card.bottom, 12);
      expect(rule.top - button.bottom, 12);
    });
  });

  group('かけなおしのルールの行', () {
    testWidgets('ルールの内容から文を作る', (tester) async {
      await _pumpBooking(tester);

      expect(find.text('15分おきに3回かけて、家族に通知'), findsOneWidget);

      tester
          .container()
          .read(retryRuleProvider.notifier)
          .save(const RetryRule(interval: Duration(hours: 1), attempts: 5));
      await tester.pump();

      expect(find.text('60分おきに5回かけて、家族に通知'), findsOneWidget);
    });

    testWidgets('1 回のルールは間隔を書かない', (tester) async {
      await _pumpBooking(tester);

      tester
          .container()
          .read(retryRuleProvider.notifier)
          .save(const RetryRule(interval: Duration(minutes: 30), attempts: 1));
      await tester.pump();

      expect(find.text('1回かけて、家族に通知'), findsOneWidget);
    });
  });

  group('アプリの中の動き', () {
    Future<void> openBookingTab(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInAuth(),
            registeredWatchedPerson(),
            sampleHome(),
            sampleCalls(),
            idleCallProgress(),
          ],
          child: const KazokuAiApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabBar),
          matching: find.text('予約電話'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('「新しい予約」で 01 を開き、もどると 06 に戻る', (tester) async {
      await openBookingTab(tester);

      await _tapVisible(tester, find.text('新しい予約'));

      expect(find.byType(AskScreen), findsOneWidget);
      expect(find.byType(BookingScreen), findsNothing);
      expect(find.byType(AppTabBar), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 2);
    });

    testWidgets('ルールの行を押すと 07 を開く', (tester) async {
      await openBookingTab(tester);

      await _tapVisible(tester, find.text('15分おきに3回かけて、家族に通知'));

      expect(find.byType(RetryRuleScreen), findsOneWidget);
    });

    testWidgets('スクロールの最後はタブバーに隠れない', (tester) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(393 * 3, 852 * 3)
        ..padding = const FakeViewPadding(top: 54 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await openBookingTab(tester);

      await tester.drag(find.byType(BookingScreen), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.text('15分おきに3回かけて、家族に通知')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppTabBar)).dy),
      );
    });
  });

  group('読み上げ', () {
    testWidgets('予約の行は日時と伝えたいことをひとつのボタンとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);
      final row = find.bySemanticsLabel('今日 12:00\n話し相手');

      expect(row, findsOneWidget);
      expect(
        tester.getSemantics(row),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('ルールの行は名前と文をひとつのボタンとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);
      final row = find.bySemanticsLabel('かけなおしのルール\n15分おきに3回かけて、家族に通知');

      expect(row, findsOneWidget);
      expect(
        tester.getSemantics(row),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });
  });
}
