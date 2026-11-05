import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';

// 枠だけの仮の実装。PR 5 で作る。
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.week, required this.onOpenCallLog});

  final WeekCallRecords week;
  final VoidCallback onOpenCallLog;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        AppButton(
          label: '通話記録を見る',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          trailingIcon: AppIcons.chevronRight,
          onTap: onOpenCallLog,
        ),
      ],
    );
  }
}
