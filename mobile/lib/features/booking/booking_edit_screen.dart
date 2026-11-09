import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/date_time_pick.dart';

// 06 で押した予約を直す。部品と日付・時刻の選び方は 01 と同じ。
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNavBar(title: '予約の編集'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    _MessageField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                    ),
                    // 通話内容は予約のものなので、伝えたいことを空にしても残す
                    _ScriptCard(script: _script),
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
              child: _EditActions(
                onBook: hasMessage ? () => _save(message) : null,
                onCall: hasMessage ? () => showComingSoon(context) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageField extends StatelessWidget {
  const _MessageField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        const ExcludeSemantics(
          child: Text('伝えたいこと', style: AppTextStyles.labelM),
        ),
        AppTextField(
          controller: controller,
          semanticLabel: '伝えたいこと',
          minHeight: 60,
          maxLines: null,
          autofocus: true,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({required this.script});

  final String script;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: AppAiTag(label: '通話内容')),
            AppButton(
              label: 'なおす',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.s,
              leadingIcon: AppIcons.pencil,
              onTap: () => showComingSoon(context),
            ),
          ],
        ),
        Text(script, style: AppTextStyles.capM),
      ],
    );
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({required this.onBook, required this.onCall});

  final VoidCallback? onBook;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        AppButton(
          label: 'この日時で予約する',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.calendarClock,
          onTap: onBook,
        ),
        AppButton(
          label: '今すぐ通話',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          leadingIcon: AppIcons.phone,
          onTap: onCall,
        ),
      ],
    );
  }
}
