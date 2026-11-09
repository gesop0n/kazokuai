import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

// モックの .setrow の見出しと値。見出しは label-s、値は label-l の太さ 500
final _labelStyle = AppTextStyles.labelS.copyWith(
  color: AppColors.inkSecondary,
);
final _valueStyle = AppTextStyles.labelL.copyWith(fontWeight: FontWeight.w400);

// 08 と 08e のカード。左右だけ 16 で、上下は行が持つ。行の間に線を引く
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.line)),
              ),
              child: children[i],
            ),
        ],
      ),
    );
  }
}

// 押せない行。メールアドレス、ログイン方法、登録日
class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: _RowText(label: label, value: value),
    );
  }
}

// 次の画面へ進む行。右に矢印を出す
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
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
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      shape: const RoundedRectangleBorder(),
      minHeight: 60,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: _RowText(label: label, value: value),
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

class _RowText extends StatelessWidget {
  const _RowText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _labelStyle),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _valueStyle,
        ),
      ],
    );
  }
}

// 見出しの下に入力欄の形を置く行。onTap があるときは、欄ごと押せる
class SettingsLabeledField extends StatelessWidget {
  const SettingsLabeledField({
    super.key,
    required this.label,
    required this.field,
    this.onTap,
    this.semanticsLabel,
    this.note,
  });

  final String label;
  final Widget field;
  final VoidCallback? onTap;

  // 欄ごと押すときに読み上げる文。指定しないときは、中の欄が読む
  final String? semanticsLabel;

  // 欄の下に出す、失敗の文
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final column = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          ExcludeSemantics(child: Text(label, style: _labelStyle)),
          field,
          if (note != null)
            Text(
              note,
              style: AppTextStyles.labelM.copyWith(color: AppColors.stateAlert),
            ),
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return column;
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      shape: const RoundedRectangleBorder(),
      semanticLabel: semanticsLabel,
      child: ExcludeSemantics(child: column),
    );
  }
}

// まだ書き換えられない値。モックの入力欄と同じ枠で出す
class SettingsValueField extends StatelessWidget {
  const SettingsValueField({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: AppColors.lineStrong, width: 1.5),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _valueStyle,
      ),
    );
  }
}
