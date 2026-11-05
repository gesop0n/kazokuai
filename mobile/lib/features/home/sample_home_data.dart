import 'package:kazokuai/features/home/home_data.dart';

// モックの 00/02/03 と同じ内容。基準日時は ADR のとおり固定する。
final sampleHomeData = HomeData(
  now: DateTime(2026, 11, 5, 10, 24),
  person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
  latestCall: Call(
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
  ),
  week: WeekCallRecords([
    DayCallRecord(date: DateTime(2026, 10, 30), talkedMinutes: 14),
    DayCallRecord(date: DateTime(2026, 10, 31), talkedMinutes: 22),
    DayCallRecord(date: DateTime(2026, 11, 1), talkedMinutes: 31),
    DayCallRecord(date: DateTime(2026, 11, 2)),
    DayCallRecord(date: DateTime(2026, 11, 3), talkedMinutes: 18),
    DayCallRecord(date: DateTime(2026, 11, 4), talkedMinutes: 12),
    DayCallRecord(date: DateTime(2026, 11, 5), talkedMinutes: 6),
  ]),
);
