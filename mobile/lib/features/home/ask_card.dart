import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/features/home/home_card_heading.dart';

class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.onOpenAsk, this.isCalling = false});

  final VoidCallback onOpenAsk;

  // 通話中の見た目は次の PR で作る
  final bool isCalling;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        const HomeCardHeading(title: 'AIに伝えてもらう', label: '予約もできます'),
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
