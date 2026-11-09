import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/firebase_tutorial_repository.dart';

void main() {
  testWidgets('記録がなければ見ていない。見たと書くとその家族の記録だけが残る', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirebaseTutorialRepository(
      auth: _Auth(_User('misaki-uid')),
      firestore: firestore,
    );
    addTearDown(repository.dispose);

    await tester.pump();
    await tester.pump();
    expect(repository.seen.value, isFalse);

    await repository.markSeen();
    await tester.pump();

    final own = await firestore
        .collection('tutorialSeen')
        .doc('misaki-uid')
        .get();
    expect(own.data(), {'seen': true});
    expect(repository.seen.value, isTrue);
    final other = await firestore
        .collection('tutorialSeen')
        .doc('kenta-uid')
        .get();
    expect(other.exists, isFalse);
  });

  testWidgets('見たと書いてあれば、見たことになる', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('tutorialSeen').doc('misaki-uid').set({
      'seen': true,
    });
    final repository = FirebaseTutorialRepository(
      auth: _Auth(_User('misaki-uid')),
      firestore: firestore,
    );
    addTearDown(repository.dispose);

    await tester.pump();
    await tester.pump();
    expect(repository.seen.value, isTrue);
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
