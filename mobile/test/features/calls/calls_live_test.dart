import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/calls/mini_calendar.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';

const _couldNotSummarize = 'まとめを作れませんでした';

final _today = DateTime(2026, 11, 5);
final _yesterday = DateTime(2026, 11, 4);
final _emptyDay = DateTime(2026, 11, 3);

final _morningUtterance = Utterance(
  at: const Duration(minutes: 4, seconds: 12),
  speaker: Speaker.parent,
  text: '薬は飲んだよ',
);

CallDetail _morningDetail() => CallDetail(
  title: '朝の電話',
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6, seconds: 12),
  parentCallName: 'ハナさん',
  points: const [
    SummaryPoint(text: '薬を飲んだ', at: Duration(minutes: 4, seconds: 12)),
  ],
  utterances: [
    for (var index = 0; index < 20; index++)
      Utterance(
        at: Duration(seconds: index),
        speaker: Speaker.ai,
        text: 'つなぎの発言$index',
      ),
    _morningUtterance,
  ],
);

CallDetail _eveningDetail() => CallDetail(
  title: '夕方の電話',
  startedAt: DateTime(2026, 11, 5, 19),
  duration: const Duration(minutes: 4),
  parentCallName: 'ハナさん',
  points: const [SummaryPoint(text: '孫の話', at: Duration(seconds: 30))],
  utterances: const [
    Utterance(
      at: Duration(seconds: 30),
      speaker: Speaker.parent,
      text: '夕方に話した内容',
    ),
  ],
);

CallDetail _failedDetail() => CallDetail(
  title: '昼の電話',
  startedAt: DateTime(2026, 11, 4, 15),
  duration: const Duration(minutes: 3),
  parentCallName: 'ハナさん',
  points: const [],
  utterances: const [
    Utterance(
      at: Duration(seconds: 20),
      speaker: Speaker.parent,
      text: '失敗した電話の発言',
    ),
  ],
  summaryFailure: _couldNotSummarize,
);

FakeCallsRepository _calls({CallLog? log}) => FakeCallsRepository(
  log: log,
  details: {
    'evening': _eveningDetail(),
    'morning': _morningDetail(),
    'failed': _failedDetail(),
  },
);

CallLog _log() => CallLog(
  today: _today,
  days: [
    CallLogDay(
      date: _today,
      entries: [
        AnsweredCallEntry(
          id: 'evening',
          startedAt: DateTime(2026, 11, 5, 19),
          text: '夕方に孫の話をした',
          duration: const Duration(minutes: 4),
          topic: CallTopic.companion,
        ),
        AnsweredCallEntry(
          id: 'morning',
          startedAt: DateTime(2026, 11, 5, 9, 2),
          text: '朝に薬を飲んだ',
          duration: const Duration(minutes: 6, seconds: 12),
          topic: CallTopic.health,
        ),
      ],
    ),
    CallLogDay(
      date: _yesterday,
      entries: [
        AnsweredCallEntry(
          id: 'failed',
          startedAt: DateTime(2026, 11, 4, 15),
          text: _couldNotSummarize,
          duration: const Duration(minutes: 3),
          topic: null,
        ),
      ],
    ),
  ],
);

Finder _inCalls(String text) =>
    find.descendant(of: find.byType(CallsScreen), matching: find.text(text));

Finder _answeredMark(DateTime date) => find.descendant(
  of: find.byKey(MiniCalendar.dayKey(date)),
  matching: find.byWidgetPredicate((widget) {
    final decoration = widget is Container ? widget.decoration : null;
    return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
  }),
);

