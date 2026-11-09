import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/firebase_home_repository.dart';

const _uid = 'misaki';

void main() {
  testWidgets('ログインした家族の見守る方だけを読み、届いた電話をホームに出す', (tester) async {
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
        .set(_call(at: DateTime(2026, 11, 5, 9), headline: '他人の電話'));
    await _person(firestore);
    final repository = _open(tester, firestore);
    try {
      await tester.pump();

      expect(repository.view.value!.person.name, '田中ハナ');
      expect(repository.view.value!.latestCall, isNull);

      await firestore
          .collection('watchedPersons')
          .doc('hanako')
          .collection('calls')
          .doc('morning')
          .set(
            _call(at: DateTime(2026, 11, 5, 9, 2), headline: '朝ごはんを食べたそうです。'),
          );
      await tester.pump();

      expect(
        repository.view.value!.latestCall!.summary.headline,
        '朝ごはんを食べたそうです。',
      );
    } finally {
      repository.dispose();
    }
  });

  testWidgets('見守る方がいなければ、ホームの中身はない', (tester) async {
    final repository = _open(tester, FakeFirebaseFirestore());
    try {
      await tester.pump();

      expect(repository.view.value, isNull);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('日付が変わると、今日の様子を計算し直す', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls')
        .doc('night')
        .set(_call(at: DateTime(2026, 11, 5, 22), headline: '夕食を食べたそうです。'));
    final start = DateTime(2026, 11, 5, 23, 59);
    final origin = tester.binding.clock.now();
    final repository = _open(
      tester,
      firestore,
      now: () => start.add(tester.binding.clock.now().difference(origin)),
    );
    try {
      await tester.pump();

      expect(repository.view.value!.todayCall, isNotNull);

      await tester.pump(const Duration(minutes: 2));

      final view = repository.view.value!;
      expect(view.todayCall, isNull);
      // 日付が変わる瞬間に計算し直す。2 分進めても、そのあとは再計算しない
      expect(view.now, DateTime(2026, 11, 6));
      expect(view.latestCall!.summary.headline, '夕食を食べたそうです。');
    } finally {
      repository.dispose();
    }
  });

  testWidgets('アプリに戻ると、その時刻で今日の様子を計算し直す', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls')
        .doc('night')
        .set(_call(at: DateTime(2026, 11, 5, 22), headline: '夕食を食べたそうです。'));
    var now = DateTime(2026, 11, 5, 23, 59);
    final repository = _open(tester, firestore, now: () => now);
    try {
      await tester.pump();

      expect(repository.view.value!.todayCall, isNotNull);

      now = DateTime(2026, 11, 6, 0, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      final view = repository.view.value!;
      expect(view.now, DateTime(2026, 11, 6, 0, 1));
      expect(view.todayCall, isNull);
    } finally {
      repository.dispose();
    }
  });
}

FirebaseHomeRepository _open(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  DateTime Function()? now,
}) {
  return FirebaseHomeRepository(
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

Map<String, Object?> _call({required DateTime at, required String headline}) =>
    {
      'startedAt': at,
      'durationMs': 60000,
      'summaryState': '作れた',
      'summary': {
        'headline': headline,
        'quote': {'text': '話した', 'offsetMs': 0},
        'meal': {
          'status': '話した',
          'said': '食べた',
          'quote': '食べたよ',
          'concerning': false,
        },
      },
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
