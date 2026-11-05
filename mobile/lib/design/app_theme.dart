import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';

final appTheme = ThemeData(
  colorScheme: const ColorScheme.light(
    surface: AppColors.paperBase,
    onSurface: AppColors.inkPrimary,
  ),
  fontFamily: 'ZenMaruGothic',
  scaffoldBackgroundColor: AppColors.paperBase,
  splashFactory: NoSplash.splashFactory,
);
