import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';

class AppAiTag extends StatelessWidget {
  const AppAiTag({
    super.key,
    required this.label,
    this.color = AppColors.inkSecondary,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        AppIcon(AppIcons.sparkles, size: 16, color: color),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.labelS.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
