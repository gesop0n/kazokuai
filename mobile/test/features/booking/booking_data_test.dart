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

      expect(calls.map((call) => call.message), [
        '話し相手',
        '薬と戸締まりの確認',
        '週末に帰ると伝える',
      ]);
      expect(calls.map((call) => call.script), [
        '「ハナさん、こんにちは。\n体調はいかがですか。」',
        '「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」',
        '「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」',
      ]);
      expect(calls.map((call) => formatBookedAt(call.at)), [
        '今日 12:00',
        '今日 19:00',
        '11/7 10:00',
      ]);
    });

    test('add は日時の順に合う場所へ足す', () {
      final notifier = container.read(bookedCallsProvider.notifier);

      notifier.add(
        at: DateTime(2026, 11, 6, 8, 30),
        message: '通院の日です',
        script: '「ハナさん、美咲さんからご伝言です。」',
      );
      notifier.add(
        at: DateTime(2026, 11, 5, 8, 30),
        message: '朝に伝える',
        script: '「ハナさん、おはようございます。」',
      );
      notifier.add(
        at: DateTime(2026, 11, 8, 9),
        message: '翌週に伝える',
        script: '「ハナさん、来週です。」',
      );
      notifier.add(
        at: DateTime(2026, 11, 5, 12),
        message: '昼にもう一件',
        script: '「ハナさん、昼です。」',
      );

      final calls = container.read(bookedCallsProvider);
      expect(calls.map((call) => call.message), [
        '朝に伝える',
        '話し相手',
        '昼にもう一件',
        '薬と戸締まりの確認',
        '通院の日です',
        '週末に帰ると伝える',
        '翌週に伝える',
      ]);
      expect(
        calls.firstWhere((call) => call.message == '通院の日です').script,
        '「ハナさん、美咲さんからご伝言です。」',
      );
      expect(
        calls.firstWhere((call) => call.message == '昼にもう一件').at,
        DateTime(2026, 11, 5, 12),
      );
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
