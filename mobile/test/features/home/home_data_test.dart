import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/home/home_format.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

void main() {
  test('今日の様子の本人の言葉に鍵括弧はない', () {
    expect(
      sampleHomeData.latestCall.summary.conditions.map((item) => item.quote),
      ['朝ごはんも食べたしね', 'よく眠れたよ', '昨日の夕方から膝が痛くてね'],
    );
  });

  test('日時をモックの形で書く', () {
    expect(formatTime(sampleHomeData.latestCall.startedAt), '9:02');
    expect(formatMonthDayWeekday(sampleHomeData.now), '11月5日(木)');
  });
}
