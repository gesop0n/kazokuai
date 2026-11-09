import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';

// 08d。ログアウトの前に、電話と記録は続くことを伝える。
// 「ログアウトする」で L1 に戻る。ルーターが、ログインしていない家族をそこへ送る
class LogoutScreen extends ConsumerWidget {
  const LogoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: 'ログアウト',
              leadingIcon: AppIcons.x,
              leadingLabel: '閉じる',
              onLeadingTap: () => popOrGoToParent(context),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _LogoutMark(),
                          const SizedBox(height: 16),
                          const Text(
                            'ログアウトしますか？',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleL,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ログアウトしても、AIからの電話や\n会話の記録はそのまま続きます。\nもう一度見るときは、ログインしてください。',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyM.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                spacing: 4,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: 'ログアウトする',
                    variant: AppButtonVariant.alert,
                    size: AppButtonSize.l,
                    onTap: () => ref.read(authRepositoryProvider).signOut(),
                  ),
                  AppButton(
                    label: 'アカウント情報にもどる',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.m,
                    underlined: true,
                    onTap: () => popOrGoToParent(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutMark extends StatelessWidget {
  const _LogoutMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.stateAlertSoft,
          shape: BoxShape.circle,
        ),
        child: const AppIcon(
          AppIcons.logOut,
          size: 36,
          color: AppColors.stateAlert,
        ),
      ),
    );
  }
}
