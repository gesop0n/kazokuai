import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

import '../../support/fake_bookings_repository.dart';
import '../../support/layout_matrix.dart';

// 高さと折り返しは文字の幅で変わるので、同梱のフォントを読み込んで測る。
// 読み込んだフォントはこのファイルのテストにだけ効く。
Future<void> _loadFonts() async {
  const families = {
    'BIZUDPGothic': ['BIZUDPGothic-Regular', 'BIZUDPGothic-Bold'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}

const _mockLayout = LayoutCase(393, 1.0);
const _narrowLargeLayout = LayoutCase(360, 1.3);

Future<void> _pumpBooking(WidgetTester tester, LayoutCase layout) =>
    pumpScreenInLayout(
      tester,
      layout,
      const Scaffold(body: BookingScreen()),
      overrides: [
        bookingsRepositoryProvider.overrideWithValue(
          FakeBookingsRepository(bookings: sampleBookedCalls),
        ),
        mockBookingNow(),
      ],
    );

Future<void> _pumpRule(
  WidgetTester tester,
  LayoutCase layout, {
  RetryRule rule = const RetryRule(
    interval: Duration(minutes: 15),
    attempts: 3,
  ),
}) => pumpScreenInLayout(
  tester,
  layout,
  const RetryRuleScreen(),
  overrides: [retryRuleProvider.overrideWithBuild((ref, self) => rule)],
);

// 行の高さは整数に丸められるので、2 行の高さに届かないことで 1 行だと判断する
Matcher _isOneLineOf(double lineHeight, LayoutCase layout) =>
    lessThan(lineHeight * layout.textScale * 1.5);

void main() {
  setUpAll(_loadFonts);

  // docs/mock/ui.html の 06 を headless Chrome で、BIZ UDPゴシックを読み込んで測った値。
  // 画面の上の状態バー 54 は引いてある。
  group('06 の大きさがモックと同じ', () {
    testWidgets('一覧のカードは幅 361 で、上から 48 の位置に出る', (tester) async {
      await _pumpBooking(tester, _mockLayout);

      // モックのカードは高さ 195。行の押せる領域を 44pt にした分、
      // 1 行の行が 14 ずつ、2 行の時刻の行が 2、合わせて 30 高い
      final card = find.byType(AppCard);
      expect(tester.getSize(card), const Size(361, 195 + 30));
      expect(tester.getTopLeft(card).dy, 48);
    });

    testWidgets('新しい予約は高さ 56、幅 361 で、カードとの間は 12', (tester) async {
      await _pumpBooking(tester, _mockLayout);

      final card = tester.getRect(find.byType(AppCard));
      final button = tester.getRect(find.widgetWithText(AppButton, '新しい予約'));
      expect(button.size, const Size(361, 56));
      expect(button.top - card.bottom, 12);
    });

    testWidgets('ルールの行は高さ 78 で、ボタンとの間は 12', (tester) async {
      await _pumpBooking(tester, _mockLayout);

      final button = tester.getRect(find.widgetWithText(AppButton, '新しい予約'));
      final row = find.ancestor(
        of: find.text('かけなおしのルール'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row), const Size(361, 78));
      expect(tester.getTopLeft(row).dy - button.bottom, 12);
      expect(tester.getSize(find.text('かけなおしのルール')).height, 24);
    });

    testWidgets('短い時刻は 1 行で、11/7 10:00 は 2 行、伝えたいことは 1 行', (tester) async {
      await _pumpBooking(tester, _mockLayout);

      for (final when in ['今日 12:00', '今日 19:00']) {
        expect(tester.getSize(find.text(when)).height, 16, reason: when);
      }
      expect(tester.getSize(find.text('11/7 10:00')).height, 32);
      for (final message in ['話し相手', '薬と戸締まりの確認', '週末に帰ると伝える']) {
        expect(tester.getSize(find.text(message)).height, 20, reason: message);
      }
    });
  });

  group('06 の文字倍率 1.3', () {
    testWidgets('短い時刻は 1 行のまま、11/7 10:00 は 2 行のまま', (tester) async {
      await _pumpBooking(tester, _narrowLargeLayout);

      for (final when in ['今日 12:00', '今日 19:00']) {
        expect(
          tester.getSize(find.text(when)).height,
          _isOneLineOf(16, _narrowLargeLayout),
          reason: when,
        );
      }
      final height = tester.getSize(find.text('11/7 10:00')).height;
      expect(height, greaterThan(16 * _narrowLargeLayout.textScale * 1.5));
      expect(height, _isOneLineOf(32, _narrowLargeLayout));
    });
  });

  group('07 の大きさがモックと同じ', () {
    // モックの 07 を headless Chrome で測った。文は 2 行で、カードは高さ 198。
    // 知らせる人のカードはない。
    testWidgets('カードの高さは文をふくめて 198', (tester) async {
      await _pumpRule(tester, _mockLayout);

      expect(find.byType(AppCard), findsOneWidget);
      expect(tester.getSize(find.byType(AppCard)), const Size(361, 198));
    });

    testWidgets('見出しからカードまでの位置が同じ', (tester) async {
      await _pumpRule(tester, _mockLayout);

      // モックは状態バーの 54 を引いた位置
      expect(tester.getTopLeft(find.text('かけなおす間隔')).dy, 114 - 54);
      expect(tester.getTopLeft(find.text('かける回数')).dy, 198 - 54);
      expect(tester.getTopLeft(find.byType(AppCard)).dy, 282 - 54);

      // チップの面は押せる領域の上下 4 の内側にある
      final chip = tester.getTopLeft(find.widgetWithText(AppChip, '15分'));
      expect(chip.dy + 4, 142 - 54);
    });

    testWidgets('丸の間の線はモックと同じ位置と幅', (tester) async {
      await _pumpRule(tester, _mockLayout);

      final line = find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.color != null && widget.child == null,
      );
      expect(line, findsNWidgets(3));
      expect(
        tester.getSize(line.first).width,
        moreOrLessEquals(18.33, epsilon: .01),
      );
      expect(tester.getSize(line.first).height, 19);
    });

    testWidgets('通知の文字は 1 行に入る', (tester) async {
      await _pumpRule(tester, _mockLayout);

      expect(
        tester.getTopLeft(find.text('家族に')).dy,
        tester.getTopLeft(find.text('通知')).dy,
      );
    });
  });

  // 流れの文字の幅は、幅 360 と文字倍率 1.3 が一番きつい
  group('07 の流れは幅 360 と文字倍率 1.3 で崩れない', () {
    for (final attempts in RetryRule.attemptChoices) {
      for (final interval in RetryRule.intervalChoices) {
        final name = '${RetryRule.intervalLabel(interval)}おきに$attempts回';
        testWidgets('$name の時刻と回は 1 行に入る', (tester) async {
          final rule = RetryRule(interval: interval, attempts: attempts);
          await _pumpRule(tester, _narrowLargeLayout, rule: rule);

          final times = rule.attemptTimes(DateTime(2026, 11, 5, 9));
          final shown = attempts > 3 ? [times.first, times.last] : times;
          for (final time in shown) {
            final label =
                '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
            for (final element in find.text(label).evaluate()) {
              expect(
                (element.renderObject! as RenderBox).size.height,
                _isOneLineOf(16, _narrowLargeLayout),
                reason: label,
              );
            }
          }
          final attemptLabels = attempts > 3
              ? ['1回目', '$attempts回目']
              : [for (var i = 1; i <= attempts; i++) '$i回目'];
          for (final label in attemptLabels) {
            expect(
              tester.getSize(find.text(label)).height,
              _isOneLineOf(16, _narrowLargeLayout),
              reason: label,
            );
          }
        });
      }
    }

    testWidgets('120分おきに10回の時刻と回は 1 行に入る', (tester) async {
      const rule = RetryRule(interval: Duration(minutes: 120), attempts: 10);
      await _pumpRule(tester, _narrowLargeLayout, rule: rule);

      for (final label in ['9:00', '3:00', '1回目', '10回目', '…']) {
        final elements = find.text(label).evaluate();
        expect(elements, isNotEmpty, reason: label);
        for (final element in elements) {
          expect(
            (element.renderObject! as RenderBox).size.height,
            _isOneLineOf(label == '…' ? 20 : 16, _narrowLargeLayout),
            reason: label,
          );
        }
      }
    });

    testWidgets('通知の文字は「家族に」と「通知」の間で折り返す', (tester) async {
      await _pumpRule(tester, _narrowLargeLayout);

      final first = tester.getRect(find.text('家族に'));
      final second = tester.getRect(find.text('通知'));
      expect(second.top, greaterThanOrEqualTo(first.bottom));
      expect(first.height, _isOneLineOf(16, _narrowLargeLayout));
      expect(second.height, _isOneLineOf(16, _narrowLargeLayout));
    });
  });

  group('07b の大きさがモックと同じ', () {
    testWidgets('知らせ、AIに伝えてもらう、今日の様子の高さ', (tester) async {
      final sample = sampleHomeDataFor(HomeStatus.missedCall);
      await pumpInLayout(
        tester,
        _mockLayout,
        MissedCallView(missedCall: sample.missedCall, onOpenAsk: () {}),
      );

      final cards = find.byType(AppCard);
      final ask = find.byType(AskCard);
      expect(tester.getSize(cards.at(0)), const Size(361, 152));
      expect(tester.getSize(ask), const Size(361, 60));
      expect(tester.getSize(cards.at(1)), const Size(361, 96));
      expect(
        tester.getTopLeft(ask).dy - tester.getBottomLeft(cards.at(0)).dy,
        12,
      );
      expect(
        tester.getTopLeft(cards.at(1)).dy - tester.getBottomLeft(ask).dy,
        12,
      );
    });
  });
}
