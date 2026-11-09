import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

// モックの askCard。カード全体が 01 を開くボタン。
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.onOpenAsk});

  final VoidCallback onOpenAsk;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onOpenAsk,
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: BorderSide(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.inkPrimary),
        child: const Row(
          children: [
            Expanded(child: Text('AIに伝えてもらう', style: AppTextStyles.titleM)),
            AppIcon(
              AppIcons.chevronRight,
              size: 20,
              color: AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
