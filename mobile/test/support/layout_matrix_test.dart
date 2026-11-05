import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_matrix.dart';

void main() {
  test('幅 3 通りと文字倍率 2 通りの組み合わせがある', () {
    expect(layoutCases, hasLength(6));
  });

  testEachLayout('幅と文字倍率が反映される', (tester, layout) async {
    late BuildContext context;
    await pumpInLayout(
      tester,
      layout,
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    expect(MediaQuery.sizeOf(context).width, layout.width);
    expect(MediaQuery.textScalerOf(context).scale(10), 10 * layout.textScale);
  });

  testWidgets('overflow を見逃さない', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Row(children: [SizedBox.square(dimension: layoutCases.first.width + 1)]),
    );

    expect(tester.takeException(), isFlutterError);
  });
}
