import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_watched_person_repository.dart';

// 見本の文が画面に収まると、開いただけで最後まで読んだことになる。
// 幅 393 で条文が折り返し、高さ 700 では最後まで届かない。
const _surface = Size(393, 700);

const _termsArticle2 =
    'ご利用者は、電話の相手がAIであること、会話の内容が文字として残ることを、見守る方に説明してください。最初の電話でもAIから説明し、同意がない場合は共有しません。';

const _privacyHeadings = [
  '第1条 取得する情報',
  '第2条 利用の目的',
  '第3条 見守る方への説明',
  '第4条 健康に関する情報',
  '第5条 情報を共有する相手',
  '第6条 外部への委託',
  '第7条 保管と削除',
  '第8条 開示、訂正、利用停止',
  '第9条 安全管理',
  '第10条 このポリシーの変更',
];

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository auth) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _surface;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        // 作ったばかりのアカウントには、見守る方がいない
        watchedPersonRepositoryProvider.overrideWithValue(
          FakeWatchedPersonRepository(status: WatchedPersonStatus.none),
        ),
      ],
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

Future<void> openRegister(WidgetTester tester) async {
  await tapText(tester, '始める');
  await tapText(tester, 'はじめての方は新規登録');
}

Future<void> openDocument(WidgetTester tester, String title) =>
    tapText(tester, '$titleに同意する');

String readProgress(WidgetTester tester) =>
    tester.getSemantics(find.bySemanticsLabel('読んだ割合')).value;

void expectAgreement(
  WidgetTester tester,
  String title, {
  required bool checked,
  required bool enabled,
}) {
  expect(
    tester.getSemantics(find.bySemanticsLabel('$titleに同意')),
    isSemantics(
      label: '$titleに同意',
      hasCheckedState: true,
      isChecked: checked,
      hasEnabledState: true,
      isEnabled: enabled,
      hasTapAction: enabled,
    ),
  );
}

Future<void> tapAgreement(WidgetTester tester, String title) async {
  await tester.tap(find.bySemanticsLabel('$titleに同意'));
  await tester.pumpAndSettle();
}

Future<void> readDocument(WidgetTester tester, String title) async {
  await openDocument(tester, title);
  await scrollDocumentTo(tester, 1);
  expect(button(tester, '同意する').onTap, isNotNull);
  await tapText(tester, '同意する');
}

