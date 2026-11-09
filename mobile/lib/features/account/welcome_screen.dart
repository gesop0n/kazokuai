import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';

// L1。ログインしていないときに開く
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '家族の様子がアプリでわかる',
                            style: AppTextStyles.display.copyWith(
                              fontSize: 26,
                              height: 36 / 26,
                              letterSpacing: .02 * 26,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 12,
                            children: [
                              _WelcomeLine(AppIcons.phone, '見守る方は電話で話すだけ'),
                              _WelcomeLine(AppIcons.sparkles, '会話の内容は短いまとめで確認'),
                              _WelcomeLine(AppIcons.pencil, '伝言や電話の時間はアプリで指定'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppButton(
                label: '始める',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: () => context.goNamed(AppRoutes.login),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeLine extends StatelessWidget {
  const _WelcomeLine(this.icon, this.text);

  final AppIcons icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.welcomeIconCircle,
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 18, color: AppColors.inkPrimary),
        ),
        Expanded(child: Text(text, style: AppTextStyles.labelM)),
      ],
    );
  }
}
