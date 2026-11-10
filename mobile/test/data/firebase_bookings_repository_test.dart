import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_bookings_repository.dart';

const _uid = 'misaki';

void main() {
  testWidgets('ログインした家族の予約を、文の空白を除いて一覧にする', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('watchedPersons').doc('hanako').set({
      'name': '田中ハナ',
      'callName': 'ハナさん',
      'familyUids': [_uid],
    });
    final bookings = firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('bookings');
    await bookings.doc('noon').set({
      'at': DateTime(2026, 11, 10, 18),
      'message': ' 夕方の伝言 ',
      'script': ' 「夕方です。」 ',
      'called': false,
    });
    await bookings.doc('called').set({
      'at': DateTime(2026, 11, 11, 9),
      'message': 'かけた伝言',
      'script': '「かけました。」',
      'called': true,
    });
    await bookings.doc('blank').set({
      'at': DateTime(2026, 11, 12, 9),
      'message': '   ',
      'script': '「空」',
    });
    final repository = _open(tester, firestore);
    try {
      await tester.pump();
      await tester.pump();

      final saved = repository.bookings.value;
      expect(saved, isNotNull);
      expect(
        saved!.map((booking) => booking.id),
        containsAll(['noon', 'called']),
      );
      expect(saved.map((booking) => booking.id), isNot(contains('blank')));
      final noon = saved.singleWhere((booking) => booking.id == 'noon');
      expect(noon.at, DateTime(2026, 11, 10, 18));
      expect(noon.message, '夕方の伝言');
      expect(noon.script, '「夕方です。」');
      expect(noon.called, isFalse);
      expect(
        saved.singleWhere((booking) => booking.id == 'called').called,
        isTrue,
      );
    } finally {
      repository.dispose();
    }
  });

  testWidgets('予約の時刻を過ぎると、一覧を出し直す', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('watchedPersons').doc('hanako').set({
      'familyUids': [_uid],
    });
    await firestore
        .collection('watchedPersons')
        .doc('hanako')
        .collection('bookings')
        .doc('soon')
        .set({
          'at': DateTime(2026, 11, 10, 15, 2),
          'message': 'すぐ',
          'script': '「すぐです。」',
          'called': false,
        });
    var now = DateTime(2026, 11, 10, 15);
    final repository = _open(tester, firestore, now: () => now);
    try {
      await tester.pump();
      await tester.pump();
      final first = repository.bookings.value;
      expect(first, isNotNull);

      now = DateTime(2026, 11, 10, 15, 2);
      await tester.pump(const Duration(minutes: 2));

      expect(identical(repository.bookings.value, first), isFalse);
      expect(repository.bookings.value!.single.id, 'soon');
    } finally {
      repository.dispose();
    }
  });

  testWidgets('保存は、ログインした家族のトークンでバックエンドへ送る', (tester) async {
    http.Request? seen;
    final repository = _open(
      tester,
      FakeFirebaseFirestore(),
      backend: Backend(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'id': 'new-1'}), 201);
        }),
      ),
    );
    try {
      await repository.create(
        at: DateTime(2026, 11, 11, 8, 30),
        message: '明日の伝言',
        script: '「明日です。」',
      );

      expect(seen, isNotNull);
      expect(seen!.url.path, '/bookings');
      expect(seen!.headers['Authorization'], 'Bearer token');
    } finally {
      repository.dispose();
    }
  });
}

FirebaseBookingsRepository _open(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  DateTime Function()? now,
  Backend? backend,
}) {
  return FirebaseBookingsRepository(
    auth: _Auth(_User(_uid)),
    firestore: firestore,
    backend:
        backend ??
        Backend(MockClient((request) async => http.Response('', 500))),
    now: now,
    binding: tester.binding,
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

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async => 'token';
}
