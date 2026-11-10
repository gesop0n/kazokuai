import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/call_progress_repository.dart';
import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/home_status.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_bookings_repository.dart';
import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_call_script_repository.dart';
import '../../support/fake_immediate_call_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);
const _message = '金曜の通院、10時に迎えに行くと伝えて';
const _script = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';
const _drafted = '「ハナさん、金曜の通院は朝10時にお迎えに行くそうです。」';
const _removedNote = '電話ではこの言い方で伝えます。聞き返されたら、同じ内容をくり返します。';
const _longMessage = '金曜の通院、10時に迎えに行くと伝えて。帰りに薬局へ寄ることも話しておいてほしいです。';

const _removedFootNote = '押すと、すぐにハナさんの固定電話にかけます';

// iPhone 17 Pro で日本語のキーボードを出したときの値
const _keyboardHeight = 336.0;

Future<FakeCallScriptRepository> _pumpAsk(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
  FakeCallScriptRepository? drafts,
  FakeCallProgressRepository? progress,
}) {
  final repository = drafts ?? FakeCallScriptRepository();
  return pumpScreenInLayout(
    tester,
    layout,
    const AskScreen(),
    overrides: [
      callScriptRepositoryProvider.overrideWithValue(repository),
      callProgressRepositoryProvider.overrideWithValue(
        progress ?? FakeCallProgressRepository(),
      ),
      emptyBookings(),
      mockBookingNow(),
    ],
  ).then((_) => repository);
}

