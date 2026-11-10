import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/app/unknown_route_screen.dart';
import 'package:kazokuai/data/bookings_repository.dart';
import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_form.dart';
import 'package:kazokuai/features/booking/date_time_pick.dart';

enum _DraftPhase { original, waiting, making, ready, failed }

// 道の id がこれからの予約でないときは、編集画面を作らずに知らせる。
// 読み終えるまでは空欄にして、見本や知らない画面を出さない。
class BookingEditRoute extends ConsumerWidget {
  const BookingEditRoute({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(bookingsRepositoryProvider);
    final clock = ref.watch(bookingNowProvider);
    return ValueListenableBuilder(
      valueListenable: repository.bookings,
      builder: (context, bookings, _) {
        // 出し直しの通知では、この build は走らない。ここで読まないと過ぎた予約を直せる。
        final now = clock();
        if (bookings == null) return const SizedBox.expand();
        for (final booking in upcomingBookings(bookings, now)) {
          if (booking.id == id) return BookingEditScreen(booking: booking);
        }
        return const UnknownRouteScreen();
      },
    );
  }
}

// 06 で押した予約を直す。伝えたいことと通話内容は 01 と同じ部品。
// 日付と時刻は、モックの 06b のとおり 2 つの欄のまま。
// 伝えたいことが変わったときだけ、保存の前に通話内容を作り直す。
class BookingEditScreen extends ConsumerStatefulWidget {
  const BookingEditScreen({super.key, required this.booking});

  final BookedCall booking;

  @override
  ConsumerState<BookingEditScreen> createState() => _BookingEditScreenState();
}

class _BookingEditScreenState extends ConsumerState<BookingEditScreen> {
  late final TextEditingController _messageController;
  late DateTime _date;
  late TimeOfDay _time;
  var _saving = false;

  Timer? _draftTimer;
  int _draftGeneration = 0;
  String? _draft;
  _DraftPhase _phase = _DraftPhase.original;

  @override
  void initState() {
    super.initState();
    final booking = widget.booking;
    _messageController = TextEditingController(text: booking.message);
    _date = DateTime(booking.at.year, booking.at.month, booking.at.day);
    _time = TimeOfDay(hour: booking.at.hour, minute: booking.at.minute);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _draftGeneration++;
    _messageController.dispose();
    super.dispose();
  }

  // 伝えたいことが元のままか空なら、元の通話内容を残す。変わったら、止まってから頼み直す。
  void _onMessageChanged(String _) {
    _draftTimer?.cancel();
    _draftGeneration++;
    final message = _messageController.text.trim();
    if (message.isEmpty || message == widget.booking.message) {
      setState(() {
        _draft = null;
        _phase = _DraftPhase.original;
      });
      return;
    }
    setState(() {
      _draft = null;
      _phase = _DraftPhase.waiting;
    });
    _draftTimer = Timer(bookingDraftPause, () => _requestDraft(message));
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
        _draft = script;
        _phase = _DraftPhase.ready;
      });
    } on CallScriptException {
      if (!mounted || generation != _draftGeneration) return;
      setState(() {
        _draft = null;
        _phase = _DraftPhase.failed;
      });
    }
  }

  String get _cardText => switch (_phase) {
    _DraftPhase.making => '案を作っています',
    _DraftPhase.failed => '案を作れませんでした',
    _DraftPhase.ready => _draft ?? widget.booking.script,
    _DraftPhase.original || _DraftPhase.waiting => widget.booking.script,
  };

  bool _canSave(String message, DateTime at, DateTime now) {
    if (_saving || message.isEmpty || !canBookAt(at, now)) return false;
    if (message == widget.booking.message) return true;
    return _phase == _DraftPhase.ready && (_draft?.trim().isNotEmpty ?? false);
  }

  Future<void> _save(String message) async {
    if (_saving) return;
    final script = message == widget.booking.message
        ? widget.booking.script
        : _draft;
    if (script == null || script.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(bookingsRepositoryProvider)
          .edit(
            id: widget.booking.id,
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
      if (!mounted) return;
      context.goNamed(AppRoutes.booking);
    } catch (error) {
      _showFailure(error);
    }
  }

  void _showFailure(Object error) {
    final text = bookingFailureMessage(error);
    if (text == null) throw error;
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final message = _messageController.text.trim();
    final clock = ref.watch(bookingNowProvider);
    final now = clock();
    final at = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final canSave = _canSave(message, at, now);
    return BookingFormLayout(
      title: '予約の編集',
      onLeadingTap: () => popOrGoToParent(context),
      actions: BookingFormActions(
        onBook: canSave ? () => _save(message) : null,
        onCall: message.isNotEmpty ? () => showComingSoon(context) : null,
      ),
      children: [
        BookingMessageField(
          controller: _messageController,
          onChanged: _onMessageChanged,
        ),
        CallScriptCard(script: _cardText),
        DateTimeFields(
          now: clock,
          date: _date,
          time: _time,
          onDateChanged: (date) => setState(() => _date = date),
          onTimeChanged: (time) => setState(() => _time = time),
        ),
      ],
    );
  }
}
