import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

class RecentCallCard extends StatelessWidget {
  const RecentCallCard({
    super.key,
    required this.call,
    required this.now,
    required this.onOpenConversation,
  });

  final Call call;
  final DateTime now;
  final VoidCallback onOpenConversation;

  @override
  Widget build(BuildContext context) {
    final summary = call.summary;
    final quote = summary.quote;
    return AppCard(
      variant: AppCardVariant.night,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('直近の電話', style: AppTextStyles.labelM),
            Text(
              '${formatRelativeDay(call.startedAt, now)} '
              '${formatTime(call.startedAt)} ・ ${call.duration.inMinutes}分',
              style: AppTextStyles.monoS.copyWith(
                color: AppColors.nightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(summary.headline, style: AppTextStyles.titleM),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: AppColors.nightLine, width: 2),
            ),
          ),
          child: Text(quote.text, style: AppTextStyles.capS),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: '会話を見る',
          variant: AppButtonVariant.light,
          size: AppButtonSize.m,
          trailingIcon: AppIcons.chevronRight,
          onTap: onOpenConversation,
        ),
      ],
    );
  }
}
