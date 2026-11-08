import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

// モックの 07b の、ヘッダーより下にあたる。スクロールと左右の余白は HomeScreen が持つ。
class MissedCallView extends StatelessWidget {
  const MissedCallView({
    super.key,
    required this.missedCall,
    required this.onOpenAsk,
  });

  final MissedCall missedCall;
  final VoidCallback onOpenAsk;

  @override
  Widget build(BuildContext context) {
    final attemptedAt = missedCall.attemptedAt.map(formatTime).join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        AppCard(
          variant: AppCardVariant.alert,
          children: [
            Row(
              spacing: 6,
              children: [
                const AppIcon(
                  AppIcons.phoneMissed,
                  size: 16,
                  color: AppColors.onStateAlert,
                ),
                const Expanded(
                  child: Text('確認をお願いします', style: AppTextStyles.labelM),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('電話に出ていません', style: AppTextStyles.titleL),
            const SizedBox(height: 4),
            Text(
              '$attemptedAtにかけましたが、応答がありませんでした。',
              style: AppTextStyles.bodyM,
            ),
          ],
        ),
        AskCard(onOpenAsk: onOpenAsk),
        AppCard(
          variant: AppCardVariant.paper,
          children: [
            const Text('今日の様子', style: AppTextStyles.titleM),
            Text(
              '今日はまだ話せていません。',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
