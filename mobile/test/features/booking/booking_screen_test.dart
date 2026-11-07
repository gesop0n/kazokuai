import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);
const _initialMessage = '今日は通院の日です。10時に迎えに行くと伝えて';

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

Future<void> _openDatePicker(WidgetTester tester) =>
    _tapVisible(tester, find.text('11/6(金)'));

Future<void> _openTimePicker(WidgetTester tester) =>
    _tapVisible(tester, find.text('08:30'));

Future<void> _book(WidgetTester tester) =>
    _tapVisible(tester, find.text('この内容で予約する'));

AppButton _bookButton(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, 'この内容で予約する'));

List<BookedCall> _bookedCalls(WidgetTester tester) =>
    tester.container().read(bookedCallsProvider);

void main() {
  group('崩れない', () {
    testEachLayout('一番下までスクロールできる', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      await tester.ensureVisible(find.text('かけなおしのルール'));
      await tester.pumpAndSettle();

      expect(find.text('かけなおしのルール'), findsOneWidget);
    });

    testEachLayout('伝える内容が長い予約を足しても', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      await tester.enterText(find.byType(TextField), 'とても長い内容です。' * 8);
      await tester.pump();
      await _book(tester);

      expect(_bookedCalls(tester), hasLength(4));
    });

    testEachLayout('日付を選ぶ画面', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      await _openDatePicker(tester);

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testEachLayout('時刻を選ぶ画面', (tester, layout) async {
      await _pumpBooking(tester, layout: layout);

      await _openTimePicker(tester);

      expect(find.byType(TimePickerDialog), findsOneWidget);
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

  group('初期値', () {
    testWidgets('モックのとおりの日付、時刻、内容で始まる', (tester) async {
      await _pumpBooking(tester);

      expect(find.text('新しい予約'), findsOneWidget);
      expect(find.text('11/6(金)'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text(_initialMessage), findsOneWidget);
    });

    testWidgets('予約している電話はモックの 3 件', (tester) async {
      await _pumpBooking(tester);

      expect(find.text('今日 12:00'), findsOneWidget);
      expect(find.text('昼の電話'), findsOneWidget);
      expect(find.text('話し相手 ・ 毎日'), findsOneWidget);
      expect(find.text('今日 19:00'), findsOneWidget);
      expect(find.text('夜の電話'), findsOneWidget);
      expect(find.text('薬と戸締まりの確認 ・ 毎日'), findsOneWidget);
      expect(find.text('11/7 10:00'), findsOneWidget);
      expect(find.text('週末に帰ると伝える'), findsOneWidget);
      expect(find.text('1回だけ'), findsOneWidget);
    });
  });

  group('日付を選ぶ', () {
    testWidgets('標準の画面を、基準の日より前を選べない形で開く', (tester) async {
      await _pumpBooking(tester);

      await _openDatePicker(tester);

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.firstDate, DateTime(2026, 11, 5));
      expect(dialog.initialDate, DateTime(2026, 11, 6));
      expect(dialog.lastDate, DateTime(2027, 11, 5));
      // 端末の時計ではなく、基準の日を今日として出す
      expect(dialog.currentDate, DateTime(2026, 11, 5));
      expect(
        Localizations.localeOf(tester.element(find.byType(DatePickerDialog))),
        const Locale('ja'),
      );
    });

    testWidgets('基準の日より前の日は押しても選ばれない', (tester) async {
      await _pumpBooking(tester);
      await _openDatePicker(tester);

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/6(金)'), findsOneWidget);
    });

    testWidgets('基準の日は選べる', (tester) async {
      await _pumpBooking(tester);
      await _openDatePicker(tester);

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/5(木)'), findsOneWidget);
    });

    testWidgets('選んだ日が欄に出る', (tester) async {
      await _pumpBooking(tester);
      await _openDatePicker(tester);

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/20(金)'), findsOneWidget);
    });

    testWidgets('キャンセルすると変わらない', (tester) async {
      await _pumpBooking(tester);
      await _openDatePicker(tester);

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('11/6(金)'), findsOneWidget);
    });
  });

  group('時刻を選ぶ', () {
    // 文字盤の代わりに、標準の画面の入力の表示で時刻を打つ
    Future<void> enterTime(
      WidgetTester tester,
      String hour,
      String minute,
    ) async {
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), hour);
      await tester.enterText(fields.at(1), minute);
      await tester.pump();
    }

    testWidgets('標準の画面を、今の値で開く', (tester) async {
      await _pumpBooking(tester);

      await _openTimePicker(tester);

      final dialog = tester.widget<TimePickerDialog>(
        find.byType(TimePickerDialog),
      );
      expect(dialog.initialTime, const TimeOfDay(hour: 8, minute: 30));
      expect(
        Localizations.localeOf(tester.element(find.byType(TimePickerDialog))),
        const Locale('ja'),
      );
    });

    testWidgets('日本語のロケールは 24 時間の表示で、午前と午後を出さない', (tester) async {
      await _pumpBooking(tester);

      await _openTimePicker(tester);

      expect(find.text('午前'), findsNothing);
      expect(find.text('午後'), findsNothing);
    });

    testWidgets('選んだ時刻を 2 桁に揃えて欄に出す', (tester) async {
      await _pumpBooking(tester);
      await _openTimePicker(tester);

      await enterTime(tester, '9', '05');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('キャンセルすると変わらない', (tester) async {
      await _pumpBooking(tester);
      await _openTimePicker(tester);

      await enterTime(tester, '9', '05');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('08:30'), findsOneWidget);
    });
  });

  group('予約する', () {
    testWidgets('押すと「1回だけ」の行を最後に足す', (tester) async {
      await _pumpBooking(tester);

      await _book(tester);

      expect(find.text('11/6 08:30'), findsOneWidget);
      expect(find.text('1回だけ'), findsNWidgets(2));
      final added = _bookedCalls(tester).last;
      expect(added.at, DateTime(2026, 11, 6, 8, 30));
      expect(added.title, _initialMessage);
      expect(added.detail, '1回だけ');
      // 入力欄と足した行の両方に同じ文字が出る
      expect(find.text(_initialMessage), findsNWidgets(2));
    });

    testWidgets('選んだ日付と時刻で予約する', (tester) async {
      await _pumpBooking(tester);
      await _openDatePicker(tester);
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await _book(tester);

      expect(find.text('今日 08:30'), findsOneWidget);
    });

    testWidgets('入力した内容の前後の空白を除いて予約する', (tester) async {
      await _pumpBooking(tester);

      await tester.enterText(find.byType(TextField), '  週末に帰ると伝えて\n');
      await tester.pump();
      await _book(tester);

      expect(_bookedCalls(tester).last.title, '週末に帰ると伝えて');
    });

    testWidgets('予約しても入力欄の内容は残る', (tester) async {
      await _pumpBooking(tester);

      await _book(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        _initialMessage,
      );
    });

    testWidgets('押すとキーボードを閉じる', (tester) async {
      await _pumpBooking(tester);
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);

      await _book(tester);

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('スクロールするとキーボードを閉じる', (tester) async {
      await _pumpBooking(tester);
      // キーボードで表示の領域が狭くなった状態にする。本文が入りきると、スクロールしない
      tester.view.physicalSize = const Size(393, 500);
      await tester.pump();
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.drag(find.byType(BookingScreen), const Offset(0, -100));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('内容が空なら押せない', (tester) async {
      await _pumpBooking(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(_bookButton(tester).onTap, isNull);
      await _book(tester);
      expect(_bookedCalls(tester), hasLength(3));
    });

    testWidgets('空白と改行だけでも押せない', (tester) async {
      await _pumpBooking(tester);

      await tester.enterText(find.byType(TextField), ' 　\n ');
      await tester.pump();

      expect(_bookButton(tester).onTap, isNull);
    });

    testWidgets('入力し直すと押せるようになる', (tester) async {
      await _pumpBooking(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.enterText(find.byType(TextField), '夕方に電話する');
      await tester.pump();

      expect(_bookButton(tester).onTap, isNotNull);
    });
  });

  group('予約している電話の行', () {
    testWidgets('押すと「準備中です」と表示する', (tester) async {
      await _pumpBooking(tester);

      await _tapVisible(tester, find.text('昼の電話'));

      expect(find.text('準備中です'), findsOneWidget);
    });

    testWidgets('足した行も押すと「準備中です」と表示する', (tester) async {
      await _pumpBooking(tester);
      await _book(tester);

      await _tapVisible(tester, find.text('11/6 08:30'));

      expect(find.text('準備中です'), findsOneWidget);
    });
  });

  group('かけなおしのルールの行', () {
    testWidgets('ルールの内容から文を作る', (tester) async {
      await _pumpBooking(tester);

      expect(find.text('10分おきに3回かけて、家族に通知'), findsOneWidget);

      tester
          .container()
          .read(retryRuleProvider.notifier)
          .save(const RetryRule(interval: Duration(hours: 1), attempts: 5));
      await tester.pump();

      expect(find.text('1時間おきに5回かけて、家族に通知'), findsOneWidget);
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
          overrides: [signedInAuth(), registeredWatchedPerson(), sampleHome()],
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

    testWidgets('ルールの行を押すと 07 を開く', (tester) async {
      await openBookingTab(tester);

      await _tapVisible(tester, find.text('10分おきに3回かけて、家族に通知'));

      expect(find.byType(RetryRuleScreen), findsOneWidget);
    });

    testWidgets('タブを切り替えても、足した予約と入力の内容は残る', (tester) async {
      await openBookingTab(tester);
      await tester.enterText(find.byType(TextField), '夕方に電話する');
      await tester.pump();
      await _book(tester);

      await tester.tap(
        find.descendant(of: find.byType(AppTabBar), matching: find.text('ホーム')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabBar),
          matching: find.text('予約電話'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('11/6 08:30'), findsOneWidget);
      expect(find.text('夕方に電話する'), findsNWidgets(2));
    });

    testWidgets('「準備中です」はタブバーに隠れない', (tester) async {
      await openBookingTab(tester);

      await _tapVisible(tester, find.text('昼の電話'));

      expect(
        tester.getBottomLeft(find.byType(SnackBar)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppTabBar)).dy),
      );
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
        tester.getBottomLeft(find.text('10分おきに3回かけて、家族に通知')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppTabBar)).dy),
      );
    });
  });

  group('読み上げ', () {
    testWidgets('日付と時刻の欄は、項目の名前と値を押せるものとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);

      expect(find.bySemanticsLabel('日付\n11/6(金)'), findsOneWidget);
      expect(find.bySemanticsLabel('時刻\n08:30'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('日付\n11/6(金)')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      // 欄の上の見出しを別に読まない
      expect(find.bySemanticsLabel('日付'), findsNothing);
      expect(find.bySemanticsLabel('時刻'), findsNothing);
      handle.dispose();
    });

    testWidgets('入力欄は「伝える内容」と読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);

      expect(
        tester.getSemantics(find.byType(EditableText)),
        isSemantics(label: '伝える内容', isTextField: true),
      );
      // 欄の上の見出しを別に読まない
      expect(find.bySemanticsLabel(RegExp(r'^伝える内容$')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('内容が空のときは、ボタンを押せないものとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);
      final button = find.bySemanticsLabel('この内容で予約する');

      expect(
        tester.getSemantics(button),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(
        tester.getSemantics(button),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('予約の行は時刻、内容、繰り返しをひとつのボタンとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBooking(tester);
      final row = find.bySemanticsLabel('今日 12:00\n昼の電話\n話し相手 ・ 毎日');

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
      final row = find.bySemanticsLabel('かけなおしのルール\n10分おきに3回かけて、家族に通知');

      expect(row, findsOneWidget);
      expect(
        tester.getSemantics(row),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });
  });
}
