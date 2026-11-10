import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

// 予約の一覧と保存を、テストが直接決める。読み終えた空の一覧から始まる。
class FakeBookingsRepository implements BookingsRepository {
  FakeBookingsRepository({List<BookedCall>? bookings, this.failure})
    : bookings = ValueNotifier(
        bookings == null ? <BookedCall>[] : List<BookedCall>.of(bookings),
      );

  @override
  final ValueNotifier<List<BookedCall>?> bookings;

  // 次の保存か直しで投げる。null なら一覧を更新する。
  Object? failure;

  final List<BookedCall> created = [];
  final List<BookedCall> edited = [];
  var _next = 0;

  @override
  Future<void> create({
    required DateTime at,
    required String message,
    required String script,
  }) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    final booking = BookedCall(
      id: 'saved-$_next',
      at: at,
      message: message,
      script: script,
    );
    _next++;
    created.add(booking);
    bookings.value = [...?bookings.value, booking];
  }

  @override
  Future<void> edit({
    required String id,
    required DateTime at,
    required String message,
    required String script,
  }) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    final booking = BookedCall(
      id: id,
      at: at,
      message: message,
      script: script,
    );
    edited.add(booking);
    bookings.value = [
      for (final current in bookings.value ?? const <BookedCall>[])
        if (current.id == id) booking else current,
    ];
  }
}

// 予約がまだない。案内のあいだだけ、見本が出る。
Override emptyBookings() =>
    bookingsRepositoryProvider.overrideWithValue(FakeBookingsRepository());

// モックの 3 件を、これからの予約として渡す。見本の日より前の時計と組む。
Override sampleBookings([FakeBookingsRepository? repository]) =>
    bookingsRepositoryProvider.overrideWithValue(
      repository ?? FakeBookingsRepository(bookings: sampleBookedCalls),
    );

// 予約の画面が読む時計。省略すると、見本の基準日。
Override mockBookingNow([DateTime? now]) =>
    bookingNowProvider.overrideWithValue(() => now ?? sampleBookingDay);
