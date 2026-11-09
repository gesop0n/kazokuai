import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/home_status.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_immediate_call_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);
const _message = '金曜の通院、10時に迎えに行くと伝えて';
const _script = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';
const _removedNote = '電話ではこの言い方で伝えます。聞き返されたら、同じ内容をくり返します。';
const _longMessage = '金曜の通院、10時に迎えに行くと伝えて。帰りに薬局へ寄ることも話しておいてほしいです。';

const _removedFootNote = '押すと、すぐにハナさんの固定電話にかけます';

// iPhone 17 Pro で日本語のキーボードを出したときの値
const _keyboardHeight = 336.0;

Future<void> _pumpAsk(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
}) => pumpScreenInLayout(tester, layout, const AskScreen());

// 遷移は go_router が要るので、アプリ全体をホームから動かす
Future<FakeImmediateCallRepository> _pumpAppAndOpenAsk(
  WidgetTester tester, {
  FakeImmediateCallRepository? calls,
}) async {
  final repository = calls ?? FakeImmediateCallRepository();
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
        immediateCallRepositoryProvider.overrideWithValue(repository),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('AIに伝えてもらう'));
  await tester.pumpAndSettle();
  expect(find.byType(AskScreen), findsOneWidget);
  return repository;
}

Future<void> _enterMessage(
  WidgetTester tester, [
  String text = _message,
]) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

AppButton _button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

TextField _textField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void _expectNeedsMessage(WidgetTester tester) {
  expect(find.text('通話内容'), findsNothing);
  expect(find.text(_script), findsNothing);
  expect(find.text('話し方'), findsNothing);
  expect(_button(tester, 'この日時で予約する').onTap, isNull);
  expect(_button(tester, '今すぐ通話').onTap, isNull);
}

