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
  final _subscriptions = <_CallSubscription>{};
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSubscription;
  Timer? _dateChange;
  String? _personId;
  Map<String, dynamic>? _person;
  List<CallDocument>? _calls;

  @override
  ValueListenable<CallLog?> get log => _log;

  // 画面がそれぞれ自分の読み込みを持つ。開いても、ほかの画面には知らせない
  @override
  CallSubscription open(String callId) {
    final subscription = _CallSubscription(this, callId);
    _subscriptions.add(subscription);
    subscription.start();
    return subscription;
  }

  void _watch(User? user) {
    _stop();
    // 開く操作が最初の認証通知より先でも、その読み込みは残す
    _log.value = null;
    for (final subscription in [..._subscriptions]) {
      subscription.clear();
    }
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
      for (final subscription in [..._subscriptions]) {
        subscription.clear();
      }
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
    for (final subscription in [..._subscriptions]) {
      subscription.start();
    }
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

  // バックグラウンドから戻ったとき。日付が変わっていれば「今日」を直す
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _publish();
  }

  void _publish() {
    final calls = _calls;
    if (_person == null || calls == null) return;
    _log.value = callLogFrom(calls: calls, now: _now());
    for (final subscription in [..._subscriptions]) {
      subscription.publish();
    }
    _armDateChange();
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
    for (final subscription in [..._subscriptions]) {
      subscription.pause();
    }
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
    for (final subscription in [..._subscriptions]) {
      subscription.close();
    }
    _log.dispose();
  }
}

// 詳細の画面が 1 つ持つ読み込み。閉じても、ほかの画面の読み込みは残る
class _CallSubscription extends ValueNotifier<CallDetail?>
    implements CallSubscription {
  _CallSubscription(this._repository, this.callId) : super(null);

  final FirebaseCallsRepository _repository;
  final String callId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _utteranceSubscription;
  var _callReady = false;
  var _utterancesReady = false;
  Map<String, dynamic>? _call;
  List<Map<String, dynamic>>? _utterances;
  var _closed = false;

  void start() {
    if (_closed) return;
    pause();
    final personId = _repository._personId;
    if (personId == null) return;
    final ref = _repository._firestore
        .collection('watchedPersons')
        .doc(personId)
        .collection('calls')
        .doc(callId);
    _callSubscription = ref
        .snapshots(includeMetadataChanges: true)
        .listen(_onCall, onError: _repository._report);
    _utteranceSubscription = ref
        .collection('utterances')
        .snapshots(includeMetadataChanges: true)
        .listen(_onUtterances, onError: _repository._report);
  }

  // 見守る方が変わるとき。値はそのままにして、次のスナップショットで入れ直す
  void pause() {
    _cancel();
    _callReady = false;
    _utterancesReady = false;
    _call = null;
    _utterances = null;
  }

  void clear() {
    if (_closed) return;
    pause();
    value = null;
  }

  void publish() {
    if (_closed || !_callReady || !_utterancesReady) return;
    final call = _call;
    final utterances = _utterances;
    if (call == null || utterances == null || _repository._person == null) {
      value = null;
      return;
    }
    value = callDetailFrom(
      callName: _repository._callName,
      call: call,
      utterances: utterances,
    );
  }

  void _onCall(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (_closed) return;
    if (!snapshot.exists && snapshot.metadata.isFromCache) return;
    _callReady = true;
    _call = snapshot.data();
    publish();
  }

  void _onUtterances(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (_closed) return;
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _utterancesReady = true;
    _utterances = [for (final doc in snapshot.docs) doc.data()];
    publish();
  }

  void _cancel() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _utteranceSubscription?.cancel();
    _utteranceSubscription = null;
  }

  // 値は変えない。変えると、画面を外している最中の builder に知らせてしまう
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _cancel();
    _repository._subscriptions.remove(this);
  }
}

String _string(Object? value) => value is String ? value : '';
