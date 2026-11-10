import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/register_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';
import 'package:kazokuai/features/sync/sync_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_bookings_repository.dart';
import '../support/fake_calls_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeWatchedPersonRepository watchedPerson,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        watchedPersonRepositoryProvider.overrideWithValue(watchedPerson),
        sampleHome(),
        sampleCalls(),
        emptyBookings(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterNames(
  WidgetTester tester, {
  required String name,
  required String callName,
}) async {
  await tester.enterText(find.bySemanticsLabel('お名前'), name);
  await tester.enterText(find.bySemanticsLabel('電話での呼び方'), callName);
  // 入力すると押せるようになるので、描き直してから押す
  await tester.pump();
}

Future<void> tapNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, '次へ'));
  await tester.pumpAndSettle();
}

bool canGoNext(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, '次へ')).onTap !=
    null;

// 本物のデータ層は、ログアウトを知らせた直後に見守る方を unknown にする。
// フレームを描く前に続けるので、2回目の redirect も遷移前の場所を読む。
Future<void> goBackFromSetup(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeWatchedPersonRepository watchedPerson,
}) async {
  await tester.tap(find.bySemanticsLabel('もどる'));
  expect(auth.signedIn.value, isFalse);
  // 偽物はログアウトしても状態を残す。本物はここで unknown になる
  watchedPerson.status.value = WatchedPersonStatus.unknown;
  await tester.pumpAndSettle();
}

Future<void> readDocument(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text('$titleに同意する'));
  await tester.tap(find.text('$titleに同意する'));
  await tester.pumpAndSettle();
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.tap(find.text('同意する'));
  await tester.pumpAndSettle();
}