void main() {
  group('開いたとき', () {
    testEachLayout('入力欄は空で、通話内容は出ず、予約も今すぐ通話も押せない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await tester.pump();

      expect(find.text('AIに伝えてもらう'), findsOneWidget);
      expect(find.text('伝えたいこと'), findsOneWidget);
      expect(find.text('11/6(金)'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(_textField(tester).controller!.text, isEmpty);
      expect(_textField(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      _expectNeedsMessage(tester);
    });

    testWidgets('入力欄はモックの最小の高さ 60 で、複数行に伸びる', (tester) async {
      await _pumpAsk(tester);

      final field = tester.widget<AppTextField>(find.byType(AppTextField));
      expect(field.maxLines, isNull);
      expect(tester.getSize(find.byType(AppTextField)).height, 60);

      await _enterMessage(tester, _longMessage * 3);
      expect(tester.getSize(find.byType(AppTextField)).height, greaterThan(60));
    });

    testWidgets('日付と時刻の欄は、項目の名前と値を押せるものとして読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAsk(tester);

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

    testWidgets('入力欄の読み上げは「伝えたいこと」で、見出しと重ならない', (tester) async {
      await _pumpAsk(tester);
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(EditableText)),
        isSemantics(label: '伝えたいこと', isTextField: true, isFocused: true),
      );
      expect(find.bySemanticsLabel('伝えたいこと'), findsOneWidget);
    });
  });

  group('通話内容', () {
    testEachLayout('文字を入れると通話内容が出て、予約も今すぐ通話も押せる', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester);

      expect(find.byType(AppAiTag), findsOneWidget);
      expect(find.text('通話内容'), findsOneWidget);
      expect(find.text(_script), findsOneWidget);
      expect(find.text('話し方'), findsNothing);
      expect(find.text('Geminiの言い方の案'), findsNothing);
      expect(find.text(_removedNote), findsNothing);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testEachLayout('長い文でも崩れない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester, _longMessage * 4);

      expect(find.text(_script), findsOneWidget);
    });

    testWidgets('文は入力の内容によって変わらない', (tester) async {
      await _pumpAsk(tester);

      await _enterMessage(tester, '庭の菊が咲きました');
      expect(find.text(_script), findsOneWidget);

      await _enterMessage(tester, '来週の予定');
      expect(find.text(_script), findsOneWidget);
    });

    testWidgets('消すと通話内容が消え、どちらのボタンも押せなくなる', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);
      expect(find.text(_script), findsOneWidget);

      await _enterMessage(tester, '');

      _expectNeedsMessage(tester);
    });

    for (final (name, spaces) in [
      ('半角', '   '),
      ('全角', '　　'),
      ('改行', '\n\n'),
    ]) {
      testWidgets('$nameの空白だけのときは空と同じ', (tester) async {
        await _pumpAsk(tester);

        await _enterMessage(tester, spaces);

        _expectNeedsMessage(tester);
      });
    }

    testWidgets('カードの順は入力欄、通話内容、日付と時刻', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);

      final fieldBottom = tester.getBottomLeft(find.byType(AppTextField)).dy;
      final card = tester.getRect(find.byType(AppCard));
      final dateTop = tester.getTopLeft(find.text('日付')).dy;
      // 欄の中の文字は左寄せなので、間隔は枠同士で見る
      final date = tester.getRect(
        find.ancestor(of: find.text('11/6(金)'), matching: find.byType(InkWell)),
      );
      final time = tester.getRect(
        find.ancestor(of: find.text('08:30'), matching: find.byType(InkWell)),
      );

      expect(card.top - fieldBottom, 16);
      expect(dateTop - card.bottom, 16);
      expect(time.left - date.right, 8);
      expect(date.top, time.top);
    });

    testWidgets('「なおす」は ghost で、押すと準備中と出る', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);

      final button = _button(tester, 'なおす');
      expect(button.variant, AppButtonVariant.ghost);
      expect(button.size, AppButtonSize.s);
      expect(button.leadingIcon, AppIcons.pencil);

      await tester.tap(find.text('なおす'));
      await tester.pump();

      expect(find.text('準備中です'), findsOneWidget);
      expect(_textField(tester).controller!.text, _message);
    });

    testEachLayout('「なおす」の押せる領域は 44pt 以上', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      final size = tester.getSize(find.widgetWithText(AppButton, 'なおす'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('下に固定の部分', () {
    testEachLayout('ボタンの種類がモックのとおりで、44pt 以上', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      expect(find.text(_removedFootNote), findsNothing);

      final book = _button(tester, 'この日時で予約する');
      expect(book.variant, AppButtonVariant.primary);
      expect(book.size, AppButtonSize.l);
      expect(book.leadingIcon, AppIcons.calendarClock);

      final call = _button(tester, '今すぐ通話');
      expect(call.variant, AppButtonVariant.secondary);
      expect(call.size, AppButtonSize.m);
      expect(call.leadingIcon, AppIcons.phone);

      expect(
        tester.getSize(find.widgetWithText(AppButton, 'この日時で予約する')).height,
        greaterThanOrEqualTo(56),
      );
      expect(
        tester.getSize(find.widgetWithText(AppButton, '今すぐ通話')).height,
        greaterThanOrEqualTo(44),
      );
    });

    testEachLayout('本文をスクロールしてもボタンは動かない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester, _longMessage * 8);
      final before = tester.getTopLeft(
        find.widgetWithText(AppButton, 'この日時で予約する'),
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する')),
        before,
      );
    });

    testWidgets('ホームバーは SafeArea で避ける', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpAsk(tester);

      // モックの .homebar の高さ 34 と、その上の間隔 8
      expect(
        tester.getBottomLeft(find.widgetWithText(AppButton, '今すぐ通話')).dy,
        852 - 34 - 8,
      );
      expect(tester.getTopLeft(find.byType(AppNavBar)).dy, 54);
    });

    testWidgets('予約と今すぐ通話の間はモックの 8', (tester) async {
      await _pumpAsk(tester);

      final book = tester.getRect(find.widgetWithText(AppButton, 'この日時で予約する'));
      final call = tester.getRect(find.widgetWithText(AppButton, '今すぐ通話'));

      expect(call.top - book.bottom, 8);
      expect(book.left, 16);
      expect(book.width, 393 - 32);
      expect(call.width, 393 - 32);
    });
  });

  group('キーボード', () {
    void showKeyboard(WidgetTester tester) {
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
      addTearDown(tester.view.resetViewInsets);
    }

    testEachLayout('ボタンはキーボードの上に 8 空けて残り、押せる', (tester, layout) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      final call = tester.getRect(find.widgetWithText(AppButton, '今すぐ通話'));
      expect(call.bottom, 852 - _keyboardHeight - 8);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testEachLayout('入力欄はボタンより上に見え、通話内容と日時はスクロールすれば全部見える', (
      tester,
      layout,
    ) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      final footTop = tester
          .getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する'))
          .dy;
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(footTop),
      );

      await tester.ensureVisible(find.text(_script));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text(_script)).dy,
        lessThanOrEqualTo(footTop),
      );

      await tester.ensureVisible(find.text('08:30'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('08:30')).dy,
        lessThanOrEqualTo(footTop),
      );
      expect(
        tester.getTopLeft(find.text('日付')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppNavBar)).dy),
      );
    });
  });

  group('日付を選ぶ', () {
    testWidgets('標準の画面を、基準の日より前を選べない形で開く', (tester) async {
      await _pumpAsk(tester);

      await _tapVisible(tester, find.text('11/6(金)'));

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
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('11/6(金)'));

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/6(金)'), findsOneWidget);
    });

    testWidgets('基準の日は選べる', (tester) async {
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('11/6(金)'));

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/5(木)'), findsOneWidget);
    });

    testWidgets('選んだ日が欄に出る', (tester) async {
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('11/6(金)'));

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('11/20(金)'), findsOneWidget);
    });

    testWidgets('キャンセルすると変わらない', (tester) async {
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('11/6(金)'));

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
      await _pumpAsk(tester);

      await _tapVisible(tester, find.text('08:30'));

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
      await _pumpAsk(tester);

      await _tapVisible(tester, find.text('08:30'));

      expect(find.text('午前'), findsNothing);
      expect(find.text('午後'), findsNothing);
    });

    testWidgets('選んだ時刻を 2 桁に揃えて欄に出す', (tester) async {
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('08:30'));

      await enterTime(tester, '9', '05');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('キャンセルすると変わらない', (tester) async {
      await _pumpAsk(tester);
      await _tapVisible(tester, find.text('08:30'));

      await enterTime(tester, '9', '05');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('08:30'), findsOneWidget);
    });
  });

  group('操作', () {
    testWidgets('「今すぐ通話」は伝えたいことと通話内容を送り、01 に留まる', (tester) async {
      final calls = await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(calls.started, [(message: _message, script: _script)]);
      expect(find.text('準備中です'), findsNothing);
      expect(find.text('電話機につながっていません'), findsNothing);
      expect(find.byType(AskScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
    });

    testWidgets('電話機がつながっていないと「電話機につながっていません」と出て、01 に留まる', (tester) async {
      final calls = FakeImmediateCallRepository(disconnected: true);
      await _pumpAppAndOpenAsk(tester, calls: calls);
      await _enterMessage(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(find.text('電話機につながっていません'), findsOneWidget);
      expect(find.text('準備中です'), findsNothing);
      expect(calls.started, isEmpty);
      expect(find.byType(AskScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);
    });

    testWidgets('今すぐ通話が失敗しても、01 に留まる', (tester) async {
      final calls = FakeImmediateCallRepository(failing: true);
      await _pumpAppAndOpenAsk(tester, calls: calls);
      await _enterMessage(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(find.text('準備中です'), findsNothing);
      expect(find.text('電話機につながっていません'), findsNothing);
      expect(calls.started, isEmpty);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testWidgets('空のあいだは「今すぐ通話」も「この日時で予約する」も何も起きない', (tester) async {
      final calls = await _pumpAppAndOpenAsk(tester);

      await tester.tap(find.text('今すぐ通話'), warnIfMissed: false);
      await tester.tap(find.text('この日時で予約する'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(calls.started, isEmpty);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
      expect(find.byType(AskScreen), findsOneWidget);
      expect(tester.container().read(bookedCallsProvider), hasLength(3));
    });

    testWidgets('「この日時で予約する」は日時の順に予約を足し、06 を開く', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);

      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 2);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
      expect(tester.testTextInput.isVisible, isFalse);

      final calls = tester.container().read(bookedCallsProvider);
      expect(calls.map((call) => call.message), [
        '話し相手',
        '薬と戸締まりの確認',
        _message,
        '週末に帰ると伝える',
      ]);
      expect(calls[2].at, DateTime(2026, 11, 6, 8, 30));
      expect(calls[2].script, _script);
      expect(find.text('11/6 08:30'), findsOneWidget);
      expect(find.text(_message), findsOneWidget);

      final tops = [
        for (final label in [
          '今日 12:00',
          '今日 19:00',
          '11/6 08:30',
          '11/7 10:00',
        ])
          tester.getTopLeft(find.text(label)).dy,
      ];
      expect(tops[0], lessThan(tops[1]));
      expect(tops[1], lessThan(tops[2]));
      expect(tops[2], lessThan(tops[3]));
    });

    testWidgets('選んだ日付の位置に予約を足す', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await _tapVisible(tester, find.text('11/6(金)'));
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      final calls = tester.container().read(bookedCallsProvider);
      expect(calls.first.message, _message);
      expect(calls.first.at, DateTime(2026, 11, 5, 8, 30));
      expect(find.text('今日 08:30'), findsOneWidget);
    });

    testWidgets('入力した内容の前後の空白を除いて予約する', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester, '  週末に電話する\n');

      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      expect(
        tester.container().read(bookedCallsProvider)[2].message,
        '週末に電話する',
      );
    });

    testWidgets('タブを切り替えても足した予約は残る', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

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
      expect(find.text(_message), findsOneWidget);
    });

    testWidgets('もどると入力は残らず、開き直すと空でフォーカスが当たる', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);

      await tester.tap(find.text('AIに伝えてもらう'));
      await tester.pumpAndSettle();

      expect(_textField(tester).controller!.text, isEmpty);
      expect(_textField(tester).focusNode!.hasFocus, isTrue);
      _expectNeedsMessage(tester);
    });

    testWidgets('もどるの読み上げはモックの aria-label', (tester) async {
      await _pumpAsk(tester);

      expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    });
  });
}
