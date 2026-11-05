import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// カードの見出しと右のラベル。1 行に収まらないときは、ラベルを次の行に送る。
class HomeCardHeading extends StatelessWidget {
  const HomeCardHeading({super.key, required this.title, required this.label});

  final String title;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(title, style: AppTextStyles.titleM),
        Text(
          label,
          // Wrap には baseline 揃えがないので、行の高さを見出しと同じにして揃える
          strutStyle: StrutStyle.fromTextStyle(
            AppTextStyles.titleM,
            forceStrutHeight: true,
          ),
          style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
        ),
      ],
    );
  }
}
