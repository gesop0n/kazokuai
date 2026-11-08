import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

// .field の見た目で文字を表示する部品。入力はできず、押すと onTap を呼ぶ。
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.text,
    required this.onTap,
    this.minHeight = 56,
  });

  final String text;
  final VoidCallback onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: const BorderSide(color: AppColors.lineStrong, width: 1.5),
      ),
      minHeight: minHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: Text(
          text,
          style: AppTextStyles.labelM.copyWith(color: AppColors.inkSecondary),
        ),
      ),
    );
  }
}
