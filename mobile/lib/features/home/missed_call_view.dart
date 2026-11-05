import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

// モックの 07b の、ヘッダーより下にあたる。スクロールと左右の余白は HomeScreen が持つ。
class MissedCallView extends StatelessWidget {
  const MissedCallView({
    super.key,
    required this.missedCall,
    required this.now,
    required this.onCallAgain,
  });

  final MissedCall missedCall;
  final DateTime now;
  final VoidCallback onCallAgain;

  @override
  Widget build(BuildContext context) {
    final lastTalk = missedCall.lastTalk;
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
            const Text('朝の電話に出ていません', style: AppTextStyles.titleL),
            const SizedBox(height: 4),
            Text(
              '$attemptedAtにかけましたが、応答がありません。外出中の可能性もあります。',
              style: AppTextStyles.bodyM,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'もう一度電話する',
              variant: AppButtonVariant.white,
              size: AppButtonSize.l,
              leadingIcon: AppIcons.phone,
              onTap: onCallAgain,
            ),
          ],
        ),
        AppCard(
          variant: AppCardVariant.paper,
          children: [
            const Text('今日の様子', style: AppTextStyles.titleM),
            Text(
              '今日はまだ話せていないので、様子は分かっていません。',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
        AppCard(
          variant: AppCardVariant.paper,
          children: [
            // このカードだけ間隔が 8 なので、1 つの Column にまとめる
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                const Text('最後に話したとき', style: AppTextStyles.titleM),
                Text(
                  '${formatRelativeDay(lastTalk.startedAt, now)} '
                  '${formatTime(lastTalk.startedAt)} ・ '
                  '${lastTalk.duration.inMinutes}分',
                  style: AppTextStyles.monoS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
                Text(lastTalk.quote, style: AppTextStyles.capS),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
