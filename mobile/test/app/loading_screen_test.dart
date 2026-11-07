import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/app/loading_screen.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_watched_person_repository.dart';
import '../support/layout_matrix.dart';

const _notice = '見守る方の情報を読み込めませんでした。';
const _reloadLabel = 'もう一度読み込む';

// 10 秒のタイマーはフレームを予約しないので、pumpAndSettle では時刻が進まない。
Future<void> pumpSignedInApp(
  WidgetTester tester,
  FakeWatchedPersonRepository watchedPerson,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        watchedPersonRepositoryProvider.overrideWithValue(watchedPerson),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('見守る方の読み取りが失敗すると、知らせと読み直しのボタンが出る', (tester) async {
    final watchedPerson = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.unreadable,
    );
    await pumpSignedInApp(tester, watchedPerson);

    expect(find.text(_notice), findsOneWidget);
    expect(tester.widget<Text>(find.text(_notice)).style, AppTextStyles.titleL);
    expect(tester.getTopLeft(find.text(_notice)).dx, 16);

    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, _reloadLabel),
    );
    expect(button.variant, AppButtonVariant.primary);
    expect(button.size, AppButtonSize.l);
    expect(tester.getTopLeft(find.byType(AppButton)).dx, 16);
    expect(
      tester.getBottomLeft(find.text(_notice)).dy,
      lessThan(tester.getTopLeft(find.byType(AppButton)).dy),
    );
    expect(find.bySemanticsLabel('読み込んでいます'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(WatchedPersonNameScreen), findsNothing);
  });

  testWidgets('答えが 10 秒来ないと、知らせと読み直しのボタンが出る', (tester) async {
    await pumpSignedInApp(
      tester,
      FakeWatchedPersonRepository(status: WatchedPersonStatus.unknown),
    );

    expect(find.bySemanticsLabel('読み込んでいます'), findsOneWidget);
    expect(find.text(_notice), findsNothing);
    expect(find.widgetWithText(AppButton, _reloadLabel), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text(_notice), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_notice), findsOneWidget);
    expect(find.widgetWithText(AppButton, _reloadLabel), findsOneWidget);
    expect(find.bySemanticsLabel('読み込んでいます'), findsNothing);
  });

  testWidgets('読み直しているあいだは何も描かず、見守る方がいればホームが開く', (tester) async {
    final watchedPerson = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.unreadable,
    );
    await pumpSignedInApp(tester, watchedPerson);
    // 失敗の直後に押すと、前の 10 秒の残りで知らせが戻っていないことを確かめられる
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.widgetWithText(AppButton, _reloadLabel));
    await tester.pump();

    expect(watchedPerson.reloads, 1);
    expect(watchedPerson.status.value, WatchedPersonStatus.unknown);
    expect(find.text(_notice), findsNothing);
    expect(find.bySemanticsLabel('読み込んでいます'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text(_notice), findsNothing);

    watchedPerson.status.value = WatchedPersonStatus.registered;
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(_notice), findsNothing);
  });

  testWidgets('答えが来ないまま読み直して、見守る方がいなければ L6 が開く', (tester) async {
    final watchedPerson = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.unknown,
    );
    await pumpSignedInApp(tester, watchedPerson);
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.widgetWithText(AppButton, _reloadLabel));
    await tester.pump();

    expect(watchedPerson.reloads, 1);
    expect(find.text(_notice), findsNothing);
    expect(find.bySemanticsLabel('読み込んでいます'), findsOneWidget);

    watchedPerson.status.value = WatchedPersonStatus.none;
    await tester.pumpAndSettle();

    expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
    expect(find.text(_notice), findsNothing);
  });

  testEachLayout('知らせと読み直しのボタンが崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const LoadingScreen(),
      overrides: [
        watchedPersonRepositoryProvider.overrideWithValue(
          FakeWatchedPersonRepository(status: WatchedPersonStatus.unreadable),
        ),
      ],
    );

    expect(find.text(_notice), findsOneWidget);
    expect(find.widgetWithText(AppButton, _reloadLabel), findsOneWidget);
  });
}
