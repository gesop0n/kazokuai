import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/call_progress_repository.dart';
import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_form.dart';
import 'package:kazokuai/features/booking/date_time_pick.dart';
import 'package:kazokuai/features/booking/date_time_sheet.dart';

// 入力が止まってから、通話内容の案を頼むまでの時間
const _draftPause = Duration(seconds: 1);

enum _DraftPhase { hidden, making, ready, failed }

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _messageController = TextEditingController();
  DateTime _date = DateTime(2026, 11, 6);
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);

  Timer? _draftTimer;
  int _draftGeneration = 0;
  String? _script;
  _DraftPhase _phase = _DraftPhase.hidden;
  late final ValueListenable<bool> _progress;

  // バックエンドに断られてから、電話がまだ最中だと分かるまでの表示。
  // 断ったあとに読み直して、終わっていればすぐ戻す
  bool _refusedWhileBusy = false;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(callProgressRepositoryProvider).inProgress;
    _progress.addListener(_onCallProgress);
  }

  // 拒否よりあとに届いた読み取りに任せる。
  // 呼び出し中を一度も読まなくても、終わったと分かれば表示を戻す
  void _onCallProgress() {
    if (!_refusedWhileBusy || !mounted) return;
    setState(() => _refusedWhileBusy = false);
  }

  @override
  void dispose() {
    _progress.removeListener(_onCallProgress);
    _draftTimer?.cancel();
    _draftGeneration++;
    _messageController.dispose();
    super.dispose();
  }

  // 文が変わったら、前の案は捨てて、止まってから頼み直す
  void _onMessageChanged(String _) {
    _draftTimer?.cancel();
    _draftGeneration++;
    final message = _messageController.text.trim();
    setState(() {
      _script = null;
      _phase = _DraftPhase.hidden;
    });
    if (message.isEmpty) return;
    _draftTimer = Timer(_draftPause, () => _requestDraft(message));
  }

  Future<void> _requestDraft(String message) async {
    final generation = _draftGeneration;
    setState(() => _phase = _DraftPhase.making);
    try {
      final script = await ref
          .read(callScriptRepositoryProvider)
          .draft(message: message);
      if (!mounted || generation != _draftGeneration) return;
      if (script.trim().isEmpty) throw const CallScriptException();
      setState(() {
        _script = script;
        _phase = _DraftPhase.ready;
      });
    } on CallScriptException {
      if (!mounted || generation != _draftGeneration) return;
      setState(() {
        _script = null;
        _phase = _DraftPhase.failed;
      });
    }
  }

  String? get _cardText => switch (_phase) {
    _DraftPhase.hidden => null,
    _DraftPhase.making => '案を作っています',
    _DraftPhase.ready => _script,
    _DraftPhase.failed => '案を作れませんでした',
  };

  bool get _canSend =>
      _phase == _DraftPhase.ready &&
      _script != null &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _call(String message) async {
    final script = _script;
    if (script == null) return;
    try {
      await ref
          .read(immediateCallRepositoryProvider)
          .start(message: message, script: script);
    } on PhoneNotConnectedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('電話機につながっていません'),
            duration: Duration(seconds: 2),
          ),
        );
    } on CallInProgressException {
      if (!mounted) return;
      setState(() => _refusedWhileBusy = true);
      // 終わった通知が拒否より先だと、このあとに通知は来ない。
      // 読み直して終わっていれば戻す。まだ読み終えていないときは戻さない。
      final stillBusy = await ref
          .read(callProgressRepositoryProvider)
          .refresh();
      if (!mounted || stillBusy != false) return;
      setState(() => _refusedWhileBusy = false);
    } on ImmediateCallException {
      // つながらない以外の失敗は、画面に留まる。文面は、このチケットでは求めない。
    }
  }

  // キーボードがシートに被らないように、開く前に欄から焦点を外す。
  // 通話記録はシートが開いているあいだの更新も見る。画面を描くたびに読まない。
  Future<void> _pickWhen() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDateTimeSheet(
      context,
      initial: DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      ),
      answeredLog: ref.read(callsRepositoryProvider).log,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _time = TimeOfDay(hour: picked.hour, minute: picked.minute);
    });
  }

  void _book(String message) {
    final script = _script;
    if (script == null) return;
    ref
        .read(bookedCallsProvider.notifier)
        .add(
          at: DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time.hour,
            _time.minute,
          ),
          message: message,
          script: script,
        );
    context.goNamed(AppRoutes.booking);
  }

  @override
  Widget build(BuildContext context) {
    final message = _messageController.text.trim();
    final cardText = _cardText;
    final canSend = _canSend;
    return BookingFormLayout(
      title: 'AIに伝えてもらう',
      onLeadingTap: () => popOrGoToParent(context),
      actions: ValueListenableBuilder<bool>(
        valueListenable: _progress,
        builder: (context, inProgress, _) {
          final busy = inProgress || _refusedWhileBusy;
          return BookingFormActions(
            onBook: canSend ? () => _book(message) : null,
            onCall: canSend && !busy ? () => _call(message) : null,
            callLabel: busy ? '通話中です' : '今すぐ通話',
          );
        },
      ),
      children: [
        BookingMessageField(
          controller: _messageController,
          onChanged: _onMessageChanged,
        ),
        if (cardText != null) CallScriptCard(script: cardText),
        DateTimeItem(date: _date, time: _time, onTap: _pickWhen),
      ],
    );
  }
}
