import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        // 複数行の入力欄は改行キーでは閉じず、キーボードがタブバーを隠すので、スクロールで閉じる
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('予約電話', style: AppTextStyles.titleL),
            SizedBox(height: 8),
            _NewBookingCard(),
            SizedBox(height: 12),
            _BookedCallsCard(),
            SizedBox(height: 12),
            _RetryRuleRow(),
          ],
        ),
      ),
    );
  }
}

class _NewBookingCard extends ConsumerStatefulWidget {
  const _NewBookingCard();

  @override
  ConsumerState<_NewBookingCard> createState() => _NewBookingCardState();
}

class _NewBookingCardState extends ConsumerState<_NewBookingCard> {
  // 選べる期間の終わりはモックにないので、基準日の 1 年後にする
  static final _lastDate = DateTime(2027, 11, 5);

  final _message = TextEditingController(text: '今日は通院の日です。10時に迎えに行くと伝えて');
  DateTime _date = DateTime(2026, 11, 6);
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: bookingToday,
      lastDate: _lastDate,
      // 既定は端末の時計の日付になる
      currentDate: bookingToday,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _book(String message) {
    ref
        .read(bookedCallsProvider.notifier)
        .addOnce(
          at: DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time.hour,
            _time.minute,
          ),
          message: message,
        );
    // キーボードを閉じて、足した行を見えるようにする
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        const Text('新しい予約', style: AppTextStyles.titleM),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Expanded(
              child: _PickField(
                label: '日付',
                value: formatPickDate(_date),
                onTap: _pickDate,
              ),
            ),
            Expanded(
              child: _PickField(
                label: '時刻',
                value: formatPickTime(_time.hour, _time.minute),
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            // 読み上げは入力欄の semanticLabel で伝える
            const ExcludeSemantics(
              child: Text('伝える内容', style: AppTextStyles.labelM),
            ),
            AppTextField(
              controller: _message,
              semanticLabel: '伝える内容',
              minHeight: 72,
              maxLines: null,
              textStyle: AppTextStyles.labelM,
            ),
          ],
        ),
        ListenableBuilder(
          listenable: _message,
          builder: (context, _) {
            final message = _message.text.trim();
            return AppButton(
              label: 'この内容で予約する',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.l,
              leadingIcon: AppIcons.calendarClock,
              onTap: message.isEmpty ? null : () => _book(message),
            );
          },
        ),
      ],
    );
  }
}

// モックの pick。AppField は文字が .label-m の inkSecondary に決まっているので、AppPressable で作る。
class _PickField extends StatelessWidget {
  const _PickField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        // 読み上げは欄の semanticLabel で伝える
        ExcludeSemantics(child: Text(label, style: AppTextStyles.labelM)),
        AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          backgroundColor: AppColors.paperRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.lineStrong, width: 1.5),
          ),
          minHeight: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          semanticLabel: label,
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: Text(value, style: AppTextStyles.monoM),
          ),
        ),
      ],
    );
  }
}

class _BookedCallsCard extends ConsumerWidget {
  const _BookedCallsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(bookedCallsProvider);
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        // このカードだけ間隔が 10 なので、1 つの Column にまとめる
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const Text('予約している電話', style: AppTextStyles.titleM),
            for (final call in calls) _BookedRow(call),
          ],
        ),
      ],
    );
  }
}

// モックの bookedRow
class _BookedRow extends StatelessWidget {
  const _BookedRow(this.call);

  final BookedCall call;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AppPressable(
        onTap: () => showComingSoon(context),
        foregroundColor: AppColors.inkPrimary,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              // モックの 72 は「11/7 10:00」がちょうど入る幅なので、文字倍率に合わせて広げる
              width: MediaQuery.textScalerOf(context).scale(72),
              child: Text(formatBookedAt(call.at), style: AppTextStyles.monoS),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.title, style: AppTextStyles.labelM),
                  Text(
                    call.detail,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const AppIcon(
              AppIcons.chevronRight,
              size: 18,
              color: AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryRuleRow extends ConsumerWidget {
  const _RetryRuleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = ref.watch(retryRuleProvider);
    return AppPressable(
      onTap: () => context.pushNamed(AppRoutes.retryRule),
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.paperSunken,
              shape: BoxShape.circle,
            ),
            child: const AppIcon(AppIcons.rotate, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('かけなおしのルール', style: AppTextStyles.labelL),
                Text(
                  rule.summary,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const AppIcon(
            AppIcons.chevronRight,
            size: 20,
            color: AppColors.inkSecondary,
          ),
        ],
      ),
    );
  }
}
