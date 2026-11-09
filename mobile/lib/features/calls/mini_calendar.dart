import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/day_mark_icon.dart';
import 'package:kazokuai/features/home/home_format.dart';

// 見本のデータの 14 日。1 日の幅は帯の 7 分の 1 で、今日を右端にして開く。
class MiniCalendar extends StatelessWidget {
  const MiniCalendar({
    super.key,
    required this.log,
    required this.selectedDay,
    required this.onTap,
  });

  static const dayCount = 14;
  static const visibleDayCount = 7;

  final CallLog log;
  final DateTime selectedDay;
  final VoidCallback onTap;

  // テストから日を探すためのキー
  @visibleForTesting
  static Key dayKey(DateTime date) => ValueKey('mini-day-$date');

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        value: formatMonthDay(selectedDay),
        button: true,
        label: 'カレンダーを開いて日付を選ぶ',
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.paperRaised,
              borderRadius: AppRadius.borderRadius,
              border: Border.all(color: AppColors.line),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                _MiniHead(onTap: onTap),
                _DayStrip(log: log, selectedDay: selectedDay, onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniHead extends StatelessWidget {
  const _MiniHead({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 24),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('過去7日間', style: AppTextStyles.labelM),
          ),
        ),
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.log,
    required this.selectedDay,
    required this.onTap,
  });

  final CallLog log;
  final DateTime selectedDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = constraints.maxWidth / MiniCalendar.visibleDayCount;
        return _DayScroller(
          dayWidth: dayWidth,
          log: log,
          selectedDay: selectedDay,
          onTap: onTap,
        );
      },
    );
  }
}

class _DayScroller extends StatefulWidget {
  const _DayScroller({
    required this.dayWidth,
    required this.log,
    required this.selectedDay,
    required this.onTap,
  });

  final double dayWidth;
  final CallLog log;
  final DateTime selectedDay;
  final VoidCallback onTap;

  @override
  State<_DayScroller> createState() => _DayScrollerState();
}

class _DayScrollerState extends State<_DayScroller> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset:
        widget.dayWidth *
        (MiniCalendar.dayCount - MiniCalendar.visibleDayCount),
  );
  var _dragged = false;

  List<DateTime> get _days {
    final today = widget.log.today;
    return [
      for (var back = MiniCalendar.dayCount - 1; back >= 0; back--)
        DateTime(today.year, today.month, today.day - back),
    ];
  }

  @override
  void didUpdateWidget(_DayScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay) {
      _reveal(widget.selectedDay);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 指を動かしたあとのタップではシートを開かない。次に押したときは開く。
  void _onTap() {
    if (_dragged) {
      _dragged = false;
      return;
    }
    widget.onTap();
  }

  void _reveal(DateTime day) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final index = _days.indexOf(day);
      if (index < 0) return;

      final dayWidth = widget.dayWidth;
      final start = _controller.offset;
      final viewEnd = start + _controller.position.viewportDimension;
      final dayStart = index * dayWidth;
      final dayEnd = dayStart + dayWidth;
      final double? target;
      if (dayStart < start - 0.5) {
        target = dayStart;
      } else if (dayEnd > viewEnd + 0.5) {
        target = dayEnd - _controller.position.viewportDimension;
      } else {
        target = null;
      }
      if (target == null) return;
      _controller.animateTo(
        target.clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // タップの判定は帯の中に置く。外に置くと、指での横移動がスクロールに届かない
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _dragged = true;
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: _DaySnapPhysics(dayWidth: widget.dayWidth),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Listener(
            onPointerDown: (_) => _dragged = false,
            child: Row(
              children: [
                for (final date in _days)
                  SizedBox(
                    width: widget.dayWidth,
                    child: _MiniDay(
                      date: date,
                      log: widget.log,
                      selectedDay: widget.selectedDay,
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

// 指を離した位置で、1 日の境界に止まる。速い操作でも隣の日までにする。
class _DaySnapPhysics extends ScrollPhysics {
  const _DaySnapPhysics({required this.dayWidth, super.parent});

  final double dayWidth;

  // これより遅いときは、いちばん近い日に戻す
  static const _flickVelocity = 50.0;

  @override
  _DaySnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _DaySnapPhysics(dayWidth: dayWidth, parent: buildParent(ancestor));
  }

  double _target(ScrollMetrics position, double velocity) {
    final page = position.pixels / dayWidth;
    final next = velocity.abs() < _flickVelocity
        ? page.roundToDouble()
        : velocity.isNegative
        ? page.floorToDouble()
        : page.ceilToDouble();
    return (next * dayWidth).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    final target = _target(position, velocity);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
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
        borderRadius: AppRadius.borderRadius,
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
