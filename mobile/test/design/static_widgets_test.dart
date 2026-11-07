import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_avatar.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';

import '../support/layout_matrix.dart';

const _longLabel = 'Geminiのまとめ。右の時刻で元の発言へ移動します。とても長い文字でも崩れません';

Widget _inline(Widget child) =>
    Align(alignment: Alignment.centerLeft, child: child);

void main() {
  group('カード', () {
    for (final variant in AppCardVariant.values) {
      testEachLayout('${variant.name} が崩れない', (tester, layout) async {
        await pumpInLayout(
          tester,
          layout,
          AppCard(
            variant: variant,
            children: const [Text(_longLabel), Text('2つ目')],
          ),
        );

        expect(find.bySemanticsLabel('2つ目'), findsOneWidget);
      });
    }

    testWidgets('paper の余白と間隔がモックと同じ', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppCard(
          variant: AppCardVariant.paper,
          children: [
            SizedBox(key: Key('a'), height: 10),
            SizedBox(key: Key('b'), height: 10),
          ],
        ),
      );

      final card = tester.getTopLeft(find.byType(AppCard));
      final a = tester.getTopLeft(find.byKey(const Key('a')));
      // 余白 16 に枠線 1 を足した位置になる
      expect(a - card, const Offset(17, 17));
      expect(tester.getTopLeft(find.byKey(const Key('b'))).dy - a.dy, 10 + 12);
    });

    testWidgets('night の余白と間隔がモックと同じ', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppCard(
          variant: AppCardVariant.night,
          children: [
            SizedBox(key: Key('a'), height: 10),
            SizedBox(key: Key('b'), height: 10),
          ],
        ),
      );

      final card = tester.getTopLeft(find.byType(AppCard));
      final a = tester.getTopLeft(find.byKey(const Key('a')));
      expect(a - card, const Offset(20, 20));
      expect(tester.getTopLeft(find.byKey(const Key('b'))).dy - a.dy, 10);
    });

    testWidgets('night の中の文字は夜の色になる', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppCard(
          variant: AppCardVariant.night,
          children: [Text('まとめ', style: AppTextStyles.titleM)],
        ),
      );

      final style = DefaultTextStyle.of(tester.element(find.text('まとめ'))).style;
      expect(style.color, AppColors.nightText);
    });
  });

  group('ピル', () {
    testEachLayout('崩れず、読み上げられる', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        _inline(
          const AppPill(
            variant: AppPillVariant.care,
            icon: AppIcons.alert,
            label: '気になる話',
          ),
        ),
      );

      expect(find.bySemanticsLabel('気になる話'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppPill)).height,
        greaterThanOrEqualTo(24),
      );
    });

    testEachLayout('長い文字でも崩れない', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        _inline(
          const AppPill(
            variant: AppPillVariant.care,
            icon: AppIcons.alert,
            label: _longLabel,
          ),
        ),
      );
    });

    testWidgets('文字はモックと同じ 700 の太さになる', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        _inline(
          const AppPill(
            variant: AppPillVariant.care,
            icon: AppIcons.alert,
            label: '気になる話',
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('気になる話'));
      expect(text.style?.fontWeight, FontWeight.w700);
      expect(text.style?.color, AppColors.inkPrimary);
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon)).color,
        AppColors.inkPrimary,
      );
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(AppPill),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.border, Border.all(color: AppColors.inkSecondary));
    });
  });

  group('丸いアイコン枠', () {
    testEachLayout('36pt で崩れず、押せず、読み上げの対象にならない', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        _inline(const AppIconCircle(AppIcons.moon)),
      );

      expect(tester.getSize(find.byType(AppIconCircle)), const Size.square(36));
      expect(find.byType(InkWell), findsNothing);
      expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    });
  });

  group('アバター', () {
    testEachLayout('36pt で崩れず、文字が枠に収まり、読み上げられる', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        _inline(const AppAvatar('ハ', color: AppColors.speakerParent)),
      );

      expect(tester.getSize(find.byType(AppAvatar)), const Size.square(36));
      expect(
        AppTextStyles.labelL.fontSize! *
            AppTextStyles.labelL.height! *
            layout.textScale,
        lessThanOrEqualTo(36),
      );
      expect(find.bySemanticsLabel('ハ'), findsOneWidget);
    });
  });

  group('AIのラベル', () {
    testEachLayout('崩れず、読み上げられる', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        const AppAiTag(
          label: 'Geminiのまとめ',
          color: AppColors.nightTextSecondary,
        ),
      );

      expect(find.bySemanticsLabel('Geminiのまとめ'), findsOneWidget);
    });

    testEachLayout('長い文字でも崩れない', (tester, layout) async {
      await pumpInLayout(tester, layout, const AppAiTag(label: _longLabel));
    });

    testWidgets('受け取った色を文字とアイコンに使う', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppAiTag(label: 'まとめ', color: AppColors.nightTextSecondary),
      );

      expect(
        tester.widget<Text>(find.text('まとめ')).style?.color,
        AppColors.nightTextSecondary,
      );
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon)).color,
        AppColors.nightTextSecondary,
      );
    });
  });
}
