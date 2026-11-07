import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/document_screen.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/register_screen.dart';
import 'package:kazokuai/features/account/sample_documents.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/layout_matrix.dart';

void main() {
  testEachLayout('L1 が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const WelcomeScreen());

    expect(find.text('はじめる'), findsOneWidget);
    expect(find.text('アカウントをお持ちの方はログイン'), findsOneWidget);
  });

  testEachLayout('L1 の絵は、幅に収まるように縮む', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const WelcomeScreen());

    final illustration = find.bySemanticsLabel('固定電話で話しながら笑っているおじいちゃん');
    expect(tester.getTopLeft(illustration).dx, greaterThanOrEqualTo(24));
    expect(
      tester.getTopRight(find.bySemanticsLabel('スマートフォンを見ながら笑っている娘')).dx,
      lessThanOrEqualTo(layout.width - 24),
    );
  });

  testEachLayout('L2 がメッセージを出しても崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const LoginScreen(),
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(unreachable: true),
        ),
      ],
    );

    await tester.enterText(
      find.bySemanticsLabel('メールアドレス'),
      'misaki@example.com',
    );
    await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
    await tester.pump();
    final logIn = find.widgetWithText(AppButton, 'ログイン');
    await tester.ensureVisible(logIn);
    await tester.tap(logIn);
    await tester.pump();

    expect(find.text('ログインできませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);
  });

  testEachLayout('L2d が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const RegisterScreen());

    expect(find.text('新規登録'), findsOneWidget);
    expect(find.text('利用規約'), findsOneWidget);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expect(find.text('同意して登録する'), findsOneWidget);
  });

  testEachLayout('L2c が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const DocumentScreen(document: termsDocument),
    );

    expect(find.text('利用規約'), findsOneWidget);
    expect(find.text('読みました'), findsOneWidget);
    expect(find.text('モック用の見本です。実際の規約ではありません。'), findsOneWidget);
  });

  testWidgets('L2 のパスワードは、目のボタンで表示と非表示を切り替えられる', (tester) async {
    await pumpScreenInLayout(
      tester,
      const LayoutCase(393, 1.0),
      const LoginScreen(),
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
    bool isObscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.bySemanticsLabel('パスワード'),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;

    expect(isObscured(), isTrue);

    await tester.tap(find.bySemanticsLabel('パスワードを表示'));
    await tester.pump();
    expect(isObscured(), isFalse);

    await tester.tap(find.bySemanticsLabel('パスワードを隠す'));
    await tester.pump();
    expect(isObscured(), isTrue);
  });
}
