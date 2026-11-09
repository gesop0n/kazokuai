import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

class RetryRuleScreen extends ConsumerStatefulWidget {
  const RetryRuleScreen({super.key});

  @override
  ConsumerState<RetryRuleScreen> createState() => _RetryRuleScreenState();
}

class _RetryRuleScreenState extends ConsumerState<RetryRuleScreen> {
  // 保存するまで Riverpod のルールは変えないので、戻ると選択は消える
  late RetryRule _draft;
  late bool _minutesCustom;
  late bool _attemptsCustom;
  late final TextEditingController _minutesInput;
  late final TextEditingController _attemptsInput;
  late final FocusNode _minutesFocus;
  late final FocusNode _attemptsFocus;

  @override
  void initState() {
    super.initState();
    final rule = ref.read(retryRuleProvider);
    _draft = rule;
    _minutesCustom = !RetryRule.intervalChoices.contains(rule.interval);
    _attemptsCustom = !RetryRule.attemptChoices.contains(rule.attempts);
    _minutesInput = TextEditingController(
      text: _minutesCustom ? '${rule.interval.inMinutes}' : '',
    );
    _attemptsInput = TextEditingController(
      text: _attemptsCustom ? '${rule.attempts}' : '',
    );
    _minutesFocus = FocusNode();
    _attemptsFocus = FocusNode();
  }

  @override
  void dispose() {
    _minutesInput.dispose();
    _attemptsInput.dispose();
    _minutesFocus.dispose();
    _attemptsFocus.dispose();
    super.dispose();
  }

  // 欄は選んだフレームで初めて木に入るので、描いたあとに入力の位置を移す
  void _requestFocus(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  // 欄が空か範囲の外のあいだは、前の規則の流れを見せたまま保存させない
  bool get _canSave =>
      (!_minutesCustom ||
          RetryRule.minutesInRange(_minutesInput.text) != null) &&
      (!_attemptsCustom ||
          RetryRule.attemptsInRange(_attemptsInput.text) != null);

  void _chooseMinutes(Duration interval) {
    setState(() {
      _minutesCustom = false;
      _draft = _draft.copyWith(interval: interval);
    });
  }

  void _chooseCustomMinutes() {
    setState(() {
      _minutesCustom = true;
      final minutes = RetryRule.minutesInRange(_minutesInput.text);
      if (minutes != null) {
        _draft = _draft.copyWith(interval: Duration(minutes: minutes));
      }
    });
    _requestFocus(_minutesFocus);
  }

  void _onMinutesChanged(String text) {
    setState(() {
      final minutes = RetryRule.minutesInRange(text);
      if (minutes != null) {
        _draft = _draft.copyWith(interval: Duration(minutes: minutes));
      }
    });
  }

  void _chooseAttempts(int attempts) {
    setState(() {
      _attemptsCustom = false;
      _draft = _draft.copyWith(attempts: attempts);
    });
  }

  void _chooseCustomAttempts() {
    setState(() {
      _attemptsCustom = true;
      final attempts = RetryRule.attemptsInRange(_attemptsInput.text);
      if (attempts != null) {
        _draft = _draft.copyWith(attempts: attempts);
      }
    });
    _requestFocus(_attemptsFocus);
  }

  void _onAttemptsChanged(String text) {
    setState(() {
      final attempts = RetryRule.attemptsInRange(text);
      if (attempts != null) _draft = _draft.copyWith(attempts: attempts);
    });
  }

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
            AppNavBar(
              title: 'かけなおしのルール',
              onLeadingTap: () => popOrGoToParent(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ChoiceGroup(
                      label: 'かけなおす間隔',
                      choices: {
                        for (final interval in RetryRule.intervalChoices)
                          interval: RetryRule.intervalLabel(interval),
                      },
                      selected: _minutesCustom ? null : _draft.interval,
                      onSelected: _chooseMinutes,
                      customSelected: _minutesCustom,
                      onCustom: _chooseCustomMinutes,
                      customField: _minutesCustom
                          ? _NumberField(
                              controller: _minutesInput,
                              focusNode: _minutesFocus,
                              semanticLabel: 'かけなおす間隔を入力',
                              unit: '分',
                              onChanged: _onMinutesChanged,
                            )
                          : null,
                    ),
                    // チップの下の余白 4 と合わせてモックの間隔 20。欄にはその余白がない
                    SizedBox(height: _minutesCustom ? 20 : 16),
                    _ChoiceGroup(
                      label: 'かける回数',
                      choices: {
                        for (final attempts in RetryRule.attemptChoices)
                          attempts: '$attempts回',
                      },
                      selected: _attemptsCustom ? null : _draft.attempts,
                      onSelected: _chooseAttempts,
                      customSelected: _attemptsCustom,
                      onCustom: _chooseCustomAttempts,
                      customField: _attemptsCustom
                          ? _NumberField(
                              controller: _attemptsInput,
                              focusNode: _attemptsFocus,
                              semanticLabel: 'かける回数を入力',
                              unit: '回',
                              onChanged: _onAttemptsChanged,
                            )
                          : null,
                    ),
                    SizedBox(height: _attemptsCustom ? 20 : 16),
                    AppCard(
                      variant: AppCardVariant.paper,
                      children: [
                        const Text(
                          '朝9:00の電話に出ないとき',
                          style: AppTextStyles.labelM,
                        ),
                        _RetryFlow(rule: _draft),
                        Text(
                          _draft.flowSentence,
                          style: AppTextStyles.bodyS.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
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
                onTap: _canSave ? _save : null,
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
    required this.customSelected,
    required this.onCustom,
    required this.customField,
  });

  final String label;
  final Map<T, String> choices;
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool customSelected;
  final VoidCallback onCustom;
  final Widget? customField;

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
                horizontalPadding: _retryChipPadding,
                onTap: () => onSelected(value),
              ),
            AppChip(
              label: 'その他',
              selected: customSelected,
              horizontalPadding: _retryChipPadding,
              onTap: onCustom,
            ),
          ],
        ),
        ?customField,
      ],
    );
  }
}

