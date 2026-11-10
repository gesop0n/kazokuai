import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/sync_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';
import 'package:kazokuai/features/sync/sync_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_sync_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

Future<void> pumpSync(
  WidgetTester tester, {
  required FakeSyncRepository sync,
  required FakeWatchedPersonRepository watched,
  FakeAuthRepository? auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          auth ?? FakeAuthRepository(signedIn: true),
        ),
        watchedPersonRepositoryProvider.overrideWithValue(watched),
        syncRepositoryProvider.overrideWithValue(sync),
        sampleHome(),
        sampleCalls(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

VoidCallback? buttonTap(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label)).onTap;

Future<void> tapKey(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pump();
}

Future<void> enterDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tapKey(tester, digit);
  }
}

Future<void> openCode(
  WidgetTester tester,
  FakeSyncRepository sync,
  FakeWatchedPersonRepository watched,
) async {
  await pumpSync(tester, sync: sync, watched: watched);
  await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
  await tester.pumpAndSettle();
}

void expectCodeBoxes(WidgetTester tester, {required bool wrong}) {
  final boxes = find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.startsWith('6桁の認証コード') ?? false),
    ),
    matching: find.byType(DecoratedBox),
  );
  expect(boxes, findsNWidgets(6));
  for (var i = 0; i < 6; i++) {
    final decoration =
        tester.widget<DecoratedBox>(boxes.at(i)).decoration as BoxDecoration;
    expect(
      decoration.color,
      wrong ? AppColors.stateAlertSoft : AppColors.paperRaised,
    );
    expect(
      decoration.border?.top.color,
      wrong ? AppColors.stateAlert : isNot(AppColors.stateAlert),
    );
  }
}

