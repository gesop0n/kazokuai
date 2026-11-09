import 'package:flutter/material.dart';

import 'package:kazokuai/features/calls/calls_data.dart';

// モックの「よく電話に出る時刻」は 3 つ
const usualAnswerTimeCount = 3;

const _stepMinutes = 5;

// 回転式は 5 分ごとなので、始まった時刻を近い 5 分に寄せる。9:02 は 9:00。
TimeOfDay snapToFiveMinutes(int hour, int minute) {
  final total = hour * 60 + minute;
  final snapped = ((total + _stepMinutes ~/ 2) ~/ _stepMinutes) * _stepMinutes;
  final inDay = snapped % (24 * 60);
  return TimeOfDay(hour: inDay ~/ 60, minute: inDay % 60);
}

// 出た電話の始まった時刻で多いものから、モックの数まで。
// 同じ数のときは、一日の早い時刻を先にする。
// 読み終えていないときと、出た電話がないときは空で、ボタンは出さない。
List<TimeOfDay> usualAnswerTimes(CallLog? log) {
  if (log == null) return const [];
  final counts = <int, int>{};
  for (final day in log.days) {
    for (final entry in day.answeredEntries) {
      final time = snapToFiveMinutes(
        entry.startedAt.hour,
        entry.startedAt.minute,
      );
      final key = time.hour * 60 + time.minute;
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return [
    for (final entry in ranked.take(usualAnswerTimeCount))
      TimeOfDay(hour: entry.key ~/ 60, minute: entry.key % 60),
  ];
}
