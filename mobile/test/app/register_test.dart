import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';

import '../support/fake_auth_repository.dart';

// 見本の文が画面に収まると、開いただけで最後まで読んだことになる。
// 幅 393 で条文が折り返し、高さ 700 では最後まで届かない。
const _surface = Size(393, 700);

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository auth) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _surface;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

// ナビの「もどる」「閉じる」は文字ではなく読み上げの名前
Future<void> tapLabel(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

AppButton button(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label));

Finder documentScroll() => find.byType(Scrollable).last;

Future<void> scrollDocumentTo(WidgetTester tester, double fraction) async {
  final position = tester.state<ScrollableState>(documentScroll()).position;
  position.jumpTo(position.maxScrollExtent * fraction);
  await tester.pumpAndSettle();
}

Future<void> openRegister(WidgetTester tester) => tapText(tester, 'はじめる');

Future<void> openDocument(WidgetTester tester, String title) =>
    tapText(tester, title);

String readProgress(WidgetTester tester) =>
    tester.getSemantics(find.bySemanticsLabel('読んだ割合')).value;

Future<void> readDocument(WidgetTester tester, String title) async {
  await openDocument(tester, title);
  await scrollDocumentTo(tester, 1);
  expect(button(tester, '読みました').onTap, isNotNull);
  await tapText(tester, '読みました');
}

void main() {
  testWidgets('L1 の「はじめる」から新規登録が開き、2つとも未読である', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    await openRegister(tester);

    expect(find.text('新規登録'), findsOneWidget);
    expect(find.text('未読'), findsNWidgets(2));
    expect(find.text('読みました'), findsNothing);
    expect(button(tester, '同意して登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);
    expect(find.text('2つとも読むと登録できます'), findsOneWidget);
  });

  testWidgets('L2 の「新規登録へ」からも新規登録が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tapText(tester, 'アカウントをお持ちの方はログイン');

    await tapText(tester, '新規登録へ');

    expect(find.text('新規登録'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('新規登録からもどると、開いた画面に戻る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tapText(tester, 'アカウントをお持ちの方はログイン');
    await tapText(tester, '新規登録へ');

    await tapLabel(tester, 'もどる');

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('最後まで読むと読んだ割合が100%になり、「読みました」を押せる', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);

    await openDocument(tester, '利用規約');

    expect(find.text('モック用の見本です。実際の規約ではありません。'), findsOneWidget);
    expect(
      find.text('最初の電話で、AIであることと、会話を文字にしてご家族に共有することを説明します。同意がない場合は共有しません。'),
      findsOneWidget,
    );
    expect(
      tester.state<ScrollableState>(documentScroll()).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(button(tester, '読みました').onTap, isNull);
    expect(readProgress(tester), '0%');

    await scrollDocumentTo(tester, 0.5);

    expect(readProgress(tester), '50%');
    expect(button(tester, '読みました').onTap, isNull);

    await scrollDocumentTo(tester, 1);

    expect(readProgress(tester), '100%');
    expect(button(tester, '読みました').onTap, isNotNull);

    await scrollDocumentTo(tester, 0);

    expect(readProgress(tester), '0%');
    expect(button(tester, '読みました').onTap, isNotNull);
  });

  testWidgets('「読みました」を押すと、その文書だけ読んだことになる', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);

    await readDocument(tester, '利用規約');

    expect(find.text('読みました'), findsOneWidget);
    expect(find.text('未読'), findsOneWidget);
    expect(button(tester, '同意して登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);
  });

  testWidgets('閉じると、その文書は未読のままである', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await openDocument(tester, 'プライバシーポリシー');
    await scrollDocumentTo(tester, 1);

    await tapLabel(tester, '閉じる');

    expect(find.text('未読'), findsNWidgets(2));
    expect(find.text('読みました'), findsNothing);
  });

  testWidgets('両方を読むと登録でき、メールアドレスとパスワードがデータ層に届く', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    expect(find.text('未読'), findsNothing);
    expect(find.text('読みました'), findsNWidgets(2));
    expect(find.text('登録すると、2つの内容に同意したことになります'), findsOneWidget);
    expect(button(tester, '同意して登録する').onTap, isNotNull);
    expect(button(tester, 'Googleで登録').onTap, isNotNull);

    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
    await tester.pump();
    await tapText(tester, '同意して登録する');

    expect(auth.submittedEmail, 'misaki@example.com');
    expect(auth.submittedPassword, 'hanasan1234');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('メールアドレスとパスワードが空のときは、データ層を呼ばずにメッセージが出る', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    await tapText(tester, '同意して登録する');

    expect(auth.submittedEmail, isNull);
    expect(find.text('メールアドレスとパスワードを入力してください'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });

  testWidgets('すでに使われているメールアドレスではメッセージが出る', (tester) async {
    final auth = FakeAuthRepository(
      accounts: {'misaki@example.com': 'hanasan1234'},
    );
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');
    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
    await tester.pump();

    await tapText(tester, '同意して登録する');

    expect(auth.submittedEmail, 'misaki@example.com');
    expect(auth.submittedPassword, 'hanasan1234');
    expect(find.text('このメールアドレスはすでに使われています'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('短いパスワードではメッセージが出る', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');
    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan');
    await tester.pump();

    await tapText(tester, '同意して登録する');

    expect(auth.submittedPassword, 'hanasan');
    expect(find.text('パスワードは8文字以上にしてください'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('通信できないとメッセージが出る', (tester) async {
    final auth = FakeAuthRepository(unreachable: true);
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');
    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
    await tester.pump();

    await tapText(tester, '同意して登録する');

    expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('入力を直すと、メッセージが消える', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');
    await tapText(tester, '同意して登録する');

    await tester.enterText(find.bySemanticsLabel('メールアドレス'), 'm');
    await tester.pump();

    expect(find.text('メールアドレスとパスワードを入力してください'), findsNothing);
  });

  testWidgets('両方を読んだあとの Google での登録は「準備中です」', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    await tapText(tester, 'Googleで登録');

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });
}
