import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
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

  testWidgets('L1 は文字の代わりにロゴを出し、アイコンの円は薄い青', (tester) async {
    await pumpScreenInLayout(
      tester,
      const LayoutCase(393, 1.0),
      const WelcomeScreen(),
    );

    expect(find.text('かぞくAI'), findsNothing);
    final logo = tester.widget<SvgPicture>(
      find.byWidgetPredicate(
        (widget) => widget is SvgPicture && widget.semanticsLabel == 'かぞくAI',
      ),
    );
    expect(logo.height, 45);
    expect(logo.width, 45 * 3078 / 1014);
    // flutter_svg は paint-order を描かない。枠を先、塗りを後に分けてある。
    final logoSvg = await rootBundle.loadString('assets/logos/kazoku.svg');
    expect(logoSvg, isNot(contains('paint-order')));
    expect(
      logoSvg.indexOf(
        '<g fill="none" stroke="#000" stroke-width="28" stroke-linejoin="round">',
      ),
      lessThan(logoSvg.indexOf('<g fill="#808080" stroke="none">')),
    );
    expect(
      logoSvg.indexOf(
        '<path fill="none" stroke="#000" stroke-width="28" stroke-linejoin="round" d="M2447',
      ),
      lessThan(logoSvg.indexOf('<path fill="#808080" stroke="none" d="M2447')),
    );

    final phone = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.icon == AppIcons.phone,
      ),
    );
    expect(phone.color, AppColors.inkPrimary);
    final circle = tester.widget<Container>(
      find
          .ancestor(of: find.byWidget(phone), matching: find.byType(Container))
          .first,
    );
    expect(
      (circle.decoration! as BoxDecoration).color,
      AppColors.welcomeIconCircle,
    );

    final grandpa = await rootBundle.loadString(
      'assets/illustrations/grandpa.svg',
    );
    expect(grandpa, contains('#B4EBFA'));
    expect(grandpa, contains('#FFF3D1'));
    expect(
      await rootBundle.loadString('assets/illustrations/daughter.svg'),
      contains('#EDC58F'),
    );
    expect(
      await rootBundle.loadString('assets/illustrations/heart.svg'),
      contains('#DC3800'),
    );
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
