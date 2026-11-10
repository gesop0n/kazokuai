import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

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

// モックのマスは 40、行間は 2。44 を重ねると次の週が下端を取るので、行を 44 にする。
const _dayRowHeight = 44.0;

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
// now は端末の今。今日から 30 日先まで、今から 1 分よりあとだけ決められる。
Future<DateTime?> showDateTimeSheet(
  BuildContext context, {
  required DateTime now,
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
    builder: (context) => DateTimeSheet(now: now, initial: initial),
  );
}

// 01b。日付はカレンダー、時刻は 5 分ごとの回転式。
class DateTimeSheet extends StatefulWidget {
  const DateTimeSheet({super.key, required this.now, required this.initial});

  final DateTime now;
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

  DateTime get _today => bookingDay(widget.now);

  DateTime get _lastDay => bookingLastDay(widget.now);

  DateTime _clampDay(DateTime day) {
    if (day.isBefore(_today)) return _today;
    if (day.isAfter(_lastDay)) return _lastDay;
    return day;
  }

  bool _canSelect(DateTime date) =>
      !date.isBefore(_today) && !date.isAfter(_lastDay);

  // 前の月がすべて今日より前なら、戻る先がない
  bool get _canGoBack {
    final previousLast = DateTime(_month.year, _month.month, 0);
    return !previousLast.isBefore(_today);
  }

  bool get _canGoForward {
    final nextFirst = DateTime(_month.year, _month.month + 1);
    return !nextFirst.isAfter(_lastDay);
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

  // 回転中は数字がポインターを受けない。世代を進めて、止めた位置で上書きしない。
  // true のときだけ、離した位置の数字を選び直す。描き直すとドラッグが消える。
  bool _onHourPointerDown() {
    if (_heldHour == null) return false;
    _heldHour = ++_hourSpin;
    if (_hourController.hasClients) {
      _hourController.jumpTo(_hourController.offset);
    }
    return true;
  }

  bool _onMinutePointerDown() {
    if (_heldMinute == null) return false;
    _heldMinute = ++_minuteSpin;
    if (_minuteController.hasClients) {
      _minuteController.jumpTo(_minuteController.offset);
    }
    return true;
  }

  void _onHourDrag() => _heldHour = null;

  void _onMinuteDrag() => _heldMinute = null;

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

  DateTime get _selectedAt => DateTime(
    _selectedDay.year,
    _selectedDay.month,
    _selectedDay.day,
    _hour,
    _minute,
  );

  // 今から 1 分ちょうどと、30 日より先は決められない。
  bool get _canConfirm => canBookAt(_selectedAt, widget.now);

  void _confirm() {
    if (!_canConfirm) return;
    Navigator.pop(context, _selectedAt);
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
                    today: _today,
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
                        onHourDrag: _onHourDrag,
                        onMinuteDrag: _onMinuteDrag,
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
                      onTap: _canConfirm ? _confirm : null,
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
    required this.today,
    required this.canSelect,
    required this.onSelect,
  });

  final DateTime month;
  final List<String> weekdays;
  final DateTime selectedDay;
  final DateTime today;
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
        // 曜日の下だけモックの行間 2。日の行は 44 で隙間なく並べ、下端が次の週にならない。
        const SizedBox(height: 2),
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
    if (date == null) return const SizedBox(height: _dayRowHeight);
    final enabled = canSelect(date);
    return _DayCell(
      date: date,
      enabled: enabled,
      isToday: date == today,
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
    return SizedBox(
      height: _dayRowHeight,
      child: AppPressable(
        onTap: onTap,
        foregroundColor: AppColors.inkPrimary,
        shape: const CircleBorder(),
        minHeight: _dayRowHeight,
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
    required this.onHourDrag,
    required this.onMinuteDrag,
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
  final bool Function() onHourPointerDown;
  final bool Function() onMinutePointerDown;
  final VoidCallback onHourDrag;
  final VoidCallback onMinuteDrag;
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
                      onDrag: onHourDrag,
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
                      onDrag: onMinuteDrag,
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

class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.controller,
    required this.label,
    required this.itemCount,
    required this.selectedIndex,
    required this.labelOf,
    required this.onSelected,
    required this.onTapItem,
    required this.onPointerDown,
    required this.onDrag,
    required this.onScrollEnd,
  });

  final FixedExtentScrollController controller;
  final String label;
  final int itemCount;
  final int selectedIndex;
  final String Function(int index) labelOf;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onTapItem;
  // 回転中なら true。プログラムの回転は数字を無視するので、離した位置で選び直す。
  final bool Function() onPointerDown;
  final VoidCallback onDrag;
  final VoidCallback onScrollEnd;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  Offset? _origin;
  var _tracking = false;
  var _dragged = false;

  void _down(PointerDownEvent event) {
    _tracking = widget.onPointerDown();
    _dragged = false;
    _origin = event.localPosition;
  }

  void _move(PointerMoveEvent event) {
    if (!_tracking || _dragged) return;
    final origin = _origin;
    if (origin == null) return;
    if ((event.localPosition - origin).distance <= kTouchSlop) return;
    _dragged = true;
    widget.onDrag();
  }

  void _up(PointerUpEvent event) {
    if (!_tracking) return;
    _tracking = false;
    // ドラッグのあとは、スクロールの終了が止まった位置を取る。
    if (_dragged) {
      _dragged = false;
      return;
    }
    widget.onTapItem(_indexAt(event.localPosition) ?? widget.selectedIndex);
  }

  void _cancel(PointerCancelEvent event) {
    if (!_tracking) return;
    _tracking = false;
    _dragged = false;
    widget.onDrag();
    widget.onScrollEnd();
  }

  // 中央の数字が scroll offset の位置。円筒はほぼ平面なので、近い番号で足りる。
  int? _indexAt(Offset local) {
    final controller = widget.controller;
    if (!controller.hasClients) return null;
    final index =
        ((local.dy - _wheelHeight / 2 + controller.offset) / _itemExtent)
            .round();
    if (index < 0 || index >= widget.itemCount) return null;
    return index;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification is ScrollEndNotification) {
              widget.onScrollEnd();
            }
            return false;
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => _fade.createShader(rect),
            child: ListWheelScrollView.useDelegate(
              controller: widget.controller,
              itemExtent: _itemExtent,
              diameterRatio: 100,
              perspective: 0.0001,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: widget.onSelected,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.itemCount,
                builder: (context, index) {
                  final selected = index == widget.selectedIndex;
                  return Semantics(
                    button: true,
                    selected: selected,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onTapItem(index),
                      child: Center(
                        child: Text(
                          widget.labelOf(index),
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
