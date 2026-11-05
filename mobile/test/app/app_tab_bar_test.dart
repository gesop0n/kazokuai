import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';

const _labels = ['ホーム', '通話記録', '予約電話'];

Widget _tabBar({int currentIndex = 0, ValueChanged<int>? onSelected}) {
  return MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AppTabBar(
        currentIndex: currentIndex,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  );
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  for (final width in [360.0, 393.0, 440.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('幅 $width、文字倍率 $scale でタブバーが overflow しない', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 852);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(const KazokuAiApp());
        await tester.pumpAndSettle();

        // 選択中の太字がいちばん広いので、すべてのタブを選んで確かめる
        for (final label in _labels) {
          await tester.tap(
            find.descendant(
              of: find.byType(AppTabBar),
              matching: find.text(label),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_button(label)), const Size(88, 56));
          expect(tester.getSize(find.byType(AppTabBar)).width, width);
        }
      });
    }
  }

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
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_tabBar(currentIndex: 1));

    expect(
      tester.getSemantics(find.text('通話記録')),
      isSemantics(
        label: '通話記録',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('ホーム')),
      isSemantics(
        label: 'ホーム',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );

    semantics.dispose();
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
    expect(weightOf('ホーム'), FontWeight.w500);
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
