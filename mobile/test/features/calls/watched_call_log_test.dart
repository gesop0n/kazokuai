import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';

import '../../support/layout_matrix.dart';

void main() {
  testWidgets('見守る方からの電話は、伝言の行なしで通話記録に出る', (tester) async {
    await pumpScreenInLayout(
      tester,
      const LayoutCase(393, 1),
      Scaffold(
        body: CallsScreen(
          log: CallLog(
            today: DateTime(2026, 11, 5),
            days: [
              CallLogDay(
                date: DateTime(2026, 11, 5),
                entries: [
                  AnsweredCallEntry(
                    id: 'from-parent',
                    startedAt: DateTime(2026, 11, 5, 9, 2),
                    text: '庭の話をした',
                    duration: const Duration(minutes: 3),
                    topic: CallTopic.companion,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('庭の話をした'), findsOneWidget);
    expect(find.text('3分'), findsOneWidget);
    expect(find.text('伝えたこと'), findsNothing);
    expect(find.textContaining('かぞくAI'), findsNothing);
  });
}
