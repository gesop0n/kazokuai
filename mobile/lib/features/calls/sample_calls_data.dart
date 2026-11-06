import 'package:kazokuai/features/calls/calls_data.dart';

// モックの 04 と 04c と同じ内容
final sampleCallLog = CallLog(
  today: DateTime(2026, 11, 5),
  days: [
    CallLogDay(
      date: DateTime(2026, 11, 5),
      entries: [
        AnsweredCallEntry(
          startedAt: DateTime(2026, 11, 5, 9, 2),
          text: '朝食と薬は済み。膝を気にしている',
          duration: const Duration(minutes: 6),
          topic: CallTopic.health,
        ),
      ],
    ),
    CallLogDay(
      date: DateTime(2026, 11, 4),
      entries: [
        AnsweredCallEntry(
          startedAt: DateTime(2026, 11, 4, 19, 0),
          text: '夕飯は大根の煮物。夜の薬も飲んだ',
          duration: const Duration(minutes: 3),
          topic: CallTopic.health,
        ),
        AnsweredCallEntry(
          startedAt: DateTime(2026, 11, 4, 12, 0),
          text: 'テレビの映し方を案内して解決',
          duration: const Duration(minutes: 9),
          topic: CallTopic.guidance,
        ),
      ],
    ),
    CallLogDay(
      date: DateTime(2026, 11, 3),
      entries: [
        AnsweredCallEntry(
          startedAt: DateTime(2026, 11, 3, 9, 0),
          text: 'お孫さんの運動会の話がはずんだ',
          duration: const Duration(minutes: 18),
          topic: CallTopic.companion,
        ),
      ],
    ),
    CallLogDay(
      date: DateTime(2026, 11, 2),
      entries: [
        MissedCallEntry(
          startedAt: DateTime(2026, 11, 2, 9, 0),
          text: '電話に出ませんでした(3回かけました)',
        ),
      ],
    ),
    CallLogDay(
      date: DateTime(2026, 11, 1),
      entries: [
        AnsweredCallEntry(
          startedAt: DateTime(2026, 11, 1, 12, 0),
          text: 'お米が残り少ないと相談があった',
          duration: const Duration(minutes: 31),
          topic: CallTopic.companion,
        ),
      ],
    ),
    CallLogDay(
      date: DateTime(2026, 10, 31),
      entries: [
        AnsweredCallEntry(
          startedAt: DateTime(2026, 10, 31, 9, 0),
          text: '庭の菊が咲き始めた話をした',
          duration: const Duration(minutes: 22),
          topic: CallTopic.companion,
        ),
      ],
    ),
  ],
  // ミニカレンダーの印とホームのグラフにはあるが、モックの 04 と 04c に行がない
  answeredDaysWithoutRecord: {DateTime(2026, 10, 30)},
);

// モックの 05 と同じ内容。モックのデータは 1 通話分なので、どの行から開いてもこれを出す。
final sampleCallDetail = CallDetail(
  title: '朝の電話',
  startedAt: DateTime(2026, 11, 5, 9, 2),
  duration: const Duration(minutes: 6, seconds: 12),
  parentCallName: 'ハナさん',
  points: const [
    SummaryPoint(text: '朝ごはんを食べ、よく眠れたそうです', at: Duration(seconds: 11)),
    SummaryPoint(
      text: '昨日の夕方から膝が痛く、階段がつらいそうです',
      at: Duration(minutes: 1, seconds: 3),
    ),
    SummaryPoint(text: '朝の薬は飲んだと話しています', at: Duration(minutes: 4, seconds: 12)),
  ],
  utterances: const [
    Utterance(
      at: Duration.zero,
      speaker: Speaker.ai,
      text: 'おはようございます、ハナさん。昨夜はよく眠れましたか。',
    ),
    Utterance(
      at: Duration(seconds: 11),
      speaker: Speaker.parent,
      text: 'よく眠れたよ。朝ごはんも食べたしね。',
    ),
    Utterance(
      at: Duration(seconds: 48),
      speaker: Speaker.ai,
      text: 'それは何よりです。お体の具合はいかがですか。',
    ),
    Utterance(
      at: Duration(minutes: 1, seconds: 3),
      speaker: Speaker.parent,
      text: '昨日の夕方から膝が痛くてね。階段がつらいの。',
      needsAttention: true,
    ),
    Utterance(
      at: Duration(minutes: 2),
      speaker: Speaker.ai,
      text: 'それはおつらいですね。美咲さんにもお伝えしておきましょうか。',
    ),
    Utterance(
      at: Duration(minutes: 2, seconds: 21),
      speaker: Speaker.parent,
      text: 'そうね、お願いしようかな。',
    ),
    // ここから下はモックにない見本。まとめの 4:12 の移動先がモックの会話にないので足した
    Utterance(
      at: Duration(minutes: 4, seconds: 5),
      speaker: Speaker.ai,
      text: '朝の薬は飲みましたか。',
    ),
    Utterance(
      at: Duration(minutes: 4, seconds: 12),
      speaker: Speaker.parent,
      text: '飲んだよ。',
    ),
  ],
);
