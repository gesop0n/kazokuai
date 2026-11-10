import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/sync_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/settings/account_info_screen.dart';
import 'package:kazokuai/features/settings/logout_screen.dart';
import 'package:kazokuai/features/settings/settings_screen.dart';
import 'package:kazokuai/features/sync/sync_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_call_progress_repository.dart';
import '../../support/fake_bookings_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_sync_repository.dart';
import '../../support/fake_watched_person_repository.dart';

Override unsyncedHome() => homeRepositoryProvider.overrideWithValue(
  FakeHomeRepository(
    HomeView(
      person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
      now: sampleHomeData.now,
      latestCall: sampleHomeData.latestCall,
      todayCall: sampleHomeData.latestCall,
    ),
  ),
);

Future<void> pumpApp(
  WidgetTester tester, {
  Override? home,
  FakeSyncRepository? sync,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        home ?? sampleHome(),
        sampleCalls(),
        emptyBookings(),
        idleCallProgress(),
        if (sync != null) syncRepositoryProvider.overrideWithValue(sync),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterCode(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
  await tester.pumpAndSettle();
  for (final digit in '123456'.split('')) {
    await tester.tap(find.bySemanticsLabel(digit));
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(AppButton, '送信'));
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
    expect(find.text('見守る方のお名前'), findsOneWidget);
    expect(find.text('お名前'), findsNothing);
    expect(find.text('田中ハナ'), findsOneWidget);
    expect(find.text('ハナさん'), findsOneWidget);
    expect(find.text('家族・孫、庭・花、料理'), findsOneWidget);
    expect(find.text('やさしい女性の声'), findsOneWidget);
    expect(find.text('同期済み'), findsOneWidget);
    expect(find.text('まだ同期していません'), findsNothing);
    expect(find.text('03-0000-0000'), findsNothing);
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

  testWidgets('電話機がない見守る方の 08 は「まだ同期していません」と出す', (tester) async {
    await pumpApp(tester, home: unsyncedHome());
    await openSettings(tester);

    expect(find.text('田中ハナさんの設定'), findsOneWidget);
    expect(find.text('田中ハナ'), findsOneWidget);
    expect(find.text('ハナさん'), findsOneWidget);
    expect(find.text('まだ同期していません'), findsOneWidget);
    expect(find.text('同期済み'), findsNothing);
    expect(find.text('03-0000-0000'), findsNothing);
  });

  testWidgets('名前と呼ぶ方と話題と声は「準備中です」と出し、電話機は同期を、かけなおしはルールを開く', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    const labels = ['見守る方のお名前', '電話での呼び方', '好きな話題', 'AIの声'];
    for (final label in labels) {
      await tapLabel(tester, label);
      expect(find.text('準備中です'), findsOneWidget);
    }

    // 表示の時間は、出てくる動きが終わってから数える
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('準備中です'), findsNothing);

    await tapLabel(tester, '同期している電話機');
    expect(find.byType(SyncScreen), findsOneWidget);
    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(find.text('準備中です'), findsNothing);
    expect(currentPath(tester, SyncScreen), '/settings/sync');

    await tester.tap(backOf(SyncScreen));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SyncScreen), findsNothing);

    await tapLabel(tester, 'かけなおしのルール');
    expect(find.byType(RetryRuleScreen), findsOneWidget);
    expect(find.text('準備中です'), findsNothing);
    expect(currentPath(tester, RetryRuleScreen), '/retry-rule');

    await tester.tap(backOf(RetryRuleScreen));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tapLabel(tester, 'アカウント情報');
    expect(find.byType(AccountInfoScreen), findsOneWidget);
    expect(find.text('準備中です'), findsNothing);
    expect(currentPath(tester, AccountInfoScreen), '/settings/account');

    await tapLabel(tester, 'パスワード');
    expect(find.text('準備中です'), findsOneWidget);
  });

  testWidgets('08 からの同期は L3 のもどると L5 からも 08 に戻り、同期済みになる', (tester) async {
    final sync = FakeSyncRepository();
    await pumpApp(tester, home: unsyncedHome(), sync: sync);
    await openSettings(tester);
    expect(find.text('まだ同期していません'), findsOneWidget);

    await tapLabel(tester, '同期している電話機');
    expect(find.byType(SyncScreen), findsOneWidget);
    await tester.tap(backOf(SyncScreen));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SyncScreen), findsNothing);
    expect(find.text('まだ同期していません'), findsOneWidget);

    await tapLabel(tester, '同期している電話機');
    await enterCode(tester);

    expect(sync.codes, ['123456']);
    expect(find.byType(SyncDoneScreen), findsOneWidget);
    expect(find.text('設定にもどる'), findsOneWidget);
    expect(find.text('セットアップへ進む'), findsNothing);
    expect(currentPath(tester, SyncDoneScreen), '/settings/sync/done');

    await tester.tap(
      find.descendant(
        of: find.byType(SyncDoneScreen),
        matching: find.bySemanticsLabel('閉じる'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SyncDoneScreen), findsNothing);
    expect(find.text('同期済み'), findsOneWidget);
    expect(find.text('まだ同期していません'), findsNothing);
    expect(currentPath(tester, SettingsScreen), '/settings');

    await tapLabel(tester, '同期している電話機');
    await enterCode(tester);
    await tester.tap(find.widgetWithText(AppButton, '設定にもどる'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SyncDoneScreen), findsNothing);
    expect(find.text('同期済み'), findsOneWidget);
    expect(currentPath(tester, SettingsScreen), '/settings');
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
