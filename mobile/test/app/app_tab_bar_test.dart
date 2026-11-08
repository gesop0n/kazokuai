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

      expect(tester.getSize(_button(label)).width, layout.width / 3);
      expect(tester.getSize(_button(label)).height, 56);
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

  testWidgets('平らな紙のバーで、上に lineStrong の線がある', (tester) async {
    await tester.pumpWidget(_tabBar());

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(AppTabBar),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, AppColors.paperRaised);
    expect(decoration.borderRadius, isNull);
    expect(decoration.boxShadow, isNull);
    expect(
      decoration.border?.top,
      const BorderSide(color: AppColors.lineStrong),
    );
  });

  testWidgets('開いているタブは太字の ink で、上に左右 20 空けた線がある', (tester) async {
    await tester.pumpWidget(_tabBar(currentIndex: 1));

    Material materialOf(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    FontWeight? weightOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.fontWeight;

    expect(materialOf('通話記録').color, Colors.transparent);
    expect(materialOf('通話記録').shape, const RoundedRectangleBorder());
    expect(weightOf('通話記録'), FontWeight.w700);
    expect(
      tester.widget<Text>(find.text('通話記録')).style?.color,
      AppColors.inkPrimary,
    );
    expect(materialOf('ホーム').color, Colors.transparent);
    expect(materialOf('ホーム').shape, const RoundedRectangleBorder());
    expect(weightOf('ホーム'), FontWeight.w400);

    final line = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == AppColors.inkPrimary,
    );
    expect(line, findsOneWidget);
    final button = _button('通話記録');
    expect(tester.getSize(line), Size(tester.getSize(button).width - 40, 3));
    expect(tester.getTopLeft(line).dx, tester.getTopLeft(button).dx + 20);
    expect(
      tester.getTopLeft(line).dy,
      tester.getTopLeft(find.byType(AppTabBar)).dy,
    );
    final box = tester.widget<ColoredBox>(line);
    expect(box.color, AppColors.inkPrimary);
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
