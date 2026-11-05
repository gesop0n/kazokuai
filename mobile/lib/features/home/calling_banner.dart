import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// 仮の実装。次の PR で作る。
// モックの 01b は固定の文字で、押しても何も起きないので、データもコールバックも受け取らない。
// 状態バーの裏まで伸ばすので、上の余白はこの部品が持つ。
class CallingBanner extends StatelessWidget {
  const CallingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: AppColors.stateOkOn,
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
            bottom: 10,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: Text(
                '通話中',
                style: AppTextStyles.labelL.copyWith(
                  color: AppColors.onStateOk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
