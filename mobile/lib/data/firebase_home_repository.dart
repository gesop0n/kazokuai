import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/home_source.dart';
import 'package:kazokuai/features/home/home_data.dart';

// ホームに出す見守る方と電話を Firestore から読む。ホームは Firestore に書かない。
// いるかどうかの監視は変えず、ホームに必要な名前と電話だけをここで読む
class FirebaseHomeRepository
    with WidgetsBindingObserver
    implements HomeRepository {
  FirebaseHomeRepository({
    required FirebaseAuth auth,
    required this._firestore,
    DateTime Function()? now,
    this._binding,
  }) : _now = now ?? DateTime.now {
    _binding?.addObserver(this);
    _authSubscription = auth.authStateChanges().listen(_watch);
  }

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;
  final WidgetsBinding? _binding;
  final _view = ValueNotifier<HomeView?>(null);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSubscription;
  Timer? _dateChange;
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
    _calls = [
      for (final doc in snapshot.docs) {...doc.data(), 'id': doc.id},
    ];
    _publish();
  }

  // バックグラウンドから戻ったとき。日付が変わっていれば今日と 7 日間を直す
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _publish();
  }

  void _publish() {
    final person = _person;
    final calls = _calls;
    if (person == null || calls == null) return;
    _view.value = homeViewFrom(person: person, calls: calls, now: _now());
    _armDateChange();
  }

  // Firestore が静かでも、次の深夜に今日の様子と 7 日間を計算し直す
  void _armDateChange() {
    _dateChange?.cancel();
    final now = _now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    var delay = nextMidnight.difference(now);
    if (delay <= Duration.zero) delay = const Duration(milliseconds: 1);
    _dateChange = Timer(delay, _publish);
  }

  void _stopCalls() {
    _callsSubscription?.cancel();
    _callsSubscription = null;
    _personId = null;
    _person = null;
    _calls = null;
  }

  void _stop() {
    _dateChange?.cancel();
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
    _dateChange?.cancel();
    _binding?.removeObserver(this);
    _authSubscription.cancel();
    _stop();
    _view.dispose();
  }
}
