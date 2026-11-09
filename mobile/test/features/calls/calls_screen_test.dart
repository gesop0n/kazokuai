import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/calls/calendar_sheet.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/calls/day_mark_icon.dart';
import 'package:kazokuai/features/calls/mini_calendar.dart';

import '../../support/layout_matrix.dart';
import 'calls_harness.dart';

const _mockLayout = LayoutCase(393, 1.0);

const _allRows = [
  '朝食と薬は済み。膝を気にしている',
  '夕飯は大根の煮物。夜の薬も飲んだ',
  'テレビの映し方を案内して解決',
  'お孫さんの運動会の話がはずんだ',
  '電話に出ませんでした(3回かけました)',
  'お米が残り少ないと相談があった',
  '庭の菊が咲き始めた話をした',
];

// 固定部の Container。MiniCalendar に一番近い
Container _pinnedHeader(WidgetTester tester) => tester.widget<Container>(
  find
      .ancestor(of: find.byType(MiniCalendar), matching: find.byType(Container))
      .first,
);

List<BoxShadow>? _pinnedShadow(WidgetTester tester) =>
    (_pinnedHeader(tester).decoration! as BoxDecoration).boxShadow;

double _titleHeight(WidgetTester tester) =>
    tester.getTopLeft(find.byType(MiniCalendar)).dy -
    8 -
    tester.getTopLeft(find.byType(CustomScrollView)).dy;

ScrollPosition _stripPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(MiniCalendar),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

double _dayWidth(WidgetTester tester) => tester
    .getSize(find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5))))
    .width;

Rect _stripRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(MiniCalendar),
    matching: find.byType(Scrollable),
  ),
);

Finder _pressOverlay(Color foreground) {
  final color = AppPressable.overlayOf(foreground);
  return find.byWidgetPredicate((widget) {
    final decoration = widget is DecoratedBox ? widget.decoration : null;
    return decoration is BoxDecoration && decoration.color == color;
  });
}

Future<void> _expectPressColor(
  WidgetTester tester,
  Finder target,
  Color foreground,
) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump();
  expect(_pressOverlay(foreground), findsOneWidget);
  await gesture.cancel();
  await tester.pump();
  expect(_pressOverlay(foreground), findsNothing);
}

void _expectOnlyRows(List<String> rows) {
  for (final row in _allRows) {
    expect(find.text(row), rows.contains(row) ? findsOneWidget : findsNothing);
  }
}

