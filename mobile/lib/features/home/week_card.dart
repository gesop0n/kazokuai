import 'dart:math';

import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_card_heading.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.week, required this.onOpenCallLog});

  final WeekCallRecords week;
  final VoidCallback onOpenCallLog;

  // テストから棒を探すためのキー
  @visibleForTesting
  static Key barKey(DateTime date) => ValueKey('week-bar-$date');

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        const HomeCardHeading(title: 'この7日間の電話', label: '棒の数字は話した分数'),
        Wrap(
          spacing: 24,
          children: [
            _Stat(
              label: '電話に出た日',
              value: '${week.answeredDays}',
              unit: ' / ${week.days.length}日',
            ),
            _Stat(
              label: '話した時間',
              value: '${week.totalTalkedMinutes}',
              unit: ' 分',
            ),
          ],
        ),
        _WeekChart(days: week.days),
        AppButton(
          label: '通話記録を見る',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          trailingIcon: AppIcons.chevronRight,
          onTap: onOpenCallLog,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
        ),
        Text.rich(
          TextSpan(
            style: AppTextStyles.labelL,
            children: [
              TextSpan(
                text: value,
                // モックの mono-m を 24/32 にした形
                style: AppTextStyles.monoM.copyWith(
                  fontSize: 24,
                  height: 32 / 24,
                ),
              ),
              TextSpan(text: unit),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<DayCallRecord> days;

  // 文字が大きくなると数字の分だけ伸びる
  static const _plotMinHeight = 112.0;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = days.fold(
      0,
      (longest, day) => max(longest, day.talkedMinutes ?? 0),
    );
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: _spokenLabel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _plotMinHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: _DayBar(
                      day: day,
                      maxMinutes: maxMinutes,
                      isToday: _isToday(day),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(
            height: 1,
            child: ColoredBox(color: AppColors.lineStrong),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _DayLabel(date: day.date, isToday: _isToday(day)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // WeekCard は now を受け取らないので、最後の日を今日として扱う
  bool _isToday(DayCallRecord day) => day == days.last;

  // 10月30日14分、31日22分、11月1日31分、2日は不在。月は変わったときだけ書く。
  String _spokenLabel() {
    final parts = <String>[];
    int? month;
    for (final day in days) {
      final monthPart = day.date.month == month ? '' : '${day.date.month}月';
      final minutes = day.talkedMinutes;
      final talked = minutes == null ? 'は不在' : '$minutes分';
      parts.add('$monthPart${day.date.day}日$talked');
      month = day.date.month;
    }
    return 'この7日間の通話時間。${parts.join('、')}';
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.maxMinutes,
    required this.isToday,
  });

  final DayCallRecord day;
  final int maxMinutes;
  final bool isToday;

  static const _minHeight = 6.0;
  static const _maxHeight = 92.0;

  @override
  Widget build(BuildContext context) {
    final minutes = day.talkedMinutes;
    if (minutes == null) return const _AbsentMark();
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 1,
      children: [
        Text(
          '$minutes',
          textAlign: TextAlign.center,
          style: AppTextStyles.monoS.copyWith(color: AppColors.inkPrimary),
        ),
        Container(
          key: WeekCard.barKey(day.date),
          width: 16,
          height: _height(minutes),
          decoration: BoxDecoration(
            color: isToday ? AppColors.inkPrimary : AppColors.lineStrong,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ],
    );
  }

  double _height(int minutes) {
    // 全ての日が 0 分のときに 0 で割らない
    if (maxMinutes == 0) return _minHeight;
    return max(_minHeight, minutes / maxMinutes * _maxHeight);
  }
}

class _AbsentMark extends StatelessWidget {
  const _AbsentMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '不在',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelS.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.stateAlertOn,
          ),
        ),
        const SizedBox(height: 5),
        // モックの × は 18 の枠の中の 14 の線で描かれている。
        // x.svg は 24 の枠の中の 12 の線なので、28 で描くと線の長さが揃う。
        const SizedBox.square(
          dimension: 18,
          child: OverflowBox(
            maxWidth: 28,
            maxHeight: 28,
            child: AppIcon(AppIcons.x, size: 28, color: AppColors.accentCall),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.date, required this.isToday});

  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final color = isToday ? AppColors.inkPrimary : AppColors.inkSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${date.day}',
          textAlign: TextAlign.center,
          style: AppTextStyles.monoS.copyWith(
            fontWeight: isToday ? FontWeight.w500 : FontWeight.w400,
            color: color,
          ),
        ),
        Text(
          weekdayLabel(date),
          textAlign: TextAlign.center,
          style: AppTextStyles.labelS.copyWith(
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            color: color,
          ),
        ),
      ],
    );
  }
}
