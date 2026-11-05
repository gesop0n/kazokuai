import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/home/calling_banner.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/home_status.dart';

import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);
const _message = '金曜の通院、10時に迎えに行くと伝えて';
const _suggestion = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';
const _note = '電話ではこの言い方で伝えます。聞き返されたら、同じ内容をくり返します。';
const _longMessage = '金曜の通院、10時に迎えに行くと伝えて。帰りに薬局へ寄ることも話しておいてほしいです。';

const _footNote = '押すと、すぐにハナさんの固定電話にかけます';

// iPhone 17 Pro で日本語のキーボードを出したときの値
const _keyboardHeight = 336.0;

List<Override> _startingAt(HomeStatus status) => [
  homeStatusProvider.overrideWithBuild((ref, self) => status),
];

Future<void> _pumpAsk(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
  HomeStatus status = HomeStatus.normal,
}) => pumpScreenInLayout(
  tester,
  layout,
  const AskScreen(),
  overrides: _startingAt(status),
);

// 遷移は go_router が要るので、アプリ全体をホームから動かす
Future<void> _pumpAppAndOpenAsk(
  WidgetTester tester, {
  HomeStatus status = HomeStatus.normal,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: _startingAt(status), child: const KazokuAiApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('伝えたいことを入力'));
  await tester.pumpAndSettle();
  expect(find.byType(AskScreen), findsOneWidget);
}

Future<void> _enterMessage(
  WidgetTester tester, [
  String text = _message,
]) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

AppButton _button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

TextField _textField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void _expectEmptyState(WidgetTester tester) {
  expect(find.text('Geminiの言い方の案'), findsNothing);
  expect(find.text(_suggestion), findsNothing);
  expect(_button(tester, '通話').onTap, isNull);
}

