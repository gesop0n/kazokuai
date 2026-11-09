import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
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

  late DateTime _selectedDay = _log.days.first.date;
  bool _isScrolledUnder = false;
  // 最初の描画のあとで測り直す。値はモックの 04c の高さ
  double _pinnedHeight = 122;

  CallLog get _log => widget.log ?? sampleCallLog;

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
    final days = _log.days;
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

  Future<void> _openCalendar() async {
    final date = await showCalendarSheet(
      context,
      log: _log,
      selectedDay: _selectedDay,
    );
    if (date == null || !mounted) return;
    _scrollToDay(date);
  }

  void _scrollToDay(DateTime date) {
    final headingTop = _headingTopOf(date);
    if (headingTop == null) return;
    // 先頭の日はモックの 04 と同じ位置に戻す
    final target = date == _log.days.first.date
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
    // 文字の大きさが変わると、見出しの位置と固定部の高さが変わる
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
                showsShadow: _isScrolledUnder,
                onOpenCalendar: _openCalendar,
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
    final days = _log.days;
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
    required this.showsShadow,
    required this.onOpenCalendar,
  });

  final CallLog log;
  final DateTime selectedDay;
  final bool showsShadow;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 04c は上 8、ミニカレンダー、下 8 で高さ 122
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.paperBase,
        boxShadow: showsShadow
            ? const [
                BoxShadow(
                  color: Color(0x24000000),
                  offset: Offset(0, 4),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: MiniCalendar(
        log: log,
        selectedDay: selectedDay,
        onTap: onOpenCalendar,
      ),
    );
  }
}
