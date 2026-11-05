import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/features/calls/calendar_sheet.dart';
import 'package:kazokuai/features/calls/call_timeline.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/mini_calendar.dart';
import 'package:kazokuai/features/calls/sample_calls_data.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key, this.log});

  final CallLog? log;

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  // 日の見出しが固定部の下端からこの距離に入ると、その日を選ぶ。
  // 04c は 11月3日の見出しが下端から 34 のところで、11月3日を選んでいる
  static const _daySwitchDistance = 40.0;
  static const _scrollDuration = Duration(milliseconds: 300);

  final _scrollController = ScrollController();
  final _titleKey = GlobalKey();
  final _pinnedKey = GlobalKey();
  final _listKey = GlobalKey();
  final _headingKeys = <DateTime, GlobalKey>{};

  CallFilter _filter = CallFilter.all;
  late DateTime _selectedDay = _log.days.first.date;
  bool _isScrolledUnder = false;
  // 最初の描画のあとで測り直す。値はモックの高さ
  double _pinnedHeight = 166;

  CallLog get _log => widget.log ?? sampleCallLog;

  List<CallLogDay> get _visibleDays => _log.daysMatching(_filter);

  double get _titleHeight => _boxOf(_titleKey).size.height;

  RenderBox _boxOf(GlobalKey key) =>
      key.currentContext!.findRenderObject()! as RenderBox;

  // 一覧の先頭から見出しまでの距離。まだ描かれていない日は null
  double? _headingTopOf(DateTime date) {
    final heading = _headingKeys[date]?.currentContext?.findRenderObject();
    if (heading is! RenderBox) return null;
    return heading.localToGlobal(Offset.zero, ancestor: _boxOf(_listKey)).dy;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncWithLayout);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncWithLayout() {
    final days = _visibleDays;
    if (days.isEmpty || !_scrollController.hasClients) return;

    final listTop = _scrollController.offset - _titleHeight;
    var selectedDay = days.first.date;
    for (final day in days) {
      final headingTop = _headingTopOf(day.date);
      if (headingTop == null || headingTop > listTop + _daySwitchDistance) {
        break;
      }
      selectedDay = day.date;
    }
    final pinnedHeight = _boxOf(_pinnedKey).size.height;
    final isScrolledUnder = listTop > 0;
    if (selectedDay == _selectedDay &&
        pinnedHeight == _pinnedHeight &&
        isScrolledUnder == _isScrolledUnder) {
      return;
    }
    setState(() {
      _selectedDay = selectedDay;
      _pinnedHeight = pinnedHeight;
      _isScrolledUnder = isScrolledUnder;
    });
  }

  void _selectFilter(CallFilter filter) {
    // 新しい結果を先頭から読めるように、一覧の先頭を固定部の下端まで戻す
    if (_scrollController.offset > _titleHeight) {
      _scrollController.jumpTo(_titleHeight);
    }
    setState(() => _filter = filter);
  }

  Future<void> _openCalendar() async {
    final date = await showCalendarSheet(
      context,
      log: _log,
      selectedDay: _selectedDay,
    );
    if (date == null || !mounted) return;

    // 絞り込みで隠れている日は移動できないので、全部に戻す
    if (!_visibleDays.any((day) => day.date == date)) {
      setState(() => _filter = CallFilter.all);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    _scrollToDay(date);
  }

  void _scrollToDay(DateTime date) {
    final headingTop = _headingTopOf(date);
    if (headingTop == null) return;
    // 先頭の日はモックの 04 と同じ位置に戻す
    final target = date == _visibleDays.first.date
        ? 0.0
        : _titleHeight + headingTop;
    _scrollController.animateTo(
      min(target, _scrollController.position.maxScrollExtent),
      duration: _scrollDuration,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 絞り込みや文字の大きさが変わると、見出しの位置と固定部の高さが変わる
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWithLayout();
    });

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                key: _titleKey,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: const Text('通話記録', style: AppTextStyles.titleL),
              ),
            ),
            PinnedHeaderSliver(
              child: _PinnedHeader(
                key: _pinnedKey,
                log: _log,
                selectedDay: _selectedDay,
                filter: _filter,
                showsShadow: _isScrolledUnder,
                onOpenCalendar: _openCalendar,
                onSelectFilter: _selectFilter,
              ),
            ),
            SliverToBoxAdapter(
              child: _buildList(constraints.maxHeight - _pinnedHeight),
            ),
          ],
        ),
      ),
    );
  }

  // 件数が少なく、日の位置を測るので、画面の外の日も全部ビルドする
  Widget _buildList(double lastDayMinHeight) {
    final days = _visibleDays;
    return Column(
      key: _listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days)
          if (day == days.last)
            // 記録が短いと、古い日を固定部の下端まで動かせず、04c の位置にも届かない
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: max(0, lastDayMinHeight)),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: _buildDay(day),
              ),
            )
          else
            _buildDay(day),
      ],
    );
  }

  Widget _buildDay(CallLogDay day) => CallDaySection(
    day: day,
    entries: day.entriesMatching(_filter),
    today: _log.today,
    headingKey: _headingKeys.putIfAbsent(day.date, GlobalKey.new),
    onOpenCall: () => context.pushNamed(AppRoutes.callDetail),
  );
}

class _PinnedHeader extends StatelessWidget {
  const _PinnedHeader({
    super.key,
    required this.log,
    required this.selectedDay,
    required this.filter,
    required this.showsShadow,
    required this.onOpenCalendar,
    required this.onSelectFilter,
  });

  final CallLog log;
  final DateTime selectedDay;
  final CallFilter filter;
  final bool showsShadow;
  final VoidCallback onOpenCalendar;
  final ValueChanged<CallFilter> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.paperBase,
        boxShadow: showsShadow
            ? const [
                BoxShadow(
                  color: Color(0x243A2A19),
                  offset: Offset(0, 4),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MiniCalendar(
              log: log,
              selectedDay: selectedDay,
              onTap: onOpenCalendar,
            ),
          ),
          // モックは折り返さず端で切れている。幅 393 で「不在」が切れるので、横に動かせるようにする
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                for (final option in CallFilter.values)
                  AppChip(
                    label: option.label,
                    selected: option == filter,
                    onTap: () => onSelectFilter(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
