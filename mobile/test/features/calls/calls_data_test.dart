import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/sample_calls_data.dart';

void main() {
  group('サンプルの一覧', () {
    test('基準日は 2026年11月5日', () {
      expect(sampleCallLog.today, DateTime(2026, 11, 5));
    });

    test('見出しと合計はモックの文字と同じ', () {
      expect(
        [
          for (final day in sampleCallLog.days)
            (
              formatDayHeading(day.date, sampleCallLog.today),
              formatDayTotal(day),
            ),
        ],
        [
          ('今日 11月5日(木)', '1回 ・ 6分'),
          ('11月4日(水)', '2回 ・ 12分'),
          ('11月3日(火)', '1回 ・ 18分'),
          ('11月2日(月)', '不在'),
          ('11月1日(日)', '1回 ・ 31分'),
          ('10月31日(土)', '1回 ・ 22分'),
        ],
      );
    });

    test('10月23日から10月30日は印はあるが、記録はない', () {
      for (var day = 23; day <= 30; day++) {
        final date = DateTime(2026, 10, day);

        expect(sampleCallLog.markOf(date), DayMark.answered, reason: '$day');
        expect(sampleCallLog.hasRecord(date), isFalse, reason: '$day');
      }
    });

    test('印は電話に出た日、不在の日、印のない日に分かれる', () {
      expect(sampleCallLog.markOf(DateTime(2026, 11, 3)), DayMark.answered);
      expect(sampleCallLog.markOf(DateTime(2026, 11, 2)), DayMark.missed);
      expect(sampleCallLog.markOf(DateTime(2026, 10, 22)), isNull);
      expect(sampleCallLog.markOf(DateTime(2026, 11, 6)), isNull);
    });
  });

  group('サンプルの詳細', () {
    test('まとめの時刻は、どれも会話の発言にある', () {
      final spokenAt = sampleCallDetail.utterances.map((u) => u.at).toSet();

      for (final point in sampleCallDetail.points) {
        expect(spokenAt, contains(point.at), reason: point.text);
      }
    });

    test('発言は時刻の順に並び、同じ時刻が重ならない', () {
      final times = sampleCallDetail.utterances.map((u) => u.at).toList();

      expect(times.toSet(), hasLength(times.length));
      expect(times, [...times]..sort());
    });

    test('4:12 の発言はハナさんで、まとめと矛盾しない', () {
      final utterance = sampleCallDetail.utterances.firstWhere(
        (u) => u.at == const Duration(minutes: 4, seconds: 12),
      );

      expect(utterance.speaker, Speaker.parent);
      expect(utterance.text, '飲んだよ。');
    });

    test('気になる発言は 1:03 だけ', () {
      expect(
        sampleCallDetail.utterances.where((u) => u.needsAttention).single.at,
        const Duration(minutes: 1, seconds: 3),
      );
    });
  });

  group('書式', () {
    test('経過時間は分と 2 桁の秒', () {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 11)), '0:11');
      expect(formatElapsed(const Duration(minutes: 4, seconds: 12)), '4:12');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 3)), '12:03');
    });

    test('詳細の日時はモックの文字と同じ', () {
      expect(
        formatCallStamp(sampleCallDetail.startedAt, sampleCallDetail.duration),
        '11/5 9:02 ・ 6分12秒',
      );
    });

    test('年月と月日', () {
      expect(formatYearMonth(DateTime(2026, 11, 5)), '2026年11月');
      expect(formatMonthDay(DateTime(2026, 11, 3)), '11月3日');
    });
  });
}
