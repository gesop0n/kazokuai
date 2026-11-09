import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';

import '../../support/layout_matrix.dart';

Call _callWith(List<Condition> conditions) => Call(
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6),
  summary: CallSummary(headline: '', conditions: conditions),
);

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

    testEachLayout('ホーム画面', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        Scaffold(body: HomeScreen(data: sampleHomeData)),
      );

      expect(find.text('今日の様子'), findsOneWidget);
      expect(find.text('7日間の電話'), findsNothing);
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
        '朝ごはんも食べたしね',
        '睡眠',
        'よく眠れた',
        'よく眠れたよ',
        '体調',
        '膝が痛い。階段がつらい',
        '昨日の夕方から膝が痛くてね',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.textContaining('「'), findsNothing);
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
        greaterThan(tester.getBottomLeft(find.text('朝ごはんも食べたしね')).dy),
      );
      expect(secondLine, lessThan(tester.getTopLeft(find.text('睡眠')).dy));
    });
  });
}
