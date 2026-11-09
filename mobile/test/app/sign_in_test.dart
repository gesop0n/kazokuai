import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_calls_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
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

  testWidgets('L2 の「Googleでログイン」は「準備中です」と出る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openLogin(tester);

    await tapText(tester, 'Googleでログイン');

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
