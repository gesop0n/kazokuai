import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';

// 仮の実装。次の PR で作る。
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
    return AppCard(
      variant: AppCardVariant.alert,
      children: [
        const Text('朝の電話に出ていません', style: AppTextStyles.titleL),
        const SizedBox(height: 16),
        AppButton(
          label: 'もう一度電話する',
          variant: AppButtonVariant.white,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.phone,
          onTap: onCallAgain,
        ),
      ],
    );
  }
}