void main() {
  group('ログインした家族が開く画面', () {
    testWidgets('見守る方がいなければ L3 が開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.none,
        ),
      );

      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.text('電話機との同期を始めます。'), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('名前がない見守る方は L6 が開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.unnamed,
        ),
      );

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('名前がある見守る方は、電話機がなくてもホームが開く', (tester) async {
      // 偽物の registered は、名前があり電話機の ID を持たない状態
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('名前がある家族が同期の画面を開いても、ホームへ戻さない', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(),
      );
      final router = GoRouter.of(tester.element(find.byType(HomeScreen)));

      router.go('/sync');
      await tester.pumpAndSettle();

      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      router.go('/sync/done');
      await tester.pumpAndSettle();

      expect(find.byType(SyncDoneScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('見守る方がいない家族は、完了の画面を開いても L3 に戻る', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.none,
        ),
      );
      final router = GoRouter.of(tester.element(find.byType(SyncScreen)));

      router.go('/sync/done');
      await tester.pumpAndSettle();

      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.text('電話機との同期を始めます。'), findsOneWidget);
      expect(find.byType(SyncDoneScreen), findsNothing);
      expect(find.text('同期が完了しました！'), findsNothing);
      expect(find.widgetWithText(AppButton, 'セットアップへ進む'), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('見守る方がいるかを読み終えるまでは、L3 も L6 もホームも開かない', (tester) async {
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: watchedPerson,
      );

      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);

      watchedPerson.status.value = WatchedPersonStatus.none;
      await tester.pumpAndSettle();

      expect(find.byType(SyncScreen), findsOneWidget);
    });

    testWidgets('ログインしていなければ、見守る方がいなくても L1 が開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.none,
        ),
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('L2 でログインしたあと、見守る方がいなければ L3 が開く', (tester) async {
      final auth = FakeAuthRepository(
        accounts: {'misaki@example.com': 'hanasan1234'},
      );
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(tester, auth: auth, watchedPerson: watchedPerson);
      await tester.tap(find.text('始める'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('メールアドレス'),
        'misaki@example.com',
      );
      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'ログイン'));
      // ログインすると、データ層が見守る方を読み始める
      watchedPerson.status.value = WatchedPersonStatus.none;
      await tester.pumpAndSettle();

      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('L6', () {
    Future<FakeWatchedPersonRepository> openL6(
      WidgetTester tester, {
      bool failing = false,
    }) async {
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unnamed,
        failing: failing,
      );
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: watchedPerson,
      );
      return watchedPerson;
    }

    testWidgets('入れた名前と呼び方がデータ層に届き、ホームが開く', (tester) async {
      final watchedPerson = await openL6(tester);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      await tapNext(tester);

      expect(watchedPerson.registrations, [(name: '田中 ハナ', callName: 'ハナさん')]);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('名前と呼び方の前後の空白は除いて渡す', (tester) async {
      final watchedPerson = await openL6(tester);

      await enterNames(tester, name: ' 田中 ハナ　', callName: 'ハナさん ');
      await tapNext(tester);

      expect(watchedPerson.registrations, [(name: '田中 ハナ', callName: 'ハナさん')]);
    });

    testWidgets('名前と呼び方の両方を入れるまで、次へを押せない', (tester) async {
      await openL6(tester);

      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: '');
      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: '　');
      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      expect(canGoNext(tester), isTrue);
    });

    testWidgets('登録できなかったときは、L6 にメッセージが出て、入力を直すと消える', (tester) async {
      await openL6(tester, failing: true);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      await tapNext(tester);

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
      expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('電話での呼び方'), 'ハナちゃん');
      await tester.pump();

      expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsNothing);
    });

    testWidgets('呼び方の見出しの横に「※あとから変更できます」が出る', (tester) async {
      await openL6(tester);

      final note = find.text('※あとから変更できます');
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(note).style,
        AppTextStyles.bodyS.copyWith(color: AppColors.inkSecondary),
      );
      // 見出しと同じ行で、その右にある
      final labelBox = tester.getRect(find.text('電話での呼び方'));
      final noteBox = tester.getRect(note);
      expect(noteBox.left, greaterThan(labelBox.right));
      expect(noteBox.center.dy, closeTo(labelBox.center.dy, 1));
      expect(find.text('再生ボタンを押すと、AIの声が流れます'), findsNothing);
    });

    testWidgets('進み具合の線は3段階のうちの1つ目で、モックの色である', (tester) async {
      // 既定の 800 は広い画面の列で幅 430 になり、線の幅が割り切れず間隔が誤差になる。
      // スマホの幅で、間隔がちょうど 6 になる幅にする。
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(392, 600)
        ..padding = FakeViewPadding.zero;
      addTearDown(tester.view.reset);

      await openL6(tester);

      final progress = find.bySemanticsLabel('3段階のうち1段階目');
      expect(progress, findsOneWidget);
      expect(
        tester.getTopLeft(progress).dy,
        lessThan(tester.getTopLeft(find.text('見守る方のお名前を\n教えてください')).dy),
      );

      final marks = find.descendant(
        of: progress,
        matching: find.byType(DecoratedBox),
      );
      expect(marks, findsNWidgets(3));
      BoxDecoration decorationAt(int index) =>
          tester.widget<DecoratedBox>(marks.at(index)).decoration
              as BoxDecoration;
      expect(decorationAt(0).color, AppColors.inkPrimary);
      expect(decorationAt(1).color, AppColors.lineStrong);
      expect(decorationAt(2).color, AppColors.lineStrong);
      expect(decorationAt(0).borderRadius, BorderRadius.circular(2));
      expect(decorationAt(1).borderRadius, BorderRadius.circular(2));
      expect(decorationAt(2).borderRadius, BorderRadius.circular(2));
      expect(tester.getSize(marks.at(0)), tester.getSize(marks.at(1)));
      expect(tester.getSize(marks.at(1)), tester.getSize(marks.at(2)));
      expect(tester.getSize(marks.at(0)).height, 4);
      expect(
        tester.getTopLeft(marks.at(1)).dx - tester.getTopRight(marks.at(0)).dx,
        6,
      );
      expect(
        tester.getTopLeft(marks.at(2)).dx - tester.getTopRight(marks.at(1)).dx,
        6,
      );
    });

    testWidgets('L2 から開いた L6 の「もどる」は、ログアウトして L1 に戻る', (tester) async {
      final auth = FakeAuthRepository(
        accounts: {'misaki@example.com': 'hanasan1234'},
      );
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(tester, auth: auth, watchedPerson: watchedPerson);
      await tester.tap(find.text('始める'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('メールアドレス'),
        'misaki@example.com',
      );
      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'ログイン'));
      watchedPerson.status.value = WatchedPersonStatus.unnamed;
      await tester.pumpAndSettle();

      await goBackFromSetup(tester, auth: auth, watchedPerson: watchedPerson);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(auth.signedIn.value, isFalse);
    });

    testWidgets('新規登録から開いた L3 の「もどる」は、ログアウトして L1 に戻る', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(393, 700);
      addTearDown(tester.view.reset);

      final auth = FakeAuthRepository();
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(tester, auth: auth, watchedPerson: watchedPerson);
      await tester.tap(find.text('始める'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('はじめての方は新規登録'));
      await tester.pumpAndSettle();
      await readDocument(tester, '利用規約');
      await readDocument(tester, 'プライバシーポリシー');
      await tester.enterText(
        find.bySemanticsLabel('メールアドレス'),
        'misaki@example.com',
      );
      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
      await tester.pump();
      await tester.tap(find.text('登録する'));
      watchedPerson.status.value = WatchedPersonStatus.none;
      await tester.pumpAndSettle();
      expect(find.byType(SyncScreen), findsOneWidget);

      await goBackFromSetup(tester, auth: auth, watchedPerson: watchedPerson);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(auth.signedIn.value, isFalse);
    });

    testWidgets('ログインしたまま開いた L6 の「もどる」は、L1 に戻る', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unnamed,
      );
      await pumpApp(tester, auth: auth, watchedPerson: watchedPerson);

      await goBackFromSetup(tester, auth: auth, watchedPerson: watchedPerson);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(auth.signedIn.value, isFalse);
    });
  });
}
