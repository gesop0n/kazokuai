import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
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

Finder _wheelScrollable(Finder wheel) {
  // 回転式の Scrollable は非公開の子クラスなので、型の一致では見つからない。
  return find.descendant(
    of: wheel,
    matching: find.byWidgetPredicate((widget) => widget is Scrollable),
  );
}

FixedExtentScrollController _wheelController(
  WidgetTester tester,
  Finder wheel,
) {
  return tester.widget<Scrollable>(_wheelScrollable(wheel)).controller!
      as FixedExtentScrollController;
}

Future<void> _spin(WidgetTester tester, Finder wheel, int index) async {
  // 見えている数個だけが作られるので、目的の位置まで回してから押す。
  _wheelController(tester, wheel).jumpToItem(index);
  await tester.pumpAndSettle();
  await tester.tap(_wheelScrollable(wheel));
  await tester.pumpAndSettle();
}

Future<void> _tapNumber(WidgetTester tester, Finder wheel, String label) {
  return tester.tap(find.descendant(of: wheel, matching: find.text(label)));
}

// 回転の途中で指を動かす。一回の移動ではドラッグと認められないことがある。
Future<void> _dragWheel(WidgetTester tester, Finder wheel, double dy) async {
  final gesture = await tester.startGesture(tester.getCenter(wheel));
  await tester.pump(const Duration(milliseconds: 20));
  const step = 20.0;
  final moves = (dy.abs() / step).ceil();
  final delta = Offset(0, dy.sign * step);
  for (var i = 0; i < moves; i++) {
    await gesture.moveBy(delta);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
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

    testWidgets('カレンダーの行はモックの高さで、日は 44pt 以上押せる', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      final first = tester.getRect(find.bySemanticsLabel('11月1日'));
      final eighth = tester.getRect(find.bySemanticsLabel('11月8日'));
      expect(first.width, greaterThanOrEqualTo(44));
      expect(first.height, greaterThanOrEqualTo(44));
      // モックのマスは 40、行間は 2。隣の週の上端は 42 下。
      expect(eighth.top - first.top, closeTo(42, 0.1));

      // 行の下 2pt はマスの外。最後の日には隣がないので、そこを押してもその日になる。
      final last = tester.getRect(find.bySemanticsLabel('11月30日'));
      await tester.tapAt(last.bottomCenter - const Offset(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('11/30(月) 8:30にする'), findsOneWidget);
    });
  });

  group('よく電話に出る時刻', () {
    testWidgets('出た電話があっても、ボタンも見出しも出さない', (tester) async {
      await _pump(
        tester,
        log: _log(
          answered: _times([(19, 0, 3), (9, 0, 2), (10, 0, 1), (12, 0, 1)]),
          missed: [DateTime(2026, 11, 4, 8, 0)],
        ),
      );
      await _open(tester);

      expect(find.text('よく電話に出る時刻'), findsNothing);
      expect(find.text('19:00'), findsNothing);
      expect(find.text('9:00'), findsNothing);
      expect(find.text('10:00'), findsNothing);
      expect(find.text('12:00'), findsNothing);
      expect(find.text('8:00'), findsNothing);
    });
  });

  group('押した数字', () {
    testWidgets('回転が終わる前に決定すると、押した時と分になる', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      await _tapNumber(tester, _minuteWheel(), '35');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('11/6(金) 8:35にする'), findsOneWidget);

      await _tapNumber(tester, _hourWheel(), '9');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('11/6(金) 9:35にする'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, '11/6(金) 9:35にする'));
      await tester.pumpAndSettle();
      expect(find.text('9:35'), findsOneWidget);
      expect(find.text('8:30'), findsNothing);
    });

    testWidgets('回転の途中でドラッグすると、止まった時刻になる', (tester) async {
      await _pump(tester, log: _log());
      await _open(tester);

      await _tapNumber(tester, _hourWheel(), '9');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('11/6(金) 9:30にする'), findsOneWidget);

      // 上へ動かすと、あとの時へ進む。
      await _dragWheel(tester, _hourWheel(), -180);
      final hour = _wheelController(tester, _hourWheel()).selectedItem;
      final label = '11/6(金) ${formatSheetTime(hour, 30)}にする';
      expect(hour, isNot(9));
      expect(find.text(label), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, label));
      await tester.pumpAndSettle();
      expect(find.text(formatSheetTime(hour, 30)), findsOneWidget);
      expect(find.text('8:30'), findsNothing);
    });
  });
}
