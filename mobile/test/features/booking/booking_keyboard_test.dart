import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/call_script_repository.dart';
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
