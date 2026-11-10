import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/sync/sync_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_bookings_repository.dart';
import '../support/fake_calls_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpApp(
  WidgetTester tester,
  FakeAuthRepository auth, {
  bool googleOnWeb = false,
  WatchedPersonStatus watchedPerson = WatchedPersonStatus.registered,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        // このファイルのテストは、Web 以外を既定にする。Web の流れだけ true にする
        googleSignInOnWebProvider.overrideWithValue(googleOnWeb),
        watchedPersonRepositoryProvider.overrideWithValue(
          FakeWatchedPersonRepository(status: watchedPerson),
        ),
        sampleHome(),
        sampleCalls(),
        emptyBookings(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> openLogin(WidgetTester tester) => tapText(tester, '始める');

Future<void> logIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await tester.enterText(find.bySemanticsLabel('メールアドレス'), email);
  await tester.enterText(find.bySemanticsLabel('パスワード'), password);
  // 入力すると押せるようになるので、描き直してから押す
  await tester.pump();
  // 見出しも「ログイン」なので、ボタンを選ぶ
  await tester.tap(find.widgetWithText(AppButton, 'ログイン'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ログインしていないときは L1 が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('ログインしているときはホームが開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository(signedIn: true));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  group('L2', () {
    FakeAuthRepository misakiOnly() =>
        FakeAuthRepository(accounts: {'misaki@example.com': 'hanasan1234'});

    testWidgets('正しいメールアドレスとパスワードでログインするとホームが開く', (tester) async {
      await pumpApp(tester, misakiOnly());

      await openLogin(tester);
      expect(find.byType(LoginScreen), findsOneWidget);

      await logIn(tester, email: 'misaki@example.com', password: 'hanasan1234');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('パスワードが違うと、L2 にメッセージが出る', (tester) async {
      await pumpApp(tester, misakiOnly());
      await openLogin(tester);

      await logIn(tester, email: 'misaki@example.com', password: 'hanasan');

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('メールアドレスかパスワードが違います'), findsOneWidget);
    });

    testWidgets('メールアドレスが違うと、L2 にメッセージが出る', (tester) async {
      await pumpApp(tester, misakiOnly());
      await openLogin(tester);

      await logIn(tester, email: 'misa@example.com', password: 'hanasan1234');

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('メールアドレスかパスワードが違います'), findsOneWidget);
    });

    testWidgets('通信できないと、L2 にメッセージが出る', (tester) async {
      await pumpApp(
        tester,
        FakeAuthRepository(
          accounts: {'misaki@example.com': 'hanasan1234'},
          unreachable: true,
        ),
      );
      await openLogin(tester);

      await logIn(tester, email: 'misaki@example.com', password: 'hanasan1234');

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('ログインできませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
    });

    testWidgets('入力を直すと、メッセージが消える', (tester) async {
      await pumpApp(tester, misakiOnly());
      await openLogin(tester);
      await logIn(tester, email: 'misaki@example.com', password: 'hanasan');

      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1');
      await tester.pump();

      expect(find.text('メールアドレスかパスワードが違います'), findsNothing);
    });

    testWidgets('メールアドレスとパスワードを入れるまで、ログインを押せない', (tester) async {
      await pumpApp(tester, misakiOnly());
      await openLogin(tester);
      bool canLogIn() =>
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'ログイン'))
              .onTap !=
          null;

      expect(canLogIn(), isFalse);

      await tester.enterText(
        find.bySemanticsLabel('メールアドレス'),
        'misaki@example.com',
      );
      await tester.pump();
      expect(canLogIn(), isFalse);

      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
      await tester.pump();
      expect(canLogIn(), isTrue);
    });

    testWidgets('もどると L1 が開く', (tester) async {
      await pumpApp(tester, misakiOnly());
      await openLogin(tester);

      await tester.tap(find.bySemanticsLabel('もどる'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  testWidgets('L1 の「始める」で L2 が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    await openLogin(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('Web 以外では、L2 の「Googleでログイン」は「準備中です」と出る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  // あるアカウントには見守る方がいる。メールアドレスでログインしたときと同じくホームへ進む。
  // 新しいアカウントには見守る方がいない。新規登録のあと同じく L3 へ進む。
  testWidgets('Web では、あるアカウントの「Googleでログイン」でホームが開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository(), googleOnWeb: true);
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('準備中です'), findsNothing);
  });

  testWidgets('Web では、新しいアカウントの「Googleでログイン」で L3 が開く', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(),
      googleOnWeb: true,
      watchedPerson: WatchedPersonStatus.none,
    );
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.byType(SyncScreen), findsOneWidget);
    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('準備中です'), findsNothing);
  });

  testWidgets('Web で Google のポップアップを閉じても、L2 は変わらない', (tester) async {
    final auth = FakeAuthRepository()..googlePopupClosed = true;
    await pumpApp(tester, auth, googleOnWeb: true);
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('ログインできませんでした。時間をおいて、もう一度お試しください'), findsNothing);
    expect(find.text('準備中です'), findsNothing);
  });

  testWidgets('Web で Google のログインに失敗すると、L2 にメッセージが出る', (tester) async {
    await pumpApp(
      tester,
      FakeAuthRepository(unreachable: true),
      googleOnWeb: true,
    );
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('ログインできませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('Web では、Google のポップアップが開いているあいだ「Googleでログイン」を押せない', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final auth = FakeAuthRepository()..pendingGoogleSignIn = gate;
    await pumpApp(tester, auth, googleOnWeb: true);
    await openLogin(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Googleでログイン'));
    await tester.pump();

    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Googleでログイン'))
          .onTap,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
