import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';

import '../support/layout_matrix.dart';

const _labels = ['ホーム', '通話記録', '予約電話'];

Widget _screen({int currentIndex = 0, ValueChanged<int>? onSelected}) {
  return Scaffold(
    bottomNavigationBar: AppTabBar(
      currentIndex: currentIndex,
      onSelected: onSelected ?? (_) {},
    ),
  );
}

Widget _tabBar({int currentIndex = 0, ValueChanged<int>? onSelected}) {
  return MaterialApp(
    home: _screen(currentIndex: currentIndex, onSelected: onSelected),
  );
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  testEachLayout('タブバーが overflow しない', (tester, layout) async {
    // 選択中の太字がいちばん広いので、すべてのタブを選んで確かめる
    for (final (index, label) in _labels.indexed) {
      await pumpScreenInLayout(tester, layout, _screen(currentIndex: index));

      expect(tester.getSize(_button(label)), const Size(88, 56));
      expect(tester.getSize(find.byType(AppTabBar)).width, layout.width);
    }
  });

  testWidgets('文字が大きくなると、高さは 56 を超えて伸びる', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: _tabBar(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(_button('ホーム')).height, greaterThan(56));
  });

  testWidgets('選択中のタブを Semantics に反映する', (tester) async {
    await tester.pumpWidget(_tabBar(currentIndex: 1));

    expect(
      tester.getSemantics(find.text('通話記録')),
      isSemantics(
        label: '通話記録',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('ホーム')),
      isSemantics(
        label: 'ホーム',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('選択中のタブは paperSunken の背景と太字になる', (tester) async {
    await tester.pumpWidget(_tabBar(currentIndex: 1));

    Material materialOf(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    FontWeight? weightOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.fontWeight;

    expect(materialOf('通話記録').color, AppColors.paperSunken);
    expect(weightOf('通話記録'), FontWeight.w700);
    expect(materialOf('ホーム').color, Colors.transparent);
    expect(weightOf('ホーム'), FontWeight.w400);
  });

  testWidgets('押すと選んだタブの番号を返す', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(_tabBar(onSelected: selected.add));

    for (final label in _labels) {
      await tester.tap(find.text(label));
    }

    expect(selected, [0, 1, 2]);
  });
}
