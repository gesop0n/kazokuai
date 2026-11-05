import 'package:flutter/material.dart';

// 押せる部品の土台。押すと前景色を薄く重ねるので、明るい面でも濃い面でも見える。
// InkWell の色は Material の上に描かれるので、背景は Material に持たせる。
class AppPressable extends StatelessWidget {
  const AppPressable({
    super.key,
    required this.onTap,
    required this.foregroundColor,
    required this.shape,
    required this.child,
    this.backgroundColor = Colors.transparent,
    this.minHeight = 44,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  }) : assert(minHeight >= 44);

  final VoidCallback onTap;
  final Color foregroundColor;
  final OutlinedBorder shape;
  final Widget child;
  final Color backgroundColor;
  final double minHeight;
  final EdgeInsets padding;
  final String? semanticLabel;

  // 不透明度 12%
  static Color overlayOf(Color foreground) => foreground.withAlpha(0x1F);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: Material(
        color: backgroundColor,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          overlayColor: WidgetStatePropertyAll(overlayOf(foregroundColor)),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 44, minHeight: minHeight),
            child: Padding(
              // CSS の border-box と同じく、枠線の内側に余白を取る
              padding: padding.add(shape.dimensions),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
