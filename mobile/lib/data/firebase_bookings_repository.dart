import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/data/bookings_source.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

// 予約を Firestore から読み、保存と直しはバックエンドへ送る。ここでは Firestore に書かない。
class FirebaseBookingsRepository
    with WidgetsBindingObserver
    implements BookingsRepository {
  FirebaseBookingsRepository({
    required FirebaseAuth auth,
    required this._firestore,
    required this._backend,
    DateTime Function()? now,
    this._binding,
  }) : _auth = auth,
       _now = now ?? DateTime.now {
    _binding?.addObserver(this);
    _authSubscription = auth.authStateChanges().listen(_watch);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Backend _backend;
  final DateTime Function() _now;
  final WidgetsBinding? _binding;
  final _bookings = ValueNotifier<List<BookedCall>?>(null);
  late final StreamSubscription<User?> _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _personSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _bookingsSubscription;
  Timer? _refresh;
  String? _personId;

  @override
  ValueListenable<List<BookedCall>?> get bookings => _bookings;

  @override
  Future<void> create({
    required DateTime at,
    required String message,
    required String script,
  }) async {
    final idToken = await _idToken();
    await _backend.createBooking(
      idToken: idToken,
      at: at,
      message: message,
      script: script,
    );
  }

  @override
  Future<void> edit({
    required String id,
    required DateTime at,
    required String message,
    required String script,
  }) async {
    final idToken = await _idToken();
    await _backend.editBooking(
      idToken: idToken,
      id: id,
      at: at,
      message: message,
      script: script,
    );
  }

  Future<String> _idToken() async {
    final String? idToken;
    try {
      idToken = await _auth.currentUser?.getIdToken();
    } on FirebaseAuthException {
      throw const BookingFailedException();
    }
    if (idToken == null) throw const BookingFailedException();
    return idToken;
  }

  void _watch(User? user) {
    _stop();
    _bookings.value = null;
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
      _stopBookings();
      _bookings.value = null;
      return;
    }
    final doc = snapshot.docs.first;
    if (_personId == doc.id) return;
    _personId = doc.id;
    _bookingsSubscription?.cancel();
    _bookingsSubscription = doc.reference
        .collection('bookings')
        .snapshots(includeMetadataChanges: true)
        .listen(_onBookings, onError: _report);
  }

  void _onBookings(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // 空のキャッシュだけで、予約がまだないと決めない
    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
    _bookings.value = [
      for (final doc in snapshot.docs) bookedCallFrom(doc.id, doc.data()),
    ].whereType<BookedCall>().toList();
    _armRefresh();
  }

  // バックグラウンドから戻ったとき。過ぎた予約を一覧から外す
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _republish();
  }

  // 次の予約の時刻か深夜に、一覧を出し直して「これからの予約」を計算し直す
  void _armRefresh() {
    _refresh?.cancel();
    final now = _now();
    var next = DateTime(now.year, now.month, now.day + 1);
    for (final booking in _bookings.value ?? const <BookedCall>[]) {
      if (booking.at.isAfter(now) && booking.at.isBefore(next)) {
        next = booking.at;
      }
    }
    var delay = next.difference(now);
    if (delay <= Duration.zero) delay = const Duration(milliseconds: 1);
    _refresh = Timer(delay, _republish);
  }

  void _republish() {
    final current = _bookings.value;
    if (current == null) return;
    _bookings.value = List<BookedCall>.of(current);
    _armRefresh();
  }

  void _stopBookings() {
    _refresh?.cancel();
    _refresh = null;
    _bookingsSubscription?.cancel();
    _bookingsSubscription = null;
    _personId = null;
  }

  void _stop() {
    _personSubscription?.cancel();
    _personSubscription = null;
    _stopBookings();
  }

  void _report(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'kazokuai data',
        context: ErrorDescription('予約を Firestore から読んでいるとき'),
      ),
    );
  }

  void dispose() {
    _refresh?.cancel();
    _binding?.removeObserver(this);
    _authSubscription.cancel();
    _stop();
    _bookings.dispose();
  }
}
