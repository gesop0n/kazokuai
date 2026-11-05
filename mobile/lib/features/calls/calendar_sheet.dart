import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/day_mark_icon.dart';

// 「記録を見る」で閉じると、選んだ日を返す
Future<DateTime?> showCalendarSheet(
  BuildContext context, {
  required CallLog log,
  required DateTime selectedDay,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    // タブバーも暗幕の下に入れる
    useRootNavigator: true,
    // 指定しないと高さが画面の 9/16 までになり、モックの 482 が入らない
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // 不透明度 48%
    barrierColor: AppColors.nightBase.withAlpha(0x7A),
    builder: (context) => CalendarSheet(log: log, initialDay: selectedDay),
  );
}

class CalendarSheet extends StatefulWidget {
  const CalendarSheet({super.key, required this.log, required this.initialDay});

  final CallLog log;
  final DateTime initialDay;

  @override
  State<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<CalendarSheet> {
  late DateTime _selectedDay = widget.initialDay;
  late DateTime _month = DateTime(_selectedDay.year, _selectedDay.month);

  void _moveMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E3A2A19),
            offset: Offset(0, -6),
            blurRadius: 24,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Grip(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      AppIconButton(
                        AppIcons.chevronLeft,
                        semanticLabel: '前の月',
                        onTap: () => _moveMonth(-1),
                      ),
                      Expanded(
                        child: Text(
                          formatYearMonth(_month),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.titleM,
                        ),
                      ),
                      AppIconButton(
                        AppIcons.chevronRight,
                        semanticLabel: '次の月',
                        onTap: () => _moveMonth(1),
                      ),
                    ],
                  ),
                  _MonthGrid(
                    month: _month,
                    log: log,
                    selectedDay: _selectedDay,
                    onSelect: (date) => setState(() => _selectedDay = date),
                  ),
                  const _Legend(),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: AppButton(
                      label: '${formatMonthDay(_selectedDay)}の記録を見る',
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.l,
                      onTap: log.hasRecord(_selectedDay)
                          ? () => Navigator.pop(context, _selectedDay)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.lineStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.log,
    required this.selectedDay,
    required this.onSelect,
  });

  static const _weekdays = ['日', '月', '火', '水', '木', '金', '土'];

  final DateTime month;
  final CallLog log;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    // 週は日曜から始まる。DateTime の日曜は 7
    final leadingBlanks = month.weekday % 7;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var day = 1; day <= dayCount; day++)
        DateTime(month.year, month.month, day),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Row(
          children: [
            for (final weekday in _weekdays)
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  child: Center(
                    child: Text(
                      weekday,
                      style: AppTextStyles.labelS.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var start = 0; start < cells.length; start += 7)
          Row(
            children: [
              for (var i = start; i < start + 7; i++)
                Expanded(child: _cellAt(cells, i)),
            ],
          ),
      ],
    );
  }

  Widget _cellAt(List<DateTime?> cells, int index) {
    final date = index < cells.length ? cells[index] : null;
    if (date == null) return const SizedBox.shrink();
    return _DayCell(
      date: date,
      today: log.today,
      mark: log.markOf(date),
      isSelected: date == selectedDay,
      onTap: () => onSelect(date),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.mark,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final DateTime today;
  final DayMark? mark;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isToday = date == today;
    final isFuture = date.isAfter(today);
    return AppPressable(
      onTap: isFuture ? null : onTap,
      foregroundColor: AppColors.inkPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      minHeight: 50,
      selected: isSelected,
      semanticLabel: _spokenLabel(isToday),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 1,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.inkPrimary : null,
                shape: BoxShape.circle,
                border: isToday
                    ? Border.all(color: AppColors.inkPrimary, width: 1.5)
                    : null,
              ),
              child: Text(
                '${date.day}',
                softWrap: false,
                style: AppTextStyles.monoM.copyWith(
                  color: switch ((isSelected, isFuture)) {
                    (true, _) => AppColors.paperRaised,
                    (_, true) => AppColors.lineStrong,
                    _ => AppColors.inkPrimary,
                  },
                  fontWeight: isFuture ? FontWeight.w400 : null,
                ),
              ),
            ),
            DayMarkIcon(mark),
          ],
        ),
      ),
    );
  }

  // 11月5日、今日、電話に出た
  String _spokenLabel(bool isToday) => [
    formatMonthDay(date),
    if (isToday) '今日',
    if (mark == DayMark.answered) '電話に出た',
    if (mark == DayMark.missed) '不在',
  ].join('、');
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 20,
      children: [
        _LegendItem(mark: DayMark.answered, label: '電話に出た'),
        _LegendItem(mark: DayMark.missed, label: '不在'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.mark, required this.label});

  final DayMark mark;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        DayMarkIcon(mark),
        Text(
          label,
          style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
        ),
      ],
    );
  }
}
