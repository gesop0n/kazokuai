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
                    _MessageField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (hasMessage) const _ScriptCard(),
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
              child: _AskActions(
                onBook: hasMessage ? () => _book(message) : null,
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
        // 入力欄の読み上げと重ならないようにする
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
  const _ScriptCard();

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
        const Text(_callScript, style: AppTextStyles.capM),
      ],
    );
  }
}

class _AskActions extends StatelessWidget {
  const _AskActions({required this.onBook, required this.onCall});

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
