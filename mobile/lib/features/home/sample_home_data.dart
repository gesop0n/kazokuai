import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_status.dart';

// 基準日時は固定し、状態ごとの値はモックの hhead の文字に合わせる
HomeData sampleHomeDataFor(HomeStatus status) => HomeData(
  now: switch (status) {
    HomeStatus.normal => DateTime(2026, 11, 5, 10, 24),
    HomeStatus.missedCall => DateTime(2026, 11, 5, 9, 31),
  },
  person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
  latestCall: _latestCall,
  missedCall: _missedCall,
);

// モックの 00/02 と同じ内容
final sampleHomeData = sampleHomeDataFor(HomeStatus.normal);

final _latestCall = Call(
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6),
  summary: CallSummary(
    headline: '朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。',
    conditions: const [
      Condition(
        kind: ConditionKind.meal,
        value: '朝ごはんを食べた',
        quote: '朝ごはんも食べたしね',
      ),
      Condition(kind: ConditionKind.sleep, value: 'よく眠れた', quote: 'よく眠れたよ'),
      Condition(
        kind: ConditionKind.health,
        value: '膝が痛い。階段がつらい',
        quote: '昨日の夕方から膝が痛くてね',
        needsAttention: true,
      ),
    ],
  ),
);

// かけなおしの既定は 15 分。モックの 07b と同じ時刻
final _missedCall = MissedCall(
  attemptedAt: [
    DateTime(2026, 11, 5, 9, 0),
    DateTime(2026, 11, 5, 9, 15),
    DateTime(2026, 11, 5, 9, 30),
  ],
);
