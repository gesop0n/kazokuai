import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_form.dart';
import 'package:kazokuai/features/booking/date_time_pick.dart';

// 文は ADR 0002 のとおり固定で、入力の内容によって変えない
const _callScript = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」';

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _messageController = TextEditingController();
  DateTime _date = DateTime(2026, 11, 6);
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _call(String message) async {
    try {
      await ref
          .read(immediateCallRepositoryProvider)
          .start(message: message, script: _callScript);
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
    } on ImmediateCallException {
      // つながらない以外の失敗は、画面に留まる。文面は、このチケットでは求めない。
    }
  }

  void _book(String message) {
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
          script: _callScript,
        );
    context.goNamed(AppRoutes.booking);
  }

  @override
  Widget build(BuildContext context) {
    final message = _messageController.text.trim();
    final hasMessage = message.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNavBar(title: 'AIに伝えてもらう'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    BookingMessageField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (hasMessage) const CallScriptCard(script: _callScript),
                    DateTimeFields(
                      date: _date,
                      time: _time,
                      onDateChanged: (date) => setState(() => _date = date),
                      onTimeChanged: (time) => setState(() => _time = time),
                    ),
                  ],
                ),
              ),
            ),
            // モックの foot はボタンとホームバーの間も 8 空ける。キーボードでホームバーが
            // 隠れるときは、この 8 がボタンとキーボードの間隔になる
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: BookingFormActions(
                onBook: hasMessage ? () => _book(message) : null,
                onCall: hasMessage ? () => _call(message) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
