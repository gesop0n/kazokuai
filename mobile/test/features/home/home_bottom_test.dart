import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

import '../../support/layout_matrix.dart';

// 11月1日から順に、分数だけを指定して週を作る
WeekCallRecords _weekOf(List<int?> minutes) => WeekCallRecords([
  for (final (index, talked) in minutes.indexed)
    DayCallRecord(date: DateTime(2026, 11, index + 1), talkedMinutes: talked),
]);

Widget _weekCard(WeekCallRecords week, {VoidCallback? onOpenCallLog}) =>
    WeekCard(week: week, onOpenCallLog: onOpenCallLog ?? () {});

Call _callWith(List<Condition> conditions) => Call(
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6),
  summary: CallSummary(
    headline: '',
    quote: Quote(text: '', spokenAt: DateTime(2026, 11, 5, 9, 3)),
    conditions: conditions,
  ),
);

Future<void> _pumpWeek(WidgetTester tester, WeekCallRecords week) =>
    pumpInLayout(tester, layoutCases.first, _weekCard(week));

Container _barOf(WidgetTester tester, DateTime date) =>
    tester.widget<Container>(find.byKey(WeekCard.barKey(date)));

double _barHeight(WidgetTester tester, DateTime date) =>
    tester.getSize(find.byKey(WeekCard.barKey(date))).height;

Color? _barColor(WidgetTester tester, DateTime date) =>
    (_barOf(tester, date).decoration! as BoxDecoration).color;

