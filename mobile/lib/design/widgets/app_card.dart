import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';

enum AppCardVariant {
  paper(
    padding: 16,
    radius: 20,
    gap: 12,
    background: AppColors.paperRaised,
    foreground: AppColors.inkPrimary,
    border: BorderSide(color: AppColors.line),
  ),
  // 子どもの間隔が場所ごとに違うので gap は 0 にして、SizedBox で開ける
  night(
    padding: 20,
    radius: 24,
    gap: 0,
    background: AppColors.nightBase,
    foreground: AppColors.nightText,
  ),
  alert(
    padding: 20,
    radius: 24,
    gap: 0,
    background: AppColors.stateAlert,
    foreground: AppColors.onStateAlert,
  );

  const AppCardVariant({
    required this.padding,
    required this.radius,
    required this.gap,
    required this.background,
    required this.foreground,
    this.border,
  });

  final double padding;
  final double radius;
  final double gap;
  final Color background;
  final Color foreground;
  final BorderSide? border;
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.variant, required this.children});

  final AppCardVariant variant;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final border = variant.border;
    return Container(
      padding: EdgeInsets.all(variant.padding),
      decoration: BoxDecoration(
        color: variant.background,
        borderRadius: BorderRadius.circular(variant.radius),
        border: border == null ? null : Border.fromBorderSide(border),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: variant.foreground),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: variant.gap,
          children: children,
        ),
      ),
    );
  }
}