// モックの [data-retry] .chip。面の高さは AppChip の 36、左右の余白だけ 12
const _retryChipPadding = 12.0;

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.focusNode,
    required this.semanticLabel,
    required this.unit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String semanticLabel;
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      focusNode: focusNode,
      semanticLabel: semanticLabel,
      minHeight: 48,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      // モックの .field input。16/24 は labelL。500 は 400、数字の字間は 0
      textStyle: AppTextStyles.labelL.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      onChanged: onChanged,
      trailing: ExcludeSemantics(
        child: Text(
          unit,
          style: AppTextStyles.labelM.copyWith(color: AppColors.inkPrimary),
        ),
      ),
    );
  }
}

// モックの flowDot と flowLine。3 回より多いときは間を「…」にする
class _RetryFlow extends StatelessWidget {
  const _RetryFlow({required this.rule});

  final RetryRule rule;

  @override
  Widget build(BuildContext context) {
    final times = rule.attemptTimes(RetryRule.flowExampleStart);
    final callIndexes = rule.attempts > 3
        ? <int?>[0, null, rule.attempts - 1]
        : <int?>[for (var i = 0; i < rule.attempts; i++) i];
    final items = <Widget>[
      for (final index in callIndexes)
        index == null ? const _FlowEllipsis() : _callDot(times[index], index),
      _FlowDot(
        icon: AppIcons.bell,
        color: AppColors.stateAlert,
        time: formatTime(times.last),
        label: const _NotifyLabel(),
        semanticLabel: '${formatTime(times.last)} 家族に通知',
      ),
    ];
    return _FlowRow(items);
  }

  _FlowDot _callDot(DateTime time, int index) {
    final clock = formatTime(time);
    return _FlowDot(
      icon: AppIcons.phone,
      color: AppColors.inkPrimary,
      time: clock,
      label: Text(
        '${index + 1}回目',
        textAlign: TextAlign.center,
        style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
      ),
      semanticLabel: '$clock ${index + 1}回目',
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow(this.items);

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const Expanded(child: _FlowLine()),
          item,
        ],
      ],
    );
  }
}

class _FlowEllipsis extends StatelessWidget {
  const _FlowEllipsis();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        '…',
        style: AppTextStyles.labelM.copyWith(color: AppColors.inkSecondary),
      ),
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
                child: AppIcon(icon, size: 16, color: AppColors.white),
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