void main() {
  group('崩れない', () {
    testEachLayout('今日の様子', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        TodayCard(call: sampleHomeData.latestCall),
      );

      expect(find.text('今日の様子'), findsOneWidget);
    });

    testEachLayout('7日間の電話', (tester, layout) async {
      await pumpInLayout(tester, layout, _weekCard(sampleHomeData.week));

      expect(find.text('7日間の電話'), findsOneWidget);
      expect(find.text('棒の数字は話した分数'), findsNothing);
    });

    testEachLayout('分数の桁が多いとき', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        _weekCard(_weekOf([100, 120, 240, null, 180, 121, 60])),
      );

      expect(find.text('240'), findsOneWidget);
    });

    testEachLayout('ホーム画面', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        Scaffold(body: HomeScreen(data: sampleHomeData)),
      );

      expect(find.byType(TodayCard), findsOneWidget);
      expect(find.byType(WeekCard), findsOneWidget);
    });
  });

  group('今日の様子', () {
    testWidgets('見出しの右に通話を始めた時刻を出す', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        TodayCard(call: sampleHomeData.latestCall),
      );

      expect(find.text('9:02の会話より'), findsOneWidget);
    });

    testWidgets('項目名、内容、本人の言葉を出し、注意書きは出さない', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        TodayCard(call: sampleHomeData.latestCall),
      );

      for (final text in [
        '食事',
        '朝ごはんを食べた',
        '「朝ごはんも食べたしね」',
        '睡眠',
        'よく眠れた',
        '「よく眠れたよ」',
        '体調',
        '膝が痛い。階段がつらい',
        '「昨日の夕方から膝が痛くてね」',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('ご本人の話をAIがまとめたものです。医療上の判断ではありません。'), findsNothing);
    });

    testWidgets('needsAttention の行だけに「気になる話」が出る', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        TodayCard(
          call: _callWith(const [
            Condition(
              kind: ConditionKind.meal,
              value: 'a',
              quote: 'b',
              needsAttention: true,
            ),
            Condition(kind: ConditionKind.sleep, value: 'c', quote: 'd'),
            Condition(kind: ConditionKind.health, value: 'e', quote: 'f'),
          ]),
        ),
      );

      expect(find.text('気になる話'), findsOneWidget);
      expect(
        tester.getCenter(find.byType(AppPill)).dy,
        tester.getCenter(find.text('食事')).dy,
      );
    });

    testWidgets('needsAttention の行がなければ「気になる話」は出ない', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        TodayCard(
          call: _callWith(const [
            Condition(kind: ConditionKind.sleep, value: 'c', quote: 'd'),
          ]),
        ),
      );

      expect(find.text('気になる話'), findsNothing);
    });

    testWidgets('1行目も含めて、どの行の上にも線を引く', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        TodayCard(call: sampleHomeData.latestCall),
      );

      // カードの枠線は四辺にあるので、上だけの線と区別できる
      final lines = find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        final border = decoration is BoxDecoration ? decoration.border : null;
        return border is Border &&
            border.top.color == AppColors.line &&
            border.bottom == BorderSide.none;
      });
      expect(
        lines,
        findsNWidgets(sampleHomeData.latestCall.summary.conditions.length),
      );

      final firstLine = tester.getTopLeft(lines.first).dy;
      expect(
        firstLine,
        greaterThan(tester.getBottomLeft(find.text('今日の様子')).dy),
      );
      expect(firstLine, lessThan(tester.getTopLeft(find.text('食事')).dy));

      final secondLine = tester.getTopLeft(lines.at(1)).dy;
      expect(
        secondLine,
        greaterThan(tester.getBottomLeft(find.text('「朝ごはんも食べたしね」')).dy),
      );
      expect(secondLine, lessThan(tester.getTopLeft(find.text('睡眠')).dy));
    });
  });

  group('見出しの行', () {
    testWidgets('週のカードに説明のラベルはない', (tester) async {
      await pumpInLayout(
        tester,
        const LayoutCase(360, 1.3),
        _weekCard(sampleHomeData.week),
      );

      expect(find.text('7日間の電話'), findsOneWidget);
      expect(find.text('棒の数字は話した分数'), findsNothing);
      expect(find.textContaining('この7日間'), findsNothing);
    });
  });

  group('数字', () {
    testWidgets('サンプルデータから「6 / 7日」と「103 分」を計算する', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(find.text('6 / 7日', findRichText: true), findsOneWidget);
      expect(find.text('103 分', findRichText: true), findsOneWidget);
    });

    testWidgets('データを変えると表示も変わる', (tester) async {
      await _pumpWeek(tester, _weekOf([100, null, null, 150, null, null, 200]));

      expect(find.text('3 / 7日', findRichText: true), findsOneWidget);
      expect(find.text('450 分', findRichText: true), findsOneWidget);
      expect(find.text('6 / 7日', findRichText: true), findsNothing);
      expect(find.text('103 分', findRichText: true), findsNothing);
    });
  });

  group('グラフ', () {
    testWidgets('不在の日は棒を出さず「不在」を出す', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(find.text('不在'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('不在')).style?.color,
        AppColors.inkPrimary,
      );
      expect(
        tester
            .widget<AppIcon>(
              find.byWidgetPredicate(
                (widget) => widget is AppIcon && widget.icon == AppIcons.x,
              ),
            )
            .color,
        AppColors.stateAlert,
      );
      expect(find.byKey(WeekCard.barKey(DateTime(2026, 11, 2))), findsNothing);
      expect(
        find.byKey(WeekCard.barKey(DateTime(2026, 11, 1))),
        findsOneWidget,
      );
    });

    testWidgets('全ての日に出ていれば「不在」は出ない', (tester) async {
      await _pumpWeek(tester, _weekOf([100, 110, 120, 130, 140, 150, 160]));

      expect(find.text('不在'), findsNothing);
    });

    testWidgets('棒の高さは週の最大に対する分数に比例する', (tester) async {
      await _pumpWeek(tester, _weekOf([100, 200, 400, null, 50, 300, 25]));

      expect(_barHeight(tester, DateTime(2026, 11, 3)), 92);
      expect(_barHeight(tester, DateTime(2026, 11, 2)), 46);
      expect(_barHeight(tester, DateTime(2026, 11, 1)), 23);
      expect(_barHeight(tester, DateTime(2026, 11, 6)), 69);
    });

    testWidgets('棒の高さはモックと同じ計算になる', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(_barHeight(tester, DateTime(2026, 11, 1)), 92);
      expect(
        _barHeight(tester, DateTime(2026, 10, 30)),
        moreOrLessEquals(14 / 31 * 92),
      );
    });

    testWidgets('短い棒は最小の 6 になる', (tester) async {
      await _pumpWeek(tester, _weekOf([100, 1, 0, 2, 3, 4, 5]));

      expect(_barHeight(tester, DateTime(2026, 11, 1)), 92);
      expect(_barHeight(tester, DateTime(2026, 11, 2)), 6);
      expect(_barHeight(tester, DateTime(2026, 11, 3)), 6);
    });

    testWidgets('全ての日が 0 分でも棒は最小の 6 になる', (tester) async {
      await _pumpWeek(tester, _weekOf([0, 0, 0, 0, 0, 0, 0]));

      expect(_barHeight(tester, DateTime(2026, 11, 1)), 6);
    });

    testWidgets('棒の幅は 16 で、下端が揃う', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      final short = find.byKey(WeekCard.barKey(DateTime(2026, 11, 5)));
      final tall = find.byKey(WeekCard.barKey(DateTime(2026, 11, 1)));
      expect(tester.getSize(short).width, 16);
      expect(tester.getBottomLeft(short).dy, tester.getBottomLeft(tall).dy);
    });

    testWidgets('最後の日だけ棒の色を変える', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(_barColor(tester, DateTime(2026, 11, 5)), AppColors.inkPrimary);
      expect(_barColor(tester, DateTime(2026, 11, 4)), AppColors.lineStrong);
    });

    testWidgets('読み上げの文がモックと一致する', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(
        find.bySemanticsLabel(
          '7日間の通話時間。10月30日14分、31日22分、11月1日31分、2日は不在、3日18分、4日12分、5日6分',
        ),
        findsOneWidget,
      );
    });

    testWidgets('月が変わらなければ月は最初の日にだけ書く', (tester) async {
      await _pumpWeek(tester, _weekOf([100, null, 110, 120, 130, 140, 150]));

      expect(
        find.bySemanticsLabel(
          '7日間の通話時間。11月1日100分、2日は不在、3日110分、4日120分、5日130分、6日140分、7日150分',
        ),
        findsOneWidget,
      );
    });

    testWidgets('グラフの中の文字は個別に読み上げない', (tester) async {
      await _pumpWeek(tester, sampleHomeData.week);

      expect(find.bySemanticsLabel('不在'), findsNothing);
      expect(find.bySemanticsLabel('31'), findsNothing);
    });

    testWidgets('文字倍率 1.3 でも棒の上の数字が切れない', (tester) async {
      await pumpInLayout(
        tester,
        const LayoutCase(360, 1.3),
        _weekCard(_weekOf([100, 200, 400, null, 50, 300, 25])),
      );

      final tallest = find.byKey(WeekCard.barKey(DateTime(2026, 11, 3)));
      final number = tester.getRect(find.text('400'));
      expect(number.bottom, lessThanOrEqualTo(tester.getTopLeft(tallest).dy));
      expect(
        number.top,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.text('6 / 7日', findRichText: true)).dy,
        ),
        reason: '数字が上の要素に重なると読めない',
      );
    });
  });

  testWidgets('「通話記録を見る」で onOpenCallLog が呼ばれる', (tester) async {
    var opened = 0;
    await pumpInLayout(
      tester,
      layoutCases.first,
      _weekCard(sampleHomeData.week, onOpenCallLog: () => opened++),
    );

    await tester.tap(find.text('通話記録を見る'));
    await tester.pump();

    expect(opened, 1);
  });
}
