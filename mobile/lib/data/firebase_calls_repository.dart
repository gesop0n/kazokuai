import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/data/calls_source.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

// 通話記録と電話の詳細を Firestore から読む。アプリは Firestore に何も書かない
class FirebaseCallsRepository
    with WidgetsBindingObserver
    implements CallsRepository {
  FirebaseCallsRepository({
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
  final _log = ValueNotifier<CallLog?>(null);
  final _detail = ValueNotifier<CallDetail?>(null);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _utteranceSubscription;
  Timer? _dateChange;
  String? _personId;
  Map<String, dynamic>? _person;
  List<CallDocument>? _calls;
  String? _openCallId;
  bool _callReady = false;
  bool _utterancesReady = false;
  Map<String, dynamic>? _openCall;
  List<Map<String, dynamic>>? _openUtterances;

  @override
  ValueListenable<CallLog?> get log => _log;

  @override
  ValueListenable<CallDetail?> get detail => _detail;

  void _watch(User? user) {
    _stop();
    // 開く操作が最初の認証通知より先でも、その電話は残す。サインアウトでは閉じる
    if (user == null) _openCallId = null;
    _log.value = null;
    _detail.value = null;
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
      _log.value = null;
      _detail.value = null;
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
    _listenDetail();
  }

  void _onCalls(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // 空のキャッシュだけで、電話がまだないと決めない
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _calls = [
      for (final doc in snapshot.docs)
        CallDocument(id: doc.id, data: doc.data()),
    ];
    _publish();
  }

  @override
  void open(String callId) {
    _openCallId = callId;
    _detail.value = null;
    _listenDetail();
  }

  @override
  void close() {
    _openCallId = null;
    _stopDetail();
  }

  void _listenDetail() {
    _stopDetail();
    _callReady = false;
    _utterancesReady = false;
    _openCall = null;
    _openUtterances = null;
    final personId = _personId;
    final callId = _openCallId;
    if (personId == null || callId == null) return;
    final ref = _firestore
        .collection('watchedPersons')
        .doc(personId)
        .collection('calls')
        .doc(callId);
    _callSubscription = ref
        .snapshots(includeMetadataChanges: true)
        .listen(_onCall, onError: _report);
    _utteranceSubscription = ref
        .collection('utterances')
        .snapshots(includeMetadataChanges: true)
        .listen(_onUtterances, onError: _report);
  }

  void _onCall(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists && snapshot.metadata.isFromCache) return;
    _callReady = true;
    _openCall = snapshot.data();
    _publishDetail();
  }

  void _onUtterances(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _utterancesReady = true;
    _openUtterances = [for (final doc in snapshot.docs) doc.data()];
    _publishDetail();
  }

  // バックグラウンドから戻ったとき。日付が変わっていれば「今日」を直す
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _publish();
  }

  void _publish() {
    final calls = _calls;
    if (_person == null || calls == null) return;
    _log.value = callLogFrom(calls: calls, now: _now());
    _publishDetail();
    _armDateChange();
  }

  void _publishDetail() {
    if (!_callReady || !_utterancesReady) return;
    final call = _openCall;
    final utterances = _openUtterances;
    if (call == null || utterances == null || _person == null) {
      _detail.value = null;
      return;
    }
    _detail.value = callDetailFrom(
      callName: _callName,
      call: call,
      utterances: utterances,
    );
  }

  String get _callName {
    final person = _person;
    if (person == null) return '';
    final callName = _string(person['callName']).trim();
    if (callName.isNotEmpty) return callName;
    return _string(person['name']).trim();
  }

  // Firestore が静かでも、次の深夜に「今日」の見出しを計算し直す
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
    _stopDetail();
  }

  void _stopDetail() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _utteranceSubscription?.cancel();
    _utteranceSubscription = null;
    _callReady = false;
    _utterancesReady = false;
    _openCall = null;
    _openUtterances = null;
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
        context: ErrorDescription('通話記録の電話を Firestore から読んでいるとき'),
      ),
    );
  }

  void dispose() {
    _dateChange?.cancel();
    _binding?.removeObserver(this);
    _authSubscription.cancel();
    _stop();
    _log.dispose();
    _detail.dispose();
  }
}

String _string(Object? value) => value is String ? value : '';
