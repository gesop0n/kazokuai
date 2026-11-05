import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

import '../support/layout_matrix.dart';

const _longLabel = '押すとすぐにハナさんの固定電話にかけて、伝えたいことをAIの声でお知らせします';

class _Pressable {
  const _Pressable({
    required this.name,
    required this.build,
    required this.semanticLabel,
    required this.minHeight,
    required this.surface,
    required this.foreground,
    this.isTransparent = false,
  });

  final String name;
  final Widget Function(VoidCallback onTap) build;
  final String semanticLabel;
  final double minHeight;
  // 重ねる色の下にある面の色
  final Color surface;
  final Color foreground;
  final bool isTransparent;
}

final _pressables = [
  _Pressable(
    name: 'ボタン L record',
    build: (onTap) => AppButton(
      label: '通話',
      variant: AppButtonVariant.record,
      size: AppButtonSize.l,
      leadingIcon: AppIcons.phone,
      onTap: onTap,
    ),
    semanticLabel: '通話',
    minHeight: 56,
    surface: AppColors.accentCall,
    foreground: AppColors.onAccentCall,
  ),
  _Pressable(
    name: 'ボタン M secondary',
    build: (onTap) => AppButton(
      label: '通話記録を見る',
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.m,
      trailingIcon: AppIcons.chevronRight,
      onTap: onTap,
    ),
    semanticLabel: '通話記録を見る',
    minHeight: 44,
    surface: AppColors.paperRaised,
    foreground: AppColors.inkPrimary,
  ),
  _Pressable(
    name: 'ボタン M light',
    build: (onTap) => AppButton(
      label: '会話を見る',
      variant: AppButtonVariant.light,
      size: AppButtonSize.m,
      trailingIcon: AppIcons.chevronRight,
      onTap: onTap,
    ),
    semanticLabel: '会話を見る',
    minHeight: 44,
    surface: AppColors.nightText,
    foreground: AppColors.nightBase,
  ),
  _Pressable(
    name: 'アイコンボタン',
    build: (onTap) => Align(
      alignment: Alignment.centerLeft,
      child: AppIconButton(AppIcons.bell, semanticLabel: '通知', onTap: onTap),
    ),
    semanticLabel: '通知',
    minHeight: 44,
    surface: AppColors.paperBase,
    foreground: AppColors.inkPrimary,
    isTransparent: true,
  ),
  _Pressable(
    name: '入力欄',
    build: (onTap) => AppField(text: '伝えたいことを入力', minHeight: 48, onTap: onTap),
    semanticLabel: '伝えたいことを入力',
    minHeight: 48,
    surface: AppColors.paperRaised,
    foreground: AppColors.inkPrimary,
  ),
];

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (la > lb ? la + .05 : lb + .05) / (la > lb ? lb + .05 : la + .05);
}

void main() {
  for (final pressable in _pressables) {
    group(pressable.name, () {
      testEachLayout('崩れず、押せて、44pt 以上で、読み上げられる', (tester, layout) async {
        var tapCount = 0;
        await pumpInLayout(tester, layout, pressable.build(() => tapCount++));

        final inkWell = find.byType(InkWell);
        await tester.tap(inkWell);
        expect(tapCount, 1);

        final size = tester.getSize(inkWell);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(pressable.minHeight));

        expect(
          tester.getSemantics(inkWell),
          isSemantics(
            label: pressable.semanticLabel,
            isButton: true,
            hasTapAction: true,
          ),
        );
      });

      testWidgets('文字倍率 1.0 の高さがモックと同じ', (tester) async {
        await pumpInLayout(tester, layoutCases.first, pressable.build(() {}));

        expect(
          tester.getSize(find.byType(InkWell)).height,
          pressable.minHeight,
        );
      });

      testWidgets('重ねた色が隠れないように、背景は Material に持たせる', (tester) async {
        await pumpInLayout(tester, layoutCases.first, pressable.build(() {}));

        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(InkWell),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          material.color,
          pressable.isTransparent ? Colors.transparent : pressable.surface,
        );
      });

      testWidgets('押すと前景色を薄く重ね、波紋を出さない', (tester) async {
        await pumpInLayout(tester, layoutCases.first, pressable.build(() {}));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InkWell)),
        );
        await tester.pump(kPressTimeout);
        await tester.pump(const Duration(milliseconds: 200));

        final overlay = AppPressable.overlayOf(pressable.foreground);
        final inkWell = tester.element(find.byType(InkWell));
        expect(Material.of(inkWell), paints..rect(color: overlay));
        expect(Theme.of(inkWell).splashFactory, NoSplash.splashFactory);

        await gesture.up();
      });

      test('重ねた色が面の色と見分けられる', () {
        final pressed = Color.alphaBlend(
          AppPressable.overlayOf(pressable.foreground),
          pressable.surface,
        );

        expect(_contrast(pressed, pressable.surface), greaterThan(1.15));
      });
    });
  }

  test('濃い面に透明の部品を置いても、前景色が明るければ重ねた色が見える', () {
    final pressed = Color.alphaBlend(
      AppPressable.overlayOf(AppColors.nightText),
      AppColors.nightBase,
    );

    expect(_contrast(pressed, AppColors.nightBase), greaterThan(1.15));
  });

  group('長い文字', () {
    testEachLayout('ボタンが折り返して、最小の高さより伸びる', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        AppButton(
          label: _longLabel * 2,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          leadingIcon: AppIcons.phone,
          trailingIcon: AppIcons.chevronRight,
          onTap: () {},
        ),
      );

      expect(tester.getSize(find.byType(InkWell)).height, greaterThan(44));
    });

    testEachLayout('入力欄が折り返して、最小の高さより伸びる', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        AppField(text: _longLabel * 2, minHeight: 48, onTap: () {}),
      );

      expect(tester.getSize(find.byType(InkWell)).height, greaterThan(48));
    });
  });

  testEachLayout('親が幅を決めるとボタンは幅いっぱいに広がる', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      AppButton(
        label: '通話',
        variant: AppButtonVariant.record,
        size: AppButtonSize.l,
        onTap: () {},
      ),
    );

    expect(tester.getSize(find.byType(InkWell)).width, layout.width - 32);
  });

  testWidgets('親が幅を決めないとボタンは中身の幅になる', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          label: '通話',
          variant: AppButtonVariant.record,
          size: AppButtonSize.l,
          onTap: () {},
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(AppButton)).width,
      lessThan(layoutCases.first.width - 32),
    );
  });

  testWidgets('アイコンボタンは 44pt の正方形で、アイコンの読み上げを重ねない', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppIconButton(AppIcons.bell, semanticLabel: '通知', onTap: () {}),
      ),
    );

    expect(tester.getSize(find.byType(AppIconButton)), const Size.square(44));
    expect(find.bySemanticsLabel('通知'), findsOneWidget);
  });

  testWidgets('入力欄の既定の高さは 56 で、TextField を使わない', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      AppField(text: '話題を入力', onTap: () {}),
    );

    expect(tester.getSize(find.byType(AppField)).height, 56);
    expect(find.byType(TextField), findsNothing);
  });
}
