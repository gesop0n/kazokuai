import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/call_progress_repository.dart';

// protocol.StateRinging と StateTalking と合わせる
const _ringing = '呼び出し中';
const _talking = '通話中';

// 見守る方の電話が呼び出し中か通話中かを Firestore から読む。アプリは Firestore に何も書かない
class FirebaseCallProgressRepository implements CallProgressRepository {
  FirebaseCallProgressRepository({
    required FirebaseAuth auth,
    required this._firestore,
  }) {
    _authSubscription = auth.authStateChanges().listen(_watch);
  }

  final FirebaseFirestore _firestore;
  final _inProgress = ValueNotifier(false);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSubscription;
  String? _personId;

  @override
  ValueListenable<bool> get inProgress => _inProgress;

  void _watch(User? user) {
    _stop();
    _inProgress.value = false;
    if (user == null) return;
    _personSubscription = _firestore
        .collection('watchedPersons')
        .where('familyUids', arrayContains: user.uid)
        .limit(1)
        // 端末のキャッシュが空なだけでは、見守る方がいないとは決められない
        .snapshots(includeMetadataChanges: true)
        .listen(_onPerson, onError: _report);
  }

  void _onPerson(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) {
      if (snapshot.metadata.isFromCache) return;
      _stopCalls();
      _inProgress.value = false;
      return;
    }
    final doc = snapshot.docs.first;
    if (_personId == doc.id && _callsSubscription != null) return;
    _personId = doc.id;
    _callsSubscription?.cancel();
    _callsSubscription = doc.reference
        .collection('calls')
        .snapshots(includeMetadataChanges: true)
        .listen(_onCalls, onError: _report);
  }

  void _onCalls(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // 空のキャッシュだけで、電話の最中でないとは決めない
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _inProgress.value = snapshot.docs.any(_isInProgress);
  }

  void _stopCalls() {
    _callsSubscription?.cancel();
    _callsSubscription = null;
    _personId = null;
  }

  void _stop() {
    _personSubscription?.cancel();
    _personSubscription = null;
    _stopCalls();
  }

  void _report(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'kazokuai data',
        context: ErrorDescription('電話の最中かを Firestore から読んでいるとき'),
      ),
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _stop();
    _inProgress.dispose();
  }
}

bool _isInProgress(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final state = doc.data()['state'];
  return state == _ringing || state == _talking;
}