void main() {
  testWidgets('L2b では、2つのチェックボックスが押せず、登録のボタンも押せない', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    await openRegister(tester);

    expect(find.text('新規登録'), findsOneWidget);
    expect(find.text('それぞれ開いて内容を読み、同意してください'), findsOneWidget);
    expect(find.text('次の2つをお読みください'), findsNothing);
    expect(find.text('未読'), findsNothing);
    expect(find.text('読みました'), findsNothing);
    expect(find.text('2つとも読むと登録できます'), findsNothing);
    expect(find.text('同意して登録する'), findsNothing);
    expect(find.text('利用規約に同意する'), findsOneWidget);
    expect(find.text('プライバシーポリシーに同意する'), findsOneWidget);
    expectAgreement(tester, '利用規約', checked: false, enabled: false);
    expectAgreement(tester, 'プライバシーポリシー', checked: false, enabled: false);
    expect(button(tester, '登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);

    final row = find
        .ancestor(
          of: find.text('利用規約に同意する'),
          matching: find.byWidgetPredicate((widget) {
            if (widget is! DecoratedBox) return false;
            final decoration = widget.decoration;
            return decoration is BoxDecoration &&
                decoration.color == AppColors.paperRaised;
          }),
        )
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
    final decoration =
        tester.widget<DecoratedBox>(row).decoration as BoxDecoration;
    expect(decoration.borderRadius, AppRadius.borderRadius);
    expect(decoration.border, Border.all(color: AppColors.line));
    final box = tester.getRect(find.bySemanticsLabel('利用規約に同意'));
    final label = tester.getRect(find.text('利用規約に同意する'));
    final chevron = tester.getRect(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.icon == AppIcons.chevronRight,
        ),
      ),
    );
    expect(box.right, lessThanOrEqualTo(label.left));
    expect(label.right, lessThanOrEqualTo(chevron.left));
    expect(box.size, const Size(44, 56));

    await tapAgreement(tester, '利用規約');

    expectAgreement(tester, '利用規約', checked: false, enabled: false);
    expect(button(tester, '登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);
  });

  testWidgets('L2 の「はじめての方は新規登録」で新規登録が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tapText(tester, '始める');

    await tapText(tester, 'はじめての方は新規登録');

    expect(find.text('新規登録'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('新規登録からもどると、開いた画面に戻る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tapText(tester, '始める');
    await tapText(tester, 'はじめての方は新規登録');

    await tapLabel(tester, 'もどる');

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('最後まで読むと読んだ割合が100%になり、「同意する」を押せる', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);

    await openDocument(tester, '利用規約');

    expect(find.text('最後まで読むと押せるようになります'), findsNothing);
    expect(find.text('モック用の見本です。実際の規約ではありません。'), findsOneWidget);
    expect(find.text(_termsArticle2), findsOneWidget);
    expect(
      find.text('最初の電話で、AIであることと、会話を文字にしてご家族に共有することを説明します。同意がない場合は共有しません。'),
      findsNothing,
    );
    expect(
      tester.state<ScrollableState>(documentScroll()).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(button(tester, '同意する').onTap, isNull);
    expect(readProgress(tester), '0%');

    await scrollDocumentTo(tester, 0.5);

    expect(readProgress(tester), '50%');
    expect(button(tester, '同意する').onTap, isNull);

    await scrollDocumentTo(tester, 1);

    expect(readProgress(tester), '100%');
    expect(button(tester, '同意する').onTap, isNotNull);

    await scrollDocumentTo(tester, 0);

    expect(readProgress(tester), '0%');
    expect(button(tester, '同意する').onTap, isNotNull);
  });

  testWidgets('画面の大きさが変わると、読んだ割合と「同意する」が更新される', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    tester.view.physicalSize = const Size(852, 393);
    await tester.pumpAndSettle();
    await openRegister(tester);
    await openDocument(tester, '利用規約');

    expect(
      tester.state<ScrollableState>(documentScroll()).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(readProgress(tester), '0%');
    expect(button(tester, '同意する').onTap, isNull);

    tester.view.physicalSize = const Size(393, 852);
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(documentScroll()).position.maxScrollExtent,
      0,
    );
    expect(readProgress(tester), '100%');
    expect(button(tester, '同意する').onTap, isNotNull);

    // 収まっただけで読了を確定しない。再び収まらなければ、最後まで読まないと押せない
    tester.view.physicalSize = const Size(852, 393);
    await tester.pumpAndSettle();

    expect(readProgress(tester), '0%');
    expect(button(tester, '同意する').onTap, isNull);
  });

  testWidgets('L2p に、プライバシーポリシーの注意書きと 10 の条文が出る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);

    await openDocument(tester, 'プライバシーポリシー');

    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expect(find.text('モック用の見本です。実際のポリシーではありません。'), findsOneWidget);
    expect(find.text('モック用の見本です。実際の規約ではありません。'), findsNothing);
    expect(find.text('第1条 サービスの内容'), findsNothing);
    for (final heading in _privacyHeadings) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(
      find.text(
        '会話には、体調、服薬、通院の話が含まれることがあります。これらは要配慮個人情報にあたる場合があるため、ご本人の同意を得たうえで取り扱います。',
      ),
      findsOneWidget,
    );
    expect(find.text('同意する'), findsOneWidget);
  });

  testWidgets('文書の終わりで「同意する」を押すと、その文書だけチェックが付いて戻る', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);

    await readDocument(tester, '利用規約');

    expect(find.text('新規登録'), findsOneWidget);
    expectAgreement(tester, '利用規約', checked: true, enabled: true);
    expectAgreement(tester, 'プライバシーポリシー', checked: false, enabled: false);
    expect(button(tester, '登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);

    await tapAgreement(tester, 'プライバシーポリシー');

    expectAgreement(tester, 'プライバシーポリシー', checked: false, enabled: false);
  });

  testWidgets('閉じると、その文書のチェックは押せないままである', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await openDocument(tester, 'プライバシーポリシー');
    await scrollDocumentTo(tester, 1);

    await tapLabel(tester, '閉じる');

    expectAgreement(tester, '利用規約', checked: false, enabled: false);
    expectAgreement(tester, 'プライバシーポリシー', checked: false, enabled: false);
    expect(find.text('未読'), findsNothing);
    expect(find.text('読みました'), findsNothing);
  });

  testWidgets('押せるチェックは押すたびに切り替わり、2つとも付いているときだけ登録できる', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    expectAgreement(tester, '利用規約', checked: true, enabled: true);
    expectAgreement(tester, 'プライバシーポリシー', checked: true, enabled: true);
    expect(button(tester, '登録する').onTap, isNotNull);
    expect(button(tester, 'Googleで登録').onTap, isNotNull);

    await tapAgreement(tester, '利用規約');

    expectAgreement(tester, '利用規約', checked: false, enabled: true);
    expect(button(tester, '登録する').onTap, isNull);
    expect(button(tester, 'Googleで登録').onTap, isNull);

    await tapAgreement(tester, '利用規約');

    expectAgreement(tester, '利用規約', checked: true, enabled: true);
    expect(button(tester, '登録する').onTap, isNotNull);
    expect(button(tester, 'Googleで登録').onTap, isNotNull);
  });

  testWidgets('両方に同意すると登録でき、メールアドレスとパスワードがデータ層に届き、L6 が開く', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    expect(find.text('登録すると、2つの内容に同意したことになります'), findsNothing);
    expect(button(tester, '登録する').onTap, isNotNull);
    expect(button(tester, 'Googleで登録').onTap, isNotNull);

    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
    await tester.pump();
    await tapText(tester, '登録する');

    expect(auth.submittedEmail, 'misaki@example.com');
    expect(auth.submittedPassword, 'hanasan1234');
    expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('メールアドレスとパスワードが空のときは、データ層を呼ばずにメッセージが出る', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    await tapText(tester, '登録する');

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

    await tapText(tester, '登録する');

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

    await tapText(tester, '登録する');

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

    await tapText(tester, '登録する');

    expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('入力を直すと、メッセージが消える', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');
    await tapText(tester, '登録する');

    await tester.enterText(find.bySemanticsLabel('メールアドレス'), 'm');
    await tester.pump();

    expect(find.text('メールアドレスとパスワードを入力してください'), findsNothing);
  });

  testWidgets('両方に同意したあとの Google での登録は「準備中です」', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openRegister(tester);
    await readDocument(tester, '利用規約');
    await readDocument(tester, 'プライバシーポリシー');

    await tapText(tester, 'Googleで登録');

    expect(find.text('準備中です'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });
}
