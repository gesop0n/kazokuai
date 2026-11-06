import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/features/home/home_format.dart';

// 予約の画面の基準日。端末の時計は使わない
final bookingToday = DateTime(2026, 11, 5);

class BookedCall {
  const BookedCall({
    required this.at,
    required this.title,
    required this.detail,
  });

  final DateTime at;
  final String title;
  final String detail;
}

final bookedCallsProvider =
    NotifierProvider<BookedCallsNotifier, List<BookedCall>>(
      BookedCallsNotifier.new,
    );

class BookedCallsNotifier extends Notifier<List<BookedCall>> {
  // モックの 06 と同じ内容
  @override
  List<BookedCall> build() => [
    BookedCall(
      at: DateTime(2026, 11, 5, 12, 0),
      title: '昼の電話',
      detail: '話し相手 ・ 毎日',
    ),
    BookedCall(
      at: DateTime(2026, 11, 5, 19, 0),
      title: '夜の電話',
      detail: '薬と戸締まりの確認 ・ 毎日',
    ),
    BookedCall(
      at: DateTime(2026, 11, 7, 10, 0),
      title: '週末に帰ると伝える',
      detail: '1回だけ',
    ),
  ];

  void addOnce({required DateTime at, required String message}) {
    state = [...state, BookedCall(at: at, title: message, detail: '1回だけ')];
  }
}

class RetryRule {
  const RetryRule({required this.interval, required this.attempts});

  static const intervalChoices = [
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];
  static const attemptChoices = [1, 2, 3, 5];

  final Duration interval;

  // 最初の 1 回をふくむ
  final int attempts;

  // 15分。1時間
  static String intervalLabel(Duration interval) => interval.inMinutes < 60
      ? '${interval.inMinutes}分'
      : '${interval.inHours}時間';

  // 1 回だけのときは間隔がないので書かない
  String get summary => attempts == 1
      ? '1回かけて、家族に通知'
      : '${intervalLabel(interval)}おきに$attempts回かけて、家族に通知';

  // first を最初の回としたときの、各回の時刻
  List<DateTime> attemptTimes(DateTime first) => [
    for (var i = 0; i < attempts; i++) first.add(interval * i),
  ];

  RetryRule copyWith({Duration? interval, int? attempts}) => RetryRule(
    interval: interval ?? this.interval,
    attempts: attempts ?? this.attempts,
  );
}

final retryRuleProvider = NotifierProvider<RetryRuleNotifier, RetryRule>(
  RetryRuleNotifier.new,
);

class RetryRuleNotifier extends Notifier<RetryRule> {
  @override
  RetryRule build() =>
      const RetryRule(interval: Duration(minutes: 15), attempts: 3);

  void save(RetryRule rule) => state = rule;
}

// 11/6(金)
String formatPickDate(DateTime date) =>
    '${date.month}/${date.day}(${weekdayLabel(date)})';

// 08:30
String formatPickTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

// 今日 12:00。基準日と別の日なら 11/7 10:00
String formatBookedAt(DateTime at) {
  final isToday =
      at.year == bookingToday.year &&
      at.month == bookingToday.month &&
      at.day == bookingToday.day;
  final day = isToday ? '今日' : '${at.month}/${at.day}';
  return '$day ${formatPickTime(at.hour, at.minute)}';
}
