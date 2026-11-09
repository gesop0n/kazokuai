import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/features/home/home_format.dart';

// 予約の画面の基準日。端末の時計は使わない
final bookingToday = DateTime(2026, 11, 5);

// 選べる期間の終わりはモックにないので、基準日の 1 年後にする
final bookingLastDate = DateTime(2027, 11, 5);

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

  // 日時の順の場所に足す
  void add({
    required DateTime at,
    required String message,
    required String script,
  }) {
    state = _insertByTime(
      state,
      BookedCall(at: at, message: message, script: script),
    );
  }

  // 伝えたいことと日時を入れ替える。通話内容はそのまま。
  // 日時が同じなら並びは動かさない。変わるときは日時の順の場所へ移す。
  void update(int index, {required DateTime at, required String message}) {
    final current = state[index];
    final updated = BookedCall(
      at: at,
      message: message,
      script: current.script,
    );
    if (current.at == at) {
      state = [
        for (var i = 0; i < state.length; i++) i == index ? updated : state[i],
      ];
      return;
    }
    final rest = [
      for (var i = 0; i < state.length; i++)
        if (i != index) state[i],
    ];
    state = _insertByTime(rest, updated);
  }

  // 同じ日時の予約がすでにあるときは、その後ろに入る
  List<BookedCall> _insertByTime(List<BookedCall> calls, BookedCall booking) {
    final index = calls.indexWhere((call) => call.at.isAfter(booking.at));
    if (index < 0) return [...calls, booking];
    return [...calls.sublist(0, index), booking, ...calls.sublist(index)];
  }
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

// 今日 12:00。基準日と別の日なら 11/7 10:00
String formatBookedAt(DateTime at) {
  final isToday =
      at.year == bookingToday.year &&
      at.month == bookingToday.month &&
      at.day == bookingToday.day;
  final day = isToday ? '今日' : '${at.month}/${at.day}';
  return '$day ${formatPickTime(at.hour, at.minute)}';
}
