import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/calls/calendar_sheet.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/day_mark_icon.dart';

import '../../support/layout_matrix.dart';
import 'calls_harness.dart';

const _mockLayout = LayoutCase(393, 1.0);

Finder get _sheet => find.byType(CalendarSheet);

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

AppButton _viewButton(WidgetTester tester) =>
    tester.widget<AppButton>(_inSheet(find.byType(AppButton)));

// 日のマス。文字ではなく読み上げの文字で探す
Finder _day(String label) => find.bySemanticsLabel(label);

BoxDecoration _circleOf(WidgetTester tester, int day) =>
    tester
            .widget<Container>(
              find
                  .ancestor(
                    of: _inSheet(find.text('$day')),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

Text _dayText(WidgetTester tester, int day) =>
    tester.widget<Text>(_inSheet(find.text('$day')));

void main() {
  group('崩れない', () {
    testEachLayout('開いたとき', (tester, layout) async {
      await pumpCallsScreen(tester, layout);

      await openCalendar(tester);

      expect(find.text('電話に出た'), findsOneWidget);
    });

    testEachLayout('週が 6 行になる月', (tester, layout) async {
      await pumpCallsScreen(tester, layout);
      await openCalendar(tester);

      // 2026年8月は土曜に始まり、6 行になる
      for (var i = 0; i < 3; i++) {
        await tapSemantics(tester, '前の月');
      }

      expect(_inSheet(find.text('2026年8月')), findsOneWidget);
      expect(_day('8月31日'), findsOneWidget);
    });
  });

  group('開く', () {
    testWidgets('ミニカレンダーを押すと開く', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      expect(_sheet, findsNothing);

      await openCalendar(tester);

      expect(_sheet, findsOneWidget);
    });

    testWidgets('タブバーも暗幕の下に入り、押してもタブは変わらない', (tester) async {
      await pumpCallsTab(tester);
      await openCalendar(tester);

      final barrier = tester.widget<ModalBarrier>(
        find.byType(ModalBarrier).last,
      );
      expect(barrier.color, AppColors.nightBase.withAlpha(0x7A));

      await tester.tap(
        find.descendant(of: find.byType(AppTabBar), matching: find.text('ホーム')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex, 1);
      expect(_sheet, findsNothing);
    });

    testWidgets('開いたときの選択は、ミニカレンダーで選んでいる日', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await scrollCallsTo(tester, 400);
      expect(miniSelection(tester), '11月3日');

      await openCalendar(tester);

      expect(_viewButton(tester).label, '11月3日の記録を見る');
      expect(_inSheet(find.text('2026年11月')), findsOneWidget);
    });

    testWidgets('選んだ日が先月なら、先月を開く', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await scrollCallsTo(tester, 800);
      expect(miniSelection(tester), '10月31日');

      await openCalendar(tester);

      expect(_inSheet(find.text('2026年10月')), findsOneWidget);
    });
  });

  group('月', () {
    testWidgets('前の月、次の月で移動する', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      await tapSemantics(tester, '前の月');
      expect(_inSheet(find.text('2026年10月')), findsOneWidget);

      await tapSemantics(tester, '次の月');
      await tapSemantics(tester, '次の月');
      expect(_inSheet(find.text('2026年12月')), findsOneWidget);
    });

    testWidgets('年をまたいで移動する', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      await tapSemantics(tester, '次の月');
      await tapSemantics(tester, '次の月');

      expect(_inSheet(find.text('2027年1月')), findsOneWidget);
    });

    testWidgets('1日は曜日の列に合う', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      double columnOf(String text) =>
          tester.getCenter(_inSheet(find.text(text)).first).dx;

      // 2026年11月は日曜に始まる
      expect(columnOf('1'), moreOrLessEquals(columnOf('日')));

      // 2026年10月は木曜に始まる
      await tapSemantics(tester, '前の月');
      expect(columnOf('1'), moreOrLessEquals(columnOf('木')));
    });

    testWidgets('月の日数を出す', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      expect(_inSheet(find.text('30')), findsOneWidget);
      expect(_inSheet(find.text('31')), findsNothing);

      await tapSemantics(tester, '前の月');
      expect(_inSheet(find.text('31')), findsOneWidget);
    });

    testWidgets('月を移っても選んだ日は変わらない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '11月3日、電話に出た');

      await tapSemantics(tester, '前の月');

      expect(_viewButton(tester).label, '11月3日の記録を見る');
    });
  });

  group('日の見た目', () {
    testWidgets('今日は丸で囲み、選んだ日は塗る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '11月3日、電話に出た');

      final today = _circleOf(tester, 5);
      expect(today.color, isNull);
      expect(today.border, Border.all(color: AppColors.inkPrimary, width: 1.5));

      final selected = _circleOf(tester, 3);
      expect(selected.color, AppColors.inkPrimary);
      expect(selected.border, isNull);
      expect(_dayText(tester, 3).style?.color, AppColors.paperRaised);

      final other = _circleOf(tester, 4);
      expect(other.color, isNull);
      expect(other.border, isNull);
    });

    testWidgets('今日より先の日は薄く細い', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      final future = _dayText(tester, 6).style!;
      expect(future.color, AppColors.lineStrong);
      expect(future.fontWeight, FontWeight.w400);
      expect(_dayText(tester, 5).style?.fontWeight, FontWeight.w500);
    });

    testWidgets('印はモックと同じで、凡例がある', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      DayMark? markOf(int day) => tester
          .widget<DayMarkIcon>(
            find.descendant(
              of: find
                  .ancestor(
                    of: _inSheet(find.text('$day')),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(DayMarkIcon),
            ),
          )
          .mark;

      expect(markOf(1), DayMark.answered);
      expect(markOf(2), DayMark.missed);
      expect(markOf(3), DayMark.answered);
      expect(markOf(4), DayMark.answered);
      expect(markOf(5), DayMark.answered);
      expect(markOf(6), isNull);
      expect(_inSheet(find.text('電話に出た')), findsOneWidget);
      expect(_inSheet(find.text('不在')), findsOneWidget);
    });

    testWidgets('日のマスは 44pt 以上ある', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(360, 1.0));
      await openCalendar(tester);

      final cell = tester.getSize(_day('11月3日、電話に出た'));

      expect(cell.width, greaterThanOrEqualTo(44));
      expect(cell.height, greaterThanOrEqualTo(44));
    });
  });

  group('日を選ぶ', () {
    testWidgets('押した日がボタンの文字になる', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      expect(_viewButton(tester).label, '11月5日の記録を見る');

      await tapSemantics(tester, '11月3日、電話に出た');

      expect(_viewButton(tester).label, '11月3日の記録を見る');
      expect(_viewButton(tester).onTap, isNotNull);
    });

    testWidgets('今日より先の日は選べない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      await tester.tap(_inSheet(find.text('6')));
      await tester.pumpAndSettle();
      expect(_viewButton(tester).label, '11月5日の記録を見る');

      await tapSemantics(tester, '次の月');
      await tester.tap(_inSheet(find.text('1')));
      await tester.pumpAndSettle();
      expect(_viewButton(tester).label, '11月5日の記録を見る');
    });

    testWidgets('記録のない日はボタンを押せない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '前の月');

      await tapSemantics(tester, '10月20日');

      expect(_viewButton(tester).label, '10月20日の記録を見る');
      expect(_viewButton(tester).onTap, isNull);
    });

    testWidgets('10月30日は印があるが、記録がないのでボタンを押せない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '前の月');

      await tapSemantics(tester, '10月30日、電話に出た');

      expect(_viewButton(tester).label, '10月30日の記録を見る');
      expect(_viewButton(tester).onTap, isNull);
    });

    testWidgets('不在の日にも記録があるので、ボタンを押せる', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      await tapSemantics(tester, '11月2日、不在');

      expect(_viewButton(tester).onTap, isNotNull);
    });
  });

  group('記録を見る', () {
    Future<void> viewDay(WidgetTester tester, String dayLabel) async {
      await openCalendar(tester);
      await tapSemantics(tester, dayLabel);
      await tester.tap(_inSheet(find.byType(AppButton)));
      await tester.pumpAndSettle();
    }

    double pinnedBottom(WidgetTester tester) =>
        tester.getBottomLeft(find.byType(AppChip).first).dy + 4;

    testWidgets('シートを閉じ、その日の見出しを固定部の下端に動かす', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);

      await viewDay(tester, '11月3日、電話に出た');

      expect(_sheet, findsNothing);
      expect(
        tester.getTopLeft(find.text('11月3日(火)')).dy - 8,
        moreOrLessEquals(pinnedBottom(tester)),
      );
      expect(miniSelection(tester), '11月3日');
    });

    testWidgets('一番古い日も固定部の下端まで動かせる', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '前の月');
      await tapSemantics(tester, '10月31日、電話に出た');
      await tester.tap(_inSheet(find.byType(AppButton)));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('10月31日(土)')).dy - 8,
        moreOrLessEquals(pinnedBottom(tester)),
      );
      expect(miniSelection(tester), '10月31日');
    });

    testWidgets('今日を選ぶと先頭に戻る', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await scrollCallsTo(tester, 400);

      await viewDay(tester, '11月5日、今日、電話に出た');

      expect(callsPosition(tester).pixels, 0);
      expect(miniSelection(tester), '11月5日');
    });

    testWidgets('絞り込みで隠れている日を選ぶと、全部に戻して移動する', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await tapFilter(tester, '体調');
      expect(find.text('11月3日(火)'), findsNothing);

      await viewDay(tester, '11月3日、電話に出た');

      expect(tester.widget<AppChip>(filterChip('全部')).selected, isTrue);
      expect(
        tester.getTopLeft(find.text('11月3日(火)')).dy - 8,
        moreOrLessEquals(pinnedBottom(tester)),
      );
      expect(miniSelection(tester), '11月3日');
    });

    testWidgets('絞り込みに残っている日なら、条件はそのまま', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await tapFilter(tester, '話し相手');

      await viewDay(tester, '11月1日、電話に出た');

      expect(tester.widget<AppChip>(filterChip('話し相手')).selected, isTrue);
      expect(miniSelection(tester), '11月1日');
    });

    testWidgets('閉じるだけなら動かない', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await scrollCallsTo(tester, 200);
      await openCalendar(tester);
      await tapSemantics(tester, '11月1日、電話に出た');

      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing);
      expect(callsPosition(tester).pixels, 200);
    });
  });

  group('読み上げ', () {
    testWidgets('月の移動はモックの aria-label で読む', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      expect(find.bySemanticsLabel('前の月'), findsOneWidget);
      expect(find.bySemanticsLabel('次の月'), findsOneWidget);
    });

    testWidgets('日は日付、今日、印を読み、選んでいる日を伝える', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      expect(
        tester.getSemantics(_day('11月5日、今日、電話に出た')),
        isSemantics(
          label: '11月5日、今日、電話に出た',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('11月2日、不在'), findsOneWidget);
    });

    testWidgets('今日より先の日は押せないと伝える', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);

      expect(
        tester.getSemantics(_day('11月6日')),
        isSemantics(
          label: '11月6日',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
    });

    testWidgets('記録のない日のボタンは押せないと伝える', (tester) async {
      await pumpCallsScreen(tester, _mockLayout);
      await openCalendar(tester);
      await tapSemantics(tester, '前の月');
      await tapSemantics(tester, '10月20日');

      final node = tester.getSemantics(find.text('10月20日の記録を見る'));

      expect(node.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
    });
  });
}
