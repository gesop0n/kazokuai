import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';

final appTheme = ThemeData(
  colorScheme: const ColorScheme.light(
    primary: AppColors.inkPrimary,
    onPrimary: AppColors.paperRaised,
    surface: AppColors.paperBase,
    onSurface: AppColors.inkPrimary,
  ),
  // カーソルと選択の色は primary に従うが、iOS の選択ハンドルは従わない
  textSelectionTheme: const TextSelectionThemeData(
    selectionHandleColor: AppColors.inkPrimary,
  ),
  fontFamily: 'BIZUDPGothic',
  scaffoldBackgroundColor: AppColors.paperBase,
  splashFactory: NoSplash.splashFactory,
);
