import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/firebase_call_progress_repository.dart';

const _uid = 'misaki';

void main() {
  testWidgets('呼び出し中か通話中のあいだは電話の最中で、終わると戻る', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    final repository = _open(firestore);
    try {
      await tester.pump();
      expect(repository.inProgress.value, isFalse);

      final calls = firestore
          .collection('watchedPersons')
          .doc('hanako')
          .collection('calls');
      await calls.doc('now').set({'state': '呼び出し中'});
      await tester.pump();
      expect(repository.inProgress.value, isTrue);

      await calls.doc('now').update({'state': '通話中'});
      await tester.pump();
      expect(repository.inProgress.value, isTrue);

      await calls.doc('now').update({'state': '終わった'});
      await tester.pump();
      expect(repository.inProgress.value, isFalse);

      await calls.doc('later').set({'state': '通話中'});
      await tester.pump();
      expect(repository.inProgress.value, isTrue);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('終わった電話や、ほかの見守る方の呼び出しでは、電話の最中にならない', (tester) async {
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
        .doc('theirs')
        .set({'state': '呼び出し中'});
    await _person(firestore);
    final calls = firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls');
    await calls.doc('ended').set({'state': '終わった'});
    await calls.doc('missed').set({'state': '出なかった'});
    await calls.doc('failed').set({'state': 'つながらなかった'});
    await calls.doc('blank').set({'message': '状態がない'});

    final repository = _open(firestore);
    try {
      await tester.pump();

      expect(repository.inProgress.value, isFalse);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('ログインしていなければ、電話の最中ではない', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('calls')
        .doc('now')
        .set({'state': '通話中'});
    final repository = _open(firestore, uid: null);
    try {
      await tester.pump();

      expect(repository.inProgress.value, isFalse);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('終わった電話の読み取りは、最中でなくても届く', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _person(firestore);
    final repository = _open(firestore);
    var notices = 0;
    repository.inProgress.addListener(() => notices++);
    try {
      await tester.pump();
      final afterOpen = notices;

      await firestore
          .collection('watchedPersons')
          .doc('hanako')
          .collection('calls')
          .doc('done')
          .set({'state': '終わった'});
      await tester.pump();

      expect(repository.inProgress.value, isFalse);
      expect(notices, greaterThan(afterOpen));
    } finally {
      repository.dispose();
    }
  });
}

FirebaseCallProgressRepository _open(
  FakeFirebaseFirestore firestore, {
  String? uid = _uid,
}) {
  return FirebaseCallProgressRepository(
    auth: _Auth(uid == null ? null : _User(uid)),
    firestore: firestore,
  );
}

Future<void> _person(FakeFirebaseFirestore firestore) {
  return firestore.collection('watchedPersons').doc('hanako').set({
    'name': '田中ハナ',
    'callName': 'ハナさん',
    'familyUids': [_uid],
  });
}

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
