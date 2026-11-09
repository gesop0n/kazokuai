import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _weekendScript = '「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」';
const _noonScript = '「ハナさん、こんにちは。\n体調はいかがですか。」';
const _eveningScript = '「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openBookingTab(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text('予約電話')),
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('保存するとその予約だけが日時の順で変わり、通話内容は変わらない', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('週末に帰ると伝える'));

    await tester.enterText(find.byType(TextField), '夕食のあとに電話する');
    await tester.pump();
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

    final calls = tester.container().read(bookedCallsProvider);
    expect(calls.map((call) => call.message), [
      '夕食のあとに電話する',
      '話し相手',
      '薬と戸締まりの確認',
    ]);
    expect(calls.map((call) => call.script), [
      _weekendScript,
      _noonScript,
      _eveningScript,
    ]);
    expect(calls.first.at, DateTime(2026, 11, 5, 9, 5));

    final tops = [
      for (final label in ['今日 09:05', '今日 12:00', '今日 19:00'])
        tester.getTopLeft(find.text(label)).dy,
    ];
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
    expect(find.text('夕食のあとに電話する'), findsOneWidget);
    expect(find.text('週末に帰ると伝える'), findsNothing);
    expect(find.text('11/7 10:00'), findsNothing);
  });

  testWidgets('伝えたいことだけ変えて保存しても、並びと通話内容は変わらない', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));

    await tester.enterText(find.byType(TextField), '  昼に話す\n');
    await tester.pump();
    await tester.tap(find.text('この日時で予約する'));
    await tester.pumpAndSettle();

    final calls = tester.container().read(bookedCallsProvider);
    expect(calls.map((call) => call.message), [
      '昼に話す',
      '薬と戸締まりの確認',
      '週末に帰ると伝える',
    ]);
    expect(calls.first.script, _noonScript);
    expect(calls.first.at, DateTime(2026, 11, 5, 12));
    expect(calls[1].script, _eveningScript);
    expect(calls[2].script, _weekendScript);
    expect(find.text('今日 12:00'), findsOneWidget);
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
    final calls = tester.container().read(bookedCallsProvider);
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
    expect(
      tester.container().read(bookedCallsProvider)[1].script,
      _eveningScript,
    );
    expect(
      tester.container().read(bookedCallsProvider)[1].message,
      '薬と戸締まりの確認',
    );
  });

  testWidgets('「今すぐ通話」は準備中と出て、06b に留まる', (tester) async {
    await openBookingTab(tester);
    await _tapVisible(tester, find.text('話し相手'));

    await tester.tap(find.text('今すぐ通話'));
    await tester.pumpAndSettle();

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.text('予約の編集'), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    final calls = tester.container().read(bookedCallsProvider);
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
    expect(tester.container().read(bookedCallsProvider), hasLength(3));
    expect(tester.container().read(bookedCallsProvider).first.message, '話し相手');
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

  group('配置', () {
    const longMessage = '夕食のあとに電話して、薬を飲んだか確かめてほしいです。';

    testEachLayout('予約の内容が見え、下までスクロールできる', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        const BookingEditScreen(index: 1),
      );
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
      await pumpScreenInLayout(
        tester,
        layout,
        const BookingEditScreen(index: 1),
      );
      await tester.enterText(find.byType(TextField), longMessage * 6);
      await tester.pump();

      await tester.ensureVisible(find.text(_eveningScript));
      await tester.pumpAndSettle();
      expect(find.text(_eveningScript), findsOneWidget);
      await tester.ensureVisible(find.text('19:00'));
      await tester.pumpAndSettle();
      expect(find.text('19:00'), findsOneWidget);
    });

    testEachLayout('押せる領域はどれも 44 以上になる', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        const BookingEditScreen(index: 1),
      );
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
      await pumpScreenInLayout(
        tester,
        layout,
        const BookingEditScreen(index: 1),
      );
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

    testEachLayout('ボタンはキーボードの上に 8 空けて残る', (tester, layout) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await pumpScreenInLayout(
        tester,
        layout,
        const BookingEditScreen(index: 1),
      );
      await tester.pump();

      expect(
        tester.getRect(find.widgetWithText(AppButton, '今すぐ通話')).bottom,
        852 - 336 - 8,
      );
    });
  });
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
