import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_field.dart';

class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.onOpenAsk});

  final VoidCallback onOpenAsk;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('AIに伝えてもらう', style: AppTextStyles.titleM),
            Text(
              '予約もできます',
              // Wrap には baseline 揃えがないので、行の高さを見出しと同じにして揃える
              strutStyle: StrutStyle.fromTextStyle(
                AppTextStyles.titleM,
                forceStrutHeight: true,
              ),
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
        AppField(text: '伝えたいことを入力', minHeight: 48, onTap: onOpenAsk),
        AppButton(
          label: '通話',
          variant: AppButtonVariant.record,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.phone,
          onTap: onOpenAsk,
        ),
      ],
    );
  }
}
