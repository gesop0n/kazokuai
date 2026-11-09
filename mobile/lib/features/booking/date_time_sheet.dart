import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';

// モックの行は 36。押せる領域は 44 以上にする
const _itemExtent = 44.0;
const _wheelHeight = 180.0;
const _columnWidth = 88.0;

// モックの .cal.book .cal-d は 40、行間は 2。押せる面は 44 で、上下 2 は行の外。
const _dayRowHeight = 40.0;
const _dayHitOutset = 2.0;

// 回転式は 5 分ごとなので、開いた時刻を近い 5 分に寄せる。9:02 は 9:00。
(int, int) _snapToFiveMinutes(int hour, int minute) {
  const step = 5;
  final total = hour * 60 + minute;
  final snapped = ((total + step ~/ 2) ~/ step) * step;
  final inDay = snapped % (24 * 60);
  return (inDay ~/ 60, inDay % 60);
}

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
    builder: (context) => DateTimeSheet(initial: initial),
  );
}

// 01b。日付はカレンダー、時刻は 5 分ごとの回転式。
class DateTimeSheet extends StatefulWidget {
  const DateTimeSheet({super.key, required this.initial});

  final DateTime initial;

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

  // 数字を押した回転の途中は、通り過ぎる位置で選んだ時刻を上書きしない。
  // 指が触れたら外して、止まった位置を選ぶ。
  int _hourSpin = 0;
  int? _heldHour;
  int _minuteSpin = 0;
  int? _heldMinute;

  @override
  void initState() {
    super.initState();
    _selectedDay = _clampDay(
      DateTime(widget.initial.year, widget.initial.month, widget.initial.day),
    );
    _month = DateTime(_selectedDay.year, _selectedDay.month);
    final time = _snapToFiveMinutes(widget.initial.hour, widget.initial.minute);
    _hour = time.$1;
    _minute = time.$2;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute ~/ 5);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
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

  // 押した数字をすぐ選び、回転はあとから追いつく。
  // 回転の途中で決めても、通り過ぎた時刻にはならない。
  void _tapHour(int index) {
    final generation = ++_hourSpin;
    _heldHour = generation;
    if (_hour != index) setState(() => _hour = index);
    _spin(_hourController, index, () => _heldHour == generation, () {
      _heldHour = null;
    });
  }

  void _tapMinute(int index) {
    final generation = ++_minuteSpin;
    _heldMinute = generation;
    final minute = index * 5;
    if (_minute != minute) setState(() => _minute = minute);
    _spin(_minuteController, index, () => _heldMinute == generation, () {
      _heldMinute = null;
    });
  }

