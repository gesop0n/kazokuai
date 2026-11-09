import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/calls_source.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';

final _now = DateTime(2026, 11, 5, 10, 24);

void main() {
  test('電話を日付ごとに新しい順に並べ、一言と長さと話の種類を付ける', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(
      firestore,
      'noon',
      _made(
        at: DateTime(2026, 11, 4, 12, 0),
        durationMs: 540000,
        headline: 'テレビの映し方を案内して解決',
        topic: '操作案内',
      ),
    );
    await _call(
      firestore,
      'morning',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 372000,
        headline: '朝食と薬は済み。膝を気にしている',
        topic: '体調',
      ),
    );
    await _call(
      firestore,
      'evening',
      _made(
        at: DateTime(2026, 11, 4, 19, 0),
        durationMs: 180000,
        headline: '夕飯は大根の煮物。夜の薬も飲んだ',
        topic: '話し相手',
      ),
    );

    final log = await _log(firestore, _now);

    expect(log.today, DateTime(2026, 11, 5));
    expect(log.answeredDaysWithoutRecord, isEmpty);
    expect(
      [
        for (final day in log.days)
          for (final entry in day.answeredEntries)
            (
              day.date,
              entry.startedAt,
              entry.text,
              entry.duration,
              entry.topic,
              entry.id,
            ),
      ],
      [
        (
          DateTime(2026, 11, 5),
          DateTime(2026, 11, 5, 9, 2),
          '朝食と薬は済み。膝を気にしている',
          const Duration(milliseconds: 372000),
          CallTopic.health,
          'morning',
        ),
        (
          DateTime(2026, 11, 4),
          DateTime(2026, 11, 4, 19, 0),
          '夕飯は大根の煮物。夜の薬も飲んだ',
          const Duration(milliseconds: 180000),
          CallTopic.companion,
          'evening',
        ),
        (
          DateTime(2026, 11, 4),
          DateTime(2026, 11, 4, 12, 0),
          'テレビの映し方を案内して解決',
          const Duration(milliseconds: 540000),
          CallTopic.guidance,
          'noon',
        ),
      ],
    );
  });

  test('ミニカレンダーは電話のあった日だけを電話に出た印にし、不在にはしない', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(
      firestore,
      'morning',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '朝',
        topic: '体調',
      ),
    );
    await _call(
      firestore,
      'failed',
      _failed(at: DateTime(2026, 11, 2, 9, 0), durationMs: 60000),
    );

    final log = await _log(firestore, _now);

    expect(log.markOf(DateTime(2026, 11, 5)), DayMark.answered);
    expect(log.markOf(DateTime(2026, 11, 2)), DayMark.answered);
    expect(log.markOf(DateTime(2026, 11, 4)), isNull);
    expect(log.markOf(DateTime(2026, 11, 6)), isNull);
    for (var day = 1; day <= 30; day++) {
      expect(
        log.markOf(DateTime(2026, 11, day)),
        isNot(DayMark.missed),
        reason: '$day',
      );
    }
    expect(
      log.days.every(
        (day) => day.entries.every((entry) => entry is AnsweredCallEntry),
      ),
      isTrue,
    );
  });

  test('詳細は時刻付きのまとめと、始まった順の会話になる', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'morning', {
      ..._made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 372000,
        headline: '朝食と薬は済み。膝を気にしている',
        topic: '体調',
        points: [
          {'text': '朝ごはんを食べ、よく眠れたそうです', 'offsetMs': 11000},
          {'text': '膝が痛く、階段がつらいそうです', 'offsetMs': 63000},
        ],
      ),
    });
    await _utterance(
      firestore,
      'morning',
      '0002',
      index: 2,
      speaker: '見守る方',
      offsetMs: 63000,
      text: '階段がつらいの。',
    );
    await _utterance(
      firestore,
      'morning',
      '0000',
      index: 0,
      speaker: 'AI',
      offsetMs: 0,
      text: 'おはようございます。',
    );
    await _utterance(
      firestore,
      'morning',
      '0001',
      index: 1,
      speaker: '見守る方',
      offsetMs: 11000,
      text: '朝ごはんも食べたしね。',
    );

    final detail = await _detail(firestore, 'morning');

    expect(detail.title, '朝の電話');
    expect(detail.startedAt, DateTime(2026, 11, 5, 9, 2));
    expect(detail.duration, const Duration(milliseconds: 372000));
    expect(detail.parentCallName, 'ハナさん');
    expect(detail.summaryFailure, isNull);
    expect(detail.points.map((point) => (point.text, point.at)), [
      ('朝ごはんを食べ、よく眠れたそうです', const Duration(milliseconds: 11000)),
      ('膝が痛く、階段がつらいそうです', const Duration(milliseconds: 63000)),
    ]);
    expect(
      detail.utterances.map(
        (utterance) => (
          utterance.at,
          utterance.speaker,
          utterance.text,
          utterance.needsAttention,
        ),
      ),
      [
        (Duration.zero, Speaker.ai, 'おはようございます。', false),
        (
          const Duration(milliseconds: 11000),
          Speaker.parent,
          '朝ごはんも食べたしね。',
          false,
        ),
        (
          const Duration(milliseconds: 63000),
          Speaker.parent,
          '階段がつらいの。',
          false,
        ),
      ],
    );
    expect(
      formatCallStamp(detail.startedAt, detail.duration),
      '11/5 9:02 ・ 6分12秒',
    );
  });

  test('まとめを作れなかった電話は、その文になり、会話は残る', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'failed', {
      ..._failed(at: DateTime(2026, 11, 5, 9, 2), durationMs: 60000),
      'summary': _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '使ってはいけないまとめ',
        topic: '体調',
        points: [
          {'text': '使ってはいけない点', 'offsetMs': 1000},
        ],
      )['summary'],
    });
    await _utterance(
      firestore,
      'failed',
      '0000',
      index: 0,
      speaker: '見守る方',
      offsetMs: 0,
      text: '聞こえていますか。',
    );

    final log = await _log(firestore, _now);
    final entry = log.days.single.entries.single as AnsweredCallEntry;
    final detail = await _detail(firestore, 'failed');

    expect(entry.text, 'まとめを作れませんでした');
    expect(entry.topic, isNull);
    expect(entry.duration, const Duration(minutes: 1));
    expect(detail.summaryFailure, 'まとめを作れませんでした');
    expect(detail.points, isEmpty);
    expect(detail.utterances.single.text, '聞こえていますか。');
    expect(detail.parentCallName, 'ハナさん');
  });

  test('出なかった電話は、電話に出ませんでしたの行になり、その日は不在になる', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'missed', {
      'state': '出なかった',
      'createdAt': DateTime(2026, 11, 2, 9),
      'message': '金曜の通院、10時に迎えに行くと伝えて',
      'script': '「ハナさん、美咲さんからご伝言です。」',
    });

    final log = await _log(firestore, _now);
    final day = log.days.single;
    final entry = day.entries.single;

    expect(day.date, DateTime(2026, 11, 2));
    expect(entry, isA<MissedCallEntry>());
    expect(entry.startedAt, DateTime(2026, 11, 2, 9));
    expect(entry.text, '電話に出ませんでした');
    expect(formatDayHeading(day.date, log.today), '11月2日(月)');
    expect(formatDayTotal(day), '不在');
    expect(log.markOf(DateTime(2026, 11, 2)), DayMark.missed);
    expect(log.markOf(DateTime(2026, 11, 5)), isNull);
  });

  test('出た電話がある日は、出なかった電話も並べ、見出しと印は出た電話で数える', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(
      firestore,
      'morning',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 372000,
        headline: '朝食と薬は済み。膝を気にしている',
        topic: '体調',
      ),
    );
    await _call(firestore, 'evening-miss', {
      'state': '出なかった',
      'createdAt': DateTime(2026, 11, 5, 19),
    });
    await _call(firestore, 'monday-miss', {
      'state': '出なかった',
      'createdAt': DateTime(2026, 11, 2, 9),
    });

    final log = await _log(firestore, _now);

    expect(
      [
        for (final day in log.days)
          for (final entry in day.entries)
            (
              day.date,
              formatDayTotal(day),
              log.markOf(day.date),
              entry is MissedCallEntry,
              entry.startedAt,
              entry.text,
            ),
      ],
      [
        (
          DateTime(2026, 11, 5),
          '1回 ・ 6分',
          DayMark.answered,
          true,
          DateTime(2026, 11, 5, 19),
          '電話に出ませんでした',
        ),
        (
          DateTime(2026, 11, 5),
          '1回 ・ 6分',
          DayMark.answered,
          false,
          DateTime(2026, 11, 5, 9, 2),
          '朝食と薬は済み。膝を気にしている',
        ),
        (
          DateTime(2026, 11, 2),
          '不在',
          DayMark.missed,
          true,
          DateTime(2026, 11, 2, 9),
          '電話に出ませんでした',
        ),
      ],
    );
    expect(log.markOf(DateTime(2026, 11, 4)), isNull);
  });

  test('呼び出し中とつながらなかった電話と、時刻のない出なかった電話は一覧に出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'ringing', {
      'state': '呼び出し中',
      'createdAt': DateTime(2026, 11, 5, 10),
    });
    await _call(firestore, 'dropped', {
      'state': 'つながらなかった',
      'createdAt': DateTime(2026, 11, 4, 9),
    });
    await _call(firestore, 'timeless', {'state': '出なかった'});
    await _call(
      firestore,
      'morning',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '朝の電話です。',
        topic: '体調',
      ),
    );

    final log = await _log(firestore, _now);
    final entry = log.days.single.entries.single as AnsweredCallEntry;

    expect(entry.id, 'morning');
    expect(entry.text, '朝の電話です。');
    expect(log.markOf(DateTime(2026, 11, 4)), isNull);
    expect(log.markOf(DateTime(2026, 11, 5)), DayMark.answered);
  });

  test('電話がまだなければ、一覧は空で、不在の印もない', () async {
    final log = await _log(FakeFirebaseFirestore(), _now);

    expect(log.today, DateTime(2026, 11, 5));
    expect(log.days, isEmpty);
    expect(log.markOf(DateTime(2026, 11, 5)), isNull);
    expect(log.answeredDaysWithoutRecord, isEmpty);
  });

  test('まだまとめていない電話は、作れなかったことにはせず、会話は読める', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'pending', {
      'startedAt': DateTime(2026, 11, 5, 9, 2),
      'durationMs': 30000,
      'summary': {'headline': '使ってはいけないまとめ', 'topic': '体調'},
    });
    await _utterance(
      firestore,
      'pending',
      '0000',
      index: 0,
      speaker: 'AI',
      offsetMs: 0,
      text: 'おはようございます。',
    );

    final log = await _log(firestore, _now);
    final entry = log.days.single.entries.single as AnsweredCallEntry;
    final detail = await _detail(firestore, 'pending');

    expect(entry.text, isEmpty);
    expect(entry.text, isNot('まとめを作れませんでした'));
    expect(entry.topic, isNull);
    expect(detail.summaryFailure, isNull);
    expect(detail.points, isEmpty);
    expect(detail.utterances.single.text, 'おはようございます。');
  });

  test('始まりの時刻がない電話は、一覧に出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(firestore, 'broken', {
      'durationMs': 1000,
      'summaryState': '作れた',
    });

    final log = await _log(firestore, _now);

    expect(log.days, isEmpty);
  });

  test('知らない話の種類は、出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _call(
      firestore,
      'odd',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '朝の電話です。',
        topic: 'その他',
      ),
    );

    final log = await _log(firestore, _now);
    final entry = log.days.single.entries.single as AnsweredCallEntry;

    expect(entry.text, '朝の電話です。');
    expect(entry.topic, isNull);
  });
}

