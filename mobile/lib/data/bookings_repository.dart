import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/app_config.dart';
import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_bookings_repository.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

// 予約の一覧と、保存と直し。画面はこれだけを使い、Firebase の型には触れない。
// 一覧は Firestore から読み、保存と直しはバックエンドを通す。
abstract interface class BookingsRepository {
  // まだ読み終えていないときは null。予約が 1 件もなくても、読み終えると空のリスト。
  // かけたあとや、時刻を過ぎたものも入る。これからの分は画面が upcomingBookings で選ぶ。
  ValueListenable<List<BookedCall>?> get bookings;

  // 新しい予約を保存する。時刻の決まりに合わないときと、送れないときは例外を投げる。
  Future<void> create({
    required DateTime at,
    required String message,
    required String script,
  });

  // 予約を直す。伝えたいことが変わったときの通話内容は、画面が先に作り直して渡す。
  Future<void> edit({
    required String id,
    required DateTime at,
    required String message,
    required String script,
  });
}

// 今から 1 分より先ではない
class BookingTooSoonException implements Exception {
  const BookingTooSoonException();

  @override
  String toString() => 'BookingTooSoonException';
}

// 今から 30 日より先
class BookingTooFarException implements Exception {
  const BookingTooFarException();

  @override
  String toString() => 'BookingTooFarException';
}

// 前後 10 分以内に別の予約がある
class BookingTooCloseException implements Exception {
  const BookingTooCloseException();

  @override
  String toString() => 'BookingTooCloseException';
}

// 予約を送れなかった。時刻の決まり以外
class BookingFailedException implements Exception {
  const BookingFailedException();

  @override
  String toString() => 'BookingFailedException';
}

// 家族に出す文。4 つの答え以外は null で、画面は握りつぶさない。
String? bookingFailureMessage(Object error) => switch (error) {
  BookingTooCloseException() => '近い時刻に予約があります',
  BookingTooSoonException() => '早すぎる',
  BookingTooFarException() => '先すぎる',
  BookingFailedException() => '送れなかった',
  _ => null,
};

// テストでは偽物に差し替える
final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  final client = http.Client();
  final repository = FirebaseBookingsRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    backend: Backend(client, baseUrl: appConfig.backendUrl),
    now: () => ref.read(bookingNowProvider)(),
    binding: WidgetsBinding.instance,
  );
  ref.onDispose(() {
    repository.dispose();
    client.close();
  });
  return repository;
});
