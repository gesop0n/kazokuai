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
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Text(title, style: AppTextStyles.titleM),
        // Wrap は baseline で揃えられないので、余白でモックの位置に近づける
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            label,
            style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
          ),
        ),
      ],
    );
  }
}
