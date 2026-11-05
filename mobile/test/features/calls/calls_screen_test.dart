import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
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

    testEachLayout('どの条件で絞り込んでも', (tester, layout) async {
      await pumpCallsScreen(tester, layout);

      for (final filter in CallFilter.values) {
        await tapFilter(tester, filter.label);
      }

      expect(find.text('通話記録'), findsOneWidget);
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
    testWidgets('見出しだけ流れ、ミニカレンダーとチップは上に残る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final titleTop = tester.getTopLeft(find.text('通話記録')).dy;

      await scrollCallsTo(tester, 20);
      expect(tester.getTopLeft(find.text('通話記録')).dy, titleTop - 20);

      await scrollCallsTo(tester, 200);
      expect(find.text('通話記録'), findsNothing);
      expect(tester.getTopLeft(find.byType(MiniCalendar)).dy, viewportTop + 8);
      expect(find.byType(AppChip), findsNWidgets(CallFilter.values.length));
      expect(
        tester.getTopLeft(find.byType(AppChip).first).dy,
        viewportTop + 8 + 106 + 4,
      );
    });

    testWidgets('一覧がもぐるときだけ影が出る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      expect(_pinnedShadow(tester), isNull);

      final titleHeight = _titleHeight(tester);
      await scrollCallsTo(tester, titleHeight);
      expect(_pinnedShadow(tester), isNull);

      await scrollCallsTo(tester, titleHeight + 1);
      final shadow = _pinnedShadow(tester)!.single;
      expect(shadow.color, const Color(0x243A2A19));
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

    testWidgets('幅が足りないチップは横に動かして押せる', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final chip = filterChip('不在');
      expect(tester.getTopRight(chip).dx, greaterThan(393));

      await tapFilter(tester, '不在');

      expect(tester.getTopRight(chip).dx, lessThanOrEqualTo(393));
      expect(tester.widget<AppChip>(chip).selected, isTrue);
    });
  });

  group('条件のチップ', () {
    testWidgets('モックの順に並び、最初は全部を選んでいる', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      final chips = tester.widgetList<AppChip>(find.byType(AppChip)).toList();
      expect(chips.map((chip) => chip.label), [
        '全部',
        '体調',
        '話し相手',
        '操作案内',
        '不在',
      ]);
      expect(chips.map((chip) => chip.selected), [
        true,
        false,
        false,
        false,
        false,
      ]);
    });

    testWidgets('条件に合う行だけを出し、全部で元に戻る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await tapFilter(tester, '体調');
      _expectOnlyRows(['朝食と薬は済み。膝を気にしている', '夕飯は大根の煮物。夜の薬も飲んだ']);
      expect(find.text('11月3日(火)'), findsNothing);

      await tapFilter(tester, '話し相手');
      _expectOnlyRows(['お孫さんの運動会の話がはずんだ', 'お米が残り少ないと相談があった', '庭の菊が咲き始めた話をした']);

      await tapFilter(tester, '操作案内');
      _expectOnlyRows(['テレビの映し方を案内して解決']);

      await tapFilter(tester, '不在');
      _expectOnlyRows(['電話に出ませんでした(3回かけました)']);

      await tapFilter(tester, '全部');
      _expectOnlyRows(_allRows);
    });

    testWidgets('見出しの合計は、絞り込んでもその日の全部の電話を数える', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await tapFilter(tester, '操作案内');

      expect(find.text('2回 ・ 12分'), findsOneWidget);
    });

    testWidgets('スクロールした状態で絞り込むと、結果の先頭が固定部の下に来る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      final titleHeight = _titleHeight(tester);
      await scrollCallsTo(tester, 400);

      await tapFilter(tester, '話し相手');

      expect(callsPosition(tester).pixels, titleHeight);
      expect(find.text('11月3日(火)').hitTestable(), findsOneWidget);
    });

    testWidgets('先頭にいるときに絞り込んでも、見出しは流れない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await tapFilter(tester, '体調');

      expect(callsPosition(tester).pixels, 0);
    });
  });

  group('ミニカレンダーの選択', () {
    testWidgets('今日までの 7 日で、印はモックと同じ', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      final days = [
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
      expect(find.text('2026年11月'), findsOneWidget);
    });

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

    testWidgets('絞り込むと、残った日の先頭を選ぶ', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await tapFilter(tester, '話し相手');
      expect(miniSelection(tester), '11月3日');

      await tapFilter(tester, '不在');
      expect(miniSelection(tester), '11月2日');

      await tapFilter(tester, '全部');
      expect(miniSelection(tester), '11月5日');
    });
  });

  group('行を押す', () {
    testWidgets('電話の行のカードを押すと 05 を開く', (tester) async {
      await pumpCallsTab(tester);

      await tester.tap(find.text('テレビの映し方を案内して解決'));
      await tester.pumpAndSettle();

      expect(find.byType(CallDetailScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);
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
        await tapSemantics(tester, 'もどる');
      }
    });

    testWidgets('不在の行を押しても開かない', (tester) async {
      await pumpCallsTab(tester);
      await tapFilter(tester, '不在');

      await tester.tap(find.text('電話に出ませんでした(3回かけました)'));
      await tester.pumpAndSettle();
      expect(find.byType(CallDetailScreen), findsNothing);

      await tester.tap(find.text('9:00'));
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

    testWidgets('選んでいる条件を読み上げに反映する', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await tapFilter(tester, '体調');

      expect(
        tester.getSemantics(find.text('体調').first),
        isSemantics(
          label: '体調',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    });
  });
}
