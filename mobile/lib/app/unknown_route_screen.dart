import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';

// 道の値が予約の番号になっていないとき。落ちずに、家族が戻れる画面を出す。
class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('このページは開けません', style: AppTextStyles.titleL),
              const Spacer(),
              AppButton(
                label: '予約電話へ',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: () => context.go('/booking'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
