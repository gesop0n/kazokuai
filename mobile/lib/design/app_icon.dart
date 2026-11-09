import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kazokuai/design/app_colors.dart';

enum AppIcons {
  phone('phone'),
  phoneMissed('phone-missed'),
  home('home'),
  list('list'),
  calendarClock('calendar-clock'),
  utensils('utensils'),
  moon('moon'),
  heart('heart'),
  alert('alert'),
  rotate('rotate'),
  bell('bell'),
  settings('settings'),
  lock('lock'),
  play('play'),
  plus('plus'),
  x('x'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  sparkles('sparkles'),
  check('check'),
  pencil('pencil'),
  eye('eye');

  const AppIcons(this.fileName);

  final String fileName;

  String get assetPath => 'assets/icons/$fileName.svg';
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color = AppColors.inkPrimary,
  });

  final AppIcons icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      icon.assetPath,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