void main() {
  group('崩れない', () {
    testEachLayout('先頭', (tester, layout) async {
      await pumpCallsScreen(tester, layout);

      expect(find.text('通話記録'), findsOneWidget);
    });

    testEachLayout('一番下までスクロールしたとき', (tester, layout) async {
      await pumpCallsScreen(tester, layout);

      await scrollCallsTo(tester, callsPosition(tester).maxScrollExtent);

      expect(find.text('庭の菊が咲き始めた話をした'), findsOneWidget);
    });

    testEachLayout('絞り込みのチップはない', (tester, layout) async {
      await pumpCallsScreen(tester, layout);

      expect(find.byType(AppChip), findsNothing);
      expect(find.text('全部'), findsNothing);
      expect(find.text('過去7日間'), findsOneWidget);
    });

    testEachLayout('一言が長く、時刻の桁が多いとき', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        Scaffold(
          body: CallsScreen(
            log: CallLog(
              today: DateTime(2026, 11, 5),
              days: [
                CallLogDay(
                  date: DateTime(2026, 11, 5),
                  entries: [
                    AnsweredCallEntry(
                      startedAt: DateTime(2026, 11, 5, 23, 59),
                      text: '朝食と薬は済み。膝を気にしている。' * 4,
                      duration: const Duration(minutes: 120),
                      topic: CallTopic.companion,
                    ),
                    MissedCallEntry(
                      startedAt: DateTime(2026, 11, 5, 12, 30),
                      text: '電話に出ませんでした(3回かけました)' * 3,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('23:59'), findsOneWidget);
    });
  });

  group('一覧', () {
    testWidgets('モックのすべての行と見出しがある', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      _expectOnlyRows(_allRows);
      for (final text in [
        '今日 11月5日(木)',
        '1回 ・ 6分',
        '11月4日(水)',
        '2回 ・ 12分',
        '11月3日(火)',
        '1回 ・ 18分',
        '11月2日(月)',
        '11月1日(日)',
        '1回 ・ 31分',
        '10月31日(土)',
        '1回 ・ 22分',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    // サンプルでは末尾の余白がタブバーより大きいので、行が多い日で確かめる
    testWidgets('行が多くても、最後の行はタブバーに隠れない', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 91);
      addTearDown(tester.view.resetPadding);
      await pumpScreenInLayout(
        tester,
        _mockLayout,
        Scaffold(
          body: CallsScreen(
            log: CallLog(
              today: DateTime(2026, 11, 5),
              days: [
                CallLogDay(
                  date: DateTime(2026, 11, 5),
                  entries: [
                    for (var hour = 23; hour >= 8; hour--)
                      AnsweredCallEntry(
                        startedAt: DateTime(2026, 11, 5, hour),
                        text: '$hour時の電話',
                        duration: const Duration(minutes: 3),
                        topic: CallTopic.health,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await scrollCallsTo(tester, callsPosition(tester).maxScrollExtent);

      expect(
        tester.getBottomLeft(find.text('8時の電話')).dy,
        lessThanOrEqualTo(852 - 91),
      );
    });

    testWidgets('10月30日の行はない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      expect(find.textContaining('10月30日'), findsNothing);
    });

    testWidgets('時刻の列は文字の大きさに合わせて広がり、どの行でも揃う', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(393, 1.3));

      final phoneRow = tester.getTopLeft(find.text('9:02')).dx;
      final longRow = tester.getTopLeft(find.text('19:00')).dx;
      final firstCard = tester.getTopLeft(find.text('朝食と薬は済み。膝を気にしている')).dx;
      final secondCard = tester.getTopLeft(find.text('夕飯は大根の煮物。夜の薬も飲んだ')).dx;

      expect(phoneRow, longRow);
      expect(firstCard, secondCard);
      // 同梱のフォントの 19:00 は 12 × 1.3 × 0.6 × 5 = 46.8
      expect(firstCard - phoneRow, greaterThanOrEqualTo(52));
    });
  });

  group('固定の部分', () {
    testWidgets('見出しだけ流れ、ミニカレンダーは上に残る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final titleTop = tester.getTopLeft(find.text('通話記録')).dy;

      await scrollCallsTo(tester, 20);
      expect(tester.getTopLeft(find.text('通話記録')).dy, titleTop - 20);

      await scrollCallsTo(tester, 200);
      expect(find.text('通話記録'), findsNothing);
      expect(tester.getTopLeft(find.byType(MiniCalendar)).dy, viewportTop + 8);
      expect(find.text('過去7日間'), findsOneWidget);
      expect(find.byType(AppChip), findsNothing);
    });

    testWidgets('一覧がもぐるときだけ影が出る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      expect(_pinnedShadow(tester), isNull);

      final titleHeight = _titleHeight(tester);
      await scrollCallsTo(tester, titleHeight);
      expect(_pinnedShadow(tester), isNull);

      await scrollCallsTo(tester, titleHeight + 1);
      final shadow = _pinnedShadow(tester)!.single;
      expect(shadow.color, const Color(0x24000000));
      expect(shadow.offset, const Offset(0, 4));
      expect(shadow.blurRadius, 10);

      await scrollCallsTo(tester, 0);
      expect(_pinnedShadow(tester), isNull);
    });

    testWidgets('固定部の背景は紙の色', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      expect(
        (_pinnedHeader(tester).decoration! as BoxDecoration).color,
        AppColors.paperBase,
      );
    });
  });

  group('ミニカレンダー', () {
    testWidgets('過去7日間の帯に 14 日あり、印はモックと同じ', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      final days = [
        (DateTime(2026, 10, 23), '金', '23', DayMark.answered),
        (DateTime(2026, 10, 24), '土', '24', DayMark.answered),
        (DateTime(2026, 10, 25), '日', '25', DayMark.answered),
        (DateTime(2026, 10, 26), '月', '26', DayMark.answered),
        (DateTime(2026, 10, 27), '火', '27', DayMark.answered),
        (DateTime(2026, 10, 28), '水', '28', DayMark.answered),
        (DateTime(2026, 10, 29), '木', '29', DayMark.answered),
        (DateTime(2026, 10, 30), '金', '30', DayMark.answered),
        (DateTime(2026, 10, 31), '土', '31', DayMark.answered),
        (DateTime(2026, 11, 1), '日', '1', DayMark.answered),
        (DateTime(2026, 11, 2), '月', '2', DayMark.missed),
        (DateTime(2026, 11, 3), '火', '3', DayMark.answered),
        (DateTime(2026, 11, 4), '水', '4', DayMark.answered),
        (DateTime(2026, 11, 5), '木', '5', DayMark.answered),
      ];
      for (final (date, weekday, day, mark) in days) {
        final cell = find.byKey(MiniCalendar.dayKey(date));
        expect(
          find.descendant(of: cell, matching: find.text(weekday)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cell, matching: find.text(day)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<DayMarkIcon>(
                find.descendant(of: cell, matching: find.byType(DayMarkIcon)),
              )
              .mark,
          mark,
          reason: '$date',
        );
      }
      expect(find.text('過去7日間'), findsOneWidget);
      expect(find.text('2026年11月'), findsNothing);
    });

    testWidgets('開いたときは今日が右端で、10月23日は帯の外', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final dayWidth = _dayWidth(tester);
      final strip = _stripRect(tester);

      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 7, epsilon: 0.5),
      );
      expect(
        tester
            .getRect(find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5))))
            .right,
        moreOrLessEquals(strip.right, epsilon: 1),
      );
      expect(
        tester
            .getRect(find.byKey(MiniCalendar.dayKey(DateTime(2026, 10, 30))))
            .left,
        moreOrLessEquals(strip.left, epsilon: 1),
      );
      expect(
        tester
            .getRect(find.byKey(MiniCalendar.dayKey(DateTime(2026, 10, 23))))
            .right,
        lessThan(strip.left),
      );
    });

    testWidgets('指で動かすと 1 日ずつ止まり、シートは開かない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final dayWidth = _dayWidth(tester);
      final day = find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 3)));

      // 今日が右端なので、右へ動かして古い日を出す。
      // ドラッグの最初の 20 は認識に使われ、残りが帯の移動になる。
      await tester.drag(day, Offset(dayWidth * 0.8 + 20, 0));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarSheet), findsNothing);
      expect(_pressOverlay(AppColors.inkPrimary), findsNothing);
      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 6, epsilon: 1),
      );

      // 半分より手前なら、動かした日に戻る
      await tester.drag(day, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 6, epsilon: 1),
      );
    });

    testWidgets('速く払うと、半分より手前でも隣の日へ進む', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final dayWidth = _dayWidth(tester);
      final position = _stripPosition(tester);
      // 指を離した瞬間の速さは、テストのドラッグでは 0 になるので、物理演算に直接渡す
      position.jumpTo(dayWidth * 6.8);

      final flicked = position.physics.createBallisticSimulation(
        position,
        -800,
      )!;
      expect(flicked.x(5), moreOrLessEquals(dayWidth * 6, epsilon: 1));

      final eased = position.physics.createBallisticSimulation(position, -10)!;
      expect(eased.x(5), moreOrLessEquals(dayWidth * 7, epsilon: 1));
    });

    testWidgets('動かしたあとに押すと、カレンダーが開く', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final day = find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 3)));

      await tester.drag(day, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsNothing);

      await tester.tap(find.text('過去7日間'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsOneWidget);
    });

    testWidgets('見えていない日を選ぶと、その日が見えるところまで帯を動かす', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final dayWidth = _dayWidth(tester);
      final before = _stripPosition(tester).pixels;

      // 11月3日は最初から見えている 7 日の中なので、帯は動かない
      await scrollCallsTo(tester, 400);
      expect(miniSelection(tester), '11月3日');
      expect(_stripPosition(tester).pixels, before);

      // 左端に戻すと 10月23日から 29日までが見える。10月31日はその外
      _stripPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await scrollCallsTo(tester, 800);

      expect(miniSelection(tester), '10月31日');
      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 2, epsilon: 1),
      );
      final strip = _stripRect(tester);
      final revealed = tester.getRect(
        find.byKey(MiniCalendar.dayKey(DateTime(2026, 10, 31))),
      );
      expect(revealed.left, greaterThanOrEqualTo(strip.left - 1));
      expect(revealed.right, lessThanOrEqualTo(strip.right + 1));
    });

    testWidgets('押すと薄い色が重なり、指を離すと消える', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await _expectPressColor(tester, find.text('過去7日間'), AppColors.inkPrimary);
      await _expectPressColor(
        tester,
        find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 4))),
        AppColors.inkPrimary,
      );
      await _expectPressColor(
        tester,
        find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5))),
        AppColors.paperRaised,
      );
      expect(find.byType(CalendarSheet), findsNothing);
    });

    testWidgets('カードの余白と隙間を押すとシートが開く', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final card = tester.getRect(find.byType(MiniCalendar));

      await tester.tapAt(card.topLeft + const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsOneWidget);

      Navigator.of(tester.element(find.byType(CalendarSheet))).pop();
      await tester.pumpAndSettle();

      final today = tester.getRect(
        find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5))),
      );
      await tester.tapAt(Offset(card.left + 4, today.center.dy));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsOneWidget);

      Navigator.of(tester.element(find.byType(CalendarSheet))).pop();
      await tester.pumpAndSettle();

      // 枠 1、余白 8、見出し 24 のあとが、見出しと日付の 4pt の隙間
      await tester.tapAt(Offset(card.center.dx, card.top + 1 + 8 + 24 + 2));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsOneWidget);
    });

    testWidgets('同じ日をシートで選び直すと、隠れていても帯がその日まで戻る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final dayWidth = _dayWidth(tester);
      final today = DateTime(2026, 11, 5);

      await tester.tap(find.text('過去7日間'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11月5日の記録を見る'));
      await tester.pumpAndSettle();
      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 7, epsilon: 1),
      );

      _stripPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      final strip = _stripRect(tester);
      expect(
        tester.getRect(find.byKey(MiniCalendar.dayKey(today))).right,
        greaterThan(strip.right),
      );

      await tester.tap(find.text('過去7日間'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11月5日の記録を見る'));
      await tester.pumpAndSettle();

      final revealed = tester.getRect(find.byKey(MiniCalendar.dayKey(today)));
      expect(revealed.left, greaterThanOrEqualTo(strip.left - 1));
      expect(revealed.right, lessThanOrEqualTo(strip.right + 1));
      expect(
        _stripPosition(tester).pixels,
        moreOrLessEquals(dayWidth * 7, epsilon: 1),
      );
    });
  });

  group('ミニカレンダーの選択', () {
    testWidgets('最初は今日を選び、塗りは選んだ日だけ', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      Color? colorOf(DateTime date) =>
          (tester
                      .widget<Container>(find.byKey(MiniCalendar.dayKey(date)))
                      .decoration!
                  as BoxDecoration)
              .color;

      expect(miniSelection(tester), '11月5日');
      expect(colorOf(DateTime(2026, 11, 5)), AppColors.inkPrimary);
      expect(colorOf(DateTime(2026, 11, 4)), isNull);
    });

    testWidgets('スクロールで見ている日に合わせて動く', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final expected = {
        '11月5日': 0.0,
        '11月4日': 200.0,
        '11月3日': 400.0,
        '11月2日': 500.0,
        '11月1日': 600.0,
        '10月31日': 800.0,
      };

      for (final MapEntry(key: date, value: offset) in expected.entries) {
        await scrollCallsTo(tester, offset);
        expect(miniSelection(tester), date, reason: 'offset $offset');
      }

      await scrollCallsTo(tester, 0);
      expect(miniSelection(tester), '11月5日');
    });
  });

  group('行を押す', () {
    testWidgets('電話の行のカードを押すと 05 を通話記録のタブで開く', (tester) async {
      await pumpCallsTab(tester);

      await tester.tap(find.text('テレビの映し方を案内して解決'));
      await tester.pumpAndSettle();

      expect(find.byType(CallDetailScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 1);
    });

    testWidgets('電話の行の時刻を押しても 05 を開く', (tester) async {
      await pumpCallsTab(tester);

      await tester.tap(find.text('9:02'));
      await tester.pumpAndSettle();

      expect(find.byType(CallDetailScreen), findsOneWidget);
    });

    testWidgets('どの行から開いても同じ内容を出す', (tester) async {
      await pumpCallsTab(tester);

      for (final row in ['朝食と薬は済み。膝を気にしている', 'お孫さんの運動会の話がはずんだ']) {
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        expect(find.text('朝の電話'), findsOneWidget);
        expect(find.text('11/5 9:02 ・ 6分12秒'), findsOneWidget);
        await tapSemantics(tester, '通話記録にもどる');
        expect(find.byType(CallsScreen), findsOneWidget);
      }
    });

    testWidgets('不在の行を押しても開かない', (tester) async {
      await pumpCallsTab(tester);
      // 11月2日の行は、固定部の下でタブバーより上に来る
      await scrollCallsTo(tester, 320);
      final missed = find.text('電話に出ませんでした(3回かけました)');
      final row = find.ancestor(of: missed, matching: find.byType(Row)).first;

      await tester.tap(missed);
      await tester.pumpAndSettle();
      expect(find.byType(CallDetailScreen), findsNothing);

      await tester.tap(find.descendant(of: row, matching: find.text('9:00')));
      await tester.pumpAndSettle();
      expect(find.byType(CallDetailScreen), findsNothing);
      expect(find.byType(CallsScreen), findsOneWidget);
    });

    testWidgets('電話の行は押せる領域が 44pt 以上ある', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      final card = tester.getSize(find.bySemanticsLabel(RegExp('^9:02の電話')));
      expect(card.width, greaterThanOrEqualTo(44));
      expect(card.height, greaterThanOrEqualTo(44));
    });
  });

  group('読み上げ', () {
    testWidgets('ミニカレンダーはモックの aria-label で、選んだ日も読む', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      expect(
        tester.getSemantics(miniCalendarSemantics),
        isSemantics(
          label: 'カレンダーを開いて日付を選ぶ',
          value: '11月5日',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('電話の行はまとめて 1 つのボタンとして読む', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^9:02の電話'))),
        isSemantics(
          label: '9:02の電話。朝食と薬は済み。膝を気にしている。体調。6分',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('不在の行は読むだけで、押せない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^9:00の電話。電話に出ませんでした')),
      );

      expect(node.label, '9:00の電話。電話に出ませんでした(3回かけました)');
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('日の見出しと合計は続けて読む', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      expect(find.bySemanticsLabel('今日 11月5日(木)\n1回 ・ 6分'), findsOneWidget);
    });
  });
}
