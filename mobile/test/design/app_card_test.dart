import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_card.dart';

import '../support/layout_matrix.dart';

void main() {
  testEachLayout('alert のカードが崩れない', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      const AppCard(
        variant: AppCardVariant.alert,
        children: [Text('朝の電話に出ていません')],
      ),
    );

    expect(find.text('朝の電話に出ていません'), findsOneWidget);
  });

  test('alert は背景が stateAlert で、余白と角丸は night と同じ', () {
    expect(AppCardVariant.alert.background, AppColors.stateAlert);
    expect(AppCardVariant.alert.foreground, AppColors.onStateAlert);
    expect(AppCardVariant.alert.padding, AppCardVariant.night.padding);
    expect(AppCardVariant.alert.radius, AppCardVariant.night.radius);
    expect(AppCardVariant.alert.gap, AppCardVariant.night.gap);
    expect(AppCardVariant.alert.border, isNull);
  });
}
