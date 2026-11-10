import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_bookings_repository.dart';
import '../../support/fake_call_script_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _weekendScript = '「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」';
const _noonScript = '「ハナさん、こんにちは。\n体調はいかがですか。」';
const _eveningScript = '「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」';
const _redrafted = '「ハナさん、昼に話します。」';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<FakeBookingsRepository> openBookingTab(
  WidgetTester tester, {
  FakeCallScriptRepository? drafts,
  DateTime? now,
}) async {
  final bookings = FakeBookingsRepository(bookings: sampleBookedCalls);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
        bookingsRepositoryProvider.overrideWithValue(bookings),
        callScriptRepositoryProvider.overrideWithValue(
          drafts ?? FakeCallScriptRepository(script: _redrafted),
        ),
        mockBookingNow(now ?? sampleBookingDay),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text('予約電話')),
  );
  await tester.pumpAndSettle();
  return bookings;
}

List<BookedCall> _saved(WidgetTester tester) =>
    tester.container().read(bookingsRepositoryProvider).bookings.value!;

FakeCallScriptRepository _drafts(WidgetTester tester) =>
    tester.container().read(callScriptRepositoryProvider)
        as FakeCallScriptRepository;

void main() {
  testWidgets('06 の予約を押すと、その予約の入った 06b がタブバーなしで開く', (tester) async {
    await openBookingTab(tester);

    await _tapVisible(tester, find.text('週末に帰ると伝える'));

    expect(find.text('予約の編集'), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    expect(find.byType(BookingScreen), findsNothing);
    expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    expect(find.text('伝えたいこと'), findsOneWidget);
    expect(find.text('通話内容'), findsOneWidget);
    expect(find.text('なおす'), findsOneWidget);
    expect(find.text(_weekendScript), findsOneWidget);
    expect(find.text(_noonScript), findsNothing);
    expect(find.text('11/7(土)'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('この日時で予約する'), findsOneWidget);
    expect(find.text('今すぐ通話'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '週末に帰ると伝える',
    );
  });

  testWidgets('日時だけ直すと、その予約だけが時刻の順で変わり、通話内容は残る', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('週末に帰ると伝える'));

    await _tapVisible(tester, find.text('11/7(土)'));
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('10:00'));
    await _enterTime(tester, '9', '05');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('この日時で予約する'));
    await tester.pumpAndSettle();

    expect(find.byType(BookingScreen), findsOneWidget);
    expect(find.text('予約の編集'), findsNothing);
    expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 2);
    expect(_drafts(tester).messages, isEmpty);

    final calls = _saved(tester);
    BookedCall byId(String id) => calls.singleWhere((call) => call.id == id);
    expect(byId('weekend').at, DateTime(2026, 11, 5, 9, 5));
    expect(byId('weekend').message, '週末に帰ると伝える');
    expect(byId('weekend').script, _weekendScript);
    expect(byId('noon').at, DateTime(2026, 11, 5, 12));
    expect(byId('noon').script, _noonScript);
    expect(byId('evening').message, '薬と戸締まりの確認');
    expect(byId('evening').script, _eveningScript);

    final tops = [
      for (final label in ['今日 09:05', '今日 12:00', '今日 19:00'])
        tester.getTopLeft(find.text(label)).dy,
    ];
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
    expect(find.text('11/7 10:00'), findsNothing);
  });

  testWidgets('伝えたいことを変えると、通話内容を作り直してから保存する', (tester) async {
    final gate = Completer<void>();
    await openBookingTab(
      tester,
      drafts: FakeCallScriptRepository(script: _redrafted, pending: gate),
    );
    await _tapVisible(tester, find.text('話し相手'));

    await tester.enterText(find.byType(TextField), '  昼に話す\n');
    await tester.pump();

    expect(find.text(_noonScript), findsOneWidget);
    expect(_button(tester, 'この日時で予約する').onTap, isNull);
    expect(_button(tester, '今すぐ通話').onTap, isNotNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('案を作っています'), findsOneWidget);
    expect(find.text(_noonScript), findsNothing);
    expect(_drafts(tester).messages, ['昼に話す']);
    expect(_button(tester, 'この日時で予約する').onTap, isNull);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(_redrafted), findsOneWidget);
    expect(_button(tester, 'この日時で予約する').onTap, isNotNull);

    await tester.tap(find.text('この日時で予約する'));
    await tester.pumpAndSettle();

    final calls = _saved(tester);
    expect(calls.first.message, '昼に話す');
    expect(calls.first.script, _redrafted);
    expect(calls.first.at, DateTime(2026, 11, 5, 12));
    expect(calls[1].script, _eveningScript);
    expect(calls[2].script, _weekendScript);
    expect(find.text('今日 12:00'), findsOneWidget);
    expect(find.text('昼に話す'), findsOneWidget);
  });

  testWidgets('伝えたいことを元に戻すと、作り直しをやめて元の通話内容を残す', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));

    await tester.enterText(find.byType(TextField), '昼に話す');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '話し相手');
    await tester.pump(const Duration(seconds: 1));

    expect(_drafts(tester).messages, isEmpty);
    expect(find.text(_noonScript), findsOneWidget);
    expect(find.text('案を作っています'), findsNothing);

    await tester.tap(find.text('この日時で予約する'));
    await tester.pumpAndSettle();

    expect(_saved(tester).first.script, _noonScript);
    expect(_saved(tester).first.message, '話し相手');
  });

  testWidgets('もどると変更は保存されない', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));
    await tester.enterText(find.byType(TextField), '昼に話す');
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(AppNavBar),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookingScreen), findsOneWidget);
    expect(find.text('話し相手'), findsOneWidget);
    expect(find.text('昼に話す'), findsNothing);
    final calls = _saved(tester);
    expect(calls.first.message, '話し相手');
    expect(calls.first.script, _noonScript);

    await _tapVisible(tester, find.text('話し相手'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '話し相手',
    );
  });

  testWidgets('「なおす」は準備中と出て、伝えたいことも通話内容も変わらない', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('薬と戸締まりの確認'));
    await tester.enterText(find.byType(TextField), '夕食のあと');
    await tester.pump();

    expect(find.text(_eveningScript), findsOneWidget);

    await tester.tap(find.text('なおす'));
    await tester.pump();

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.text(_eveningScript), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '夕食のあと',
    );
    expect(_saved(tester)[1].script, _eveningScript);
    expect(_saved(tester)[1].message, '薬と戸締まりの確認');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('「今すぐ通話」は準備中と出て、06b に留まる', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));

    await tester.tap(find.text('今すぐ通話'));
    await tester.pumpAndSettle();

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.text('予約の編集'), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    final calls = _saved(tester);
    expect(calls.first.message, '話し相手');
    expect(calls.first.at, DateTime(2026, 11, 5, 12));
    expect(calls, hasLength(3));
  });

  testWidgets('伝えたいことが空のあいだは、予約も今すぐ通話も押せない', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(find.text(_noonScript), findsOneWidget);
    expect(find.text('なおす'), findsOneWidget);
    expect(_button(tester, 'この日時で予約する').onTap, isNull);
    expect(_button(tester, '今すぐ通話').onTap, isNull);

    await tester.tap(find.text('今すぐ通話'), warnIfMissed: false);
    await tester.tap(find.text('この日時で予約する'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('準備中です'), findsNothing);
    expect(find.text('予約の編集'), findsOneWidget);
    expect(_saved(tester), hasLength(3));
    expect(_saved(tester).first.message, '話し相手');
  });

  for (final (name, spaces) in [('半角', '   '), ('全角', '　　'), ('改行', '\n\n')]) {
    testWidgets('$nameの空白だけのときは空と同じ', (tester) async {
      await openBookingTab(tester);
      await _tapVisible(tester, find.text('話し相手'));

      await tester.enterText(find.byType(TextField), spaces);
      await tester.pump();

      expect(find.text(_noonScript), findsOneWidget);
      expect(_button(tester, 'この日時で予約する').onTap, isNull);
      expect(_button(tester, '今すぐ通話').onTap, isNull);
    });
  }

  testWidgets('日付は今日から 30 日先までで、近すぎる時刻は入らない', (tester) async {
    final now = DateTime(2026, 11, 10, 15, 9);
    // 入力した 15 時を、12 時間表記の検査で落さない。
    tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
    await pumpScreenInLayout(
      tester,
      const LayoutCase(393, 1.0),
      BookingEditScreen(
        booking: BookedCall(
          id: 'later',
          at: DateTime(2026, 11, 10, 16),
          message: '夕方の伝言',
          script: '「夕方」',
        ),
      ),
      overrides: [mockBookingNow(now)],
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('日付'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.firstDate, DateTime(2026, 11, 10));
    expect(dialog.lastDate, DateTime(2026, 12, 10));
    expect(dialog.currentDate, DateTime(2026, 11, 10));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('時刻'));
    await tester.pumpAndSettle();
    await _enterTime(tester, '15', '10');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('16:00'), findsOneWidget);
    expect(find.text('15:10'), findsNothing);

    await tester.tap(find.bySemanticsLabel('時刻'));
    await tester.pumpAndSettle();
    await _enterTime(tester, '15', '15');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15:15'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('日付'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('12/10(木)'), findsOneWidget);
    expect(_button(tester, 'この日時で予約する').onTap, isNull);
  });

  for (final (failure, text) in [
    (const BookingTooCloseException(), '近い時刻に予約があります'),
    (const BookingTooSoonException(), '早すぎる'),
    (const BookingTooFarException(), '先すぎる'),
    (const BookingFailedException(), '送れなかった'),
  ]) {
    testWidgets('$text と出て、06b に留まる', (tester) async {
      final bookings = await openBookingTab(tester);
      await _tapVisible(tester, find.text('話し相手'));
      bookings.failure = failure;

      await tester.tap(find.text('この日時で予約する'));
      await tester.pump();

      expect(find.text(text), findsOneWidget);
      expect(find.text('予約の編集'), findsOneWidget);
      expect(find.byType(BookingScreen), findsNothing);
      expect(bookings.edited, isEmpty);
      expect(_saved(tester).first.message, '話し相手');
      await tester.pump(const Duration(seconds: 2));
    });
  }

  group('配置', () {
    const longMessage = '夕食のあとに電話して、薬を飲んだか確かめてほしいです。';

    testEachLayout('予約の内容が見え、下までスクロールできる', (tester, layout) async {
      await _pumpEdit(tester, layout);
      await tester.pump();

      expect(find.text('予約の編集'), findsOneWidget);
      expect(find.text(_eveningScript), findsOneWidget);
      await tester.ensureVisible(find.text('19:00'));
      await tester.pumpAndSettle();
      expect(find.text('11/5(木)'), findsOneWidget);
      expect(find.text('この日時で予約する'), findsOneWidget);
      expect(find.text('今すぐ通話'), findsOneWidget);
    });

    testEachLayout('長い伝えたいことでも崩れない', (tester, layout) async {
      await _pumpEdit(tester, layout);
      await tester.enterText(find.byType(TextField), longMessage * 6);
      await tester.pump();

      expect(find.text(_eveningScript), findsOneWidget);
      await tester.ensureVisible(find.text('19:00'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('19:00'), findsOneWidget);
    });

    testEachLayout('押せる領域はどれも 44 以上になる', (tester, layout) async {
      await _pumpEdit(tester, layout);
      await tester.pump();

      final pressables = find.descendant(
        of: find.byType(BookingEditScreen),
        matching: find.byType(InkWell),
      );
      expect(pressables, findsWidgets);
      for (final element in pressables.evaluate()) {
        final size = (element.renderObject! as RenderBox).size;
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testEachLayout('本文をスクロールしてもボタンは動かない', (tester, layout) async {
      await _pumpEdit(tester, layout);
      await tester.enterText(find.byType(TextField), longMessage * 8);
      await tester.pump();
      final before = tester.getTopLeft(find.text('この日時で予約する'));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('この日時で予約する')), before);
    });

    testEachLayout('ボタンはキーボードの下に隠れる', (tester, layout) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await _pumpEdit(tester, layout);
      await tester.pump();

      expect(
        tester.getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する')).dy,
        greaterThanOrEqualTo(852 - 336),
      );
    });
  });
}

Future<void> _pumpEdit(WidgetTester tester, LayoutCase layout) {
  return pumpScreenInLayout(
    tester,
    layout,
    BookingEditScreen(booking: sampleBookedCalls[1]),
    overrides: [
      callScriptRepositoryProvider.overrideWithValue(
        FakeCallScriptRepository(),
      ),
      mockBookingNow(),
    ],
  );
}

AppButton _button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

Future<void> _enterTime(WidgetTester tester, String hour, String minute) async {
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