void main() {
  testWidgets('L3 から認証コードを送り、L5 の「セットアップへ進む」で L6 からホームへ進む', (tester) async {
    final sync = FakeSyncRepository();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await pumpSync(tester, sync: sync, watched: watched);

    expect(find.text('＃ボタン'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();
    expect(sync.starts, 1);
    expect(find.text('電話機の受話器を上げて\n「＃」を押してください'), findsOneWidget);
    expect(find.text('＃ボタン'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('6桁の認証コード'), findsOneWidget);
    expect(buttonTap(tester, '送信'), isNull);

    await enterDigits(tester, '123456');
    expect(find.bySemanticsLabel('6桁の認証コード、123456'), findsOneWidget);
    expect(buttonTap(tester, '送信'), isNotNull);

    await tapKey(tester, '1文字消す');
    expect(find.bySemanticsLabel('6桁の認証コード、12345'), findsOneWidget);
    expect(buttonTap(tester, '送信'), isNull);

    await enterDigits(tester, '6');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    expect(sync.codes, ['123456']);
    expect(watched.status.value, WatchedPersonStatus.unnamed);
    expect(find.byType(SyncDoneScreen), findsOneWidget);
    expect(find.text('同期が完了しました！'), findsOneWidget);
    expect(find.text('かぞくAIの電話機'), findsOneWidget);
    expect(find.text('03-0000-0000'), findsNothing);
    expect(find.text('＃ボタン'), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, 'セットアップへ進む'));
    await tester.pumpAndSettle();

    expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
    await tester.enterText(find.bySemanticsLabel('お名前'), '田中 ハナ');
    await tester.enterText(find.bySemanticsLabel('電話での呼び方'), 'ハナさん');
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, '次へ'));
    await tester.pumpAndSettle();

    expect(watched.registrations, [(name: '田中 ハナ', callName: 'ハナさん')]);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('L5 の「閉じる」は L6 を開く', (tester) async {
    final sync = FakeSyncRepository();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('閉じる'));
    await tester.pumpAndSettle();

    expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
    expect(find.byType(SyncDoneScreen), findsNothing);
  });

  testWidgets('送信の連打は、認証コードを 1 回だけ送る', (tester) async {
    final sync = FakeSyncRepository()..pendingSend = Completer<void>();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');

    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pump();

    expect(sync.codes, ['123456']);
    sync.pendingSend!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SyncDoneScreen), findsOneWidget);
  });

  testWidgets('認証コードが違うと赤くなり、次の数字で入れ直す', (tester) async {
    final sync = FakeSyncRepository()
      ..sendError = const SyncCodeWrongException();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    expect(find.text('認証コードが違います'), findsOneWidget);
    expect(find.text('電話機の「＃」をもう一度押すと、\n認証コードがもう一度流れます。'), findsOneWidget);
    expect(find.bySemanticsLabel('6桁の認証コード、123456'), findsOneWidget);
    expectCodeBoxes(tester, wrong: true);
    expect(buttonTap(tester, '送信'), isNotNull);
    expect(find.byType(SyncDoneScreen), findsNothing);

    await tapKey(tester, '9');

    expect(find.bySemanticsLabel('6桁の認証コード、9'), findsOneWidget);
    expect(find.text('認証コードが違います'), findsNothing);
    expectCodeBoxes(tester, wrong: false);
    expect(buttonTap(tester, '送信'), isNull);
  });

  testWidgets('L3+ は、待ちの画面から開いても認証コードの入力に戻る', (tester) async {
    final sync = FakeSyncRepository();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await pumpSync(tester, sync: sync, watched: watched);
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, '認証コードが聞こえないとき'));
    await tester.pumpAndSettle();

    expect(find.text('受話器を耳にしっかり当てる'), findsOneWidget);
    expect(find.text('もう一度「＃」を押す'), findsOneWidget);
    expect(find.text('電源とインターネットを確かめる'), findsOneWidget);
    expect(find.text('抜けていないか確かめてから、「同期を始める」からやり直します'), findsOneWidget);
    expect(find.text('電源と電話線'), findsNothing);
    expect(find.text('＃ボタン'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(find.text('認証コードの入力'), findsOneWidget);
    expect(find.text('受話器から聞こえた\n6桁の数字を入力してください'), findsOneWidget);
    expect(sync.starts, 1);
  });

  testWidgets('待ちの画面のもどるは始めの画面に戻り、コードの画面のもどるは待ちに戻る', (tester) async {
    final auth = FakeAuthRepository(signedIn: true);
    final sync = FakeSyncRepository();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await pumpSync(tester, auth: auth, sync: sync, watched: watched);
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(auth.signedIn.value, isTrue);
    expect(sync.starts, 1);

    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(find.text('電話機の受話器を上げて\n「＃」を押してください'), findsOneWidget);
    expect(auth.signedIn.value, isTrue);
  });

  testWidgets('L3 の「もどる」はログアウトして L1 に戻る', (tester) async {
    final auth = FakeAuthRepository(signedIn: true);
    final sync = FakeSyncRepository();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await pumpSync(tester, auth: auth, sync: sync, watched: watched);

    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(auth.signedIn.value, isFalse);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SyncScreen), findsNothing);
  });

  testWidgets('同期の準備が終わると、数字キーを隠して始めからやり直す', (tester) async {
    // 切れたときと、5 回目の間違いは、API が同じ応答なので同じ表示になる
    final sync = FakeSyncRepository()
      ..sendError = const SyncPrepEndedException();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    expect(find.text('同期の準備が終わりました'), findsOneWidget);
    expect(find.text('「同期を始める」から、もう一度始めてください。'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '送信'), findsNothing);
    expect(find.bySemanticsLabel('1'), findsNothing);
    expect(find.text('認証コードが聞こえないとき'), findsOneWidget);
    expectCodeBoxes(tester, wrong: false);

    await tester.tap(find.widgetWithText(AppButton, '同期を始めるからやり直す'));
    await tester.pumpAndSettle();

    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(find.byType(SyncScreen), findsOneWidget);
  });

  testWidgets('もどって同期を始め直すと、終わった知らせと前の入力を消す', (tester) async {
    final sync = FakeSyncRepository()
      ..sendError = const SyncPrepEndedException();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    expect(find.text('同期の準備が終わりました'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(find.text('電話機との同期を始めます。'), findsOneWidget);

    sync.sendError = null;
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();

    expect(sync.starts, 2);

    await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
    await tester.pumpAndSettle();

    expect(find.text('同期の準備が終わりました'), findsNothing);
    expect(find.bySemanticsLabel('6桁の認証コード'), findsOneWidget);
    expect(find.bySemanticsLabel('6桁の認証コード、123456'), findsNothing);
    expect(find.bySemanticsLabel('1'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '送信'), findsOneWidget);
  });

  testWidgets('認証コードを送れなくても、数字キーと送信は残る', (tester) async {
    final sync = FakeSyncRepository()..sendError = const SyncFailedException();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await openCode(tester, sync, watched);
    await enterDigits(tester, '123456');
    await tester.tap(find.widgetWithText(AppButton, '送信'));
    await tester.pumpAndSettle();

    expect(find.text('送信できませんでした'), findsOneWidget);
    expect(buttonTap(tester, '送信'), isNotNull);
    expect(find.bySemanticsLabel('1'), findsOneWidget);
    expect(find.bySemanticsLabel('6桁の認証コード、123456'), findsOneWidget);
    expectCodeBoxes(tester, wrong: false);
    expect(find.text('認証コードが違います'), findsNothing);
    expect(find.byType(SyncDoneScreen), findsNothing);
  });

  testWidgets('同期を始められなくても、始めすぎても、L3 に留まる', (tester) async {
    final sync = FakeSyncRepository()..startError = const SyncFailedException();
    final watched = FakeWatchedPersonRepository(
      status: WatchedPersonStatus.none,
    );
    await pumpSync(tester, sync: sync, watched: watched);

    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();

    expect(find.text('同期を始められませんでした'), findsOneWidget);
    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(buttonTap(tester, '同期を始める'), isNotNull);
    expect(sync.starts, 1);

    sync.startError = const SyncPrepLimitedException();
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();

    expect(find.text('しばらくしてから、もう一度お試しください'), findsOneWidget);
    expect(find.text('同期を始められませんでした'), findsNothing);
    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(buttonTap(tester, '同期を始める'), isNotNull);
  });

  testEachLayout('L3 が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const SyncScreen(),
      overrides: [
        syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
      ],
    );

    expect(find.text('電話機との同期を始めます。'), findsOneWidget);
    expect(find.text('＃ボタン'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '同期を始める'), findsOneWidget);
  });

  testEachLayout('認証コードの画面が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const SyncScreen(),
      overrides: [
        syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
      ],
    );
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '認証コードを入力する'));
    await tester.pumpAndSettle();

    expect(find.text('受話器から聞こえた\n6桁の数字を入力してください'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '送信'), findsOneWidget);
    expect(find.bySemanticsLabel('1文字消す'), findsOneWidget);
  });

  testEachLayout('L3+ が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const SyncScreen(),
      overrides: [
        syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
      ],
    );
    await tester.tap(find.widgetWithText(AppButton, '同期を始める'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '認証コードが聞こえないとき'));
    await tester.pumpAndSettle();

    expect(find.text('電源とインターネットを確かめる'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '認証コードを入力する'), findsOneWidget);
  });

  testEachLayout('L5 が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const SyncDoneScreen());

    expect(find.text('同期が完了しました！'), findsOneWidget);
    expect(find.text('かぞくAIの電話機'), findsOneWidget);
    expect(find.text('＃ボタン'), findsNothing);
    expect(find.widgetWithText(AppButton, 'セットアップへ進む'), findsOneWidget);
  });
}
