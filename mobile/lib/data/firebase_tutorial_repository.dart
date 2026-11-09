import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/tutorial_repository.dart';

// 使い方を見たか。ドキュメント ID は家族の uid で、アプリが Firestore に書くのはここだけ
class FirebaseTutorialRepository implements TutorialRepository {
  FirebaseTutorialRepository({
    required FirebaseAuth auth,
    required this._firestore,
  }) {
    _auth = auth.authStateChanges().listen(_watch);
  }

  static const _collection = 'tutorialSeen';

  final FirebaseFirestore _firestore;
  final _seen = ValueNotifier<bool?>(null);
  late final StreamSubscription<User?> _auth;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _doc;
  String? _uid;

  @override
  ValueListenable<bool?> get seen => _seen;

  void _watch(User? user) {
    _doc?.cancel();
    _doc = null;
    _uid = user?.uid;
    _seen.value = null;
    if (user == null) return;
    _doc = _firestore
        .collection(_collection)
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen(_onSnapshot, onError: _onError);
  }

  // 端末のキャッシュが空なだけでは、まだ見ていないとは決められない
  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists && snapshot.metadata.isFromCache) return;
    _seen.value = snapshot.data()?['seen'] == true;
  }

  void _onError(Object error, StackTrace stack) {
    _seen.value = null;
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }

  @override
  Future<void> markSeen() async {
    final uid = _uid;
    if (uid == null) return;
    _seen.value = true;
    await _firestore.collection(_collection).doc(uid).set({'seen': true});
  }

  void dispose() {
    _auth.cancel();
    _doc?.cancel();
    _seen.dispose();
  }
}