void main() {
  group('開いたとき', () {
    testEachLayout('入力欄は空でフォーカスが当たり、案は出ず、通話は押せない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await tester.pump();

      expect(find.text('AIに伝えてもらう'), findsOneWidget);
      expect(find.text('伝えたいこと'), findsOneWidget);
      expect(_textField(tester).controller!.text, isEmpty);
      expect(_textField(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      _expectEmptyState(tester);
      expect(_button(tester, '日時を決めて予約する').onTap, isNotNull);
    });

    testWidgets('入力欄はモックの最小の高さ 60 で、複数行に伸びる', (tester) async {
      await _pumpAsk(tester);

      final field = tester.widget<AppTextField>(find.byType(AppTextField));
      expect(field.maxLines, isNull);
      expect(tester.getSize(find.byType(AppTextField)).height, 60);

      await _enterMessage(tester, _longMessage * 3);
      expect(tester.getSize(find.byType(AppTextField)).height, greaterThan(60));
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

  group('言い方の案', () {
    testEachLayout('文字を入れると案が出て、通話が押せる', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester);

      expect(find.byType(AppAiTag), findsOneWidget);
      expect(find.text('Geminiの言い方の案'), findsOneWidget);
      expect(find.text(_suggestion), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
      expect(_button(tester, '通話').onTap, isNotNull);
    });

    testEachLayout('長い文でも崩れない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);

      await _enterMessage(tester, _longMessage * 4);

      expect(find.text(_suggestion), findsOneWidget);
    });

    testWidgets('文は入力の内容によって変わらない', (tester) async {
      await _pumpAsk(tester);

      await _enterMessage(tester, '庭の菊が咲きました');
      expect(find.text(_suggestion), findsOneWidget);

      await _enterMessage(tester, '来週の予定');
      expect(find.text(_suggestion), findsOneWidget);
    });

    testWidgets('消すと案が消え、通話が押せなくなる', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);
      expect(find.text(_suggestion), findsOneWidget);

      await _enterMessage(tester, '');

      _expectEmptyState(tester);
    });

    for (final (name, spaces) in [
      ('半角', '   '),
      ('全角', '　　'),
      ('改行', '\n\n'),
    ]) {
      testWidgets('$nameの空白だけのときは空と同じ', (tester) async {
        await _pumpAsk(tester);

        await _enterMessage(tester, spaces);

        _expectEmptyState(tester);
      });
    }

    testWidgets('カードの順はモックのとおりで、案は入力欄と話し方の間に出る', (tester) async {
      await _pumpAsk(tester);
      await _enterMessage(tester);

      final fieldBottom = tester.getBottomLeft(find.byType(AppTextField)).dy;
      final card = tester.getRect(find.byType(AppCard));
      final voiceTop = tester.getTopLeft(find.text('話し方')).dy;

      expect(card.top - fieldBottom, 16);
      expect(voiceTop - card.bottom, 16);
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
    testEachLayout('文言とボタンの種類がモックのとおりで、44pt 以上', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      expect(find.text(_footNote), findsOneWidget);

      final call = _button(tester, '通話');
      expect(call.variant, AppButtonVariant.record);
      expect(call.size, AppButtonSize.l);
      expect(call.leadingIcon, AppIcons.phone);

      final book = _button(tester, '日時を決めて予約する');
      expect(book.variant, AppButtonVariant.secondary);
      expect(book.size, AppButtonSize.m);
      expect(book.leadingIcon, isNull);

      expect(
        tester.getSize(find.widgetWithText(AppButton, '通話')).height,
        greaterThanOrEqualTo(56),
      );
      expect(
        tester.getSize(find.widgetWithText(AppButton, '日時を決めて予約する')).height,
        greaterThanOrEqualTo(44),
      );
    });

    testEachLayout('本文をスクロールしてもボタンは動かない', (tester, layout) async {
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester, _longMessage * 8);
      final before = tester.getTopLeft(find.widgetWithText(AppButton, '通話'));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.widgetWithText(AppButton, '通話')), before);
    });

    testWidgets('ホームバーは SafeArea で避ける', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpAsk(tester);

      // モックの .homebar の高さ 34
      expect(
        tester.getBottomLeft(find.widgetWithText(AppButton, '日時を決めて予約する')).dy,
        852 - 34,
      );
      expect(tester.getTopLeft(find.byType(AppNavBar)).dy, 54);
    });

    testWidgets('通話と予約の間と、文言と通話の間はモックの 8', (tester) async {
      await _pumpAsk(tester);

      final note = tester.getRect(find.text(_footNote));
      final call = tester.getRect(find.widgetWithText(AppButton, '通話'));
      final book = tester.getRect(find.widgetWithText(AppButton, '日時を決めて予約する'));

      expect(call.top - note.bottom, 8);
      expect(book.top - call.bottom, 8);
      expect(call.left, 16);
      expect(call.width, 393 - 32);
      expect(book.width, 393 - 32);
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

      final book = tester.getRect(find.widgetWithText(AppButton, '日時を決めて予約する'));
      expect(book.bottom, 852 - _keyboardHeight - 8);
      expect(_button(tester, '通話').onTap, isNotNull);
    });

    testEachLayout('入力欄はボタンより上に見え、案もスクロールすれば全部見える', (tester, layout) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      final noteTop = tester.getTopLeft(find.text(_footNote)).dy;
      expect(
        tester.getBottomLeft(find.byType(AppTextField)).dy,
        lessThan(noteTop),
      );
      // 案の見出しは、スクロールしなくても見える
      expect(
        tester.getTopLeft(find.text('Geminiの言い方の案')).dy,
        lessThan(noteTop),
      );

      await tester.ensureVisible(find.text(_suggestion));
      await tester.pumpAndSettle();

      final suggestion = tester.getRect(find.text(_suggestion));
      expect(suggestion.bottom, lessThanOrEqualTo(noteTop));
      expect(
        suggestion.top,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppNavBar)).dy),
      );
    });

    testEachLayout('話し方もスクロールで届く', (tester, layout) async {
      showKeyboard(tester);
      await _pumpAsk(tester, layout: layout);
      await _enterMessage(tester);

      await tester.ensureVisible(find.text('大きい'));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.text('大きい')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text(_footNote)).dy),
      );
    });
  });

  group('操作', () {
    testWidgets('「通話」を押すと通話中になり、ホームに戻る', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);

      await tester.tap(find.text('通話').last);
      await tester.pumpAndSettle();

      expect(tester.container().read(homeStatusProvider), HomeStatus.calling);
      expect(find.byType(AskScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CallingBanner), findsOneWidget);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 0);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('空のあいだは「通話」を押しても何も起きない', (tester) async {
      await _pumpAppAndOpenAsk(tester);

      await tester.tap(find.text('通話').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
      expect(find.byType(AskScreen), findsOneWidget);
    });

    testWidgets('「日時を決めて予約する」は予約電話のタブに移り、通話は始めない', (tester) async {
      await _pumpAppAndOpenAsk(tester);
      await _enterMessage(tester);

      await tester.tap(find.text('日時を決めて予約する'));
      await tester.pumpAndSettle();

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 2);
      expect(tester.container().read(homeStatusProvider), HomeStatus.normal);
      expect(tester.testTextInput.isVisible, isFalse);
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

      await tester.tap(find.text('伝えたいことを入力'));
      await tester.pumpAndSettle();

      expect(_textField(tester).controller!.text, isEmpty);
      expect(_textField(tester).focusNode!.hasFocus, isTrue);
      _expectEmptyState(tester);
    });

    testWidgets('もどるの読み上げはモックの aria-label', (tester) async {
      await _pumpAsk(tester);

      expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    });
  });

  group('通話中に開いたとき', () {
    testEachLayout('「通話」の位置に押せない「現在通話中です」を出す', (tester, layout) async {
      await _pumpAsk(tester, layout: layout, status: HomeStatus.calling);
      await _enterMessage(tester);

      expect(find.text('通話'), findsNothing);
      final button = _button(tester, '現在通話中です');
      expect(button.onTap, isNull);
      expect(button.size, AppButtonSize.l);
      expect(button.leadingIcon, isNull);
      expect(_button(tester, '日時を決めて予約する').onTap, isNotNull);
    });

    testWidgets('入力しても押せず、案は出る', (tester) async {
      await _pumpAppAndOpenAsk(tester, status: HomeStatus.calling);
      await _enterMessage(tester);

      expect(find.text(_suggestion), findsOneWidget);

      await tester.tap(find.text('現在通話中です').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AskScreen), findsOneWidget);
      expect(tester.container().read(homeStatusProvider), HomeStatus.calling);
    });

    testWidgets('入力が空でも文言は「現在通話中です」', (tester) async {
      await _pumpAsk(tester, status: HomeStatus.calling);

      expect(find.text('現在通話中です'), findsOneWidget);
      expect(find.text('通話'), findsNothing);
    });

    testWidgets('読み上げは押せないボタン', (tester) async {
      await _pumpAsk(tester, status: HomeStatus.calling);

      expect(
        tester.getSemantics(find.widgetWithText(AppButton, '現在通話中です')),
        isSemantics(
          label: '現在通話中です',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
    });

    testWidgets('「通話」と同じ位置に出る', (tester) async {
      await _pumpAsk(tester);
      final normal = tester.getRect(find.widgetWithText(AppButton, '通話'));

      tester.container().read(homeStatusProvider.notifier).startCall();
      await tester.pump();

      expect(tester.getRect(find.widgetWithText(AppButton, '現在通話中です')), normal);
    });
  });
}
