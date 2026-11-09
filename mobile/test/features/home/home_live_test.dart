import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/today_card.dart';

import '../../support/fake_home_repository.dart';
import '../../support/layout_matrix.dart';

final _now = DateTime(2026, 11, 5, 10, 24);

void main() {
  testWidgets('直近の電話に、まとめと始まった時刻と長さを出し、本人の言葉は出さない', (tester) async {
    await _pump(
      tester,
      _view(
        latest: _call(
          at: DateTime(2026, 11, 5, 9, 2),
          minutes: 6,
          headline: '朝ごはんを食べたそうです。',
        ),
        today: _call(
          at: DateTime(2026, 11, 5, 9, 2),
          minutes: 6,
          headline: '朝ごはんを食べたそうです。',
          conditions: const [
            Condition(
              kind: ConditionKind.meal,
              value: '朝ごはんを食べた',
              quote: '朝ごはんも食べたしね',
            ),
            Condition(kind: ConditionKind.sleep, value: '話していない', quote: ''),
            Condition(
              kind: ConditionKind.health,
              value: '膝が痛い',
              quote: '膝が痛くてね',
              needsAttention: true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('朝ごはんを食べたそうです。'), findsWidgets);
    expect(find.text('今日 9:02 ・ 6分'), findsOneWidget);
    expect(find.text('9:03'), findsNothing);
    expect(find.text('食事'), findsOneWidget);
    expect(find.text('朝ごはんを食べた'), findsOneWidget);
    expect(find.text('朝ごはんも食べたしね'), findsOneWidget);
    expect(find.text('睡眠'), findsOneWidget);
    expect(find.text('話していない'), findsOneWidget);
    expect(find.text('体調'), findsOneWidget);
    expect(find.text('膝が痛い'), findsOneWidget);
    expect(find.text('膝が痛くてね'), findsOneWidget);
    expect(find.text('気になる話'), findsOneWidget);
    expect(find.text('9:02の会話より'), findsOneWidget);
    expect(find.text('7日間の電話'), findsNothing);

    final pill = tester.widget<AppPill>(find.byType(AppPill));
    expect(pill.label, '気になる話');
    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(AppPill),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.color, AppColors.stateCareSoft);
    expect(find.byType(AskCard), findsOneWidget);
  });

  testWidgets('今日の様子は今日の最後の電話から出し、直近が昨日でも今日は話していない', (tester) async {
    await _pump(
      tester,
      _view(
        latest: _call(
          at: DateTime(2026, 11, 4, 19, 0),
          minutes: 3,
          headline: '昨日の電話です。',
          conditions: const [
            Condition(
              kind: ConditionKind.meal,
              value: '夕食を食べた',
              quote: '昨日食べた',
            ),
          ],
        ),
      ),
    );

    expect(find.text('昨日の電話です。'), findsOneWidget);
    expect(find.text('昨日 19:00 ・ 3分'), findsOneWidget);
    expect(find.text('19:01'), findsNothing);
    expect(find.text('夕食を食べた'), findsNothing);
    expect(find.text('話していない'), findsNWidgets(3));
    expect(find.textContaining('の会話より'), findsNothing);
    expect(find.byType(TodayCard), findsOneWidget);
  });

  testWidgets('まとめを作れなかった電話は、その文言を出して本人の言葉は出さない', (tester) async {
    await _pump(
      tester,
      _view(
        latest: _call(
          at: DateTime(2026, 11, 5, 9, 2),
          minutes: 1,
          headline: 'まとめを作れませんでした',
          conditions: const [
            Condition(kind: ConditionKind.meal, value: '話していない', quote: ''),
            Condition(kind: ConditionKind.sleep, value: '話していない', quote: ''),
            Condition(kind: ConditionKind.health, value: '話していない', quote: ''),
          ],
        ),
        todaySameAsLatest: true,
      ),
    );

    expect(find.text('まとめを作れませんでした'), findsWidgets);
    expect(find.text('今日 9:02 ・ 1分'), findsOneWidget);
    expect(find.text('使ってはいけない言葉'), findsNothing);
    expect(find.byType(RecentCallCard), findsOneWidget);
    expect(find.byType(AskCard), findsOneWidget);
  });

  testWidgets('電話がまだなければ、空のカードを出さずに短く知らせ、伝えるカードは残す', (tester) async {
    await _pump(tester, _view());

    expect(find.text('田中ハナさん'), findsOneWidget);
    expect(find.text('まだ電話がありません'), findsOneWidget);
    expect(find.byType(RecentCallCard), findsNothing);
    expect(find.byType(TodayCard), findsNothing);
    expect(find.text('7日間の電話'), findsNothing);
    expect(find.byType(AskCard), findsOneWidget);
    expect(find.byType(MissedCallView), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester, HomeView view) {
  return pumpScreenInLayout(
    tester,
    layoutCases.first,
    const Scaffold(body: HomeScreen()),
    overrides: [
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(view)),
    ],
  );
}

HomeView _view({Call? latest, Call? today, bool todaySameAsLatest = false}) {
  return HomeView(
    person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
    now: _now,
    latestCall: latest,
    todayCall: today ?? (todaySameAsLatest ? latest : null),
  );
}

Call _call({
  required DateTime at,
  required int minutes,
  required String headline,
  List<Condition> conditions = const [],
}) {
  return Call(
    startedAt: at,
    duration: Duration(minutes: minutes),
    summary: CallSummary(headline: headline, conditions: conditions),
  );
}
