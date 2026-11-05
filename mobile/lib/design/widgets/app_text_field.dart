import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// .field と .field.focus の見た目で、実際に入力できる部品。押すと画面を開くだけの入力欄は AppField。
// maxLines を 1 以外にすると複数行になり、モックの複数行の欄と同じく文字を上に寄せる。
// カーソルと選択の色は appTheme で inkPrimary になる。
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.semanticLabel,
    this.minHeight = 56,
    this.maxLines = 1,
    this.textStyle,
    this.autofocus = false,
    this.onChanged,
  }) : assert(minHeight >= 44);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? semanticLabel;
  final double minHeight;
  final int? maxLines;
  // 既定はモックの入力欄に多い .label-l の太さ 500
  final TextStyle? textStyle;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  static const _borderWidth = 1.5;
  static const _borderRadius = BorderRadius.all(Radius.circular(16));

  // 親から渡されないときだけ自分で持つ
  FocusNode? _ownFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMultiline = widget.maxLines != 1;
    final style =
        (widget.textStyle ??
                AppTextStyles.labelL.copyWith(fontWeight: FontWeight.w500))
            .copyWith(color: AppColors.inkPrimary);
    return GestureDetector(
      // TextField は文字の高さしかないので、余白を押しても入力できるようにする
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _focusNode.requestFocus,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, child) => Container(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: EdgeInsets.symmetric(
            horizontal: 16 + _borderWidth,
            vertical: (isMultiline ? 12 : 0) + _borderWidth,
          ),
          decoration: const BoxDecoration(
            color: AppColors.paperRaised,
            borderRadius: _borderRadius,
          ),
          // フォーカスで枠が太くなっても文字が動かないように、枠は余白の上に描く
          foregroundDecoration: BoxDecoration(
            borderRadius: _borderRadius,
            border: _focusNode.hasFocus
                ? Border.all(color: AppColors.inkPrimary, width: 2)
                : Border.all(color: AppColors.lineStrong, width: _borderWidth),
          ),
          child: child,
        ),
        child: Align(
          alignment: isMultiline ? Alignment.topLeft : Alignment.centerLeft,
          heightFactor: 1,
          child: Semantics(
            label: widget.semanticLabel,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              maxLines: widget.maxLines,
              style: style,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              decoration: InputDecoration.collapsed(
                hintText: widget.hintText,
                hintStyle: style.copyWith(color: AppColors.inkSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
