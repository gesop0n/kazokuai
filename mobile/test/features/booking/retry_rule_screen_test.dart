import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

List<Override> _startingWith(RetryRule rule) => [
  retryRuleProvider.overrideWithBuild((ref, self) => rule),
];

Future<void> _pumpRule(
  WidgetTester tester, {
  LayoutCase layout = _standardLayout,
  RetryRule? rule,
}) => pumpScreenInLayout(
  tester,
  layout,
  const RetryRuleScreen(),
  overrides: rule == null ? const [] : _startingWith(rule),
);

AppChip _chip(WidgetTester tester, String label) =>
    tester.widget<AppChip>(find.widgetWithText(AppChip, label));

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AppChip, label));
  await tester.pump();
}

List<String> _selectedLabels(WidgetTester tester) => tester
    .widgetList<AppChip>(find.byType(AppChip))
    .where((chip) => chip.selected)
    .map((chip) => chip.label)
    .toList();

// 間隔の「その他」が 0、回数の「その他」が 1。欄は開いている順に並ぶ
Future<void> _tapCustom(WidgetTester tester, int index) async {
  await tester.tap(find.widgetWithText(AppChip, 'その他').at(index));
  await tester.pump();
}

Future<void> _typeInField(WidgetTester tester, int index, String text) async {
  await tester.enterText(find.byType(TextField).at(index), text);
  await tester.pump();
}

void _expectCanSave(WidgetTester tester, bool canSave) {
  expect(
    tester.getSemantics(find.bySemanticsLabel('このルールで保存')),
    isSemantics(isButton: true, hasEnabledState: true, isEnabled: canSave),
  );
}

// 読み上げの文で流れを並び順に取り出す
List<String> _flowLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final label = node.label;
    if (RegExp(r'^\d+:\d{2} ').hasMatch(label)) labels.add(label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(RetryRuleScreen)));
  return labels;
}

