import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/settings/account_info_screen.dart';
import 'package:kazokuai/features/settings/logout_screen.dart';
import 'package:kazokuai/features/settings/settings_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';

Future<void> pumpApp(WidgetTester tester) async {
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

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('田中ハナさんの設定'));
  await tester.pumpAndSettle();
}

Future<void> openAccount(WidgetTester tester) async {
  await openSettings(tester);
  await tester.ensureVisible(find.text('アカウント情報'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('アカウント情報'));
  await tester.pumpAndSettle();
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder backOf(Type screen) => find.descendant(
  of: find.byType(screen),
  matching: find.descendant(
    of: find.byType(AppNavBar),
    matching: find.byType(InkWell),
  ),
);

String currentPath(WidgetTester tester, Type screen) =>
    GoRouter.of(tester.element(find.byType(screen)))
        .routeInformationProvider
        .value
        .uri
        .path;

void main() {
  testWidgets('歯車で 08 を開き、もどるとホームに戻る', (tester) async {
    await pumpApp(tester);

    await openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('田中ハナさんの設定'), findsOneWidget);
    expect(find.text('田中ハナ'), findsOneWidget);
    expect(find.text('ハナさん'), findsOneWidget);
    expect(find.text('家族・孫、庭・花、料理'), findsOneWidget);
    expect(find.text('やさしい女性の声'), findsOneWidget);
    expect(find.text('03-0000-0000'), findsOneWidget);
    expect(find.text('15分おきに3回かけて、家族に通知'), findsOneWidget);
    expect(find.text('tanaka.taro@example.com'), findsOneWidget);
    expect(find.byType(AppTabBar), findsNothing);
    expect(currentPath(tester, SettingsScreen), '/settings');

    await tester.tap(backOf(SettingsScreen));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(AppTabBar), findsOneWidget);
  });

  testWidgets('アカウント情報以外は「準備中です」と出す', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    const labels = [
      'お名前',
      '電話での呼び方',
      '好きな話題',
      'AIの声',
      '同期している電話機',
      'かけなおしのルール',
    ];
    for (final label in labels) {
      await tapLabel(tester, label);
      expect(find.text('準備中です'), findsOneWidget);
    }

    // 表示の時間は、出てくる動きが終わってから数える
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('準備中です'), findsNothing);

    await tapLabel(tester, 'アカウント情報');
    expect(find.byType(AccountInfoScreen), findsOneWidget);
    expect(find.text('準備中です'), findsNothing);
    expect(currentPath(tester, AccountInfoScreen), '/settings/account');

    await tapLabel(tester, 'パスワード');
    expect(find.text('準備中です'), findsOneWidget);
    await tapLabel(tester, 'チュートリアル確認');
    expect(find.text('準備中です'), findsOneWidget);
  });

  testWidgets('08e に名前、メール、ログイン方法、登録日を出し、名前を保存できる', (tester) async {
    await pumpApp(tester);
    await openAccount(tester);

    expect(find.text('あなたのお名前'), findsOneWidget);
    expect(find.text('田中 太郎'), findsOneWidget);
    expect(find.text('tanaka.taro@example.com'), findsWidgets);
    expect(find.text('メールアドレスとパスワード'), findsOneWidget);
    expect(find.text('2026年11月5日'), findsOneWidget);
    expect(find.text('使い方をもう一度見る'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '佐藤 花子');
    await tester.tap(find.text('メールアドレス'));
    await tester.pumpAndSettle();

    await tester.tap(backOf(AccountInfoScreen));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tapLabel(tester, 'アカウント情報');
    expect(find.text('佐藤 花子'), findsOneWidget);
    expect(find.text('田中 太郎'), findsNothing);
  });

  testWidgets('確認を閉じてもログアウトせず、ログアウトすると L1 に戻る', (tester) async {
    await pumpApp(tester);
    await openAccount(tester);

    await tapLabel(tester, 'ログアウト');
    expect(find.byType(LogoutScreen), findsOneWidget);
    expect(find.text('ログアウトしますか？'), findsOneWidget);
    expect(
      find.text('ログアウトしても、AIからの電話や\n会話の記録はそのまま続きます。\nもう一度見るときは、ログインしてください。'),
      findsOneWidget,
    );
    expect(currentPath(tester, LogoutScreen), '/settings/account/logout');

    await tester.tap(find.text('アカウント情報にもどる'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountInfoScreen), findsOneWidget);
    expect(find.byType(LogoutScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsNothing);

    await tapLabel(tester, 'ログアウト');
    await tester.tap(find.bySemanticsLabel('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountInfoScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    await tapLabel(tester, 'ログアウト');
    await tester.tap(find.text('ログアウトする'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(LogoutScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
  });
}
