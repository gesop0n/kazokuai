import 'package:flutter/material.dart';

import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';

// 枠だけの仮の実装。PR 4 で作る。
class RecentCallCard extends StatelessWidget {
  const RecentCallCard({
    super.key,
    required this.call,
    required this.person,
    required this.now,
    required this.onOpenConversation,
  });

  final Call call;
  final WatchedPerson person;
  final DateTime now;
  final VoidCallback onOpenConversation;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.night,
      children: [
        AppButton(
          label: '会話を見る',
          variant: AppButtonVariant.light,
          size: AppButtonSize.m,
          onTap: onOpenConversation,
        ),
      ],
    );
  }
}