Future<void> _openCalls(WidgetTester tester, FakeCallsRepository calls) async {
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        sampleHome(),
        callsRepositoryProvider.overrideWithValue(calls),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text('通話記録')),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _detailPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CallDetailScreen),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  testWidgets('通話記録は新しい順に、まとめと時刻と長さと話の種類を出す', (tester) async {
    await _openCalls(tester, _calls(log: _log()));

    expect(
      tester.getTopLeft(_inCalls('夕方に孫の話をした')).dy,
      lessThan(tester.getTopLeft(_inCalls('朝に薬を飲んだ')).dy),
    );
    expect(
      tester.getTopLeft(_inCalls('朝に薬を飲んだ')).dy,
      lessThan(tester.getTopLeft(_inCalls(_couldNotSummarize)).dy),
    );
    expect(_inCalls('今日 11月5日(木)'), findsOneWidget);
    expect(_inCalls('11月4日(水)'), findsOneWidget);
    expect(_inCalls('19:00'), findsOneWidget);
    expect(_inCalls('話し相手'), findsOneWidget);
    expect(_inCalls('4分'), findsOneWidget);
    expect(_inCalls('9:02'), findsOneWidget);
    expect(_inCalls('体調'), findsOneWidget);
    expect(_inCalls('6分'), findsOneWidget);
    expect(_inCalls('15:00'), findsOneWidget);
    expect(_inCalls('3分'), findsOneWidget);
  });

  testWidgets('電話のあった日だけ印を付け、不在にはしない', (tester) async {
    await _openCalls(tester, _calls(log: _log()));

    expect(_answeredMark(_today), findsOneWidget);
    expect(_answeredMark(_yesterday), findsOneWidget);
    expect(_answeredMark(_emptyDay), findsNothing);
    expect(
      find.descendant(
        of: find.byType(MiniCalendar),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(find.text('不在'), findsNothing);
  });

  testWidgets('開いた電話のまとめの時刻で、その発言へ動く', (tester) async {
    await _openCalls(tester, _calls(log: _log()));
    await tester.tap(_inCalls('朝に薬を飲んだ'));
    await tester.pumpAndSettle();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 480);
    await tester.pumpAndSettle();

    expect(find.text('夕方に話した内容'), findsNothing);
    expect(find.text('薬は飲んだよ').hitTestable(), findsNothing);

    await tester.tap(find.bySemanticsLabel('4:12の発言へ移動'));
    await tester.pumpAndSettle();

    expect(_detailPosition(tester).pixels, greaterThan(0));
    expect(find.text('薬は飲んだよ').hitTestable(), findsOneWidget);
  });

  testWidgets('まとめを作れなかった電話は、一覧と詳細にその文を出し、会話は読める', (tester) async {
    await _openCalls(tester, _calls(log: _log()));

    expect(_inCalls(_couldNotSummarize), findsOneWidget);
    await tester.tap(_inCalls(_couldNotSummarize));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CallDetailScreen),
        matching: find.text(_couldNotSummarize),
      ),
      findsOneWidget,
    );
    expect(find.text('失敗した電話の発言'), findsOneWidget);
    expect(find.text('まとめの間違いを直す'), findsOneWidget);
    expect(find.bySemanticsLabel('4:12の発言へ移動'), findsNothing);
    expect(find.text('不在'), findsNothing);
  });

  testWidgets('電話がまだなければ、まだ電話がありませんと出す', (tester) async {
    await _openCalls(
      tester,
      _calls(
        log: CallLog(today: _today, days: const []),
      ),
    );

    expect(find.text('まだ電話がありません'), findsOneWidget);
    expect(find.text('過去7日間'), findsOneWidget);
    expect(find.text('通話記録'), findsWidgets);
    expect(find.text('朝食と薬は済み。膝を気にしている'), findsNothing);
    expect(find.text('不在'), findsNothing);
  });

  testWidgets('読み終えるまでは、まだ電話がありませんと出さない', (tester) async {
    await _openCalls(tester, _calls());

    expect(find.text('まだ電話がありません'), findsNothing);
    expect(find.text('過去7日間'), findsNothing);
    expect(find.text('朝食と薬は済み。膝を気にしている'), findsNothing);
  });

  testWidgets('ホームの会話を見るは、その電話の詳細を開く', (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInAuth(),
          registeredWatchedPerson(),
          homeRepositoryProvider.overrideWithValue(
            FakeHomeRepository(
              HomeView(
                person: sampleHomeData.person,
                now: DateTime(2026, 11, 5, 10, 24),
                latestCall: Call(
                  id: 'morning',
                  startedAt: DateTime(2026, 11, 5, 9, 2),
                  duration: const Duration(minutes: 6, seconds: 12),
                  summary: const CallSummary(headline: '朝のまとめ', conditions: []),
                ),
                todayCall: null,
              ),
            ),
          ),
          callsRepositoryProvider.overrideWithValue(_calls(log: _log())),
        ],
        child: const KazokuAiApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('会話を見る'));
    await tester.pumpAndSettle();

    expect(find.text('薬は飲んだよ'), findsOneWidget);
    expect(find.text('よく眠れたよ。朝ごはんも食べたしね。'), findsNothing);
  });
}
