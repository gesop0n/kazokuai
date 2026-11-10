import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/home_source.dart';
import 'package:kazokuai/features/home/home_data.dart';

const _uid = 'misaki';
final _now = DateTime(2026, 11, 5, 10, 24);

void main() {
  test('作れた電話を、直近の電話と今日の様子にする', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'newer',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 400000,
        headline: '朝ごはんを食べたそうです。',
        quote: '朝ごはんも食べたしね',
        offsetMs: 60000,
        meal: _talked('朝ごはんを食べた', '朝ごはんも食べたしね'),
        sleep: _silent(),
        health: _talked('膝が痛い', '膝が痛くてね', concerning: true),
      ),
    );
    await _call(
      firestore,
      'earlier',
      _made(
        at: DateTime(2026, 11, 5, 8, 0),
        durationMs: 90000,
        headline: 'ひとつ前の電話です。',
        quote: 'さっき起きた',
        offsetMs: 0,
        meal: _talked('何も食べていない', '何も食べていない'),
        sleep: _silent(),
        health: _silent(),
      ),
    );

    final home = await _home(firestore, _now);

    expect(home.person.name, '田中ハナ');
    expect(home.person.callName, 'ハナさん');
    expect(home.person.initial, 'ハ');
    expect(home.now, _now);

    final latest = home.latestCall!;
    expect(latest.id, 'newer');
    expect(latest.startedAt, DateTime(2026, 11, 5, 9, 2));
    expect(latest.duration, const Duration(milliseconds: 400000));
    expect(latest.summary.headline, '朝ごはんを食べたそうです。');

    final today = home.todayCall!;
    expect(today.summary.headline, '朝ごはんを食べたそうです。');
    expect(today.summary.conditions.map((item) => item.kind), [
      ConditionKind.meal,
      ConditionKind.sleep,
      ConditionKind.health,
    ]);
    expect(today.summary.conditions[0].value, '朝ごはんを食べた');
    expect(today.summary.conditions[0].quote, '朝ごはんも食べたしね');
    expect(today.summary.conditions[0].needsAttention, isFalse);
    expect(today.summary.conditions[1].value, '話していない');
    expect(today.summary.conditions[1].quote, isEmpty);
    expect(today.summary.conditions[1].needsAttention, isFalse);
    expect(today.summary.conditions[2].value, '膝が痛い');
    expect(today.summary.conditions[2].quote, '膝が痛くてね');
    expect(today.summary.conditions[2].needsAttention, isTrue);
  });

  test('今日の様子は、その日の最後の電話だけで、昨日の電話は直近になっても今日にはしない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'yesterday',
      _made(
        at: DateTime(2026, 11, 4, 19, 0),
        durationMs: 180000,
        headline: '昨日の電話です。',
        quote: '昨日食べた',
        offsetMs: 0,
        meal: _talked('夕食を食べた', '昨日食べた'),
        sleep: _silent(),
        health: _silent(),
      ),
    );

    final home = await _home(firestore, DateTime(2026, 11, 5, 8));

    expect(home.latestCall!.summary.headline, '昨日の電話です。');
    expect(home.todayCall, isNull);
  });

  test('今日の最後の電話が今日の様子になり、それより新しい電話が直近になる', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'today',
      _made(
        at: DateTime(2026, 11, 5, 9, 0),
        durationMs: 360000,
        headline: '今日',
        quote: '今日',
        offsetMs: 0,
        meal: _silent(),
        sleep: _silent(),
        health: _silent(),
      ),
    );
    await _call(
      firestore,
      'also-today',
      _bare(at: DateTime(2026, 11, 5, 12, 0), durationMs: 90000),
    );

    final home = await _home(firestore, _now);

    expect(home.latestCall!.startedAt, DateTime(2026, 11, 5, 12, 0));
    expect(home.todayCall!.startedAt, DateTime(2026, 11, 5, 12, 0));
  });

  test('7 日間より前の電話でも、直近の電話には出す', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'old',
      _made(
        at: DateTime(2026, 10, 20, 9, 0),
        durationMs: 120000,
        headline: 'だいぶ前の電話です。',
        quote: '前に話した',
        offsetMs: 1000,
        meal: _silent(),
        sleep: _silent(),
        health: _silent(),
      ),
    );

    final home = await _home(firestore, _now);

    expect(home.latestCall!.summary.headline, 'だいぶ前の電話です。');
    expect(home.latestCall!.startedAt, DateTime(2026, 10, 20, 9, 0));
    expect(home.todayCall, isNull);
  });

  test('まとめを作れなかった電話は、その文言になり、様子は話していない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(firestore, 'failed', {
      'startedAt': DateTime(2026, 11, 5, 9, 2),
      'durationMs': 60000,
      'summaryState': '作れなかった',
      'summary': _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '使ってはいけないまとめ',
        quote: '使ってはいけない言葉',
        offsetMs: 0,
        meal: _talked('食べた', '食べた'),
        sleep: _silent(),
        health: _talked('痛い', '痛い', concerning: true),
      )['summary'],
    });

    final home = await _home(firestore, _now);
    final call = home.latestCall!;

    expect(call.summary.headline, 'まとめを作れませんでした');
    expect(call.startedAt, DateTime(2026, 11, 5, 9, 2));
    expect(call.duration, const Duration(minutes: 1));
    expect(
      call.summary.conditions.every(
        (item) =>
            item.value == '話していない' &&
            item.quote.isEmpty &&
            !item.needsAttention,
      ),
      isTrue,
    );
    expect(home.todayCall!.summary.headline, 'まとめを作れませんでした');
  });

  test('まだまとめていない電話は、作れなかったことにはしない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'pending',
      _bare(at: DateTime(2026, 11, 5, 9, 2), durationMs: 30000),
    );

    final home = await _home(firestore, _now);

    expect(home.latestCall!.summary.headline, isEmpty);
    expect(home.latestCall!.summary.headline, isNot('まとめを作れませんでした'));
  });

  test('話していない項目は、言葉が残っていても話していない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'morning',
      _made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 60000,
        headline: '朝',
        quote: '朝',
        offsetMs: 0,
        meal: {
          'status': '話していない',
          'said': '残った様子',
          'quote': '残った言葉',
          'concerning': true,
        },
        sleep: _silent(),
        health: _silent(),
      ),
    );

    final meal = (await _home(
      firestore,
      _now,
    )).todayCall!.summary.conditions.first;

    expect(meal.value, '話していない');
    expect(meal.quote, isEmpty);
    expect(meal.needsAttention, isFalse);
  });

  test('見守る方からの電話は、今日の様子に入り、伝言の返答は出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(firestore, 'from-parent', {
      ..._made(
        at: DateTime(2026, 11, 5, 9, 2),
        durationMs: 180000,
        headline: '庭の話をした',
        quote: '',
        offsetMs: 0,
        meal: _talked('ご飯を食べた', 'ご飯は食べたよ'),
        sleep: _silent(),
        health: _silent(),
      ),
      'message': '',
      'startedByWatchedPerson': true,
    });

    final home = await _home(firestore, _now);

    expect(home.todayCall!.id, 'from-parent');
    expect(home.todayCall!.summary.conditions.first.value, 'ご飯を食べた');
    expect(home.reply, isNull);
  });

  test('伝言への返答は、伝えたことと、返答を話した時刻になる', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'with-reply',
      _made(
        at: DateTime(2026, 11, 5, 10, 28),
        durationMs: 120000,
        headline: '伝言を伝えたそうです。',
        quote: 'わかったよ',
        offsetMs: 0,
        meal: _silent(),
        sleep: _silent(),
        health: _silent(),
        told: '金曜の通院は、朝10時にお迎えに来る',
        reply: 'わかったよ。玄関で待ってるね。',
        replyOffsetMs: 60000,
      ),
    );

    final reply = (await _home(
      firestore,
      DateTime(2026, 11, 5, 10, 30),
    )).reply!;

    expect(reply.told, '金曜の通院は、朝10時にお迎えに来る');
    expect(reply.text, 'わかったよ。玄関で待ってるね。');
    expect(reply.saidAt, DateTime(2026, 11, 5, 10, 29));
  });

  test('それより新しい電話のまとめが届くと、返答は出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'older',
      _replyCall(at: DateTime(2026, 11, 5, 10, 28)),
    );
    await _call(
      firestore,
      'newer',
      _made(
        at: DateTime(2026, 11, 5, 11, 0),
        durationMs: 60000,
        headline: 'そのあとの電話です。',
        quote: '元気だよ',
        offsetMs: 0,
        meal: _silent(),
        sleep: _silent(),
        health: _silent(),
      ),
    );

    final home = await _home(firestore, DateTime(2026, 11, 5, 11, 10));

    expect(home.reply, isNull);
    expect(home.latestCall!.id, 'newer');
  });

  test('それより新しい電話のまとめがまだなければ、前の返答を出す', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'older',
      _replyCall(at: DateTime(2026, 11, 5, 10, 28)),
    );
    await _call(
      firestore,
      'newer',
      _bare(at: DateTime(2026, 11, 5, 11, 0), durationMs: 30000),
    );

    final home = await _home(firestore, DateTime(2026, 11, 5, 11, 10));

    expect(home.reply!.text, 'わかったよ。玄関で待ってるね。');
    expect(home.latestCall!.id, 'newer');
  });

  test('まとめを作れなかったあとの電話でも、前の返答を出す', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'older',
      _replyCall(at: DateTime(2026, 11, 5, 10, 28)),
    );
    await _call(firestore, 'newer', {
      'startedAt': DateTime(2026, 11, 5, 11, 0),
      'durationMs': 60000,
      'summaryState': '作れなかった',
      'summary': {
        'told': '使わない',
        'reply': {'text': '使わない返答', 'offsetMs': 0},
      },
    });

    final home = await _home(firestore, DateTime(2026, 11, 5, 11, 10));

    expect(home.reply!.text, 'わかったよ。玄関で待ってるね。');
    expect(home.latestCall!.id, 'newer');
    expect(home.latestCall!.summary.headline, 'まとめを作れませんでした');
  });

  test('返答の文がない電話は、返答を出さない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'empty',
      _replyCall(at: DateTime(2026, 11, 5, 10, 28), reply: '   '),
    );

    final home = await _home(firestore, DateTime(2026, 11, 5, 10, 30));

    expect(home.reply, isNull);
  });

  test('返答のある電話が複数なら、まとめの届いているいちばん新しいものを出す', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await _call(
      firestore,
      'older',
      _replyCall(at: DateTime(2026, 11, 5, 9, 0), reply: '古い返答'),
    );
    await _call(
      firestore,
      'newer',
      _replyCall(at: DateTime(2026, 11, 5, 10, 28), reply: '新しい返答'),
    );

    final home = await _home(firestore, DateTime(2026, 11, 5, 10, 30));

    expect(home.reply!.text, '新しい返答');
  });

  test('電話機の ID がある見守る方は同期済みで、空ならまだ同期していない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);

    var home = await _home(firestore, _now);
    expect(home.person.hasPhone, isFalse);

    await firestore.collection('watchedPersons').doc('hanako').update({
      'phoneId': '   ',
    });
    home = await _home(firestore, _now);
    expect(home.person.hasPhone, isFalse);

    await firestore.collection('watchedPersons').doc('hanako').update({
      'phoneId': 'phone-1',
    });
    home = await _home(firestore, _now);
    expect(home.person.hasPhone, isTrue);
  });

  test('電話がまだなければ、直近の電話も今日の様子もない', () async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);

    final home = await _home(firestore, _now);

    expect(home.latestCall, isNull);
    expect(home.todayCall, isNull);
  });
}

