import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/home/home_format.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

void main() {
  test('サンプルの7日間はモックの数字と一致する', () {
    final week = sampleHomeData.week;

    expect(week.days, hasLength(7));
    expect(week.answeredDays, 6);
    expect(week.totalTalkedMinutes, 103);
  });

  test('サンプルの曜日はモックと一致する', () {
    expect(sampleHomeData.week.days.map((day) => weekdayLabel(day.date)), [
      '金',
      '土',
      '日',
      '月',
      '火',
      '水',
      '木',
    ]);
  });

  test('日時をモックの形で書く', () {
    expect(formatTime(sampleHomeData.latestCall.startedAt), '9:02');
    expect(formatMonthDayWeekday(sampleHomeData.now), '11月5日(木)');
  });
}
