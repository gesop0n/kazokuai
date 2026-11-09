import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/app/unknown_route_screen.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_form.dart';
import 'package:kazokuai/features/booking/date_time_pick.dart';

// 道の index が予約の番号でないときは、編集画面を作らずに知らせる。
// int.parse のままだと、/booking/edit/x でアプリが落ちる。
class BookingEditRoute extends ConsumerWidget {
  const BookingEditRoute({super.key, required this.index});

  final String index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = int.tryParse(index);
    final count = ref.watch(bookedCallsProvider).length;
    if (parsed == null || parsed < 0 || parsed >= count) {
      return const UnknownRouteScreen();
    }
    return BookingEditScreen(index: parsed);
  }
}

// 06 で押した予約を直す。伝えたいことと通話内容は 01 と同じ部品。
// 日付と時刻は、モックの 06b のとおり 2 つの欄のまま。
class BookingEditScreen extends ConsumerStatefulWidget {
  const BookingEditScreen({super.key, required this.index});

  final int index;

  @override
  ConsumerState<BookingEditScreen> createState() => _BookingEditScreenState();
}

class _BookingEditScreenState extends ConsumerState<BookingEditScreen> {
  late final TextEditingController _messageController;
  late final String _script;
  late DateTime _date;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    final booking = ref.read(bookedCallsProvider)[widget.index];
    _messageController = TextEditingController(text: booking.message);
    _script = booking.script;
    _date = DateTime(booking.at.year, booking.at.month, booking.at.day);
    _time = TimeOfDay(hour: booking.at.hour, minute: booking.at.minute);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _save(String message) {
    ref
        .read(bookedCallsProvider.notifier)
        .update(
          widget.index,
          at: DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time.hour,
            _time.minute,
          ),
          message: message,
        );
    context.goNamed(AppRoutes.booking);
  }

  @override
  Widget build(BuildContext context) {
    final message = _messageController.text.trim();
    final hasMessage = message.isNotEmpty;
    return BookingFormLayout(
      title: '予約の編集',
      onLeadingTap: () => popOrGoToParent(context),
      actions: BookingFormActions(
        onBook: hasMessage ? () => _save(message) : null,
        onCall: hasMessage ? () => showComingSoon(context) : null,
      ),
      children: [
        BookingMessageField(
          controller: _messageController,
          onChanged: (_) => setState(() {}),
        ),
        // 通話内容は予約のものなので、伝えたいことを空にしても残す
        CallScriptCard(script: _script),
        DateTimeFields(
          date: _date,
          time: _time,
          onDateChanged: (date) => setState(() => _date = date),
          onTimeChanged: (time) => setState(() => _time = time),
        ),
      ],
    );
  }
}
