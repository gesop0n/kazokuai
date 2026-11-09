import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/home/home_format.dart';

// 1 日分の見出しと行。
class CallDaySection extends StatelessWidget {
  const CallDaySection({
    super.key,
    required this.day,
    required this.today,
    required this.headingKey,
    required this.onOpenCall,
  });

  final CallLogDay day;
  final DateTime today;
  final Key headingKey;
  final VoidCallback onOpenCall;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeading(
          key: headingKey,
          heading: formatDayHeading(day.date, today),
          total: formatDayTotal(day),
        ),
        for (final entry in day.entries)
          switch (entry) {
            AnsweredCallEntry() => _CallRow(entry: entry, onTap: onOpenCall),
            MissedCallEntry() => _MissedRow(entry: entry),
          },
      ],
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({super.key, required this.heading, required this.total});

  final String heading;
  final String total;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 8,
          children: [
            Expanded(child: Text(heading, style: AppTextStyles.labelL)),
            Text(
              total,
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.time,
    required this.icon,
    required this.iconBackground,
    required this.card,
  });

  final DateTime time;
  final AppIcons icon;
  final Color iconBackground;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // レールの線をカードの下端まで伸ばす
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            SizedBox(
              // 文字が大きくなると 19:00 が幅 40 に入らないので、一緒に広げる
              width: MediaQuery.textScalerOf(context).scale(40),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                // 読み上げはカードにまとめる
                child: ExcludeSemantics(
                  child: Text(
                    formatTime(time),
                    style: AppTextStyles.monoS.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ),
            ),
            _Rail(icon: icon, background: iconBackground),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.icon, required this.background});

  final AppIcons icon;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          spacing: 4,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: AppIcon(icon, size: 12, color: AppColors.onAvatar),
            ),
            Expanded(
              child: SizedBox(
                width: 2,
                // 不透明度 50%
                child: ColoredBox(color: AppColors.lineStrong.withAlpha(0x80)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.entry, required this.onTap});

  final AnsweredCallEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = '${entry.duration.inMinutes}分';
    final topic = entry.topic.label;
    return GestureDetector(
      // カードの外の時刻とレールを押しても開く
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: _RowFrame(
        time: entry.startedAt,
        icon: AppIcons.phone,
        iconBackground: AppColors.inkPrimary,
        card: AppPressable(
          onTap: onTap,
          foregroundColor: AppColors.inkPrimary,
          backgroundColor: AppColors.paperRaised,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadius,
            side: const BorderSide(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(12),
          semanticLabel:
              '${formatTime(entry.startedAt)}の電話。${entry.text}。$topic。$minutes',
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Text(
                  entry.text,
                  // モックは .cap-s の大きさだけ 15 にしている。行の高さは 22 のまま
                  style: AppTextStyles.capS.copyWith(
                    fontSize: 15,
                    height: 22 / 15,
                    letterSpacing: .03 * 15,
                  ),
                ),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        topic,
                        style: AppTextStyles.labelS.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ),
                    Text(
                      minutes,
                      style: AppTextStyles.monoS.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissedRow extends StatelessWidget {
  const _MissedRow({required this.entry});

  final MissedCallEntry entry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${formatTime(entry.startedAt)}の電話。${entry.text}',
      child: _RowFrame(
        time: entry.startedAt,
        icon: AppIcons.phoneMissed,
        iconBackground: AppColors.stateAlert,
        card: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.stateAlertSoft,
            borderRadius: AppRadius.borderRadius,
            border: Border.all(color: AppColors.stateAlert, width: 2),
          ),
          child: Text(
            entry.text,
            style: AppTextStyles.labelM.copyWith(color: AppColors.inkPrimary),
          ),
        ),
      ),
    );
  }
}
