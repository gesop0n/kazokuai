import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_watched_person_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';

const _uid = 'misaki';

void main() {
  testWidgets('名前が空、ない、空白だけなら unnamed で、名前があれば電話機がなくても registered', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('watchedPersons').doc('hana').set({
      'name': '',
      'callName': '',
      'familyUids': [_uid],
    });
    final repository = _open(firestore);
    try {
      await tester.pump();
      expect(repository.status.value, WatchedPersonStatus.unnamed);

      await firestore.collection('watchedPersons').doc('hana').set({
        'name': ' \n　',
        'callName': '',
        'familyUids': [_uid],
      });
      await tester.pump();
      expect(repository.status.value, WatchedPersonStatus.unnamed);

      await firestore.collection('watchedPersons').doc('hana').set({
        'callName': '',
        'familyUids': [_uid],
      });
      await tester.pump();
      expect(repository.status.value, WatchedPersonStatus.unnamed);

      await firestore.collection('watchedPersons').doc('hana').set({
        'name': '田中ハナ',
        'callName': 'ハナさん',
        'familyUids': [_uid],
      });
      await tester.pump();
      expect(repository.status.value, WatchedPersonStatus.registered);

      repository.noteLinkedWithoutName();
      expect(repository.status.value, WatchedPersonStatus.registered);
    } finally {
      repository.dispose();
    }
  });

  testWidgets('名前のない見守る方は、結び付けたあと unnamed のまま', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('watchedPersons').doc('hana').set({
      'name': '',
      'familyUids': [_uid],
    });
    final repository = _open(firestore);
    try {
      await tester.pump();

      repository.noteLinkedWithoutName();

      expect(repository.status.value, WatchedPersonStatus.unnamed);
    } finally {
      repository.dispose();
    }
  });
}

FirebaseWatchedPersonRepository _open(FakeFirebaseFirestore firestore) {
  return FirebaseWatchedPersonRepository(
    auth: _Auth(_User(_uid)),
    firestore: firestore,
    backend: Backend(
      MockClient((request) async => http.Response('unreachable', 500)),
    ),
  );
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this._user);

  final User? _user;

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(_user);
}

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;
}
