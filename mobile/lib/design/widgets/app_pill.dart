import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';

enum AppPillVariant {
  care(background: AppColors.stateCareSoft, foreground: AppColors.stateCareOn),
  ok(background: AppColors.stateOkSoft, foreground: AppColors.stateOkOn);

  const AppPillVariant({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.variant,
    this.icon,
    required this.label,
  });

  final AppPillVariant variant;
  final AppIcons? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: variant.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: icon == null ? 0 : 4,
        children: [
          if (icon != null) AppIcon(icon, size: 14, color: variant.foreground),
          Flexible(
            child: Text(
              label,
              // .pill は .label-s と同じ大きさで、太さだけ 700
              style: AppTextStyles.labelS.copyWith(
                fontWeight: FontWeight.w700,
                color: variant.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
