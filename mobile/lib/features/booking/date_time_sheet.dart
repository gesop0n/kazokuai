import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/usual_answer_times.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';

// モックの行は 36。押せる領域は 44 以上にする
const _itemExtent = 44.0;
const _wheelHeight = 180.0;
const _columnWidth = 88.0;

const _wheelIdle = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w400,
  fontSize: 22,
  height: 28 / 22,
  letterSpacing: 0,
  color: AppColors.inkTertiary,
  leadingDistribution: TextLeadingDistribution.even,
);

const _wheelSelected = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w700,
  fontSize: 26,
  height: 28 / 26,
  letterSpacing: 0,
  color: AppColors.inkPrimary,
  leadingDistribution: TextLeadingDistribution.even,
);

const _fade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x00000000),
    Color(0xFF000000),
    Color(0xFF000000),
    Color(0x00000000),
  ],
  stops: [0, 0.35, 0.65, 1],
);

// 決定した日時を返す。閉じただけなら null で、01 の日時は変えない。
Future<DateTime?> showDateTimeSheet(
  BuildContext context, {
  required DateTime initial,
  required ValueListenable<CallLog?> answeredLog,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // 回転式を上下に回すドラッグを、シートを閉じる動きに取られないようにする
    enableDrag: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: AppColors.scrim,
    builder: (context) =>
        DateTimeSheet(initial: initial, answeredLog: answeredLog),
  );
}

// 01b。日付はカレンダー、時刻は 5 分ごとの回転式。
class DateTimeSheet extends StatefulWidget {
  const DateTimeSheet({
    super.key,
    required this.initial,
    required this.answeredLog,
  });

  final DateTime initial;

  // 開いたあとに届く通話記録も、よく出る時刻に反映する
  final ValueListenable<CallLog?> answeredLog;

  @override
  State<DateTimeSheet> createState() => _DateTimeSheetState();
}

class _DateTimeSheetState extends State<DateTimeSheet> {
  static const _weekdays = ['日', '月', '火', '水', '木', '金', '土'];

  late DateTime _selectedDay;
  late DateTime _month;
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  // 候補や数字への移動中は、途中の位置で選んだ時刻を上書きしない
  int _spinSerial = 0;
  int? _heldSpin;
  int _heldPending = 0;

