import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar(this.initial, {super.key, required this.color});

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initial,
        // .avatar.M は .label-l と違って字間がない
        style: AppTextStyles.labelL.copyWith(
          letterSpacing: 0,
          color: AppColors.onAvatar,
        ),
      ),
    );
  }
}
