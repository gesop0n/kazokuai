import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

enum AppButtonSize {
  l(
    minHeight: 56,
    horizontalPadding: 24,
    iconSize: 20,
    textStyle: AppTextStyles.labelL,
  ),
  m(
    minHeight: 44,
    horizontalPadding: 16,
    iconSize: 18,
    textStyle: AppTextStyles.labelM,
  );

  const AppButtonSize({
    required this.minHeight,
    required this.horizontalPadding,
    required this.iconSize,
    required this.textStyle,
  });

  final double minHeight;
  final double horizontalPadding;
  final double iconSize;
  final TextStyle textStyle;
}

enum AppButtonVariant {
  record(background: AppColors.accentCall, foreground: AppColors.onAccentCall),
  secondary(
    background: AppColors.paperRaised,
    foreground: AppColors.inkPrimary,
    border: BorderSide(color: AppColors.lineStrong, width: 1.5),
  ),
  light(background: AppColors.nightText, foreground: AppColors.nightBase);

  const AppButtonVariant({
    required this.background,
    required this.foreground,
    this.border = BorderSide.none,
  });

  final Color background;
  final Color foreground;
  final BorderSide border;
}

// 親が幅を決めればその幅に広がり、決めなければ中身の幅になる
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.variant,
    required this.size,
    required this.onTap,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final VoidCallback onTap;
  final AppIcons? leadingIcon;
  final AppIcons? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = this.leadingIcon;
    final trailingIcon = this.trailingIcon;
    return AppPressable(
      onTap: onTap,
      foregroundColor: variant.foreground,
      backgroundColor: variant.background,
      shape: StadiumBorder(side: variant.border),
      minHeight: size.minHeight,
      padding: EdgeInsets.symmetric(horizontal: size.horizontalPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          if (leadingIcon != null)
            AppIcon(
              leadingIcon,
              size: size.iconSize,
              color: variant.foreground,
            ),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: size.textStyle.copyWith(color: variant.foreground),
            ),
          ),
          if (trailingIcon != null)
            AppIcon(
              trailingIcon,
              size: size.iconSize,
              color: variant.foreground,
            ),
        ],
      ),
    );
  }
}
