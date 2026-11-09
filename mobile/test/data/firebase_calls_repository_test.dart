import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/firebase_calls_repository.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

const _uid = 'misaki';

void main() {
  testWidgets('ログインした家族の電話だけを、通話記録と詳細にする', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('watchedPersons').doc('other').set({
      'name': '佐藤タロウ',
      'callName': 'タロウさん',
      'familyUids': ['kenta'],
    });
    await firestore
        .collection('watchedPersons')
        .doc('other')
        .collection('calls')
        .doc('secret')
        .set(_made(at: DateTime(2026, 11, 5, 8), headline: '他人の電話'));
    await _person(firestore);
    final repository = _open(tester, firestore);
    try {
      await tester.pump();

      expect(repository.log.value, isNotNull);
      expect(repository.log.value!.days, isEmpty);

      await firestore
          .collection('watchedPersons')
          .doc('hanako')
          .collection('calls')
          .doc('morning')
          .set(
            _made(
              at: DateTime(2026, 11, 5, 9, 2),
              headline: '朝食と薬は済み。膝を気にしている',
              topic: '体調',
              points: [
                {'text': '朝ごはんを食べたそうです', 'offsetMs': 11000},
              ],
            ),
          );
      await firestore
          .collection('watchedPersons')
          .doc('hanako')
          .collection('calls')
          .doc('morning')
          .collection('utterances')
          .doc('0000')
          .set({
            'index': 0,
            'speaker': '見守る方',
            'offsetMs': 11000,
            'text': '朝ごはんも食べたしね。',
          });
      await tester.pump();

      final entry = repository.log.value!.days.single.answeredEntries.single;
      expect(entry.id, 'morning');
      expect(entry.text, '朝食と薬は済み。膝を気にしている');
      expect(entry.topic, CallTopic.health);
      expect(
        repository.log.value!.markOf(DateTime(2026, 11, 5)),
        DayMark.answered,
      );
      expect(
        repository.log.value!.days.any(
          (day) => day.entries.any((entry) => entry.text == '他人の電話'),
        ),
        isFalse,
      );

      repository.open('morning');
      await tester.pump();

      final detail = repository.detail.value!;
      expect(detail.parentCallName, 'ハナさん');
      expect(detail.points.single.text, '朝ごはんを食べたそうです');
      expect(detail.points.single.at, const Duration(milliseconds: 11000));
      expect(detail.utterances.single.text, '朝ごはんも食べたしね。');
      expect(detail.utterances.single.speaker, Speaker.parent);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('日付が変わると、今日の見出しの基準日を計算し直す', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls')
        .doc('night')
        .set(_made(at: DateTime(2026, 11, 5, 22), headline: '夕食を食べたそうです。'));
    final start = DateTime(2026, 11, 5, 23, 59);
    final origin = tester.binding.clock.now();
    final repository = _open(
      tester,
      firestore,
      now: () => start.add(tester.binding.clock.now().difference(origin)),
    );
    try {
      await tester.pump();

      expect(repository.log.value!.today, DateTime(2026, 11, 5));

      await tester.pump(const Duration(minutes: 2));

      final log = repository.log.value!;
      expect(log.today, DateTime(2026, 11, 6));
      expect(log.days.single.date, DateTime(2026, 11, 5));
      expect(log.days.single.answeredEntries.single.text, '夕食を食べたそうです。');
    } finally {
      repository.dispose();
    }
  });

  testWidgets('アプリに戻ると、その時刻で今日を計算し直す', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls')
        .doc('night')
        .set(_made(at: DateTime(2026, 11, 5, 22), headline: '夕食を食べたそうです。'));
    var now = DateTime(2026, 11, 5, 23, 59);
    final repository = _open(tester, firestore, now: () => now);
    try {
      await tester.pump();

      expect(repository.log.value!.today, DateTime(2026, 11, 5));

      now = DateTime(2026, 11, 6, 0, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(repository.log.value!.today, DateTime(2026, 11, 6));
      expect(repository.log.value!.days.single.date, DateTime(2026, 11, 5));
    } finally {
      repository.dispose();
    }
  });
}

FirebaseCallsRepository _open(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  DateTime Function()? now,
}) {
  return FirebaseCallsRepository(
    auth: _Auth(_User(_uid)),
    firestore: firestore,
    now: now,
    binding: tester.binding,
  );
}

Future<void> _person(FakeFirebaseFirestore firestore) {
  return firestore.collection('watchedPersons').doc('hanako').set({
    'name': '田中ハナ',
    'callName': 'ハナさん',
    'familyUids': [_uid],
  });
}

Map<String, Object?> _made({
  required DateTime at,
  required String headline,
  String topic = '体調',
  List<Map<String, Object?>> points = const [],
}) => {
  'startedAt': at,
  'durationMs': 60000,
  'summaryState': '作れた',
  'summary': {'headline': headline, 'topic': topic, 'points': points},
};

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this._user);

  final User? _user;

  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(_user);
}

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;
}
