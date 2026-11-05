import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/booking/booking_data.dart';

void main() {
  group('RetryRule.summary', () {
    test('モックの初期値は「15分おきに3回かけて、家族に通知」', () {
      const rule = RetryRule(interval: Duration(minutes: 15), attempts: 3);

      expect(rule.summary, '15分おきに3回かけて、家族に通知');
    });

    test('間隔と回数が文に入る', () {
      const rule = RetryRule(interval: Duration(hours: 1), attempts: 5);

      expect(rule.summary, '1時間おきに5回かけて、家族に通知');
    });

    test('1 回のときは間隔を書かない', () {
      const rule = RetryRule(interval: Duration(minutes: 30), attempts: 1);

      expect(rule.summary, '1回かけて、家族に通知');
    });
  });

  group('RetryRule.intervalLabel', () {
    test('選択肢の文字はモックのとおり', () {
      expect(RetryRule.intervalChoices.map(RetryRule.intervalLabel), [
        '10分',
        '15分',
        '30分',
        '1時間',
      ]);
    });
  });

  group('RetryRule.attemptTimes', () {
    final first = DateTime(2026, 11, 5, 9);

    test('最初の回から間隔ごとに進む', () {
      const rule = RetryRule(interval: Duration(minutes: 15), attempts: 3);

      expect(rule.attemptTimes(first), [
        DateTime(2026, 11, 5, 9),
        DateTime(2026, 11, 5, 9, 15),
        DateTime(2026, 11, 5, 9, 30),
      ]);
    });

    test('1 回なら最初の回だけ', () {
      const rule = RetryRule(interval: Duration(hours: 1), attempts: 1);

      expect(rule.attemptTimes(first), [DateTime(2026, 11, 5, 9)]);
    });

    test('1 時間おきに 5 回なら 13 時まで', () {
      const rule = RetryRule(interval: Duration(hours: 1), attempts: 5);

      expect(rule.attemptTimes(first).last, DateTime(2026, 11, 5, 13));
    });
  });

  group('日時の書き方', () {
    test('日付の欄は 11/6(金)', () {
      expect(formatPickDate(DateTime(2026, 11, 6)), '11/6(金)');
      expect(formatPickDate(DateTime(2026, 12, 25)), '12/25(金)');
    });

    test('時刻の欄は 2 桁に揃える', () {
      expect(formatPickTime(8, 30), '08:30');
      expect(formatPickTime(19, 5), '19:05');
    });

    test('基準日の予約は「今日」と書く', () {
      expect(formatBookedAt(DateTime(2026, 11, 5, 12)), '今日 12:00');
      expect(formatBookedAt(DateTime(2026, 11, 5, 8, 30)), '今日 08:30');
    });

    test('基準日と別の日は月と日で書く', () {
      expect(formatBookedAt(DateTime(2026, 11, 7, 10)), '11/7 10:00');
      expect(formatBookedAt(DateTime(2027, 11, 5, 10)), '11/5 10:00');
    });
  });

  group('Provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('予約の初期値はモックの 3 件', () {
      final calls = container.read(bookedCallsProvider);

      expect(calls.map((call) => call.title), ['昼の電話', '夜の電話', '週末に帰ると伝える']);
      expect(calls.map((call) => call.detail), [
        '話し相手 ・ 毎日',
        '薬と戸締まりの確認 ・ 毎日',
        '1回だけ',
      ]);
      expect(calls.map((call) => formatBookedAt(call.at)), [
        '今日 12:00',
        '今日 19:00',
        '11/7 10:00',
      ]);
    });

    test('addOnce は「1回だけ」の予約を最後に足す', () {
      final at = DateTime(2026, 11, 6, 8, 30);
      container
          .read(bookedCallsProvider.notifier)
          .addOnce(at: at, message: '通院の日です');

      final calls = container.read(bookedCallsProvider);
      expect(calls, hasLength(4));
      expect(calls.last.at, at);
      expect(calls.last.title, '通院の日です');
      expect(calls.last.detail, '1回だけ');
    });

    test('ルールの初期値は 15 分おきに 3 回', () {
      final rule = container.read(retryRuleProvider);

      expect(rule.interval, const Duration(minutes: 15));
      expect(rule.attempts, 3);
    });

    test('save でルールが変わる', () {
      container
          .read(retryRuleProvider.notifier)
          .save(const RetryRule(interval: Duration(hours: 1), attempts: 2));

      expect(container.read(retryRuleProvider).summary, '1時間おきに2回かけて、家族に通知');
    });
  });
}
