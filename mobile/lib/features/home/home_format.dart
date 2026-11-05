const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

String weekdayLabel(DateTime date) => _weekdays[date.weekday - 1];

// 9:02
String formatTime(DateTime date) =>
    '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

// 今日。now と別の日なら 11月4日
String formatRelativeDay(DateTime date, DateTime now) =>
    date.year == now.year && date.month == now.month && date.day == now.day
    ? '今日'
    : '${date.month}月${date.day}日';

// 11月5日(木)
String formatMonthDayWeekday(DateTime date) =>
    '${date.month}月${date.day}日(${weekdayLabel(date)})';
