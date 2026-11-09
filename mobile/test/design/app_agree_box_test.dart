import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_agree_box.dart';

import '../support/layout_matrix.dart';

Finder _mark(String label) => find.descendant(
  of: find.bySemanticsLabel(label),
  matching: find.byType(DecoratedBox),
);

BoxDecoration _decoration(WidgetTester tester, String label) =>
    tester.widget<DecoratedBox>(_mark(label)).decoration as BoxDecoration;

void main() {
  testWidgets('チェックなしは線だけの四角で、押すと反応する', (tester) async {
    var taps = 0;
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppAgreeBox(
          checked: false,
          semanticLabel: 'チェックなし',
          onTap: () => taps++,
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppAgreeBox)), const Size(44, 56));
    expect(tester.getSize(_mark('チェックなし')), const Size(24, 24));
    expect(
      tester.getCenter(_mark('チェックなし')),
      tester.getCenter(find.byType(AppAgreeBox)),
    );

    final decoration = _decoration(tester, 'チェックなし');
    expect(decoration.color, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(6));
    expect(
      decoration.border,
      Border.all(color: AppColors.lineStrong, width: 1.5),
    );
    expect(find.byType(AppIcon), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('チェックなし')),
      isSemantics(
        label: 'チェックなし',
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isButton: false,
      ),
    );

    final rect = tester.getRect(find.byType(AppAgreeBox));
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.tapAt(rect.bottomRight - const Offset(1, 1));
    expect(taps, 2);
  });

  testWidgets('チェックありは ink の地に白いチェックが出る', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      const Align(
        alignment: Alignment.centerLeft,
        child: AppAgreeBox(
          checked: true,
          semanticLabel: 'チェックあり',
          onTap: _noop,
        ),
      ),
    );

    final decoration = _decoration(tester, 'チェックあり');
    expect(decoration.color, AppColors.inkPrimary);
    expect(
      decoration.border,
      Border.all(color: AppColors.inkPrimary, width: 1.5),
    );
    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.icon, AppIcons.check);
    expect(icon.size, 16);
    expect(icon.color, AppColors.white);
    expect(
      tester.getSemantics(find.bySemanticsLabel('チェックあり')),
      isSemantics(isChecked: true, isEnabled: true),
    );
  });

  testWidgets('押せないときは paper-sunken の地で、押しても何も起きない', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      const Align(
        alignment: Alignment.centerLeft,
        child: AppAgreeBox(checked: false, semanticLabel: '押せない', onTap: null),
      ),
    );

    final decoration = _decoration(tester, '押せない');
    expect(decoration.color, AppColors.paperSunken);
    expect(
      decoration.border,
      Border.all(color: AppColors.lineStrong, width: 1.5),
    );
    expect(find.byType(AppIcon), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('押せない')),
      isSemantics(
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );

    await tester.tap(find.bySemanticsLabel('押せない'));
    expect(
      tester.getSemantics(find.bySemanticsLabel('押せない')),
      isSemantics(isChecked: false, isEnabled: false),
    );
  });
}

void _noop() {}
