import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

class RetryRuleScreen extends ConsumerStatefulWidget {
  const RetryRuleScreen({super.key});

  @override
  ConsumerState<RetryRuleScreen> createState() => _RetryRuleScreenState();
}

class _RetryRuleScreenState extends ConsumerState<RetryRuleScreen> {
  // 保存するまで Riverpod のルールは変えないので、戻ると選択は消える
  late RetryRule _draft = ref.read(retryRuleProvider);

  void _save() {
    ref.read(retryRuleProvider.notifier).save(_draft);
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNavBar(title: 'かけなおしのルール'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '電話に出なかったら、\nどうしますか',
                      style: AppTextStyles.titleL,
                    ),
                    const SizedBox(height: 20),
                    _ChoiceGroup(
                      label: 'かけなおす間隔',
                      choices: {
                        for (final interval in RetryRule.intervalChoices)
                          interval: RetryRule.intervalLabel(interval),
                      },
                      selected: _draft.interval,
                      onSelected: (interval) => setState(
                        () => _draft = _draft.copyWith(interval: interval),
                      ),
                    ),
                    // チップの上下の透明の余白 4 をふくめて、モックの間隔 20 になる
                    const SizedBox(height: 16),
                    _ChoiceGroup(
                      label: 'かける回数(最初の1回をふくむ)',
                      choices: {
                        for (final attempts in RetryRule.attemptChoices)
                          attempts: '$attempts回',
                      },
                      selected: _draft.attempts,
                      onSelected: (attempts) => setState(
                        () => _draft = _draft.copyWith(attempts: attempts),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppCard(
                      variant: AppCardVariant.paper,
                      children: [
                        const Text(
                          '朝9:00の電話に出ないときの流れ',
                          style: AppTextStyles.labelM,
                        ),
                        _RetryFlow(rule: _draft),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _NotifiedPeople(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: AppButton(
                label: 'このルールで保存',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Map<T, String> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // チップの上の透明の余白 4 をふくめて、モックの間隔 8 になる
      spacing: 4,
      children: [
        Text(label, style: AppTextStyles.labelM),
        // チップの上下の透明の余白がモックの行の間隔 8 になる
        Wrap(
          spacing: 8,
          children: [
            for (final MapEntry(key: value, value: chipLabel)
                in choices.entries)
              AppChip(
                label: chipLabel,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}

// モックの flowDot と flowLine。
class _RetryFlow extends StatelessWidget {
  const _RetryFlow({required this.rule});

  // 朝 9:00 の電話を例にする
  static final _firstCall = DateTime(2026, 11, 5, 9);

  // 幅 68 の丸は幅 360 のカードに 4 つまで並ぶ。5 回のときの 6 つは 2 段に分ける
  static const _maxDotsInRow = 4;
  static const _dotsInRowWhenSplit = 3;

  final RetryRule rule;

  @override
  Widget build(BuildContext context) {
    final times = rule.attemptTimes(_firstCall);
    final dots = [
      for (final (index, time) in times.indexed)
        _FlowDot(
          icon: AppIcons.phone,
          color: AppColors.inkPrimary,
          time: formatTime(time),
          label: Text(
            '${index + 1}回目',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
          ),
          semanticLabel: '${formatTime(time)} ${index + 1}回目',
        ),
      _FlowDot(
        icon: AppIcons.bell,
        color: AppColors.stateAlert,
        time: formatTime(times.last),
        label: const _NotifyLabel(),
        semanticLabel: '${formatTime(times.last)} 家族に通知',
      ),
    ];
    final dotsInRow = dots.length <= _maxDotsInRow
        ? dots.length
        : _dotsInRowWhenSplit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (var start = 0; start < dots.length; start += dotsInRow)
          _FlowRow(dots.sublist(start, start + dotsInRow)),
      ],
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow(this.dots);

  final List<_FlowDot> dots;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, dot) in dots.indexed) ...[
          if (index > 0) const Expanded(child: _FlowLine()),
          dot,
        ],
      ],
    );
  }
}

class _FlowDot extends StatelessWidget {
  const _FlowDot({
    required this.icon,
    required this.color,
    required this.time,
    required this.label,
    required this.semanticLabel,
  });

  final AppIcons icon;
  final Color color;
  final String time;
  final Widget label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 68,
          child: Column(
            spacing: 6,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                // モックはどちらの丸も白のアイコン
                child: AppIcon(icon, size: 16, color: AppColors.onAccentCall),
              ),
              Text(
                time,
                textAlign: TextAlign.center,
                style: AppTextStyles.monoS,
              ),
              label,
            ],
          ),
        ),
      ),
    );
  }
}

// 幅が足りないときは「家族に」と「通知」の間で折り返す。「通」と「知」の間で切らない
class _NotifyLabel extends StatelessWidget {
  const _NotifyLabel();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary);
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text('家族に', style: style),
        Text('通知', style: style),
      ],
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(top: 17),
      color: AppColors.lineStrong,
    );
  }
}

class _NotifiedPeople extends StatelessWidget {
  const _NotifiedPeople();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        const Text('知らせる人', style: AppTextStyles.labelM),
        AppCard(
          variant: AppCardVariant.paper,
          children: [
            // このカードだけ間隔が 10 なので、1 つの Column にまとめる
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                const _NotifiedPersonRow(name: '美咲(あなた)'),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: const _NotifiedPersonRow(name: '健太(弟)'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _NotifiedPersonRow extends StatelessWidget {
  const _NotifiedPersonRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Expanded(child: Text(name, style: AppTextStyles.labelL)),
        Text(
          'アプリに通知',
          style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
        ),
      ],
    );
  }
}
