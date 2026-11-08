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
        border: Border(top: BorderSide(color: AppColors.lineStrong)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (index, tab) in _tabs.indexed)
              Expanded(
                child: _TabButton(
                  icon: tab.icon,
                  label: tab.label,
                  selected: index == currentIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
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

    // AppPressable の読み上げは独立したノードなので、selected とまとめて 1 つにする。
    // 上の 1 は枠線の分。開いているタブの線は、その枠線に重ねて引く。
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SizedBox(
            width: double.infinity,
            child: MergeSemantics(
              child: Semantics(
                selected: selected,
                child: AppPressable(
                  onTap: onTap,
                  foregroundColor: color,
                  backgroundColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(),
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
          ),
        ),
        if (selected)
          const Positioned(
            top: 0,
            left: 20,
            right: 20,
            height: 3,
            child: ColoredBox(color: AppColors.inkPrimary),
          ),
      ],
    );
  }
}