  void _spin(
    FixedExtentScrollController controller,
    int index,
    bool Function() stillHeld,
    void Function() clear,
  ) {
    controller
        .animateToItem(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (!mounted || !stillHeld()) return;
          clear();
        });
  }

  // 指が触れた時点で、押して始めた回転を止める。
  // 値はまだ変えず、ドラッグが勝ってから止まった位置を取る。描き直すとドラッグが消える。
  void _onHourPointerDown() => _stopSpin(
    _hourController,
    () => _heldHour != null,
    () => _heldHour = null,
  );

  void _onMinutePointerDown() => _stopSpin(
    _minuteController,
    () => _heldMinute != null,
    () => _heldMinute = null,
  );

  void _stopSpin(
    FixedExtentScrollController controller,
    bool Function() spinning,
    void Function() clearHold,
  ) {
    if (!spinning()) return;
    if (controller.hasClients) controller.jumpTo(controller.offset);
    clearHold();
  }

  void _onHourScrollEnd() => _takeStopped(
    _hourController,
    _heldHour,
    () => _hour,
    (index) => _hour = index,
  );

  void _onMinuteScrollEnd() => _takeStopped(
    _minuteController,
    _heldMinute,
    () => _minute ~/ 5,
    (index) => _minute = index * 5,
  );

  void _takeStopped(
    FixedExtentScrollController controller,
    int? held,
    int Function() current,
    void Function(int index) apply,
  ) {
    if (held != null || !controller.hasClients) return;
    final index = controller.selectedItem;
    if (index == current()) return;
    setState(() => apply(index));
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
                          if (_heldHour != null || index == _hour) return;
                          setState(() => _hour = index);
                        },
                        onMinute: (index) {
                          final minute = index * 5;
                          if (_heldMinute != null || minute == _minute) return;
                          setState(() => _minute = minute);
                        },
                        onTapHour: _tapHour,
                        onTapMinute: _tapMinute,
                        onHourPointerDown: _onHourPointerDown,
                        onMinutePointerDown: _onMinutePointerDown,
                        onHourScrollEnd: _onHourScrollEnd,
                        onMinuteScrollEnd: _onMinuteScrollEnd,
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
    return _HitOutset(
      outset: _dayHitOutset,
      child: Column(
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
            _HitOutset(
              outset: _dayHitOutset,
              child: Row(
                children: [
                  for (var i = start; i < start + 7; i++)
                    Expanded(child: _cellAt(cells, i)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cellAt(List<DateTime?> cells, int index) {
    final date = index < cells.length ? cells[index] : null;
    if (date == null) return const SizedBox(height: _dayRowHeight);
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
    // マスの高さは 40。押せる面は 44 で、上下にはみ出す。
    return SizedBox(
      height: _dayRowHeight,
      child: OverflowBox(
        alignment: Alignment.center,
        minHeight: _dayRowHeight + _dayHitOutset * 2,
        maxHeight: _dayRowHeight + _dayHitOutset * 2,
        child: AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          shape: const CircleBorder(),
          minHeight: _dayRowHeight + _dayHitOutset * 2,
          selected: isSelected,
          semanticLabel: label,
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
    required this.onTapHour,
    required this.onTapMinute,
    required this.onHourPointerDown,
    required this.onMinutePointerDown,
    required this.onHourScrollEnd,
    required this.onMinuteScrollEnd,
  });

  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final int hour;
  final int minute;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final ValueChanged<int> onTapHour;
  final ValueChanged<int> onTapMinute;
  final VoidCallback onHourPointerDown;
  final VoidCallback onMinutePointerDown;
  final VoidCallback onHourScrollEnd;
  final VoidCallback onMinuteScrollEnd;

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
                      onTapItem: onTapHour,
                      onPointerDown: onHourPointerDown,
                      onScrollEnd: onHourScrollEnd,
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
                      onTapItem: onTapMinute,
                      onPointerDown: onMinutePointerDown,
                      onScrollEnd: onMinuteScrollEnd,
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
    required this.onTapItem,
    required this.onPointerDown,
    required this.onScrollEnd,
  });

  final FixedExtentScrollController controller;
  final String label;
  final int itemCount;
  final int selectedIndex;
  final String Function(int index) labelOf;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onTapItem;
  final VoidCallback onPointerDown;
  final VoidCallback onScrollEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: Listener(
        onPointerDown: (_) => onPointerDown(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification is ScrollEndNotification) {
              onScrollEnd();
            }
            return false;
          },
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
                      onTap: () => onTapItem(index),
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
        ),
      ),
    );
  }
}

// 子の上下にはみ出した分も押せる。行の高さは子のまま。
class _HitOutset extends SingleChildRenderObjectWidget {
  const _HitOutset({required this.outset, required super.child});

  final double outset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitOutset(outset);

  @override
  void updateRenderObject(BuildContext context, _RenderHitOutset renderObject) {
    renderObject.outset = outset;
  }
}

class _RenderHitOutset extends RenderProxyBox {
  _RenderHitOutset(this._outset);

  double _outset;

  double get outset => _outset;

  set outset(double value) {
    if (_outset == value) return;
    _outset = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty) return false;
    if (position.dx < 0 || position.dx >= size.width) return false;
    if (position.dy < -outset || position.dy >= size.height + outset) {
      return false;
    }
    final y = position.dy.clamp(0.0, size.height - 0.001);
    if (hitTestChildren(result, position: Offset(position.dx, y))) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
