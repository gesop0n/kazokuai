import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// .field と .field.focus の見た目で、実際に入力できる部品。押すと画面を開くだけの入力欄は AppField。
// maxLines を 1 以外にすると複数行になり、モックの複数行の欄と同じく文字を上に寄せる。
// カーソルと選択の色は appTheme で inkPrimary になる。
// trailing は枠の内側の右端に置く(L2 のパスワードを表示するボタン)。
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
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
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
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  static const _borderWidth = 1.5;

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
    final trailing = widget.trailing;
    final isMultiline = widget.maxLines != 1;
    final style =
        (widget.textStyle ??
                AppTextStyles.labelL.copyWith(fontWeight: FontWeight.w400))
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
          padding: EdgeInsets.fromLTRB(
            16 + _borderWidth,
            (isMultiline ? 12 : 0) + _borderWidth,
            (trailing == null ? 16 : 6) + _borderWidth,
            (isMultiline ? 12 : 0) + _borderWidth,
          ),
          decoration: const BoxDecoration(
            color: AppColors.paperRaised,
            borderRadius: AppRadius.borderRadius,
          ),
          // フォーカスで枠が太くなっても文字が動かないように、枠は余白の上に描く
          foregroundDecoration: BoxDecoration(
            borderRadius: AppRadius.borderRadius,
            border: _focusNode.hasFocus
                ? Border.all(color: AppColors.inkPrimary, width: 2)
                : Border.all(color: AppColors.lineStrong, width: _borderWidth),
          ),
          child: child,
        ),
        child: Row(
          crossAxisAlignment: isMultiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                label: widget.semanticLabel,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  maxLines: widget.maxLines,
                  style: style,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  inputFormatters: widget.inputFormatters,
                  autofillHints: widget.autofillHints,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hintText,
                    hintStyle: style.copyWith(color: AppColors.inkSecondary),
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
