import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';

// 枠だけの仮の実装。PR 5 で作る。
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.call});

  final Call call;

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      variant: AppCardVariant.paper,
      children: [Text('今日の様子', style: AppTextStyles.titleM)],
    );
  }
}
