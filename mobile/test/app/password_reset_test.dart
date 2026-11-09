import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/password_reset_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        registeredWatchedPerson(),
        sampleHome(),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openReset(WidgetTester tester) async {
  await tester.tap(find.text('始める'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('パスワードを忘れた場合'));
  await tester.pumpAndSettle();
}

Future<void> sendReset(WidgetTester tester, String label) async {
  await tester.enterText(
    find.bySemanticsLabel('メールアドレス'),
    'misaki@example.com',
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(AppButton, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('L2 の「パスワードを忘れた場合」で L2a が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    await openReset(tester);

    expect(find.byType(PasswordResetScreen), findsOneWidget);
    expect(find.text('パスワードの再設定'), findsOneWidget);
    expect(find.text('準備中です'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('もどると L2 が開く', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await openReset(tester);

    await tester.tap(find.bySemanticsLabel('もどる'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PasswordResetScreen), findsNothing);
  });

  testWidgets('送れると送信したことを出し、ログインにもどるで L2 に戻る', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth);
    await openReset(tester);

    await sendReset(tester, '再設定メールを送る');

    expect(auth.resetEmails, ['misaki@example.com']);
    expect(find.text('メールを送信しました'), findsOneWidget);
    expect(find.text('届いたメールのリンクから、新しいパスワードを設定してください。'), findsOneWidget);
    expect(find.text('再設定メールを送る'), findsNothing);
    final check = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == AppIcons.check,
    );
    expect(tester.widget<AppIcon>(check).color, AppColors.inkPrimary);
    expect(
      (tester
                  .widget<Container>(
                    find
                        .ancestor(of: check, matching: find.byType(Container))
                        .first,
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      AppColors.stateOkSoft,
    );

    await tester.tap(find.widgetWithText(AppButton, 'ログインにもどる'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PasswordResetScreen), findsNothing);
    expect(auth.resetEmails, ['misaki@example.com']);
  });

  testWidgets('送れないときは注意を出し、もう一度送ると届く', (tester) async {
    final auth = FakeAuthRepository(resetFailures: 1);
    await pumpApp(tester, auth);
    await openReset(tester);

    await sendReset(tester, '再設定メールを送る');

    expect(auth.resetEmails, ['misaki@example.com']);
    expect(find.text('メールを送信できませんでした'), findsOneWidget);
    expect(find.text('メールアドレスと通信状況を確認して、もう一度お試しください。'), findsOneWidget);
    expect(find.text('メールを送信しました'), findsNothing);
    final retry = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'もう一度送る'),
    );
    expect(retry.leadingIcon, AppIcons.rotate);
    final alert = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == AppIcons.alert,
    );
    expect(tester.widget<AppIcon>(alert).color, AppColors.stateAlert);
    final card = tester.widget<Container>(
      find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.color == AppColors.stateAlertSoft;
      }),
    );
    expect(
      card.decoration,
      BoxDecoration(
        color: AppColors.stateAlertSoft,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: AppColors.stateAlert, width: 2),
      ),
    );

    await sendReset(tester, 'もう一度送る');

    expect(auth.resetEmails, ['misaki@example.com', 'misaki@example.com']);
    expect(find.text('メールを送信しました'), findsOneWidget);
    expect(find.text('メールを送信できませんでした'), findsNothing);
    expect(find.text('ログインにもどる'), findsOneWidget);
  });
}
