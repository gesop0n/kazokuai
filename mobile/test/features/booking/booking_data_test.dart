import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/booking/booking_data.dart';

void main() {
  group('RetryRule.summary', () {
    test('既定は「15分おきに3回かけて、家族に通知」', () {
      const rule = RetryRule(interval: Duration(minutes: 15), attempts: 3);

      expect(rule.summary, '15分おきに3回かけて、家族に通知');
    });

    test('間隔は 60 分を超えても分で書く', () {
      const rule = RetryRule(interval: Duration(minutes: 90), attempts: 4);

      expect(rule.summary, '90分おきに4回かけて、家族に通知');
    });

    test('1 時間も 60分と書く', () {
      const rule = RetryRule(interval: Duration(hours: 1), attempts: 2);

      expect(rule.summary, '60分おきに2回かけて、家族に通知');
    });

    test('1 回のときは間隔を書かない', () {
      const rule = RetryRule(interval: Duration(minutes: 30), attempts: 1);

      expect(rule.summary, '1回かけて、家族に通知');
    });
  });

  group('RetryRule.flowSentence', () {
    test('3 回までは間隔と、最後の回の時刻を書く', () {
      const rule = RetryRule(interval: Duration(minutes: 15), attempts: 3);

      expect(rule.flowSentence, '9:00から15分おきに3回かけて、出なければ9:30に家族に通知します。');
    });

    test('1 回のときは同じ時刻に通知する', () {
      const rule = RetryRule(interval: Duration(minutes: 30), attempts: 1);

      expect(rule.flowSentence, '9:00に1回かけて、出なければ9:00に家族に通知します。');
    });

    test('90 分は時間にせず、最後の回の時刻を書く', () {
      const rule = RetryRule(interval: Duration(minutes: 90), attempts: 4);

      expect(rule.flowSentence, '9:00から90分おきに4回かけて、出なければ13:30に家族に通知します。');
    });
  });

  group('RetryRule の選択肢', () {
    test('間隔は 5分、10分、15分、30分', () {
      expect(RetryRule.intervalChoices.map(RetryRule.intervalLabel), [
        '5分',
        '10分',
        '15分',
        '30分',
      ]);
    });

    test('回数は最初の 1 回をふくめて 1回、2回、3回', () {
      expect(RetryRule.attemptChoices, [1, 2, 3]);
    });
  });

  group('RetryRule の入力できる範囲', () {
    test('分は 1 から 120', () {
      expect(RetryRule.minutesInRange('1'), 1);
      expect(RetryRule.minutesInRange('120'), 120);
      expect(RetryRule.minutesInRange(' 15 '), 15);
      expect(RetryRule.minutesInRange(''), isNull);
      expect(RetryRule.minutesInRange('0'), isNull);
      expect(RetryRule.minutesInRange('121'), isNull);
      expect(RetryRule.minutesInRange('1.5'), isNull);
    });

    test('回数は 1 から 10', () {
      expect(RetryRule.attemptsInRange('1'), 1);
      expect(RetryRule.attemptsInRange('10'), 10);
      expect(RetryRule.attemptsInRange(''), isNull);
      expect(RetryRule.attemptsInRange('0'), isNull);
      expect(RetryRule.attemptsInRange('11'), isNull);
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

    test('01 の日時は時を 0 埋めしない', () {
      expect(formatSheetTime(8, 30), '8:30');
      expect(formatSheetTime(9, 0), '9:00');
      expect(formatSheetTime(19, 5), '19:05');
    });

    test('今日の予約は「今日」と書く', () {
      final today = DateTime(2026, 11, 5, 15);
      expect(
        formatBookedAt(DateTime(2026, 11, 5, 12), today: today),
        '今日 12:00',
      );
      expect(
        formatBookedAt(DateTime(2026, 11, 5, 8, 30), today: today),
        '今日 08:30',
      );
    });

    test('今日と別の日は月と日で書く', () {
      final today = DateTime(2026, 11, 5);
      expect(
        formatBookedAt(DateTime(2026, 11, 7, 10), today: today),
        '11/7 10:00',
      );
      expect(
        formatBookedAt(DateTime(2027, 11, 5, 10), today: today),
        '11/5 10:00',
      );
    });
  });

  group('これからの予約', () {
    final now = DateTime(2026, 11, 10, 15);

    BookedCall booking(
      String id,
      DateTime at, {
      String message = '伝言',
      bool called = false,
    }) => BookedCall(
      id: id,
      at: at,
      message: message,
      script: '「通話内容」',
      called: called,
    );

    test('かけていない、今よりあとの予約だけを時刻の順に並べる', () {
      final upcoming = upcomingBookings([
        booking('later', DateTime(2026, 11, 12, 9), message: 'あと'),
        booking('past', DateTime(2026, 11, 9, 9), message: '前'),
        booking(
          'called',
          DateTime(2026, 11, 11, 9),
          message: 'かけた',
          called: true,
        ),
        booking('soon', DateTime(2026, 11, 10, 18), message: '近い'),
        booking('same', DateTime(2026, 11, 10, 18), message: '同時'),
        booking('now', now, message: 'ちょうど今'),
      ], now);

      expect(upcoming.map((call) => call.id), ['same', 'soon', 'later']);
    });

    test('見本はモックの 3 件で、今日は見本の日', () {
      expect(sampleBookedCalls.map((call) => call.id), [
        'noon',
        'evening',
        'weekend',
      ]);
      expect(sampleBookedCalls.map((call) => call.message), [
        '話し相手',
        '薬と戸締まりの確認',
        '週末に帰ると伝える',
      ]);
      expect(
        sampleBookedCalls.map(
          (call) => formatBookedAt(call.at, today: sampleBookingDay),
        ),
        ['今日 12:00', '今日 19:00', '11/7 10:00'],
      );
    });

    test('今から 1 分よりあと、30 日先まで予約できる', () {
      expect(canBookAt(now.add(const Duration(minutes: 1)), now), isFalse);
      expect(
        canBookAt(now.add(const Duration(minutes: 1, seconds: 1)), now),
        isTrue,
      );
      expect(canBookAt(now.add(const Duration(days: 30)), now), isTrue);
      expect(
        canBookAt(now.add(const Duration(days: 30, seconds: 1)), now),
        isFalse,
      );
      expect(bookingDay(now), DateTime(2026, 11, 10));
      expect(bookingLastDay(now), DateTime(2026, 12, 10));
    });
  });

  group('Provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('ルールの初期値は 15 分おきに 3 回', () {
      final rule = container.read(retryRuleProvider);

      expect(rule.interval, const Duration(minutes: 15));
      expect(rule.attempts, 3);
      expect(rule.summary, '15分おきに3回かけて、家族に通知');
    });

    test('save でルールが変わる', () {
      container
          .read(retryRuleProvider.notifier)
          .save(const RetryRule(interval: Duration(minutes: 90), attempts: 2));

      expect(container.read(retryRuleProvider).summary, '90分おきに2回かけて、家族に通知');
    });
  });
}