Future<CallLog> _log(FakeFirebaseFirestore firestore, DateTime now) async {
  final calls = await firestore
      .collection('watchedPersons')
      .doc('hanako')
      .collection('calls')
      .get();
  return callLogFrom(
    calls: [
      for (final call in calls.docs)
        CallDocument(id: call.id, data: call.data()),
    ],
    now: now,
  );
}

Future<CallDetail> _detail(FakeFirebaseFirestore firestore, String id) async {
  final call = await firestore
      .collection('watchedPersons')
      .doc('hanako')
      .collection('calls')
      .doc(id)
      .get();
  final utterances = await call.reference.collection('utterances').get();
  return callDetailFrom(
    callName: 'ハナさん',
    call: call.data()!,
    utterances: [for (final utterance in utterances.docs) utterance.data()],
  )!;
}

Future<void> _call(
  FakeFirebaseFirestore firestore,
  String id,
  Map<String, Object?> data,
) {
  return firestore
      .collection('watchedPersons')
      .doc('hanako')
      .collection('calls')
      .doc(id)
      .set(data);
}

Future<void> _utterance(
  FakeFirebaseFirestore firestore,
  String callId,
  String id, {
  required int index,
  required String speaker,
  required int offsetMs,
  required String text,
}) {
  return firestore
      .collection('watchedPersons')
      .doc('hanako')
      .collection('calls')
      .doc(callId)
      .collection('utterances')
      .doc(id)
      .set({
        'index': index,
        'speaker': speaker,
        'offsetMs': offsetMs,
        'text': text,
      });
}

Map<String, Object?> _made({
  required DateTime at,
  required int durationMs,
  required String headline,
  required String topic,
  List<Map<String, Object?>> points = const [],
}) => {
  'startedAt': at,
  'durationMs': durationMs,
  'summaryState': '作れた',
  'summary': {
    'headline': headline,
    'quote': {'text': '', 'offsetMs': 0},
    'meal': _silent(),
    'sleep': _silent(),
    'health': _silent(),
    'topic': topic,
    'points': points,
  },
};

Map<String, Object?> _failed({required DateTime at, required int durationMs}) =>
    {'startedAt': at, 'durationMs': durationMs, 'summaryState': '作れなかった'};

Map<String, Object?> _silent() => {
  'status': '話していない',
  'said': '',
  'quote': '',
  'concerning': false,
};
