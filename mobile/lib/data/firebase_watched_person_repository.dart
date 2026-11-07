import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/watched_person_repository.dart';

// 見守る方は Firestore から読み、登録はバックエンドを通す。アプリは Firestore に何も書かない
class FirebaseWatchedPersonRepository implements WatchedPersonRepository {
  FirebaseWatchedPersonRepository({
    required FirebaseAuth auth,
    required this._firestore,
    required this._backend,
  }) : _auth = auth {
    _authSubscription = auth.authStateChanges().listen(_watch);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Backend _backend;
  final _status = ValueNotifier(WatchedPersonStatus.unknown);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySubscription;

  @override
  ValueListenable<WatchedPersonStatus> get status => _status;

  // ログインした家族を家族の一覧に持つ見守る方を探す。セキュリティルールは、この条件の読み取りだけを許す
  void _watch(User? user) {
    _querySubscription?.cancel();
    _querySubscription = null;
    _status.value = WatchedPersonStatus.unknown;
    if (user == null) return;
    _querySubscription = _firestore
        .collection('watchedPersons')
        .where('familyUids', arrayContains: user.uid)
        .limit(1)
        // 端末のキャッシュが空なだけでは、見守る方がいないとは決められない。サーバーで確かめた結果も受け取る
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (snapshot.docs.isNotEmpty) {
              _status.value = WatchedPersonStatus.registered;
            } else if (!snapshot.metadata.isFromCache) {
              _status.value = WatchedPersonStatus.none;
            }
          },
          onError: (Object error, StackTrace stack) => FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'kazokuai data',
              context: ErrorDescription('見守る方を Firestore から読んでいるとき'),
            ),
          ),
        );
  }

  @override
  Future<void> register({
    required String name,
    required String callName,
  }) async {
    final String? idToken;
    try {
      idToken = await _auth.currentUser?.getIdToken();
    } on FirebaseAuthException {
      throw const RegisterWatchedPersonException();
    }
    if (idToken == null) throw const RegisterWatchedPersonException();
    await _backend.registerWatchedPerson(
      idToken: idToken,
      name: name,
      callName: callName,
    );
    // Firestore からの知らせを待たずに、すぐにホームへ進める
    _status.value = WatchedPersonStatus.registered;
  }

  void dispose() {
    _authSubscription.cancel();
    _querySubscription?.cancel();
    _status.dispose();
  }
}
