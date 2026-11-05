import 'package:flutter/material.dart';

import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_field.dart';

// 枠だけの仮の実装。PR 4 で作る。
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.onOpenAsk});

  final VoidCallback onOpenAsk;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [AppField(text: '伝えたいことを入力', minHeight: 48, onTap: onOpenAsk)],
    );
  }
}
