import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_call_script_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/layout_matrix.dart';

const _layout = LayoutCase(393, 1.0);

Finder _hourWheel() => find.bySemanticsLabel(RegExp(r'^時$'));

Finder _minuteWheel() => find.bySemanticsLabel(RegExp(r'^分$'));

CallLog _log({
  List<DateTime> answered = const [],
  List<DateTime> missed = const [],
}) {
  if (answered.isEmpty && missed.isEmpty) {
    return CallLog(today: DateTime(2026, 11, 5), days: const []);
  }
  return CallLog(
    today: DateTime(2026, 11, 5),
    days: [
      CallLogDay(
        date: DateTime(2026, 11, 4),
        entries: [
          for (final at in answered)
            AnsweredCallEntry(
              startedAt: at,
              text: '出た',
              duration: const Duration(minutes: 3),
              topic: CallTopic.health,
            ),
          for (final at in missed)
            MissedCallEntry(startedAt: at, text: '電話に出ませんでした'),
        ],
      ),
    ],
  );
}

List<DateTime> _times(List<(int, int, int)> counts) => [
  for (final (hour, minute, count) in counts)
    for (var i = 0; i < count; i++) DateTime(2026, 11, 4, hour, minute),
];

Future<void> _pump(
  WidgetTester tester, {
  LayoutCase layout = _layout,
  CallLog? log,
  FakeCallsRepository? calls,
}) {
  return pumpScreenInLayout(
    tester,
    layout,
    const AskScreen(),
    overrides: [
      callScriptRepositoryProvider.overrideWithValue(
        FakeCallScriptRepository(),
      ),
      idleCallProgress(),
      callsRepositoryProvider.overrideWithValue(
        calls ?? FakeCallsRepository(log: log),
      ),
    ],
  );
}

void _expectWheelHits(WidgetTester tester, Finder wheel) {
  final hits = find.descendant(
    of: wheel,
    matching: find.byType(GestureDetector),
  );
  expect(hits, findsWidgets);
  final count = tester.widgetList(hits).length;
  for (var i = 0; i < count; i++) {
    final size = tester.getSize(hits.at(i));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('日時を選ぶ'));
  await tester.pumpAndSettle();
}

Future<void> _spin(WidgetTester tester, Finder wheel, int index) async {
  // 見えている数個だけが作られるので、目的の位置まで回してから押す。
  // 回転式の Scrollable は非公開の子クラスなので、型の一致では見つからない。
  final scrollable = find.descendant(
    of: wheel,
    matching: find.byWidgetPredicate((widget) => widget is Scrollable),
  );
  final controller =
      tester.widget<Scrollable>(scrollable).controller!
          as FixedExtentScrollController;
  controller.jumpToItem(index);
  await tester.pumpAndSettle();
  await tester.tap(scrollable);
  await tester.pumpAndSettle();
}