// ドキュメントの形は Firestore に書いてから読む。誰の電話を取るかはリポジトリのテスト
Future<HomeView> _home(FakeFirebaseFirestore firestore, DateTime now) async {
  final person = await firestore
      .collection('watchedPersons')
      .doc('hanako')
      .get();
  final calls = await person.reference.collection('calls').get();
  return homeViewFrom(
    person: person.data()!,
    calls: [
      for (final call in calls.docs) {...call.data(), 'id': call.id},
    ],
    now: now,
  );
}

Future<void> _person(FakeFirebaseFirestore firestore) {
  return firestore.collection('watchedPersons').doc('hanako').set({
    'name': '田中ハナ',
    'callName': 'ハナさん',
    'familyUids': [_uid],
  });
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

Map<String, Object?> _made({
  required DateTime at,
  required int durationMs,
  required String headline,
  required String quote,
  required int offsetMs,
  required Map<String, Object?> meal,
  required Map<String, Object?> sleep,
  required Map<String, Object?> health,
  String told = '',
  String reply = '',
  int replyOffsetMs = 0,
}) => {
  'startedAt': at,
  'durationMs': durationMs,
  'summaryState': '作れた',
  'summary': {
    'headline': headline,
    'quote': {'text': quote, 'offsetMs': offsetMs},
    'meal': meal,
    'sleep': sleep,
    'health': health,
    'topic': '体調',
    'points': <Object?>[],
    'told': told,
    'reply': {'text': reply, 'offsetMs': replyOffsetMs},
  },
};

Map<String, Object?> _replyCall({
  required DateTime at,
  String reply = 'わかったよ。玄関で待ってるね。',
}) => _made(
  at: at,
  durationMs: 120000,
  headline: '伝言を伝えたそうです。',
  quote: 'わかったよ',
  offsetMs: 0,
  meal: _silent(),
  sleep: _silent(),
  health: _silent(),
  told: '金曜の通院は、朝10時にお迎えに来る',
  reply: reply,
  replyOffsetMs: 60000,
);

Map<String, Object?> _bare({required DateTime at, required int durationMs}) => {
  'startedAt': at,
  'durationMs': durationMs,
};

Map<String, Object?> _talked(
  String said,
  String quote, {
  bool concerning = false,
}) => {'status': '話した', 'said': said, 'quote': quote, 'concerning': concerning};

Map<String, Object?> _silent() => {
  'status': '話していない',
  'said': '',
  'quote': '',
  'concerning': false,
};
