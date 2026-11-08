import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

enum AppButtonSize {
  l(
    minHeight: 56,
    horizontalPadding: 24,
    iconSize: 20,
    textStyle: AppTextStyles.labelL,
  ),
  m(
    minHeight: 44,
    horizontalPadding: 16,
    iconSize: 18,
    textStyle: AppTextStyles.labelM,
  ),
  // ghost の小さいボタン(01 の「なおす」)。モックの高さ 32 では押せる領域が足りないので 44 にする
  s(
    minHeight: 44,
    horizontalPadding: 8,
    iconSize: 16,
    textStyle: AppTextStyles.labelM,
  ),
  // s の左右の余白をなくし、文字を親の端に揃える(05 の「まとめの間違いを直す」)
  sFlush(
    minHeight: 44,
    horizontalPadding: 0,
    iconSize: 16,
    textStyle: AppTextStyles.labelM,
  );

  const AppButtonSize({
    required this.minHeight,
    required this.horizontalPadding,
    required this.iconSize,
    required this.textStyle,
  });

  final double minHeight;
  final double horizontalPadding;
  final double iconSize;
  final TextStyle textStyle;
}

enum AppButtonVariant {
  primary(background: AppColors.inkPrimary, foreground: AppColors.paperRaised),
  record(background: AppColors.accentCall, foreground: AppColors.onAccentCall),
  secondary(
    background: AppColors.paperRaised,
    foreground: AppColors.inkPrimary,
    border: BorderSide(color: AppColors.lineStrong, width: 1.5),
  ),
  light(background: AppColors.nightText, foreground: AppColors.nightBase),
  ghost(background: Colors.transparent, foreground: AppColors.inkSecondary),
  // モックの ghost-ink。背景はなく、文字は ink
  ghostInk(background: Colors.transparent, foreground: AppColors.inkPrimary),
  // 07b の注意の赤のカードに置く。文字とアイコンは ink
  white(background: AppColors.onStateAlert, foreground: AppColors.inkPrimary);

  const AppButtonVariant({
    required this.background,
    required this.foreground,
    this.border = BorderSide.none,
  });

  final Color background;
  final Color foreground;
  final BorderSide border;
}

// 親が幅を決めればその幅に広がり、決めなければ中身の幅になる。
// onTap が null のときは押せず、背景は buttonDisabled、文字は inkSecondary になる。
// 副ボタンだけは、モックの .btn.secondary:disabled のとおり枠線を残す。
// leading は AppIcons にない、色を変えずに出す画像(Google のロゴ)に使う。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.variant,
    required this.size,
    required this.onTap,
    this.leadingIcon,
    this.leading,
    this.trailingIcon,
    this.underlined = false,
  }) : assert(leadingIcon == null || leading == null);

  final String label;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final VoidCallback? onTap;
  final AppIcons? leadingIcon;
  final Widget? leading;
  final AppIcons? trailingIcon;

  // モックの text-underline-offset は Text の下線では位置を変えられない。
  // 05 のまとめの時刻と同じく、文字の下端に線を引く
  final bool underlined;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = this.leadingIcon;
    final trailingIcon = this.trailingIcon;
    final isEnabled = onTap != null;
    final foreground = isEnabled ? variant.foreground : AppColors.inkSecondary;
    final keepsBorder = isEnabled || variant == AppButtonVariant.secondary;
    final labelText = Text(
      label,
      textAlign: TextAlign.center,
      style: size.textStyle.copyWith(color: foreground),
    );
    return AppPressable(
      onTap: onTap,
      foregroundColor: foreground,
      backgroundColor: isEnabled
          ? variant.background
          : AppColors.buttonDisabled,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: keepsBorder ? variant.border : BorderSide.none,
      ),
      minHeight: size.minHeight,
      padding: EdgeInsets.symmetric(horizontal: size.horizontalPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          if (leadingIcon != null)
            AppIcon(leadingIcon, size: size.iconSize, color: foreground),
          ?leading,
          Flexible(
            child: underlined
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: foreground)),
                    ),
                    child: labelText,
                  )
                : labelText,
          ),
          if (trailingIcon != null)
            AppIcon(trailingIcon, size: size.iconSize, color: foreground),
        ],
      ),
    );
  }
}
