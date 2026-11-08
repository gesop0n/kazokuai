import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

import '../support/layout_matrix.dart';

const _longText = '押すとすぐにハナさんの固定電話にかけて、伝えたいことをAIの声でお知らせします';

Border _borderOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppTextField),
      matching: find.byType(Container),
    ),
  );
  final decoration = container.foregroundDecoration! as BoxDecoration;
  return decoration.border! as Border;
}

void main() {
  testEachLayout('崩れず、44pt 以上で、入力できて、読み上げられる', (tester, layout) async {
    final changes = <String>[];
    await pumpInLayout(
      tester,
      layout,
      AppTextField(
        hintText: '話題を入力(例: 大相撲)',
        semanticLabel: '話題',
        onChanged: changes.add,
      ),
    );

    final size = tester.getSize(find.byType(AppTextField));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(56));

    await tester.enterText(find.byType(TextField), '庭の菊');
    await tester.pump();
    expect(changes, ['庭の菊']);

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(isTextField: true, isFocused: true, value: '庭の菊'),
    );
  });

  testEachLayout('複数行で長い文字を入れると、最小の高さより伸びる', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      AppTextField(
        controller: TextEditingController(text: _longText * 3),
        minHeight: 60,
        maxLines: null,
      ),
    );

    expect(tester.getSize(find.byType(AppTextField)).height, greaterThan(60));
  });

  testEachLayout('1 行のときは長い文字でも高さが変わらない', (tester, layout) async {
    await pumpInLayout(
      tester,
      layout,
      AppTextField(controller: TextEditingController(text: _longText * 3)),
    );

    expect(tester.getSize(find.byType(AppTextField)).height, 56);
  });

  testEachLayout('長いヒントでも崩れない', (tester, layout) async {
    await pumpInLayout(tester, layout, AppTextField(hintText: _longText * 3));

    expect(tester.getSize(find.byType(AppTextField)).height, 56);
  });

  testWidgets('読み上げの名前が入力欄に付く', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      const AppTextField(semanticLabel: '伝えたいこと'),
    );

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(label: '伝えたいこと', isTextField: true),
    );
  });

  testWidgets('ヒントを読み上げる', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      const AppTextField(hintText: '話題を入力'),
    );

    expect(find.bySemanticsLabel(RegExp('話題を入力')), findsOneWidget);
  });

  group('モックの値', () {
    testWidgets('既定の高さは 56 で、角丸 8、枠 1.5 の lineStrong', (tester) async {
      await pumpInLayout(tester, layoutCases.first, const AppTextField());

      expect(tester.getSize(find.byType(AppTextField)).height, 56);

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppTextField),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.paperRaised);
      expect(decoration.borderRadius, AppRadius.borderRadius);
      expect(
        _borderOf(tester).top,
        const BorderSide(color: AppColors.lineStrong, width: 1.5),
      );
    });

    testWidgets('最小の高さを指定できる', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppTextField(minHeight: 72, maxLines: null),
      );

      expect(tester.getSize(find.byType(AppTextField)).height, 72);
    });

    testWidgets('1 行は上下の中央、複数行は上から 12 の余白を取る', (tester) async {
      await pumpInLayout(tester, layoutCases.first, const AppTextField());

      final field = tester.getRect(find.byType(AppTextField));
      final line = tester.getRect(find.byType(EditableText));
      expect(line.center.dy, field.center.dy);
      expect(line.left - field.left, 16 + 1.5);

      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppTextField(minHeight: 72, maxLines: null),
      );

      final tall = tester.getRect(find.byType(AppTextField));
      expect(
        tester.getRect(find.byType(EditableText)).top - tall.top,
        12 + 1.5,
      );
    });

    testWidgets('文字は既定で labelL の太さ 400、ヒントは同じ大きさで inkSecondary', (
      tester,
    ) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppTextField(hintText: '話題を入力'),
      );

      final style = tester.widget<TextField>(find.byType(TextField)).style!;
      expect(style.fontSize, AppTextStyles.labelL.fontSize);
      expect(style.height, AppTextStyles.labelL.height);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, AppColors.inkPrimary);

      final hint = tester.widget<Text>(find.text('話題を入力')).style!;
      expect(hint.fontSize, AppTextStyles.labelL.fontSize);
      expect(hint.color, AppColors.inkSecondary);
    });

    testWidgets('文字の大きさを変えられる', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppTextField(textStyle: AppTextStyles.labelM),
      );

      final style = tester.widget<TextField>(find.byType(TextField)).style!;
      expect(style.fontSize, AppTextStyles.labelM.fontSize);
      expect(style.color, AppColors.inkPrimary);
    });
  });

  group('フォーカス', () {
    testWidgets('フォーカスすると枠が 2 の inkPrimary になり、外すと戻る', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpInLayout(
        tester,
        layoutCases.first,
        AppTextField(focusNode: focusNode),
      );

      focusNode.requestFocus();
      await tester.pump();
      expect(
        _borderOf(tester).top,
        const BorderSide(color: AppColors.inkPrimary, width: 2),
      );

      focusNode.unfocus();
      await tester.pump();
      expect(
        _borderOf(tester).top,
        const BorderSide(color: AppColors.lineStrong, width: 1.5),
      );
    });

    testWidgets('枠が太くなっても大きさと文字の位置は変わらない', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpInLayout(
        tester,
        layoutCases.first,
        AppTextField(focusNode: focusNode),
      );

      final fieldBefore = tester.getRect(find.byType(AppTextField));
      final lineBefore = tester.getRect(find.byType(EditableText));

      focusNode.requestFocus();
      await tester.pump();

      expect(tester.getRect(find.byType(AppTextField)), fieldBefore);
      expect(tester.getRect(find.byType(EditableText)), lineBefore);
    });

    testWidgets('文字の外の余白を押してもフォーカスする', (tester) async {
      await pumpInLayout(tester, layoutCases.first, const AppTextField());

      final field = tester.getRect(find.byType(AppTextField));
      await tester.tapAt(field.bottomLeft + const Offset(4, -4));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );
    });

    testWidgets('autofocus を指定すると最初からフォーカスする', (tester) async {
      await pumpInLayout(
        tester,
        layoutCases.first,
        const AppTextField(autofocus: true),
      );
      await tester.pump();

      expect(
        _borderOf(tester).top,
        const BorderSide(color: AppColors.inkPrimary, width: 2),
      );
    });

    testWidgets('自分で作った FocusNode は破棄し、渡された FocusNode は破棄しない', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpInLayout(
        tester,
        layoutCases.first,
        AppTextField(focusNode: focusNode),
      );
      await tester.pumpWidget(const SizedBox());

      // 破棄されていれば addListener が例外になる
      expect(() => focusNode.addListener(() {}), returnsNormally);
    });
  });

  testWidgets('カーソルと選択の色、選択ハンドルの色は inkPrimary', (tester) async {
    await pumpInLayout(
      tester,
      layoutCases.first,
      const AppTextField(autofocus: true),
    );
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.cursorColor, AppColors.inkPrimary);
    expect(editable.selectionColor?.withAlpha(0xFF), AppColors.inkPrimary);
    expect(
      CupertinoTheme.of(tester.element(find.byType(AppTextField)))
          .selectionHandleColor,
      AppColors.inkPrimary,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('controller の文字を表示する', (tester) async {
    final controller = TextEditingController(text: '金曜の通院');
    addTearDown(controller.dispose);
    await pumpInLayout(
      tester,
      layoutCases.first,
      AppTextField(controller: controller),
    );

    expect(find.text('金曜の通院'), findsOneWidget);
  });
}
