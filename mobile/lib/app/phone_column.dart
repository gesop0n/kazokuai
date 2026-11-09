import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';

// 画面がスマホより広いときは、アプリをスマホの幅の列にして真ん中に置く。まわりは無地。
class PhoneColumn extends StatelessWidget {
  const PhoneColumn({super.key, required this.child});

  final Widget child;

  // 仕様のおよそ 430 ポイント。これ以下の画面は、今までどおり幅いっぱい。
  static const width = 430.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= width) return child;

    return ColoredBox(
      color: AppColors.paperSunken,
      child: Align(
        alignment: Alignment.topCenter,
        child: MediaQuery(
          data: media.copyWith(size: Size(width, media.size.height)),
          child: SizedBox(
            width: width,
            height: media.size.height,
            child: ColoredBox(color: AppColors.paperBase, child: child),
          ),
        ),
      ),
    );
  }
}
