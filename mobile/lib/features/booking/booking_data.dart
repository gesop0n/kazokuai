import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/features/home/home_format.dart';

// 予約の画面の基準日。端末の時計は使わない
final bookingToday = DateTime(2026, 11, 5);

class BookedCall {
  const BookedCall({
    required this.at,
    required this.message,
    required this.script,
  });

  final DateTime at;

  // 伝えたいこと
  final String message;

  // 通話内容
  final String script;
}

final bookedCallsProvider =
    NotifierProvider<BookedCallsNotifier, List<BookedCall>>(
      BookedCallsNotifier.new,
    );

class BookedCallsNotifier extends Notifier<List<BookedCall>> {
  // モックの BOOKED と同じ内容。日時の順
  @override
  List<BookedCall> build() => [
    BookedCall(
      at: DateTime(2026, 11, 5, 12, 0),
      message: '話し相手',
      script: '「ハナさん、こんにちは。\n体調はいかがですか。」',
    ),
    BookedCall(
      at: DateTime(2026, 11, 5, 19, 0),
      message: '薬と戸締まりの確認',
      script: '「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」',
    ),
    BookedCall(
      at: DateTime(2026, 11, 7, 10, 0),
      message: '週末に帰ると伝える',
      script: '「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」',
    ),
  ];

  // 日時の順の場所に足す。同じ日時の予約がすでにあるときは、その後ろに入る
  void add({
    required DateTime at,
    required String message,
    required String script,
  }) {
    final booking = BookedCall(at: at, message: message, script: script);
    final index = state.indexWhere((call) => call.at.isAfter(at));
    state = index < 0
        ? [...state, booking]
        : [...state.sublist(0, index), booking, ...state.sublist(index)];
  }
}

class RetryRule {
  const RetryRule({required this.interval, required this.attempts});

  static const intervalChoices = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];
  static const attemptChoices = [1, 2, 3];

  // 「入力」で入れられる範囲。電話機が従うルールはここまで
  static const minimumMinutes = 1;
  static const maximumMinutes = 60;
  static const minimumAttempts = 1;
  static const maximumAttempts = 5;

  final Duration interval;

  // 最初の 1 回をふくむ
  final int attempts;

  // 45分。60分は1時間
  static String intervalLabel(Duration interval) => interval.inMinutes < 60
      ? '${interval.inMinutes}分'
      : '${interval.inHours}時間';

  // 空、整数でない、範囲の外は null
  static int? minutesInRange(String text) =>
      _inRange(text, minimum: minimumMinutes, maximum: maximumMinutes);

  static int? attemptsInRange(String text) =>
      _inRange(text, minimum: minimumAttempts, maximum: maximumAttempts);

  static int? _inRange(
    String text, {
    required int minimum,
    required int maximum,
  }) {
    final value = int.tryParse(text.trim());
    if (value == null || value < minimum || value > maximum) return null;
    return value;
  }

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
      const RetryRule(interval: Duration(minutes: 10), attempts: 3);

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
