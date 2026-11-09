import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/design/app_theme.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';

import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_call_script_repository.dart';
import '../../support/layout_matrix.dart';

// iPhone 17 Pro で日本語のキーボードを出したときの高さ。01 の既存のテストと同じ
const _keyboardHeight = 336.0;

// モック、iPhone SE、キーボードで下のボタンが中身にかぶさる短い高さ
const _heights = <double>[852, 667, 480];

void main() {
  for (final height in _heights) {
    for (final textScale in const [1.0, 1.3]) {
      final layout = LayoutCase(360, textScale);
      final label = '高さ ${height.toInt()}、文字倍率 $textScale';

      testWidgets('01 は $label でも、キーボードの上に入力欄が押しつぶされず見える', (tester) async {
        await _pumpWithKeyboard(
          tester,
          layout: layout,
          height: height,
          screen: const AskScreen(),
          overrides: [
            callScriptRepositoryProvider.overrideWithValue(
              FakeCallScriptRepository(),
            ),
            idleCallProgress(),
          ],
        );

        await _expectFieldAboveKeyboard(tester, height);
        await _expectRestingFooterReturns(tester, height);
      });

      testWidgets('06b は $label でも、キーボードの上に入力欄が押しつぶされず見える', (tester) async {
        await _pumpWithKeyboard(
          tester,
          layout: layout,
          height: height,
          screen: const BookingEditScreen(index: 0),
        );

        await _expectFieldAboveKeyboard(tester, height);
        await _expectTimeAboveKeyboard(tester, height, '12:00');
      });
    }
  }

  testWidgets('長い文でも入力欄の高さはキーボードで変わらず、末尾はキーボードの上までスクロールできる', (tester) async {
    const height = 667.0;
    const message = '金曜の通院のあと、薬局に寄って、夜の薬を確認してほしいです。';
    await _pumpWithKeyboard(
      tester,
      layout: const LayoutCase(360, 1.0),
      height: height,
      screen: const AskScreen(),
      overrides: [
        callScriptRepositoryProvider.overrideWithValue(
          FakeCallScriptRepository(),
        ),
        idleCallProgress(),
      ],
    );
    await tester.enterText(find.byType(TextField), message * 4);
    await tester.pump();

    final openHeight = tester.getSize(find.byType(AppTextField)).height;
    await _scrollFieldBottomAboveKeyboard(tester, height);
    expect(openHeight, greaterThan(60));

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(
      tester.getSize(find.byType(AppTextField)).height,
      closeTo(openHeight, 0.1),
    );
  });

  for (final ask in const [true, false]) {
    final label = ask ? '01' : '06b';

    testWidgets('$label はキーボードを開閉しても入力欄を作り直さず、閉じても開き直さない', (tester) async {
      await _pumpForm(tester, ask: ask);
      await tester.pumpAndSettle();
      final fieldState = tester.state(find.byType(AppTextField));
      final focus = _focusNode(tester);
      expect(focus.hasFocus, isTrue);
      expect(_textInputShows(tester), greaterThan(0));

      _showKeyboard(tester);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AppTextField)), same(fieldState));
      expect(_focusNode(tester), same(focus));

      focus.unfocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      tester.testTextInput.log.clear();

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(_textInputShows(tester), 0);
      expect(_focusNode(tester), same(focus));
      expect(focus.hasFocus, isFalse);
      expect(tester.state(find.byType(AppTextField)), same(fieldState));
    });

    testWidgets('$label は iOS で欄の外を押すとキーボードが閉じ、ボタンに届く', (tester) async {
      await _pumpForm(tester, ask: ask, ios: true);
      _showKeyboard(tester);
      await tester.pumpAndSettle();
      final focus = _focusNode(tester);
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.byType(AppTextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.text(ask ? 'AIに伝えてもらう' : '予約の編集'));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await _expectFooterAtRest(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('$label は iOS で本文をドラッグするとキーボードが閉じ、ボタンに届く', (tester) async {
      await _pumpForm(tester, ask: ask, ios: true);
      _showKeyboard(tester);
      await tester.pumpAndSettle();
      final focus = _focusNode(tester);
      expect(focus.hasFocus, isTrue);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      await _expectFooterAtRest(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

Future<void> _pumpWithKeyboard(
  WidgetTester tester, {
  required LayoutCase layout,
  required double height,
  required Widget screen,
  List<Override> overrides = const [],
}) async {
  await pumpScreenInLayout(tester, layout, screen, overrides: overrides);
  tester.view
    ..physicalSize = Size(layout.width, height)
    ..viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
  await tester.pump();
}

// 入力欄はキーボードに隠れず、閉じたときと同じ高さのまま
Future<void> _expectFieldAboveKeyboard(
  WidgetTester tester,
  double height,
) async {
  expect(tester.takeException(), isNull);

  final field = find.byType(AppTextField);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();

  final keyboardTop = height - _keyboardHeight;
  // ボタンはキーボードの下に残る。上へ持ち上げると入力欄の場所を取る
  expect(
    tester.getTopLeft(find.widgetWithText(AppButton, 'この日時で予約する')).dy,
    greaterThanOrEqualTo(keyboardTop),
  );
  final rect = tester.getRect(field);
  final navBottom = tester.getBottomLeft(find.byType(AppNavBar)).dy;
  expect(rect.height, greaterThanOrEqualTo(60));
  expect(rect.top, greaterThanOrEqualTo(navBottom));
  expect(rect.bottom, lessThanOrEqualTo(keyboardTop));

  final openHeight = rect.height;
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();
  expect(tester.getSize(field).height, closeTo(openHeight, 0.1));

  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
  await tester.pumpAndSettle();
}

Future<void> _expectTimeAboveKeyboard(
  WidgetTester tester,
  double height,
  String time,
) async {
  await tester.ensureVisible(find.text(time));
  await tester.pumpAndSettle();

  final keyboardTop = height - _keyboardHeight;
  final rect = tester.getRect(find.text(time));
  final navBottom = tester.getBottomLeft(find.byType(AppNavBar)).dy;
  expect(rect.top, greaterThanOrEqualTo(navBottom));
  expect(rect.bottom, lessThanOrEqualTo(keyboardTop));
}

// キーボードを閉じると、ボタンはまた画面の下に戻る
Future<void> _expectRestingFooterReturns(
  WidgetTester tester,
  double height,
) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();

  expect(
    tester.getRect(find.widgetWithText(AppButton, '今すぐ通話')).bottom,
    closeTo(height - 8, 0.1),
  );
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required bool ask,
  bool ios = false,
}) {
  final screen = ask ? const AskScreen() : const BookingEditScreen(index: 0);
  // appTheme は読み込み時の OS を覚えている。iOS の跳ね返りを試すときは差し替える
  return pumpScreenInLayout(
    tester,
    const LayoutCase(360, 1.0),
    ios
        ? Theme(
            data: appTheme.copyWith(platform: TargetPlatform.iOS),
            child: screen,
          )
        : screen,
    overrides: ask
        ? [
            callScriptRepositoryProvider.overrideWithValue(
              FakeCallScriptRepository(),
            ),
            idleCallProgress(),
          ]
        : const [],
  );
}

void _showKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
}

FocusNode _focusNode(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).focusNode!;
}

int _textInputShows(WidgetTester tester) {
  return tester.testTextInput.log
      .where((call) => call.method == 'TextInput.show')
      .length;
}

// キーボードを閉じると、ボタンはまた画面の下に戻る。高さは pumpScreenInLayout の 852
Future<void> _expectFooterAtRest(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.widgetWithText(AppButton, '今すぐ通話')).bottom,
    closeTo(852 - 8, 0.1),
  );
}

Future<void> _scrollFieldBottomAboveKeyboard(
  WidgetTester tester,
  double height,
) async {
  final keyboardTop = height - _keyboardHeight;
  final field = find.byType(AppTextField);
  for (var i = 0; i < 30; i++) {
    if (tester.getRect(field).bottom <= keyboardTop) return;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -60));
    await tester.pump();
  }
  expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop));
}
