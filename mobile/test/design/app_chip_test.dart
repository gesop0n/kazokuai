import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';

import '../support/layout_matrix.dart';

const _longLabel = '押すとすぐにハナさんの固定電話にかけて、伝えたいことをAIの声でお知らせします';

Material _surfaceOf(WidgetTester tester) => tester.widget<Material>(
  find
      .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
      .first,
);

void main() {
  for (final size in AppChipSize.values) {
    group('高さ ${size.height.toInt()}', () {
      testEachLayout('崩れず、押せて、44pt 以上で、読み上げられる', (tester, layout) async {
        var tapCount = 0;
        await pumpInLayout(
          tester,
          layout,
          Align(
            alignment: Alignment.centerLeft,
            child: AppChip(
              label: '全部',
              selected: true,
              size: size,
              onTap: () => tapCount++,
            ),
          ),
        );

        await tester.tap(find.byType(AppChip));
        expect(tapCount, 1);

        final chip = tester.getSize(find.byType(AppChip));
        expect(chip.width, greaterThanOrEqualTo(44));
        expect(chip.height, greaterThanOrEqualTo(44));

        expect(
          tester.getSemantics(find.byType(InkWell)),
          isSemantics(
            label: '全部',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true,
          ),
        );
      });

      testWidgets('見た目の高さはモックと同じで、上下の余白も押せる', (tester) async {
        var tapCount = 0;
        await pumpInLayout(
          tester,
          layoutCases.first,
          Align(
            alignment: Alignment.centerLeft,
            child: AppChip(
              label: '全部',
              selected: false,
              size: size,
              onTap: () => tapCount++,
            ),
          ),
        );

        expect(tester.getSize(find.byType(InkWell)).height, size.height);
        expect(tester.getSize(find.byType(AppChip)).height, 44);

        final rect = tester.getRect(find.byType(AppChip));
        await tester.tapAt(rect.topCenter + const Offset(0, 1));
        expect(tapCount, 1);
        await tester.tapAt(rect.bottomCenter - const Offset(0, 1));
        expect(tapCount, 2);
      });
    });
  }

  testWidgets('左右の余白は高さ 36 で 16、高さ 32 で 12', (tester) async {
    for (final (size, padding) in [
      (AppChipSize.m, 16.0),
      (AppChipSize.s, 12.0),
    ]) {
      await pumpInLayout(
        tester,
        layoutCases.first,
        Align(
          alignment: Alignment.centerLeft,
          child: AppChip(
            label: '全部',
            selected: false,
            size: size,
            onTap: () {},
          ),
        ),
      );

      // 枠線の 1 の内側に余白を取る
      expect(
        tester.getTopLeft(find.text('全部')).dx -
            tester.getTopLeft(find.byType(AppChip)).dx,
        padding + 1,
      );
    }
  });

  testWidgets('選んでいないときは紙の色に細い線', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChip(label: '体調', selected: false, onTap: () {}),
      ),
    );

    final surface = _surfaceOf(tester);
    expect(surface.color, AppColors.paperRaised);
    expect(
      surface.shape,
      const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: BorderSide(color: AppColors.lineStrong),
      ),
    );
    expect(
      tester.widget<Text>(find.text('体調')).style?.color,
      AppColors.inkPrimary,
    );
    expect(
      tester.getSemantics(find.byType(InkWell)),
      isSemantics(hasSelectedState: true, isSelected: false),
    );
  });

  testWidgets('選んでいるときは濃い色で、文字は紙の色', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChip(label: '全部', selected: true, onTap: () {}),
      ),
    );

    final surface = _surfaceOf(tester);
    expect(surface.color, AppColors.inkPrimary);
    expect(
      surface.shape,
      const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: BorderSide(color: AppColors.inkPrimary),
      ),
    );
    expect(
      tester.widget<Text>(find.text('全部')).style?.color,
      AppColors.paperRaised,
    );
  });

  testWidgets('アイコンは 16 で、文字の左に 8 空けて文字と同じ色で出す', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChip(
          label: 'お孫さん',
          selected: true,
          icon: AppIcons.check,
          onTap: () {},
        ),
      ),
    );

    final icon = find.byType(AppIcon);
    expect(tester.getSize(icon), const Size.square(16));
    expect(tester.widget<AppIcon>(icon).color, AppColors.paperRaised);
    expect(
      tester.getTopLeft(find.text('お孫さん')).dx - tester.getTopRight(icon).dx,
      8,
    );
  });

  testWidgets('アイコンを渡さなければ出さない', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChip(label: '全部', selected: false, onTap: () {}),
      ),
    );

    expect(find.byType(AppIcon), findsNothing);
  });

  testWidgets('1 回押しても onTap は 1 回だけ呼ばれる', (tester) async {
    var tapCount = 0;
    await pumpInLayout(
      tester,
      layoutCases.first,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChip(label: '全部', selected: false, onTap: () => tapCount++),
      ),
    );

    await tester.tap(find.byType(InkWell));
    expect(tapCount, 1);
  });

  testEachLayout('長い文字でも崩れない', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      AppChip(
        label: _longLabel * 2,
        selected: false,
        icon: AppIcons.plus,
        onTap: () {},
      ),
    );

    expect(tester.getSize(find.byType(InkWell)).height, greaterThan(36));
  });

  testEachLayout('Wrap で並べると、入らないチップは次の行に送る', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      Wrap(
        spacing: 8,
        children: [
          for (final label in const [
            '全部',
            '体調',
            '話し相手',
            '操作案内',
            '不在',
            'カスタマイズ',
          ])
            AppChip(label: label, selected: false, onTap: () {}),
        ],
      ),
    );

    expect(find.byType(AppChip), findsNWidgets(6));
  });
}
