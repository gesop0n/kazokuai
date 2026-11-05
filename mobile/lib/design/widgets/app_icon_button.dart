import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton(
    this.icon, {
    super.key,
    required this.semanticLabel,
    required this.onTap,
  });

  final AppIcons icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: AppPressable(
        onTap: onTap,
        foregroundColor: AppColors.inkPrimary,
        shape: const CircleBorder(),
        semanticLabel: semanticLabel,
        child: Center(child: AppIcon(icon)),
      ),
    );
  }
}
