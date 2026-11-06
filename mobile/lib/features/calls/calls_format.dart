import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

// 11月3日
String formatMonthDay(DateTime date) => '${date.month}月${date.day}日';

// 2026年11月
String formatYearMonth(DateTime date) => '${date.year}年${date.month}月';

// 今日 11月5日(木)。今日でなければ 11月4日(水)
String formatDayHeading(DateTime date, DateTime today) {
  final heading = formatMonthDayWeekday(date);
  return date == today ? '今日 $heading' : heading;
}

// 2回 ・ 12分。電話に出なかった日は 不在
String formatDayTotal(CallLogDay day) {
  final answered = day.answeredEntries;
  if (answered.isEmpty) return '不在';
  final minutes = answered.fold(
    0,
    (total, entry) => total + entry.duration.inMinutes,
  );
  return '${answered.length}回 ・ $minutes分';
}

// 1:03
String formatElapsed(Duration elapsed) =>
    '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

// 11/5 9:02 ・ 6分12秒
String formatCallStamp(DateTime startedAt, Duration duration) =>
    '${startedAt.month}/${startedAt.day} ${formatTime(startedAt)} ・ '
    '${duration.inMinutes}分${duration.inSeconds % 60}秒';
