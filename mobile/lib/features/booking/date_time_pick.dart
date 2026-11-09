import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

// 選べる期間の終わりはモックにないので、基準日の 1 年後にする
final _lastDate = DateTime(2027, 11, 5);

// モックの pick。01 と 06b が同じ欄と選び方を使う。
class DateTimeFields extends StatelessWidget {
  const DateTimeFields({
    super.key,
    required this.date,
    required this.time,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  final DateTime date;
  final TimeOfDay time;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: bookingToday,
      lastDate: _lastDate,
      // 既定は端末の時計の日付になる
      currentDate: bookingToday,
    );
    if (picked != null) onDateChanged(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked != null) onTimeChanged(picked);
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
