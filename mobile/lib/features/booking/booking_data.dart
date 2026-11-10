import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/features/home/home_format.dart';

// 予約の画面が「今」を読む時計。テストは決めた時刻に差し替える。
final bookingNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// その日の 0 時。カレンダーの今日。
DateTime bookingDay(DateTime now) => DateTime(now.year, now.month, now.day);

// 今から 30 日先の日付。その日のうち、今から 30 日を過ぎる時刻は選べない。
DateTime bookingLastDay(DateTime now) {
  final end = now.add(const Duration(days: 30));
  return DateTime(end.year, end.month, end.day);
}

// バックエンドの時刻の決まりと同じ。今から 1 分よりあと、30 日先まで。
// 1 分ちょうどと、30 日より先は選べない。
bool canBookAt(DateTime at, DateTime now) =>
    at.isAfter(now.add(const Duration(minutes: 1))) &&
    !at.isAfter(now.add(const Duration(days: 30)));

class BookedCall {
  const BookedCall({
    required this.id,
    required this.at,
    required this.message,
    required this.script,
    this.called = false,
  });

  // Firestore のドキュメント ID
  final String id;

  final DateTime at;

  // 伝えたいこと
  final String message;

  // 通話内容
  final String script;

  // かけたあとの予約は、これからの一覧に出さない
  final bool called;
}

// 使い方の案内で、これからの予約がまだないときに出す見本。モックの BOOKED。
// 案内が終わると出さない。日付の「今日」は、この見本の日で書く。
final sampleBookingDay = DateTime(2026, 11, 5);

final sampleBookedCalls = [
  BookedCall(
    id: 'noon',
    at: DateTime(2026, 11, 5, 12),
    message: '話し相手',
    script: '「ハナさん、こんにちは。\n体調はいかがですか。」',
  ),
  BookedCall(
    id: 'evening',
    at: DateTime(2026, 11, 5, 19),
    message: '薬と戸締まりの確認',
    script: '「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」',
  ),
  BookedCall(
    id: 'weekend',
    at: DateTime(2026, 11, 7, 10),
    message: '週末に帰ると伝える',
    script: '「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」',
  ),
];

// まだかけていない、今よりあとの予約を時刻の順に並べる。
List<BookedCall> upcomingBookings(List<BookedCall> bookings, DateTime now) {
  final upcoming = [
    for (final booking in bookings)
      if (!booking.called && booking.at.isAfter(now)) booking,
  ];
  upcoming.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    if (byTime != 0) return byTime;
    return a.id.compareTo(b.id);
  });
  return upcoming;
}

class RetryRule {
  const RetryRule({required this.interval, required this.attempts});

  static const intervalChoices = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];
  static const attemptChoices = [1, 2, 3];

  // 「その他」で入れられる範囲。電話機が従うルールはここまで
  static const minimumMinutes = 1;
  static const maximumMinutes = 120;
  static const minimumAttempts = 1;
  static const maximumAttempts = 10;

  // 朝 9:00 の電話を例にした、流れの文の起点
  static final flowExampleStart = DateTime(2026, 11, 5, 9);

  final Duration interval;

  // 最初の 1 回をふくむ
  final int attempts;

  // 間隔はいつも分で書く。90分は「90分」
  static String intervalLabel(Duration interval) => '${interval.inMinutes}分';

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

  // 07 の流れの下に出す文。1 回のときは、かけた時刻と同じ時刻に通知する
  String get flowSentence {
    final start = formatTime(flowExampleStart);
    final notify = formatTime(attemptTimes(flowExampleStart).last);
    if (attempts == 1) {
      return '$startに1回かけて、出なければ$notifyに家族に通知します。';
    }
    return '$startから${intervalLabel(interval)}おきに$attempts回かけて、出なければ$notifyに家族に通知します。';
  }

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

// 08:30。予約の一覧と 06b の欄
String formatPickTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

// 8:30。01 の日時と 01b は、モックのとおり時を 0 埋めしない
String formatSheetTime(int hour, int minute) =>
    '$hour:${minute.toString().padLeft(2, '0')}';

// 今日 12:00。今日と別の日なら 11/7 10:00
String formatBookedAt(DateTime at, {required DateTime today}) {
  final day = bookingDay(today);
  final isToday =
      at.year == day.year && at.month == day.month && at.day == day.day;
  final label = isToday ? '今日' : '${at.month}/${at.day}';
  return '$label ${formatPickTime(at.hour, at.minute)}';
}
