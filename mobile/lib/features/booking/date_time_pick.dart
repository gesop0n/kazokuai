import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

// 06b の日付と時刻。01 は日時を 1 つにまとめて、01b で選ぶ。
class DateTimeFields extends StatelessWidget {
  const DateTimeFields({
    super.key,
    required this.now,
    required this.date,
    required this.time,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  // 端末の今を、選んだ瞬間に読む。開いたときの時刻のままだと、
  // ピッカーを出しているあいだに 1 分以内になっても入ってしまう。
  final DateTime Function() now;
  final DateTime date;
  final TimeOfDay time;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;

  Future<void> _pickDate(BuildContext context) async {
    final current = now();
    final today = bookingDay(current);
    final last = bookingLastDay(current);
    // 開いている予約の日が範囲の外でも、ピッカーが落ちないように収める。
    var initial = date;
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
      currentDate: today,
    );
    if (picked != null) onDateChanged(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked == null) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      picked.hour,
      picked.minute,
    );
    // 閉じたときの今で見る。開いたときに 1 分よりあとでも、閉じるまでに入ることがある。
    if (!canBookAt(at, now())) return;
    onTimeChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Expanded(
          child: DateTimePickField(
            label: '日付',
            value: formatPickDate(date),
            onTap: () => _pickDate(context),
          ),
        ),
        Expanded(
          child: DateTimePickField(
            label: '時刻',
            value: formatPickTime(time.hour, time.minute),
            onTap: () => _pickTime(context),
          ),
        ),
      ],
    );
  }
}

// AppField は文字が label-m の inkSecondary に決まっているので、AppPressable で作る。
class DateTimePickField extends StatelessWidget {
  const DateTimePickField({
    super.key,
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
            borderRadius: AppRadius.borderRadius,
            side: const BorderSide(color: AppColors.lineStrong, width: 1.5),
          ),
          minHeight: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          semanticLabel: label,
          // 欄の値は見出しの読み上げに重ねない。01 の日時と同じ。
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: ExcludeSemantics(
              child: Text(value, style: AppTextStyles.monoM),
            ),
          ),
        ),
      ],
    );
  }
}

// 01 の日時。押すと 01b が開く。日付と時刻は別の文字にして、欄の値を別々に読める。
class DateTimeItem extends StatelessWidget {
  const DateTimeItem({
    super.key,
    required this.date,
    required this.time,
    required this.onTap,
  });

  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text('日時', style: AppTextStyles.labelM),
        AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          backgroundColor: AppColors.paperRaised,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadius,
            side: const BorderSide(color: AppColors.lineStrong, width: 1.5),
          ),
          minHeight: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          semanticLabel: '日時を選ぶ',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Text(formatPickDate(date), style: AppTextStyles.monoM),
                Text(' ', style: AppTextStyles.monoM),
                Text(
                  formatSheetTime(time.hour, time.minute),
                  style: AppTextStyles.monoM,
                ),
                const Spacer(),
                const AppIcon(
                  AppIcons.calendarClock,
                  size: 20,
                  color: AppColors.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
