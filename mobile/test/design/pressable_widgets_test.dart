import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
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
    name: 'ボタン L primary',
    build: (onTap) => AppButton(
      label: 'このルールで保存',
      variant: AppButtonVariant.primary,
      size: AppButtonSize.l,
      onTap: onTap,
    ),
    semanticLabel: 'このルールで保存',
    minHeight: 56,
    surface: AppColors.inkPrimary,
    foreground: AppColors.paperRaised,
  ),
  _Pressable(
    name: 'ボタン M ghost',
    build: (onTap) => AppButton(
      label: 'うまくいかないときの連絡先',
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.m,
      onTap: onTap,
    ),
    semanticLabel: 'うまくいかないときの連絡先',
    minHeight: 44,
    surface: AppColors.paperBase,
    foreground: AppColors.inkSecondary,
    isTransparent: true,
  ),
  _Pressable(
    name: 'ボタン S ghost',
    build: (onTap) => Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        label: 'なおす',
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.s,
        leadingIcon: AppIcons.pencil,
        onTap: onTap,
      ),
    ),
    semanticLabel: 'なおす',
    minHeight: 44,
    surface: AppColors.paperRaised,
    foreground: AppColors.inkSecondary,
    isTransparent: true,
  ),
  _Pressable(
    name: 'ボタン S ghost(左右の余白なし)',
    build: (onTap) => Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        label: 'まとめの間違いを直す',
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.sFlush,
        leadingIcon: AppIcons.pencil,
        onTap: onTap,
      ),
    ),
    semanticLabel: 'まとめの間違いを直す',
    minHeight: 44,
    surface: AppColors.paperRaised,
    foreground: AppColors.inkSecondary,
    isTransparent: true,
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
        label: 'この日時で予約する',
        variant: AppButtonVariant.primary,
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
          label: 'この日時で予約する',
          variant: AppButtonVariant.primary,
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

  testWidgets('ボタンと入力欄の角は 8', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Column(
        children: [
          AppButton(
            label: 'このルールで保存',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.l,
            onTap: () {},
          ),
          AppField(text: '伝えたいことを入力', onTap: () {}),
        ],
      ),
    );

    RoundedRectangleBorder shapeOf(String label) =>
        tester
                .widget<Material>(
                  find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .shape!
            as RoundedRectangleBorder;

    expect(shapeOf('このルールで保存').borderRadius, AppRadius.borderRadius);
    final field = shapeOf('伝えたいことを入力');
    expect(field.borderRadius, AppRadius.borderRadius);
    expect(
      field.side,
      const BorderSide(color: AppColors.lineStrong, width: 1.5),
    );
  });

  group('onTap が null のボタン', () {
    for (final variant in AppButtonVariant.values) {
      testEachLayout('${variant.name} は押せず、読み上げも押せない状態になる', (
        tester,
        layout,
      ) async {
        await pumpInLayout(
          tester,
          layout,
          AppButton(
            label: 'この日時で予約する',
            variant: variant,
            size: AppButtonSize.l,
            onTap: null,
          ),
        );

        final inkWell = find.byType(InkWell);
        expect(tester.getSize(inkWell).height, greaterThanOrEqualTo(56));
        expect(tester.widget<InkWell>(inkWell).onTap, isNull);
        expect(
          tester.getSemantics(inkWell),
          isSemantics(
            label: 'この日時で予約する',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
      });

      testWidgets('${variant.name} はモックの disabledBtn の見た目になる', (tester) async {
        await pumpInLayout(
          tester,
          layoutCases.first,
          AppButton(
            label: 'この日時で予約する',
            variant: variant,
            size: AppButtonSize.l,
            leadingIcon: AppIcons.phone,
            onTap: null,
          ),
        );

        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(InkWell),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, AppColors.buttonDisabled);
        expect(
          material.shape,
          RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadius,
            side: variant == AppButtonVariant.secondary
                ? const BorderSide(color: AppColors.lineStrong, width: 1.5)
                : BorderSide.none,
          ),
        );
        expect(
          tester.widget<Text>(find.text('この日時で予約する')).style?.color,
          AppColors.inkSecondary,
        );
        expect(
          tester.widget<AppIcon>(find.byType(AppIcon)).color,
          AppColors.inkSecondary,
        );
      });
    }

    testWidgets('押しても色を重ねない', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppButton(
          label: 'この日時で予約する',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.l,
          onTap: null,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InkWell)),
      );
      await tester.pump(kPressTimeout);
      await tester.pump(const Duration(milliseconds: 200));

      final overlay = AppPressable.overlayOf(AppColors.inkSecondary);
      final inkWell = tester.element(find.byType(InkWell));
      expect(Material.of(inkWell), isNot(paints..rect(color: overlay)));

      await gesture.up();
    });

    testWidgets('onTap を渡すと押せる見た目に戻る', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        AppButton(
          label: 'この日時で予約する',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.l,
          onTap: () {},
        ),
      );

      expect(
        tester.getSemantics(find.byType(InkWell)),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
    });
  });

  testWidgets('sFlush は文字の左端が親の端に揃い、s は 8 の余白を取る', (tester) async {
    for (final (size, inset) in [
      (AppButtonSize.s, 8.0),
      (AppButtonSize.sFlush, 0.0),
    ]) {
      await pumpInLayout(
        tester,
        layoutCases.first,
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'なおす',
            variant: AppButtonVariant.ghost,
            size: size,
            leadingIcon: AppIcons.pencil,
            onTap: () {},
          ),
        ),
      );

      final button = tester.getTopLeft(find.byType(AppButton)).dx;
      expect(tester.getTopLeft(find.byType(AppIcon)).dx - button, inset);
      expect(tester.getSize(find.byType(AppIcon)).width, 16);
    }
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
