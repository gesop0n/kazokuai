import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_theme.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_avatar.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/main_gallery.dart';

import '../support/layout_matrix.dart';

void main() {
  testEachLayout('部品一覧画面が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const GalleryScreen());

    for (final type in [
      AppAiTag,
      AppAvatar,
      AppButton,
      AppCard,
      AppField,
      AppIconButton,
      AppIconCircle,
      AppPill,
    ]) {
      expect(find.byType(type), findsWidgets);
    }
  });

  testWidgets('ボタンの 3 種類が並ぶ', (tester) async {
    await pumpScreenInLayout(tester, layoutCases.first, const GalleryScreen());

    final variants = tester
        .widgetList<AppButton>(find.byType(AppButton))
        .map((button) => button.variant);
    expect(variants, containsAll(AppButtonVariant.values));
  });

  testWidgets('紫の primary が標準部品に出ない', (tester) async {
    await pumpScreenInLayout(tester, layoutCases.first, const GalleryScreen());

    final primary = appTheme.colorScheme.primary;
    for (final material in tester.widgetList<Material>(find.byType(Material))) {
      expect(material.color?.withAlpha(0xFF), isNot(primary));
    }
    const states = [
      WidgetState.pressed,
      WidgetState.focused,
      WidgetState.hovered,
    ];
    for (final inkWell in tester.widgetList<InkWell>(find.byType(InkWell))) {
      for (final state in states) {
        final overlay = inkWell.overlayColor?.resolve({state});
        expect(overlay, isNotNull);
        expect(overlay?.withAlpha(0xFF), isNot(primary));
      }
    }
  });

  testWidgets('ロケールが ja で、文字倍率の上限が 1.3 になる', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const GalleryApp());

    final context = tester.element(find.byType(GalleryScreen));
    expect(Localizations.localeOf(context), const Locale('ja'));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(13, .001));
    expect(Theme.of(context).splashFactory, NoSplash.splashFactory);
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      appTheme.scaffoldBackgroundColor,
    );
  });
}
