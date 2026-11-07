import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_status.dart';

// 基準日時は固定し、状態ごとの値はモックの hhead の文字に合わせる
HomeData sampleHomeDataFor(HomeStatus status) => HomeData(
  now: switch (status) {
    HomeStatus.normal => DateTime(2026, 11, 5, 10, 24),
    HomeStatus.calling => DateTime(2026, 11, 5, 10, 27),
    HomeStatus.missedCall => DateTime(2026, 11, 5, 9, 31),
  },
  person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
  latestCall: _latestCall,
  week: _week,
  missedCall: _missedCall,
);

// モックの 00/02/03 と同じ内容
final sampleHomeData = sampleHomeDataFor(HomeStatus.normal);

final _latestCall = Call(
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6),
  summary: CallSummary(
    headline: '朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。',
    quote: Quote(
      text: '「昨日の夕方から膝が痛くてね。\n階段がつらいの。」',
      spokenAt: DateTime(2026, 11, 5, 9, 3),
    ),
    conditions: const [
      Condition(
        kind: ConditionKind.meal,
        value: '朝ごはんを食べた',
        quote: '「朝ごはんも食べたしね」',
      ),
      Condition(kind: ConditionKind.sleep, value: 'よく眠れた', quote: '「よく眠れたよ」'),
      Condition(
        kind: ConditionKind.health,
        value: '膝が痛い。階段がつらい',
        quote: '「昨日の夕方から膝が痛くてね」',
        needsAttention: true,
      ),
    ],
  ),
);

final _week = WeekCallRecords([
  DayCallRecord(date: DateTime(2026, 10, 30), talkedMinutes: 14),
  DayCallRecord(date: DateTime(2026, 10, 31), talkedMinutes: 22),
  DayCallRecord(date: DateTime(2026, 11, 1), talkedMinutes: 31),
  DayCallRecord(date: DateTime(2026, 11, 2)),
  DayCallRecord(date: DateTime(2026, 11, 3), talkedMinutes: 18),
  DayCallRecord(date: DateTime(2026, 11, 4), talkedMinutes: 12),
  DayCallRecord(date: DateTime(2026, 11, 5), talkedMinutes: 6),
]);

// かけなおしの既定は 10 分。モックの 07b はまだ 15 分の時刻のまま
final _missedCall = MissedCall(
  attemptedAt: [
    DateTime(2026, 11, 5, 9, 0),
    DateTime(2026, 11, 5, 9, 10),
    DateTime(2026, 11, 5, 9, 20),
  ],
  lastTalk: LastTalk(
    startedAt: DateTime(2026, 11, 4, 19, 0),
    duration: const Duration(minutes: 3),
    quote: '「さっき飲んだよ。膝が少し痛むけど、大丈夫。」',
  ),
);
