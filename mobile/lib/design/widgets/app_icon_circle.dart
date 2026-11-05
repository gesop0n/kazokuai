import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';

// 押せない飾り。読み上げの対象にしない。
class AppIconCircle extends StatelessWidget {
  const AppIconCircle(this.icon, {super.key});

  final AppIcons icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.paperSunken,
        shape: BoxShape.circle,
      ),
      child: AppIcon(icon, size: 18),
    );
  }
}
