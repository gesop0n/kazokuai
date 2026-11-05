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
    this.hitPadding = 0,
    this.semanticLabel,
    this.selected,
  }) : assert(minHeight + hitPadding * 2 >= 44);

  // null のときは押せない
  final VoidCallback? onTap;
  final Color foregroundColor;
  final OutlinedBorder shape;
  final Widget child;
  final Color backgroundColor;
  final double minHeight;
  final EdgeInsets padding;
  // 面の上下に足す、押せる透明の余白(モックの .chip-hit)
  final double hitPadding;
  final String? semanticLabel;
  final bool? selected;

  // 不透明度 12%
  static Color overlayOf(Color foreground) => foreground.withAlpha(0x1F);

  @override
  Widget build(BuildContext context) {
    final surface = Material(
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
    );
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: hitPadding == 0
          ? surface
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: hitPadding),
                child: surface,
              ),
            ),
    );
  }
}