// 遷移は go_router が要るので、アプリ全体をホームから動かす
Future<FakeImmediateCallRepository> _pumpAppAndOpenAsk(
  WidgetTester tester, {
  FakeImmediateCallRepository? calls,
  FakeCallScriptRepository? drafts,
  FakeCallProgressRepository? progress,
}) async {
  final repository = calls ?? FakeImmediateCallRepository();
  final scripts = drafts ?? FakeCallScriptRepository(script: _drafted);
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
        callScriptRepositoryProvider.overrideWithValue(scripts),
        callProgressRepositoryProvider.overrideWithValue(
          progress ?? FakeCallProgressRepository(),
        ),
        emptyBookings(),
        mockBookingNow(),
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

// 入力が止まってから案が届くまで。偽物がすぐ返すときは、1 秒で案が出る
Future<void> _waitForDraft(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _setWheel(WidgetTester tester, Finder wheel, int index) async {
  final scrollable = find.descendant(
    of: wheel,
    matching: find.byWidgetPredicate((widget) => widget is Scrollable),
  );
  final controller =
      tester.widget<Scrollable>(scrollable).controller!
          as FixedExtentScrollController;
  controller.jumpToItem(index);
  await tester.pumpAndSettle();
}

AppButton _button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

FakeBookingsRepository _bookings(WidgetTester tester) =>
    tester.container().read(bookingsRepositoryProvider)
        as FakeBookingsRepository;

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
      expect(find.text('8:30'), findsOneWidget);
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

    testWidgets('日時の欄は、日時を選ぶボタンとして読み、中の値は重ねない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAsk(tester);

      expect(find.bySemanticsLabel('日時を選ぶ'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('日時を選ぶ')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
      expect(find.bySemanticsLabel('11/6(金)'), findsNothing);
      expect(find.bySemanticsLabel('8:30'), findsNothing);
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
    testEachLayout('入力が止むと、呼び方を使った通話内容が出て、予約も今すぐ通話も押せる', (
      tester,
      layout,
    ) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester);
      await _waitForDraft(tester);

      expect(find.byType(AppAiTag), findsOneWidget);
      expect(find.text('通話内容'), findsOneWidget);
      expect(find.text(_script), findsOneWidget);
      expect(find.text('話し方'), findsNothing);
      expect(find.text('Geminiの言い方の案'), findsNothing);
      expect(find.text(_removedNote), findsNothing);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testWidgets('入力が止むまでは案を頼まず、止んでから頼んだ案を出す', (tester) async {
      final drafts = FakeCallScriptRepository(script: _drafted);
      await _pumpAsk(tester, drafts: drafts);

      await _enterMessage(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(drafts.messages, isEmpty);
      expect(find.text('案を作っています'), findsNothing);
      expect(find.text(_drafted), findsNothing);
      expect(find.text(_script), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNull);

      await tester.pump(const Duration(milliseconds: 500));

      expect(drafts.messages, [_message]);
      expect(find.text(_drafted), findsOneWidget);
      expect(find.text('案を作っています'), findsNothing);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testWidgets('打ち直すと、止まるまでを数え直し、前の案は残さない', (tester) async {
      final drafts = FakeCallScriptRepository(
        onDraft: (message) async =>
            message == '庭の菊' ? '「ハナさん、菊が咲いたそうです。」' : '「ハナさん、来週の予定です。」',
      );
      await _pumpAsk(tester, drafts: drafts);

      await _enterMessage(tester, '庭の菊');
      await tester.pump(const Duration(milliseconds: 800));
      await _enterMessage(tester, '来週の予定');
      await tester.pump(const Duration(milliseconds: 800));

      expect(drafts.messages, isEmpty);
      expect(find.text('「ハナさん、菊が咲いたそうです。」'), findsNothing);
      expect(find.text('案を作っています'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));

      expect(drafts.messages, ['来週の予定']);
      expect(find.text('「ハナさん、来週の予定です。」'), findsOneWidget);
      expect(find.text('「ハナさん、菊が咲いたそうです。」'), findsNothing);
    });

    testWidgets('先の案が後から届いても、今の文の案だけを出す', (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      final drafts = FakeCallScriptRepository(
        onDraft: (message) async {
          if (message == '庭の菊') {
            await first.future;
            return '「ハナさん、菊が咲いたそうです。」';
          }
          await second.future;
          return '「ハナさん、来週の予定です。」';
        },
      );
      await _pumpAsk(tester, drafts: drafts);

      await _enterMessage(tester, '庭の菊');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('案を作っています'), findsOneWidget);
      expect(drafts.messages, ['庭の菊']);

      await _enterMessage(tester, '来週の予定');
      expect(find.text('案を作っています'), findsNothing);
      expect(find.text('「ハナさん、菊が咲いたそうです。」'), findsNothing);

      first.complete();
      await tester.pump();
      expect(find.text('「ハナさん、菊が咲いたそうです。」'), findsNothing);
      expect(find.text('案を作っています'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(drafts.messages, ['庭の菊', '来週の予定']);
      expect(find.text('案を作っています'), findsOneWidget);

      second.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('「ハナさん、来週の予定です。」'), findsOneWidget);
      expect(find.text('「ハナさん、菊が咲いたそうです。」'), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testWidgets('案を作っているあいだは、その文が出て、予約も今すぐ通話も押せない', (tester) async {
      final gate = Completer<void>();
      final drafts = FakeCallScriptRepository(script: _drafted, pending: gate);
      await _pumpAsk(tester, drafts: drafts);

      await _enterMessage(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('案を作っています'), findsOneWidget);
      expect(find.text(_drafted), findsNothing);
      expect(find.text('通話内容'), findsOneWidget);
      expect(_button(tester, 'この日時で予約する').onTap, isNull);
      expect(_button(tester, '今すぐ通話').onTap, isNull);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('案を作っています'), findsNothing);
      expect(find.text(_drafted), findsOneWidget);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testWidgets('案を作れなかったときは、その文が出て、空の通話内容では押せない', (tester) async {
      await _pumpAsk(tester, drafts: FakeCallScriptRepository(failing: true));

      await _enterMessage(tester);
      await _waitForDraft(tester);

      expect(find.text('案を作れませんでした'), findsOneWidget);
      expect(find.text(_script), findsNothing);
      expect(find.text('通話内容'), findsOneWidget);
      expect(_button(tester, 'この日時で予約する').onTap, isNull);
      expect(_button(tester, '今すぐ通話').onTap, isNull);

      await tester.tap(find.text('今すぐ通話'), warnIfMissed: false);
      await tester.tap(find.text('この日時で予約する'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('案を作れませんでした'), findsOneWidget);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testEachLayout('長い文でも崩れない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester, _longMessage * 4);
      await _waitForDraft(tester);

      expect(find.text(_script), findsOneWidget);
    });

    testWidgets('消すと通話内容が消え、どちらのボタンも押せなくなる', (tester) async {
      final drafts = await _pumpAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);
      expect(find.text(_script), findsOneWidget);

      await _enterMessage(tester, '');
      await tester.pump(const Duration(seconds: 1));

      _expectNeedsMessage(tester);
      expect(drafts.messages, [_message]);
    });

    for (final (name, spaces) in [
      ('半角', '   '),
      ('全角', '　　'),
      ('改行', '\n\n'),
    ]) {
      testWidgets('$nameの空白だけのときは空と同じ', (tester) async {
        final drafts = await _pumpAsk(tester);

        await _enterMessage(tester, spaces);
        await tester.pump(const Duration(seconds: 1));

        _expectNeedsMessage(tester);
        expect(drafts.messages, isEmpty);
      });
    }

    testWidgets('カードの順は入力欄、通話内容、日時', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      final fieldBottom = tester.getBottomLeft(find.byType(AppTextField)).dy;
      final card = tester.getRect(find.byType(AppCard));
      final whenTop = tester.getTopLeft(find.text('日時')).dy;
      final when = tester.getRect(
        find.ancestor(of: find.text('11/6(金)'), matching: find.byType(InkWell)),
      );

      expect(card.top - fieldBottom, 16);
      expect(whenTop - card.bottom, 16);
      expect(when.top - tester.getBottomLeft(find.text('日時')).dy, 8);
    });

    testWidgets('「なおす」は ghost で、押すと準備中と出る', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);

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
      await _waitForDraft(tester);

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

    testEachLayout('ボタンはキーボードの下に隠れ、予約も今すぐ通話も押せるまま', (tester, layout) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      final keyboardTop = 852 - _keyboardHeight;
      expect(
        tester.getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する')).dy,
        greaterThanOrEqualTo(keyboardTop),
      );
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
    });

    testEachLayout('入力欄はキーボードの上に見え、通話内容と日時はスクロールすれば全部見える', (
      tester,
      layout,
    ) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      final keyboardTop = 852 - _keyboardHeight;
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(keyboardTop),
      );

      await tester.ensureVisible(find.text(_script));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text(_script)).dy,
        lessThanOrEqualTo(keyboardTop),
      );

      await tester.ensureVisible(find.text('8:30'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('8:30')).dy,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        tester.getTopLeft(find.text('日時')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppNavBar)).dy),
      );
    });
  });

  group('操作', () {
    testWidgets('「今すぐ通話」は伝えたいことと通話内容を送り、01 に留まる', (tester) async {
      final calls = await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(find.text(_drafted), findsOneWidget);
      expect(find.text(_script), findsNothing);
      expect(calls.started, [(message: _message, script: _drafted)]);
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
      await _waitForDraft(tester);

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
      await _waitForDraft(tester);

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
      expect(_bookings(tester).bookings.value, isEmpty);
    });

    testWidgets('「この日時で予約する」は予約を保存し、06 を開く', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 2);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
      expect(tester.testTextInput.isVisible, isFalse);

      final saved = _bookings(tester).created.single;
      expect(saved.message, _message);
      expect(saved.at, DateTime(2026, 11, 6, 8, 30));
      expect(saved.script, _drafted);
      expect(find.text('11/6 08:30'), findsOneWidget);
      expect(find.text(_message), findsOneWidget);
      expect(find.text('話し相手'), findsNothing);
    });

    testWidgets('選んだ日時の位置に予約を足す', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);
      await _tapVisible(tester, find.bySemanticsLabel('日時を選ぶ'));
      await tester.tap(find.bySemanticsLabel('11月5日、今日'));
      await tester.pumpAndSettle();
      await _setWheel(tester, find.bySemanticsLabel(RegExp(r'^時$')), 9);
      await _setWheel(tester, find.bySemanticsLabel(RegExp(r'^分$')), 0);
      await tester.tap(find.widgetWithText(AppButton, '11/5(木) 9:00にする'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      final saved = _bookings(tester).created.single;
      expect(saved.message, _message);
      expect(saved.at, DateTime(2026, 11, 5, 9));
      expect(find.text('今日 09:00'), findsOneWidget);
    });

    testWidgets('入力した内容の前後の空白を除いて予約する', (tester) async {
      final drafts = FakeCallScriptRepository(script: _drafted);
      await _pumpAppAndOpenAsk(tester, drafts: drafts);
      await _enterMessage(tester, '  週末に電話する\n');
      await _waitForDraft(tester);

      expect(drafts.messages, ['週末に電話する']);
      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      expect(_bookings(tester).created.single.message, '週末に電話する');
    });

    for (final (failure, text) in [
      (const BookingTooCloseException(), '近い時刻に予約があります'),
      (const BookingTooSoonException(), '早すぎる'),
      (const BookingTooFarException(), '先すぎる'),
      (const BookingFailedException(), '送れなかった'),
    ]) {
      testWidgets('$text と出て、01 に留まる', (tester) async {
        await _pumpAppAndOpenAsk(tester);
        await _enterMessage(tester);
        await _waitForDraft(tester);
        final bookings = _bookings(tester);
        bookings.failure = failure;

        await tester.tap(find.text('この日時で予約する'));
        await tester.pump();

        expect(find.text(text), findsOneWidget);
        expect(find.byType(AskScreen), findsOneWidget);
        expect(find.byType(BookingScreen), findsNothing);
        expect(bookings.created, isEmpty);
        await tester.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('タブを切り替えても足した予約は残る', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);
      await _waitForDraft(tester);
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

  group('電話の最中', () {
    testWidgets('呼び出し中か通話中は「通話中です」で押せない。終わると「今すぐ通話」に戻る', (tester) async {
      final progress = FakeCallProgressRepository(inProgress: true);
      await _pumpAsk(tester, progress: progress);

      expect(find.text('通話中です'), findsOneWidget);
      expect(find.text('今すぐ通話'), findsNothing);
      expect(_button(tester, '通話中です').onTap, isNull);
      expect(_button(tester, 'この日時で予約する').onTap, isNull);

      await _enterMessage(tester);
      await _waitForDraft(tester);

      final call = _button(tester, '通話中です');
      expect(call.onTap, isNull);
      expect(call.variant, AppButtonVariant.secondary);
      expect(call.size, AppButtonSize.m);
      expect(call.leadingIcon, AppIcons.phone);
      final icon = tester.widget<AppIcon>(
        find.descendant(
          of: find.widgetWithText(AppButton, '通話中です'),
          matching: find.byType(AppIcon),
        ),
      );
      expect(icon.icon, AppIcons.phone);
      expect(icon.color, AppColors.inkSecondary);
      expect(icon.size, 18);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);

      await tester.tap(find.text('通話中です'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(AskScreen), findsOneWidget);

      progress.inProgress.value = false;
      await tester.pump();

      expect(find.text('今すぐ通話'), findsOneWidget);
      expect(find.text('通話中です'), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testWidgets('電話の最中でも「この日時で予約する」は予約できる', (tester) async {
      final progress = FakeCallProgressRepository(inProgress: true);
      final calls = FakeImmediateCallRepository();
      await _pumpAppAndOpenAsk(tester, calls: calls, progress: progress);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      expect(_button(tester, '通話中です').onTap, isNull);
      await tester.tap(find.text('この日時で予約する'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(calls.started, isEmpty);
      expect(_bookings(tester).created.single.message, _message);
      expect(find.text('11/6 08:30'), findsOneWidget);
    });

    testWidgets('電話の最中と断られたら「通話中です」と出て、終わると「今すぐ通話」に戻る', (tester) async {
      final progress = FakeCallProgressRepository();
      final calls = FakeImmediateCallRepository(inProgress: true);
      await _pumpAppAndOpenAsk(tester, calls: calls, progress: progress);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(find.text('通話中です'), findsOneWidget);
      expect(find.text('今すぐ通話'), findsNothing);
      expect(find.text('電話機につながっていません'), findsNothing);
      expect(find.text('準備中です'), findsNothing);
      expect(_button(tester, '通話中です').onTap, isNull);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(calls.started, isEmpty);
      expect(find.byType(AskScreen), findsOneWidget);

      progress.inProgress.value = true;
      await tester.pump();
      expect(find.text('通話中です'), findsOneWidget);

      progress.inProgress.value = false;
      await tester.pump();

      expect(find.text('今すぐ通話'), findsOneWidget);
      expect(find.text('通話中です'), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testWidgets('呼び出し中を読まなくても、終わったと分かれば「今すぐ通話」に戻る', (tester) async {
      final progress = FakeCallProgressRepository();
      final calls = FakeImmediateCallRepository(inProgress: true);
      await _pumpAppAndOpenAsk(tester, calls: calls, progress: progress);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pumpAndSettle();

      expect(find.text('通話中です'), findsOneWidget);
      expect(_button(tester, '通話中です').onTap, isNull);

      // 進行中の通知を経由せず、終わったあとの読み取りだけが届く
      progress.inProgress.read(false);
      await tester.pump();

      expect(find.text('今すぐ通話'), findsOneWidget);
      expect(find.text('通話中です'), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testWidgets('終わった通知が拒否より先でも「今すぐ通話」に戻る', (tester) async {
      final progress = FakeCallProgressRepository();
      final gate = Completer<void>();
      final calls = FakeImmediateCallRepository(
        inProgress: true,
        gate: gate.future,
      );
      await _pumpAppAndOpenAsk(tester, calls: calls, progress: progress);
      await _enterMessage(tester);
      await _waitForDraft(tester);

      await tester.tap(find.text('今すぐ通話'));
      await tester.pump();

      progress.inProgress.read(true);
      await tester.pump();
      expect(find.text('通話中です'), findsOneWidget);

      progress.inProgress.read(false);
      await tester.pump();
      expect(find.text('今すぐ通話'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('今すぐ通話'), findsOneWidget);
      expect(find.text('通話中です'), findsNothing);
      expect(_button(tester, '今すぐ通話').onTap, isNotNull);
      expect(_button(tester, 'この日時で予約する').onTap, isNotNull);
      expect(find.byType(AskScreen), findsOneWidget);
      expect(calls.started, isEmpty);
    });
  });
}
