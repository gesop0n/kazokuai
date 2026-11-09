import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/password_reset_screen.dart';
import 'package:kazokuai/features/account/register_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/settings/account_info_screen.dart';
import 'package:kazokuai/features/settings/logout_screen.dart';
import 'package:kazokuai/features/settings/settings_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_call_progress_repository.dart';
import '../support/fake_calls_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

// 読み直すと、押し開いた画面の下には何もない。タブバーもない画面は、
// 「もどる」で、ふだん開く元の画面へ移る。
Future<void> openAt(
  WidgetTester tester,
  String path, {
  bool signedIn = true,
}) async {
  tester.platformDispatcher.defaultRouteNameTestValue = path;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedIn
            ? signedInAuth()
            : authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
        idleCallProgress(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openSignedIn(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
        idleCallProgress(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('もどる'));
  await tester.pumpAndSettle();
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

int currentTab(WidgetTester tester) =>
    tester.widget<AppTabBar>(find.byType(AppTabBar)).currentIndex;

void main() {
  group('下に何もないとき', () {
    testWidgets('01 の「もどる」はホームに移る', (tester) async {
      await openAt(tester, '/ask');
      expect(find.byType(AskScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(currentTab(tester), 0);
    });

    testWidgets('予約の編集の「もどる」は予約電話に移る', (tester) async {
      await openAt(tester, '/booking/edit/0');
      expect(find.byType(BookingEditScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(BookingEditScreen), findsNothing);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(currentTab(tester), 2);
    });

    testWidgets('かけなおしのルールの「もどる」は予約電話に移る', (tester) async {
      await openAt(tester, '/retry-rule');
      expect(find.byType(RetryRuleScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(RetryRuleScreen), findsNothing);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(currentTab(tester), 2);
    });

    testWidgets('08 の「もどる」はホームに移る', (tester) async {
      await openAt(tester, '/settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(currentTab(tester), 0);
    });

    testWidgets('08e の「もどる」は 08 に移る', (tester) async {
      await openAt(tester, '/settings/account');
      expect(find.byType(AccountInfoScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(AccountInfoScreen), findsNothing);
      expect(find.byType(AppTabBar), findsNothing);
    });

    testWidgets('08d の「閉じる」は 08e に移る', (tester) async {
      await openAt(tester, '/settings/account/logout');
      expect(find.byType(LogoutScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tester.tap(find.bySemanticsLabel('閉じる'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountInfoScreen), findsOneWidget);
      expect(find.byType(LogoutScreen), findsNothing);
    });

    testWidgets('L2 の「もどる」は L1 に移る', (tester) async {
      await openAt(tester, '/welcome/login', signedIn: false);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('新規登録の「もどる」は L1 に移る', (tester) async {
      await openAt(tester, '/welcome/register', signedIn: false);
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
    });

    testWidgets('L2a の「もどる」は L2 に移る', (tester) async {
      await openAt(tester, '/welcome/login/reset', signedIn: false);
      expect(find.byType(PasswordResetScreen), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);

      await tapBack(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PasswordResetScreen), findsNothing);
    });

    testWidgets('電話の詳細の「もどる」は通話記録に移る', (tester) async {
      await openAt(tester, '/calls/detail');
      expect(find.byType(CallDetailScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('通話記録にもどる'));
      await tester.pumpAndSettle();

      expect(find.byType(CallsScreen), findsOneWidget);
      expect(find.byType(CallDetailScreen), findsNothing);
      expect(currentTab(tester), 1);
    });
  });

  group('ふだんどおり開いたとき', () {
    testWidgets('ホームから開いた 01 の「もどる」はホームに戻る', (tester) async {
      await openSignedIn(tester);

      await tester.tap(find.text('AIに伝えてもらう'));
      await tester.pumpAndSettle();
      expect(find.byType(AskScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(currentTab(tester), 0);
    });

    testWidgets('予約電話から開いた 01 の「もどる」は予約電話に戻る', (tester) async {
      await openSignedIn(tester);
      await tapTab(tester, '予約電話');

      await tapVisible(tester, '新しい予約');
      expect(find.byType(AskScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(AskScreen), findsNothing);
      expect(currentTab(tester), 2);
    });

    testWidgets('予約電話から開いた編集の「もどる」は予約電話に戻る', (tester) async {
      await openSignedIn(tester);
      await tapTab(tester, '予約電話');

      await tapVisible(tester, '話し相手');
      expect(find.byType(BookingEditScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(BookingEditScreen), findsNothing);
      expect(currentTab(tester), 2);
    });

    testWidgets('予約電話から開いたかけなおしのルールの「もどる」は予約電話に戻る', (tester) async {
      await openSignedIn(tester);
      await tapTab(tester, '予約電話');

      await tapVisible(tester, '15分おきに3回かけて、家族に通知');
      expect(find.byType(RetryRuleScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.byType(RetryRuleScreen), findsNothing);
      expect(currentTab(tester), 2);
    });

    testWidgets('L1 から開いた L2 の「もどる」は L1 に戻る', (tester) async {
      await openAt(tester, '/welcome', signedIn: false);

      await tester.tap(find.text('始める'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('L2 から開いた新規登録の「もどる」は L2 に戻る', (tester) async {
      await openAt(tester, '/welcome/login', signedIn: false);

      await tester.tap(find.text('はじめての方は新規登録'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
    });

    testWidgets('L2 から開いた L2a の「もどる」は L2 に戻る', (tester) async {
      await openAt(tester, '/welcome/login', signedIn: false);

      await tester.tap(find.text('パスワードを忘れた場合'));
      await tester.pumpAndSettle();
      expect(find.byType(PasswordResetScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PasswordResetScreen), findsNothing);
    });
  });
}