void main() {
  group('崩れない', () {
    for (final attempts in RetryRule.attemptChoices) {
      for (final interval in RetryRule.intervalChoices) {
        final label = '${RetryRule.intervalLabel(interval)}おきに$attempts回';
        testEachLayout(label, (tester, layout) async {
          await _pumpRule(
            tester,
            layout: layout,
            rule: RetryRule(interval: interval, attempts: attempts),
          );

          await tester.ensureVisible(find.textContaining('家族に通知します'));
          await tester.pumpAndSettle();

          expect(find.text('このルールで保存'), findsOneWidget);
          expect(find.text('知らせる人'), findsNothing);
        });
      }
    }

    testEachLayout('120分おきに10回', (tester, layout) async {
      await _pumpRule(
        tester,
        layout: layout,
        rule: const RetryRule(interval: Duration(minutes: 120), attempts: 10),
      );

      await tester.ensureVisible(find.textContaining('家族に通知します'));
      await tester.pumpAndSettle();

      expect(find.text('…'), findsOneWidget);
      expect(find.text('このルールで保存'), findsOneWidget);
    });

    testEachLayout('押せる領域はどれも 44 以上になる', (tester, layout) async {
      await _pumpRule(tester, layout: layout);

      final pressables = find.descendant(
        of: find.byType(RetryRuleScreen),
        matching: find.byType(InkWell),
      );
      expect(pressables, findsWidgets);
      for (final element in pressables.evaluate()) {
        final size = (element.renderObject! as RenderBox).size;
        expect(size.width, greaterThanOrEqualTo(44));
      }
      for (final element in find.byType(AppChip).evaluate()) {
        expect(
          (element.renderObject! as RenderBox).size.height,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testEachLayout('保存のボタンは本文がスクロールしても画面の下に残る', (tester, layout) async {
      await _pumpRule(tester, layout: layout);
      final before = tester.getTopLeft(find.text('このルールで保存')).dy;

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('このルールで保存')).dy, before);
    });
  });

  group('見出し', () {
    testWidgets('題はなく、流れは「出ないとき」', (tester) async {
      await _pumpRule(tester);

      expect(find.textContaining('どうしますか'), findsNothing);
      expect(find.textContaining('出ないときの流れ'), findsNothing);
      expect(find.text('朝9:00の電話に出ないとき'), findsOneWidget);
    });
  });

  group('選択', () {
    testWidgets('選択肢が並び、初期値は 15 分と 3 回', (tester) async {
      await _pumpRule(tester);

      for (final label in ['5分', '10分', '15分', '30分', '1回', '2回', '3回']) {
        expect(find.widgetWithText(AppChip, label), findsOneWidget);
      }
      expect(find.widgetWithText(AppChip, 'その他'), findsNWidgets(2));
      expect(find.widgetWithText(AppChip, '入力'), findsNothing);
      expect(find.text('かける回数(最初の1回をふくむ)'), findsNothing);
      expect(find.text('1時間'), findsNothing);
      expect(find.text('5回'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(_selectedLabels(tester), ['15分', '3回']);

      final chip = find.widgetWithText(AppChip, '15分');
      expect(
        tester
            .getSize(find.descendant(of: chip, matching: find.byType(InkWell)))
            .height,
        36,
      );
      // 枠線の 1 の内側に、左右 12 の余白を取る
      expect(
        tester.getTopLeft(find.text('15分')).dx - tester.getTopLeft(chip).dx,
        13,
      );
    });

    testWidgets('押すとそのチップだけが選ばれる', (tester) async {
      await _pumpRule(tester);

      await _tapChip(tester, '30分');
      await _tapChip(tester, '1回');

      expect(_chip(tester, '30分').selected, isTrue);
      expect(_chip(tester, '15分').selected, isFalse);
      expect(_chip(tester, '1回').selected, isTrue);
      expect(_chip(tester, '3回').selected, isFalse);
    });
  });

  group('入力', () {
    testWidgets('間隔は分の欄で、1〜120 なら保存でき、空と範囲の外はできない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);
      await tester.pump();

      expect(find.text('分'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppTextField)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getTopLeft(find.text('分')).dy,
        greaterThan(
          tester.getBottomLeft(find.widgetWithText(AppChip, '30分')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('分')).dy,
        lessThan(tester.getTopLeft(find.text('かける回数')).dy),
      );
      expect(_selectedLabels(tester), ['その他', '3回']);
      expect(
        tester.getSemantics(find.byType(EditableText)),
        isSemantics(label: 'かけなおす間隔を入力', isTextField: true, isFocused: true),
      );
      final number = tester.widget<EditableText>(find.byType(EditableText));
      expect(number.style.fontFamily, AppTextStyles.labelL.fontFamily);
      expect(number.style.fontWeight, FontWeight.w400);
      expect(number.style.fontSize, AppTextStyles.labelL.fontSize);
      expect(number.style.height, AppTextStyles.labelL.height);
      expect(number.style.letterSpacing, 0);
      expect(
        tester.widget<Text>(find.text('分')).style?.fontSize,
        AppTextStyles.labelM.fontSize,
      );
      _expectCanSave(tester, false);

      await _typeInField(tester, 0, '0');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '121');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '1');
      _expectCanSave(tester, true);
      await _typeInField(tester, 0, '120');
      _expectCanSave(tester, true);
      handle.dispose();
    });

    testWidgets('回数は回の欄で、1〜10 なら保存でき、空と範囲の外はできない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 1);
      await tester.pump();

      expect(find.text('回'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppTextField)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getTopLeft(find.text('回')).dy,
        greaterThan(
          tester.getBottomLeft(find.widgetWithText(AppChip, '3回')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('回')).dy,
        lessThan(tester.getTopLeft(find.text('朝9:00の電話に出ないとき')).dy),
      );
      expect(_selectedLabels(tester), ['15分', 'その他']);
      expect(
        tester.getSemantics(find.byType(EditableText)),
        isSemantics(label: 'かける回数を入力', isTextField: true, isFocused: true),
      );
      expect(
        tester.widget<Text>(find.text('回')).style?.fontSize,
        AppTextStyles.labelM.fontSize,
      );
      _expectCanSave(tester, false);

      await _typeInField(tester, 0, '0');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '11');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '1');
      _expectCanSave(tester, true);
      await _typeInField(tester, 0, '10');
      _expectCanSave(tester, true);
      handle.dispose();
    });

    testWidgets('どちらかが範囲の外なら保存できない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);
      await _typeInField(tester, 0, '7');
      await _tapCustom(tester, 1);
      await tester.pump();
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(fields[0].focusNode.hasFocus, isFalse);
      expect(fields[1].focusNode.hasFocus, isTrue);
      await _typeInField(tester, 1, '11');
      _expectCanSave(tester, false);

      await _typeInField(tester, 1, '4');
      _expectCanSave(tester, true);
      await _typeInField(tester, 0, '');
      _expectCanSave(tester, false);
      handle.dispose();
    });

    testWidgets('入れた数ですぐ流れを計算し直す', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);
      await _typeInField(tester, 0, '90');
      await _tapCustom(tester, 1);
      await _typeInField(tester, 1, '4');

      expect(_flowLabels(tester), ['9:00 1回目', '13:30 4回目', '13:30 家族に通知']);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('2回目'), findsNothing);
      expect(
        find.text('9:00から90分おきに4回かけて、出なければ13:30に家族に通知します。'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('チップを選び直すと欄が消えて保存できる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);
      await _tapChip(tester, '5分');

      expect(find.byType(TextField), findsNothing);
      expect(_selectedLabels(tester), ['5分', '3回']);
      _expectCanSave(tester, true);
      handle.dispose();
    });
  });

  group('朝9:00の流れ', () {
    testWidgets('初期値はモックのとおり', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      expect(_flowLabels(tester), [
        '9:00 1回目',
        '9:15 2回目',
        '9:30 3回目',
        '9:30 家族に通知',
      ]);
      expect(find.text('…'), findsNothing);
      expect(
        find.text('9:00から15分おきに3回かけて、出なければ9:30に家族に通知します。'),
        findsOneWidget,
      );
      final sentence = tester.widget<Text>(
        find.text('9:00から15分おきに3回かけて、出なければ9:30に家族に通知します。'),
      );
      expect(sentence.style?.fontSize, AppTextStyles.bodyS.fontSize);
      expect(sentence.style?.height, AppTextStyles.bodyS.height);
      expect(sentence.style?.color, AppColors.inkSecondary);
      expect(
        tester.getTopLeft(find.textContaining('家族に通知します')).dy,
        greaterThan(tester.getBottomLeft(find.text('3回目')).dy),
      );
      handle.dispose();
    });

    testWidgets('選択を変えるとすぐに計算し直す', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapChip(tester, '5分');
      await _tapChip(tester, '2回');

      expect(_flowLabels(tester), ['9:00 1回目', '9:05 2回目', '9:05 家族に通知']);
      handle.dispose();
    });

    testWidgets('1 回のときは、最初の回と同じ時刻に通知する', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapChip(tester, '1回');

      expect(_flowLabels(tester), ['9:00 1回目', '9:00 家族に通知']);
      handle.dispose();
    });

    testWidgets('画面の文字も選択から作る', (tester) async {
      await _pumpRule(tester);

      expect(find.text('9:00'), findsOneWidget);
      expect(find.text('9:15'), findsOneWidget);
      expect(find.text('9:30'), findsNWidgets(2));
      expect(find.text('3回目'), findsOneWidget);
      expect(find.text('4回目'), findsNothing);

      await _tapChip(tester, '5分');
      await _tapChip(tester, '1回');

      expect(find.text('9:00'), findsNWidgets(2));
      expect(find.text('9:05'), findsNothing);
      expect(find.text('2回目'), findsNothing);
    });

    testWidgets('最後の丸だけベルで、ほかは電話のアイコン', (tester) async {
      await _pumpRule(tester);

      expect(_flowIcons(tester), [
        AppIcons.phone,
        AppIcons.phone,
        AppIcons.phone,
        AppIcons.bell,
      ]);
      final bell = tester.widget<AppIcon>(
        find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.icon == AppIcons.bell,
        ),
      );
      expect(bell.color, AppColors.white);
      final circle = tester.widget<Container>(
        find
            .ancestor(of: find.byWidget(bell), matching: find.byType(Container))
            .first,
      );
      expect((circle.decoration! as BoxDecoration).color, AppColors.stateAlert);
    });

    testWidgets('通知の文字は 1 行に入るときは見た目も 1 行に並ぶ', (tester) async {
      await _pumpRule(tester);

      expect(find.text('家族に'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
    });

    testWidgets('3 回までは 1 段に並ぶ', (tester) async {
      await _pumpRule(tester);

      final phones = find.byWidgetPredicate(_isFlowCircle);
      final tops = phones.evaluate().map(
        (element) =>
            (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
      );
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets('3 回より多いときは 1回目、…、最後の回、家族に通知が 1 段に並ぶ', (tester) async {
      await _pumpRule(
        tester,
        rule: const RetryRule(interval: Duration(minutes: 15), attempts: 5),
      );

      expect(_flowLabels(tester), ['9:00 1回目', '10:00 5回目', '10:00 家族に通知']);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('2回目'), findsNothing);
      final tops = find
          .byWidgetPredicate(_isFlowCircle)
          .evaluate()
          .map(
            (element) => (element.renderObject! as RenderBox)
                .localToGlobal(Offset.zero)
                .dy,
          )
          .toList();
      expect(tops, hasLength(3));
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets('1 回のときは、かけた時刻と同じ文になる', (tester) async {
      await _pumpRule(tester);

      await _tapChip(tester, '1回');

      expect(find.text('9:00に1回かけて、出なければ9:00に家族に通知します。'), findsOneWidget);
    });
  });

  testWidgets('知らせる人は出ない', (tester) async {
    await _pumpRule(tester);

    expect(find.text('知らせる人'), findsNothing);
    expect(find.text('美咲(あなた)'), findsNothing);
    expect(find.text('健太(弟)'), findsNothing);
    expect(find.text('アプリに通知'), findsNothing);
  });

  group('保存と戻る', () {
    Future<void> openRule(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInAuth(),
            registeredWatchedPerson(),
            sampleHome(),
            sampleCalls(),
          ],
          child: const KazokuAiApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabBar),
          matching: find.text('予約電話'),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data?.endsWith('家族に通知') ?? false),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('このルールで保存'));
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('もどる'));
      await tester.pumpAndSettle();
    }

    testWidgets('保存すると 06 に戻り、行の文字が変わる', (tester) async {
      await openRule(tester);

      await _tapChip(tester, '5分');
      await _tapChip(tester, '2回');
      await save(tester);

      expect(find.byType(RetryRuleScreen), findsNothing);
      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.text('5分おきに2回かけて、家族に通知'), findsOneWidget);
    });

    testWidgets('入力した数も保存できる', (tester) async {
      await openRule(tester);

      await _tapCustom(tester, 0);
      await _typeInField(tester, 0, '90');
      await _tapCustom(tester, 1);
      await _typeInField(tester, 1, '4');
      await save(tester);

      expect(find.text('90分おきに4回かけて、家族に通知'), findsOneWidget);

      await openRule(tester);
      expect(_selectedLabels(tester), ['その他', 'その他']);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        '90',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
        '4',
      );
    });

    testWidgets('保存せずに戻ると変更は残らない', (tester) async {
      await openRule(tester);

      await _tapChip(tester, '5分');
      await _tapChip(tester, '1回');
      await back(tester);

      expect(find.byType(BookingScreen), findsOneWidget);
      expect(find.text('15分おきに3回かけて、家族に通知'), findsOneWidget);

      await openRule(tester);
      expect(_chip(tester, '15分').selected, isTrue);
      expect(_chip(tester, '3回').selected, isTrue);
    });

    testWidgets('保存したルールを次に開くと選ばれている', (tester) async {
      await openRule(tester);
      await _tapChip(tester, '30分');
      await _tapChip(tester, '2回');
      await save(tester);

      await openRule(tester);

      expect(_chip(tester, '30分').selected, isTrue);
      expect(_chip(tester, '2回').selected, isTrue);
      expect(_chip(tester, '15分').selected, isFalse);
    });

    testWidgets('保存せずに戻っても 1 度保存したルールは残る', (tester) async {
      await openRule(tester);
      await _tapChip(tester, '30分');
      await save(tester);

      await openRule(tester);
      await _tapChip(tester, '5分');
      await back(tester);

      expect(find.text('30分おきに3回かけて、家族に通知'), findsOneWidget);
    });
  });

  group('読み上げ', () {
    testWidgets('選んでいるチップは選択中として読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('15分')),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('30分')),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('流れの丸は時刻と名前を続けて読み、文字を別に読まない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      expect(find.bySemanticsLabel('9:30 家族に通知'), findsOneWidget);
      expect(find.bySemanticsLabel('家族に'), findsNothing);
      expect(find.bySemanticsLabel('9:00'), findsNothing);
      handle.dispose();
    });

    testWidgets('戻るボタンは「もどる」と読む', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      expect(find.bySemanticsLabel('もどる'), findsOneWidget);
      handle.dispose();
    });
  });
}

// 流れの丸は幅 36 の円の Container で作っている
bool _isFlowCircle(Widget widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration! as BoxDecoration).shape == BoxShape.circle;

List<AppIcons> _flowIcons(WidgetTester tester) {
  return tester
      .widgetList<AppIcon>(
        find.descendant(
          of: find.byWidgetPredicate(_isFlowCircle),
          matching: find.byType(AppIcon),
        ),
      )
      .map((icon) => icon.icon)
      .toList();
}