  @override
  void initState() {
    super.initState();
    _selectedDay = _clampDay(
      DateTime(widget.initial.year, widget.initial.month, widget.initial.day),
    );
    _month = DateTime(_selectedDay.year, _selectedDay.month);
    final time = snapToFiveMinutes(widget.initial.hour, widget.initial.minute);
    _hour = time.hour;
    _minute = time.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute ~/ 5);
    widget.answeredLog.addListener(_onAnsweredLog);
  }

  @override
  void didUpdateWidget(DateTimeSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answeredLog == widget.answeredLog) return;
    oldWidget.answeredLog.removeListener(_onAnsweredLog);
    widget.answeredLog.addListener(_onAnsweredLog);
  }

  @override
  void dispose() {
    widget.answeredLog.removeListener(_onAnsweredLog);
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _onAnsweredLog() {
    if (mounted) setState(() {});
  }

  DateTime _clampDay(DateTime day) {
    if (day.isBefore(bookingToday)) return bookingToday;
    if (day.isAfter(bookingLastDate)) return bookingLastDate;
    return day;
  }

  bool _canSelect(DateTime date) =>
      !date.isBefore(bookingToday) && !date.isAfter(bookingLastDate);

  // 前の月がすべて基準日より前なら、戻る先がない
  bool get _canGoBack {
    final previousLast = DateTime(_month.year, _month.month, 0);
    return !previousLast.isBefore(bookingToday);
  }

  bool get _canGoForward {
    final nextFirst = DateTime(_month.year, _month.month + 1);
    return !nextFirst.isAfter(bookingLastDate);
  }

  void _moveMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  // 押した時点で値を決め、回転はあとから追いつく。
  // 回転の途中で決めても、通り過ぎた時刻にはならない。
  void _spinTo(TimeOfDay time) {
    final generation = ++_spinSerial;
    _heldSpin = generation;
    _heldPending = 2;
    setState(() {
      _hour = time.hour;
      _minute = time.minute;
    });
    _animate(_hourController, time.hour, generation);
    _animate(_minuteController, time.minute ~/ 5, generation);
  }

  void _animate(
    FixedExtentScrollController controller,
    int item,
    int generation,
  ) {
    controller
        .animateToItem(
          item,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (!mounted || _heldSpin != generation) return;
          _heldPending--;
          if (_heldPending > 0) return;
          _heldSpin = null;
        });
  }

  void _confirm() {
    Navigator.pop(
      context,
      DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        _hour,
        _minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label =
        '${formatPickDate(_selectedDay)} ${formatSheetTime(_hour, _minute)}にする';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.value),
        ),
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
                spacing: 12,
                children: [
                  Row(
                    children: [
                      _MonthButton(
                        icon: AppIcons.chevronLeft,
                        label: '前の月',
                        onTap: _canGoBack ? () => _moveMonth(-1) : null,
                      ),
                      Expanded(
                        child: Text(
                          formatYearMonth(_month),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.titleM,
                        ),
                      ),
                      _MonthButton(
                        icon: AppIcons.chevronRight,
                        label: '次の月',
                        onTap: _canGoForward ? () => _moveMonth(1) : null,
                      ),
                    ],
                  ),
                  _MonthGrid(
                    month: _month,
                    weekdays: _weekdays,
                    selectedDay: _selectedDay,
                    canSelect: _canSelect,
                    onSelect: (date) => setState(() => _selectedDay = date),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      const Text('時刻', style: AppTextStyles.labelM),
                      _Wheel(
                        hourController: _hourController,
                        minuteController: _minuteController,
                        hour: _hour,
                        minute: _minute,
                        onHour: (index) {
                          if (_heldSpin != null || index == _hour) return;
                          setState(() => _hour = index);
                        },
                        onMinute: (index) {
                          final minute = index * 5;
                          if (_heldSpin != null || minute == _minute) return;
                          setState(() => _minute = minute);
                        },
                      ),
                      if (usualAnswerTimes(widget.answeredLog.value).isNotEmpty)
                        _UsualTimes(
                          times: usualAnswerTimes(widget.answeredLog.value),
                          onTap: _spinTo,
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: AppButton(
                      label: label,
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.l,
                      onTap: _confirm,
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

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.3 : 1,
      child: SizedBox.square(
        dimension: 44,
        child: AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          shape: const CircleBorder(),
          semanticLabel: label,
          child: Center(
            child: AppIcon(icon, size: 22, color: AppColors.inkPrimary),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.weekdays,
    required this.selectedDay,
    required this.canSelect,
    required this.onSelect,
  });

  final DateTime month;
  final List<String> weekdays;
  final DateTime selectedDay;
  final bool Function(DateTime date) canSelect;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
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
            for (final weekday in weekdays)
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
    if (date == null) return const SizedBox(height: 44);
    final enabled = canSelect(date);
    return _DayCell(
      date: date,
      enabled: enabled,
      isToday: date == bookingToday,
      isSelected: date == selectedDay,
      onTap: enabled ? () => onSelect(date) : null,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.enabled,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool enabled;
  final bool isToday;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = isToday ? '${formatMonthDay(date)}、今日' : formatMonthDay(date);
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      shape: const CircleBorder(),
      minHeight: 44,
      selected: isSelected,
      semanticLabel: label,
      // モックのマスは 40。押せる領域は 44 にする
      child: ExcludeSemantics(
        child: Center(
          child: Container(
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
                color: isSelected
                    ? AppColors.paperRaised
                    : enabled
                    ? AppColors.inkPrimary
                    : AppColors.lineStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.hourController,
    required this.minuteController,
    required this.hour,
    required this.minute,
    required this.onHour,
    required this.onMinute,
  });

  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final int hour;
  final int minute;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.borderRadius,
      child: ColoredBox(
        color: AppColors.paperBase,
        child: SizedBox(
          height: _wheelHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 12,
                right: 12,
                top: (_wheelHeight - _itemExtent) / 2,
                height: _itemExtent,
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.paperSunken,
                      borderRadius: AppRadius.borderRadius,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  SizedBox(
                    width: _columnWidth,
                    height: _wheelHeight,
                    child: _WheelColumn(
                      controller: hourController,
                      label: '時',
                      itemCount: 24,
                      selectedIndex: hour,
                      labelOf: (index) => '$index',
                      onSelected: onHour,
                    ),
                  ),
                  const ExcludeSemantics(
                    child: Text(':', style: _wheelSelected),
                  ),
                  SizedBox(
                    width: _columnWidth,
                    height: _wheelHeight,
                    child: _WheelColumn(
                      controller: minuteController,
                      label: '分',
                      itemCount: 12,
                      selectedIndex: minute ~/ 5,
                      labelOf: (index) =>
                          (index * 5).toString().padLeft(2, '0'),
                      onSelected: onMinute,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.label,
    required this.itemCount,
    required this.selectedIndex,
    required this.labelOf,
    required this.onSelected,
  });

  final FixedExtentScrollController controller;
  final String label;
  final int itemCount;
  final int selectedIndex;
  final String Function(int index) labelOf;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _fade.createShader(rect),
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _itemExtent,
          diameterRatio: 100,
          perspective: 0.0001,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onSelected,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) {
              final selected = index == selectedIndex;
              return Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => controller.animateToItem(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  ),
                  child: Center(
                    child: Text(
                      labelOf(index),
                      style: selected ? _wheelSelected : _wheelIdle,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UsualTimes extends StatelessWidget {
  const _UsualTimes({required this.times, required this.onTap});

  final List<TimeOfDay> times;
  final ValueChanged<TimeOfDay> onTap;

  @override
  Widget build(BuildContext context) {
    // 見出しが長くて折り返すときは、ボタンの並びを崩さない。
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _UsualHeading(),
        // 文字を大きくしても、ボタンの並びが欄からはみ出さない
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              for (final time in times)
                _UsualChip(
                  label: formatSheetTime(time.hour, time.minute),
                  onTap: () => onTap(time),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UsualHeading extends StatelessWidget {
  const _UsualHeading();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.stateOk,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          'よく電話に出る時刻',
          style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
        ),
      ],
    );
  }
}

class _UsualChip extends StatelessWidget {
  const _UsualChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: const BorderSide(color: AppColors.lineStrong),
      ),
      // モックのチップは 32。上下の余白で押せる領域を 44 にする
      minHeight: 32,
      hitPadding: 6,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label, style: AppTextStyles.monoM),
    );
  }
}