void main() {
  group('日時', () {
    testWidgets('日付と時刻の欄の代わりに、日時が 1 つある', (tester) async {
      await _pump(tester, log: _log());

      expect(find.text('日時'), findsOneWidget);
      expect(find.text('11/6(金)'), findsOneWidget);
      expect(find.text('8:30'), findsOneWidget);
      expect(find.text('日付'), findsNothing);
      expect(find.text('時刻'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('日時を選ぶ')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
    });

    testEachLayout('シートを開いても崩れない', (tester, layout) async {
      await _pump(tester, layout: layout, log: _log());

      await _open(tester);

      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('時刻'), findsOneWidget);
    });
  });

  group('01b で選ぶ', () {
    testWidgets('今日より前は選べず、選んだ日と時刻は決定するまで欄に出ない', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('11/6(金) 8:30にする'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('前の月')),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );

      await tester.tap(find.bySemanticsLabel('11月4日'));
      await tester.pumpAndSettle();
      expect(find.text('11/6(金) 8:30にする'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('11月5日、今日'));
      await tester.pumpAndSettle();
      expect(find.text('11/5(木) 8:30にする'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('11月20日'));
      await tester.pumpAndSettle();
      expect(find.text('11/20(金) 8:30にする'), findsOneWidget);

      await _spin(tester, _hourWheel(), 15);
      await _spin(tester, _minuteWheel(), 0);
      expect(find.text('11/20(金) 15:00にする'), findsOneWidget);

      // 暗幕を押すと、決定していないので欄は開いたときのまま
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('11/6(金)'), findsOneWidget);
      expect(find.text('8:30'), findsOneWidget);
      expect(find.text('11/20(金)'), findsNothing);
    });

    testWidgets('決定すると、選んだ日と時刻が欄に出る', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      await tester.tap(find.bySemanticsLabel('11月20日'));
      await tester.pumpAndSettle();
      await _spin(tester, _hourWheel(), 15);
      await _spin(tester, _minuteWheel(), 0);
      await tester.tap(find.widgetWithText(AppButton, '11/20(金) 15:00にする'));
      await tester.pumpAndSettle();

      expect(find.text('2026年11月'), findsNothing);
      expect(find.text('11/20(金)'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('8:30'), findsNothing);
    });

    testWidgets('次の月へ進むと、前の月が押せる', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      await tester.tap(find.bySemanticsLabel('次の月'));
      await tester.pumpAndSettle();

      expect(find.text('2026年12月'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('前の月')),
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
    });

    testWidgets('基準日の 1 年後より先の日は選べない', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      for (var i = 0; i < 12; i++) {
        await tester.tap(find.bySemanticsLabel('次の月'));
        await tester.pumpAndSettle();
      }

      expect(find.text('2027年11月'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('次の月')),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );

      await tester.tap(find.bySemanticsLabel('11月6日'));
      await tester.pumpAndSettle();
      expect(find.text('11/6(金) 8:30にする'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('11月5日'));
      await tester.pumpAndSettle();
      expect(find.text('11/5(金) 8:30にする'), findsOneWidget);
    });

    testWidgets('時刻の数字は 44pt 以上押せる', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      _expectWheelHits(tester, _hourWheel());
      _expectWheelHits(tester, _minuteWheel());
    });
  });

  group('よく電話に出る時刻', () {
    testWidgets('出た電話の始まった時刻で多いものから 3 つ出し、押すとその時刻になる', (tester) async {
      await _pump(
        tester,
        log: _log(
          answered: _times([(19, 0, 3), (9, 0, 2), (10, 0, 1), (12, 0, 1)]),
          missed: [DateTime(2026, 11, 4, 8, 0)],
        ),
      );
      await _open(tester);

      expect(find.text('よく電話に出る時刻'), findsOneWidget);
      final labels = ['19:00', '9:00', '10:00'];
      final lefts = [
        for (final label in labels) tester.getTopLeft(find.text(label)).dx,
      ];
      expect(lefts[0], lessThan(lefts[1]));
      expect(lefts[1], lessThan(lefts[2]));
      expect(find.text('12:00'), findsNothing);
      expect(find.text('8:00'), findsNothing);

      await tester.tap(find.text('19:00'));
      await tester.pumpAndSettle();
      expect(find.text('11/6(金) 19:00にする'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, '11/6(金) 19:00にする'));
      await tester.pumpAndSettle();
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('8:30'), findsNothing);
    });

    testWidgets('5 分に寄らない始まりも、近い 5 分として数える', (tester) async {
      await _pump(tester, log: _log(answered: _times([(9, 2, 3)])));
      await _open(tester);

      expect(find.text('9:00'), findsOneWidget);
      expect(find.text('9:02'), findsNothing);
    });

    testWidgets('出た電話がなければ、ボタンも見出しも出さない', (tester) async {
      await _pump(tester, log: _log(missed: [DateTime(2026, 11, 2, 9, 0)]));
      await _open(tester);

      expect(find.text('よく電話に出る時刻'), findsNothing);
      expect(find.text('9:00'), findsNothing);
    });

    testWidgets('通話記録を読み終えていなければ、ボタンは出さない', (tester) async {
      await _pump(tester);
      await _open(tester);

      expect(find.text('よく電話に出る時刻'), findsNothing);
      expect(find.text('9:00'), findsNothing);
    });

    testWidgets('開いたあとに通話記録が届くと、よく出る時刻が出る', (tester) async {
      final calls = FakeCallsRepository();
      await _pump(tester, calls: calls);
      await _open(tester);

      expect(find.text('よく電話に出る時刻'), findsNothing);

      calls.log.value = _log(answered: _times([(9, 0, 1)]));
      await tester.pump();

      expect(find.text('よく電話に出る時刻'), findsOneWidget);
      expect(find.text('9:00'), findsOneWidget);
    });

    testWidgets('候補を押して回転中に決定しても、その候補の時刻になる', (tester) async {
      await _pump(tester, log: _log(answered: _times([(19, 0, 1)])));
      await _open(tester);

      await tester.tap(find.text('19:00'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('11/6(金) 19:00にする'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, '11/6(金) 19:00にする'));
      await tester.pumpAndSettle();
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('8:30'), findsNothing);
    });
  });
}
