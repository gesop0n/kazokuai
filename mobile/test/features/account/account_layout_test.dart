import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/document_screen.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/password_reset_screen.dart';
import 'package:kazokuai/features/account/register_screen.dart';
import 'package:kazokuai/features/account/sample_documents.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/layout_matrix.dart';

void main() {
  testEachLayout('L1 が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const WelcomeScreen());

    expect(find.text('家族の様子がアプリでわかる'), findsOneWidget);
    expect(find.text('見守る方は電話で話すだけ'), findsOneWidget);
    expect(find.text('会話の内容は短いまとめで確認'), findsOneWidget);
    expect(find.text('伝言や電話の時間はアプリで指定'), findsOneWidget);
    expect(find.text('始める'), findsOneWidget);
    expect(find.text('はじめる'), findsNothing);
    expect(find.text('アカウントをお持ちの方はログイン'), findsNothing);
    expect(find.textContaining('離れていても'), findsNothing);
    expect(find.textContaining('ご実家'), findsNothing);
    expect(find.bySemanticsLabel('かぞくAI'), findsNothing);
  });

  testWidgets('L1 は見出しと 3 つの行を上下の真ん中に置き、行の間は 32 と 12', (tester) async {
    const layout = LayoutCase(393, 1.0);
    await pumpScreenInLayout(tester, layout, const WelcomeScreen());

    Finder circle(AppIcons icon) => find
        .ancestor(
          of: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.icon == icon,
          ),
          matching: find.byType(Container),
        )
        .first;

    final heading = find.text('家族の様子がアプリでわかる');
    final phone = circle(AppIcons.phone);
    final sparkles = circle(AppIcons.sparkles);
    final pencil = circle(AppIcons.pencil);
    expect(tester.getTopLeft(phone).dy - tester.getBottomLeft(heading).dy, 32);
    expect(tester.getTopLeft(sparkles).dy - tester.getBottomLeft(phone).dy, 12);
    expect(
      tester.getTopLeft(pencil).dy - tester.getBottomLeft(sparkles).dy,
      12,
    );

    final headingTop = tester.getTopLeft(heading).dy;
    final linesBottom = tester.getBottomLeft(pencil).dy;
    final buttonTop = tester
        .getTopLeft(find.widgetWithText(AppButton, '始める'))
        .dy;
    expect(headingTop, closeTo(buttonTop - linesBottom, 1));

    final icon = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.icon == AppIcons.phone,
      ),
    );
    expect(icon.color, AppColors.inkPrimary);
    expect(
      (tester.widget<Container>(phone).decoration! as BoxDecoration).color,
      AppColors.welcomeIconCircle,
    );
  });

  test('ロゴと絵のファイルはアプリのアセットにない', () {
    expect(File('assets/logos/kazoku.svg').existsSync(), isFalse);
    expect(Directory('assets/illustrations').existsSync(), isFalse);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('illustrations')));
    expect(pubspec, isNot(contains('kazoku.svg')));
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
    expect(find.text('パスワードを忘れた場合'), findsOneWidget);
    expect(find.text('はじめての方は新規登録'), findsOneWidget);
    expect(find.text('新規登録へ'), findsNothing);
    expect(find.text('はじめての方は'), findsNothing);
  });

  testWidgets('L2 の 2 つのリンクは幅と文字色が違い、文字の下端に線がある', (tester) async {
    const layout = LayoutCase(393, 1.0);
    await pumpScreenInLayout(tester, layout, const LoginScreen());

    final signUp = find.widgetWithText(AppButton, 'はじめての方は新規登録');
    final forgot = find.widgetWithText(AppButton, 'パスワードを忘れた場合');
    expect(tester.getSize(signUp).width, layout.width - 32);
    expect(tester.getSize(forgot).width, lessThan(layout.width - 32));
    expect(tester.getCenter(forgot).dx, closeTo(layout.width / 2, 1));
    expect(
      tester.widget<Text>(find.text('はじめての方は新規登録')).style?.color,
      AppColors.inkSecondary,
    );
    expect(
      tester.widget<Text>(find.text('パスワードを忘れた場合')).style?.color,
      AppColors.inkPrimary,
    );

    void expectUnderline(String label, Color color) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
            .first,
      );
      expect(
        (box.decoration as BoxDecoration).border?.bottom,
        BorderSide(color: color),
      );
      expect(tester.widget<Text>(find.text(label)).style?.decoration, isNull);
    }

    expectUnderline('はじめての方は新規登録', AppColors.inkSecondary);
    expectUnderline('パスワードを忘れた場合', AppColors.inkPrimary);
  });

  testEachLayout('L2a が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const PasswordResetScreen());

    expect(find.text('パスワードの再設定'), findsOneWidget);
    expect(
      find.text('登録したメールアドレスを入力してください。再設定用のリンクをメールでお送りします。'),
      findsOneWidget,
    );
    expect(find.text('再設定メールを送る'), findsOneWidget);
  });

  testEachLayout('L2a が送信したことを出しても崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const PasswordResetScreen(),
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );

    await _sendReset(tester);

    expect(find.text('メールを送信しました'), findsOneWidget);
    expect(find.text('ログインにもどる'), findsOneWidget);
  });

  testEachLayout('L2ab が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const PasswordResetScreen(),
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(resetFailures: 1),
        ),
      ],
    );

    await _sendReset(tester);

    expect(find.text('メールを送信できませんでした'), findsOneWidget);
    expect(find.text('もう一度送る'), findsOneWidget);
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

Future<void> _sendReset(WidgetTester tester) async {
  await tester.enterText(
    find.bySemanticsLabel('メールアドレス'),
    'misaki@example.com',
  );
  await tester.pump();
  final send = find.widgetWithText(AppButton, '再設定メールを送る');
  await tester.ensureVisible(send);
  await tester.tap(send);
  await tester.pumpAndSettle();
}
