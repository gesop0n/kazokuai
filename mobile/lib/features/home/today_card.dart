import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/features/home/home_card_heading.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.call});

  final Call call;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        HomeCardHeading(
          title: '今日の様子',
          label: '${formatTime(call.startedAt)}の会話より',
        ),
        for (final (index, condition) in call.summary.conditions.indexed)
          _ConditionRow(condition, hasLineAbove: index > 0),
        Text(
          'ご本人の話をAIがまとめたものです。医療上の判断ではありません。',
          style: AppTextStyles.bodyS.copyWith(color: AppColors.inkSecondary),
        ),
      ],
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow(this.condition, {required this.hasLineAbove});

  final Condition condition;
  final bool hasLineAbove;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (condition.kind) {
      ConditionKind.meal => (AppIcons.utensils, '食事'),
      ConditionKind.sleep => (AppIcons.moon, '睡眠'),
      ConditionKind.health => (AppIcons.heart, '体調'),
    };
    return Container(
      padding: EdgeInsets.only(top: hasLineAbove ? 12 : 0),
      decoration: hasLineAbove
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          AppIconCircle(icon),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AppTextStyles.labelS.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ),
                    if (condition.needsAttention)
                      const AppPill(
                        variant: AppPillVariant.care,
                        icon: AppIcons.alert,
                        label: '気になる話',
                      ),
                  ],
                ),
                Text(condition.value, style: AppTextStyles.labelL),
                Text(
                  condition.quote,
                  style: AppTextStyles.capS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
