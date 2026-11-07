import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  static const _tabs = [
    (icon: AppIcons.home, label: 'ホーム'),
    (icon: AppIcons.list, label: '通話記録'),
    (icon: AppIcons.calendarClock, label: '予約電話'),
  ];

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E000000),
            offset: Offset(0, -6),
            blurRadius: 24,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (index, tab) in _tabs.indexed)
                _TabButton(
                  icon: tab.icon,
                  label: tab.label,
                  selected: index == currentIndex,
                  onTap: () => onSelected(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.inkPrimary : AppColors.inkSecondary;

    // AppPressable の読み上げは独立したノードなので、selected とまとめて 1 つにする
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: SizedBox(
          width: 88,
          child: AppPressable(
            onTap: onTap,
            foregroundColor: color,
            backgroundColor: selected
                ? AppColors.paperSunken
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            minHeight: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 2,
              children: [
                AppIcon(icon, color: color),
                Text(
                  label,
                  style: AppTextStyles.labelS.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
