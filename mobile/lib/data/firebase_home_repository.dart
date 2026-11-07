import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/home_source.dart';
import 'package:kazokuai/features/home/home_data.dart';

// ホームに出す見守る方と電話を Firestore から読む。アプリは Firestore に何も書かない。
// いるかどうかの監視は変えず、ホームに必要な名前と電話だけをここで読む
class FirebaseHomeRepository implements HomeRepository {
  FirebaseHomeRepository({
    required FirebaseAuth auth,
    required this._firestore,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _authSubscription = auth.authStateChanges().listen(_watch);
  }

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;
  final _view = ValueNotifier<HomeView?>(null);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSubscription;
  String? _personId;
  Map<String, dynamic>? _person;
  List<Map<String, dynamic>>? _calls;

  @override
  ValueListenable<HomeView?> get view => _view;

  void _watch(User? user) {
    _stop();
    _view.value = null;
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
      _view.value = null;
      return;
    }
    final doc = snapshot.docs.first;
    _person = doc.data();
    if (_personId == doc.id) {
      _publish();
      return;
    }
    _personId = doc.id;
    _calls = null;
    _callsSubscription?.cancel();
    _callsSubscription = doc.reference
        .collection('calls')
        .snapshots(includeMetadataChanges: true)
        .listen(_onCalls, onError: _report);
  }

  void _onCalls(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // 空のキャッシュだけで、電話がまだないと決めない
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _calls = [for (final doc in snapshot.docs) doc.data()];
    _publish();
  }

  void _publish() {
    final person = _person;
    final calls = _calls;
    if (person == null || calls == null) return;
    _view.value = homeViewFrom(person: person, calls: calls, now: _now());
  }

  void _stopCalls() {
    _callsSubscription?.cancel();
    _callsSubscription = null;
    _personId = null;
    _person = null;
    _calls = null;
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
        context: ErrorDescription('ホームの電話を Firestore から読んでいるとき'),
      ),
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _stop();
    _view.dispose();
  }
}
