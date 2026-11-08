import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

enum AppChipSize {
  m(height: 36, horizontalPadding: 16),
  // 01 の話し方
  s(height: 32, horizontalPadding: 12);

  const AppChipSize({required this.height, required this.horizontalPadding});

  final double height;
  final double horizontalPadding;
}

// 上下の透明の余白を足して、押せる領域を 44pt にする(モックの .chip-hit)。
// 余白も部品の大きさに入るので、Wrap で並べるときは runSpacing を 0 にするとモックの間隔 8 になる。
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.size = AppChipSize.m,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppChipSize size;
  final AppIcons? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final foreground = selected ? AppColors.paperRaised : AppColors.inkPrimary;
    return AppPressable(
      onTap: onTap,
      foregroundColor: foreground,
      backgroundColor: selected ? AppColors.inkPrimary : AppColors.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: BorderSide(
          color: selected ? AppColors.inkPrimary : AppColors.lineStrong,
        ),
      ),
      minHeight: size.height,
      hitPadding: (44 - size.height) / 2,
      padding: EdgeInsets.symmetric(horizontal: size.horizontalPadding),
      selected: selected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          if (icon != null) AppIcon(icon, size: 16, color: foreground),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelM.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
