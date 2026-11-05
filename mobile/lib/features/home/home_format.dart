const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

String weekdayLabel(DateTime date) => _weekdays[date.weekday - 1];

// 9:02
String formatTime(DateTime date) =>
    '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

// 今日、昨日。それ以外の日なら 11月4日
String formatRelativeDay(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  if (day == DateTime(now.year, now.month, now.day)) return '今日';
  if (day == DateTime(now.year, now.month, now.day - 1)) return '昨日';
  return '${date.month}月${date.day}日';
}

// 11月5日(木)
String formatMonthDayWeekday(DateTime date) =>
    '${date.month}月${date.day}日(${weekdayLabel(date)})';
