import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/day_mark_icon.dart';
import 'package:kazokuai/features/home/home_format.dart';

// 今日までの 7 日。全体で 1 つのボタンになる。
class MiniCalendar extends StatelessWidget {
  const MiniCalendar({
    super.key,
    required this.log,
    required this.selectedDay,
    required this.onTap,
  });

  final CallLog log;
  final DateTime selectedDay;
  final VoidCallback onTap;

  // テストから日を探すためのキー
  @visibleForTesting
  static Key dayKey(DateTime date) => ValueKey('mini-day-$date');

  @override
  Widget build(BuildContext context) {
    final today = log.today;
    return MergeSemantics(
      child: Semantics(
        value: formatMonthDay(selectedDay),
        child: AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          backgroundColor: AppColors.paperRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(8),
          semanticLabel: 'カレンダーを開いて日付を選ぶ',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                _MiniHead(label: formatYearMonth(today)),
                Row(
                  children: [
                    for (var back = 6; back >= 0; back--)
                      Expanded(
                        child: _MiniDay(
                          date: DateTime(
                            today.year,
                            today.month,
                            today.day - back,
                          ),
                          log: log,
                          selectedDay: selectedDay,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniHead extends StatelessWidget {
  const _MiniHead({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.labelM)),
            const AppIcon(
              AppIcons.chevronDown,
              size: 20,
              color: AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.date,
    required this.log,
    required this.selectedDay,
  });

  final DateTime date;
  final CallLog log;
  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    final isSelected = date == selectedDay;
    final color = isSelected ? AppColors.paperRaised : AppColors.inkPrimary;
    return Container(
      key: MiniCalendar.dayKey(date),
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.inkPrimary : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 1,
        children: [
          Text(
            weekdayLabel(date),
            style: AppTextStyles.labelS.copyWith(color: color),
          ),
          Text(
            '${date.day}',
            style: AppTextStyles.monoM.copyWith(color: color),
          ),
          DayMarkIcon(
            log.markOf(date),
            answeredColor: isSelected
                ? AppColors.paperRaised
                : AppColors.lineStrong,
          ),
        ],
      ),
    );
  }
}
