const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

String weekdayLabel(DateTime date) => _weekdays[date.weekday - 1];

// 9:02
String formatTime(DateTime date) =>
    '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

// 11月5日(木)
String formatMonthDayWeekday(DateTime date) =>
    '${date.month}月${date.day}日(${weekdayLabel(date)})';
