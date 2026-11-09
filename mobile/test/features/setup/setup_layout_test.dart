import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';

import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

void main() {
  testEachLayout('L6 がメッセージを出しても崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const WatchedPersonNameScreen(),
      overrides: [
        watchedPersonRepositoryProvider.overrideWithValue(
          FakeWatchedPersonRepository(
            status: WatchedPersonStatus.none,
            failing: true,
          ),
        ),
      ],
    );

    await tester.enterText(find.bySemanticsLabel('お名前'), '田中 ハナ');
    await tester.enterText(find.bySemanticsLabel('電話での呼び方'), 'ハナさん');
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, '次へ'));
    await tester.pump();

    expect(find.text('セットアップ'), findsOneWidget);
    expect(find.text('※あとから変更できます'), findsOneWidget);
    expect(find.bySemanticsLabel('3段階のうち1段階目'), findsOneWidget);
    expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
  });
}
