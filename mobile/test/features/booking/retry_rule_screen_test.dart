import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';

import '../../support/fake_auth_repository.dart';
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

// 間隔の「入力」が 0、回数の「入力」が 1。欄は開いている順に並ぶ
Future<void> _tapCustom(WidgetTester tester, int index) async {
  await tester.tap(find.widgetWithText(AppChip, '入力').at(index));
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

          await tester.ensureVisible(find.text('知らせる人'));
          await tester.pumpAndSettle();

          expect(find.text('このルールで保存'), findsOneWidget);
        });
      }
    }

    testEachLayout('60分おきに5回', (tester, layout) async {
      await _pumpRule(
        tester,
        layout: layout,
        rule: const RetryRule(interval: Duration(minutes: 60), attempts: 5),
      );

      await tester.ensureVisible(find.text('知らせる人'));
      await tester.pumpAndSettle();

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
    testWidgets('選択肢が並び、初期値は 10 分と 3 回', (tester) async {
      await _pumpRule(tester);

      for (final label in ['5分', '10分', '30分', '1回', '2回', '3回']) {
        expect(find.widgetWithText(AppChip, label), findsOneWidget);
      }
      expect(find.widgetWithText(AppChip, '入力'), findsNWidgets(2));
      expect(find.text('15分'), findsNothing);
      expect(find.text('1時間'), findsNothing);
      expect(find.text('5回'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(_selectedLabels(tester), ['10分', '3回']);
    });

    testWidgets('押すとそのチップだけが選ばれる', (tester) async {
      await _pumpRule(tester);

      await _tapChip(tester, '30分');
      await _tapChip(tester, '1回');

      expect(_chip(tester, '30分').selected, isTrue);
      expect(_chip(tester, '10分').selected, isFalse);
      expect(_chip(tester, '1回').selected, isTrue);
      expect(_chip(tester, '3回').selected, isFalse);
    });
  });

  group('入力', () {
    testWidgets('間隔は分の欄で、1〜60 なら保存でき、空と範囲の外はできない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);

      expect(find.text('分'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('分')).dy,
        greaterThan(
          tester.getBottomLeft(find.widgetWithText(AppChip, '30分')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('分')).dy,
        lessThan(tester.getTopLeft(find.text('かける回数(最初の1回をふくむ)')).dy),
      );
      expect(_selectedLabels(tester), ['入力', '3回']);
      _expectCanSave(tester, false);

      await _typeInField(tester, 0, '0');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '61');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '1');
      _expectCanSave(tester, true);
      await _typeInField(tester, 0, '60');
      _expectCanSave(tester, true);
      handle.dispose();
    });

    testWidgets('回数は回の欄で、1〜5 なら保存でき、空と範囲の外はできない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 1);

      expect(find.text('回'), findsOneWidget);
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
      expect(_selectedLabels(tester), ['10分', '入力']);
      _expectCanSave(tester, false);

      await _typeInField(tester, 0, '0');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '6');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '');
      _expectCanSave(tester, false);
      await _typeInField(tester, 0, '1');
      _expectCanSave(tester, true);
      await _typeInField(tester, 0, '5');
      _expectCanSave(tester, true);
      handle.dispose();
    });

    testWidgets('どちらかが範囲の外なら保存できない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRule(tester);

      await _tapCustom(tester, 0);
      await _typeInField(tester, 0, '7');
      await _tapCustom(tester, 1);
      await _typeInField(tester, 1, '6');
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
      await _typeInField(tester, 0, '60');
      await _tapCustom(tester, 1);
      await _typeInField(tester, 1, '5');

      expect(_flowLabels(tester), [
        '9:00 1回目',
        '10:00 2回目',
        '11:00 3回目',
        '12:00 4回目',
        '13:00 5回目',
        '13:00 家族に通知',
      ]);
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
        '9:10 2回目',
        '9:20 3回目',
        '9:20 家族に通知',
      ]);
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
      expect(find.text('9:10'), findsOneWidget);
      expect(find.text('9:20'), findsNWidgets(2));
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

    testWidgets('5 回のときは 3 つずつ 2 段に分ける', (tester) async {
      await _pumpRule(
        tester,
        rule: const RetryRule(interval: Duration(minutes: 10), attempts: 5),
      );

      final tops = find
          .byWidgetPredicate(_isFlowCircle)
          .evaluate()
          .map(
            (element) => (element.renderObject! as RenderBox)
                .localToGlobal(Offset.zero)
                .dy,
          )
          .toList();
      expect(tops, hasLength(6));
      expect(tops[0], tops[2]);
      expect(tops[3], tops[5]);
      expect(tops[3], greaterThan(tops[0]));
    });
  });

  testWidgets('知らせる人はモックのとおり', (tester) async {
    await _pumpRule(tester);

    expect(find.text('知らせる人'), findsOneWidget);
    expect(find.text('美咲(あなた)'), findsOneWidget);
    expect(find.text('健太(弟)'), findsOneWidget);
    expect(find.text('アプリに通知'), findsNWidgets(2));
  });

  group('保存と戻る', () {
    Future<void> openRule(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signedInAuth(), registeredWatchedPerson(), sampleHome()],
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
      await _typeInField(tester, 0, '45');
      await _tapCustom(tester, 1);
      await _typeInField(tester, 1, '4');
      await save(tester);

      expect(find.text('45分おきに4回かけて、家族に通知'), findsOneWidget);

      await openRule(tester);
      expect(_selectedLabels(tester), ['入力', '入力']);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        '45',
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
      expect(find.text('10分おきに3回かけて、家族に通知'), findsOneWidget);

      await openRule(tester);
      expect(_chip(tester, '10分').selected, isTrue);
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
      expect(_chip(tester, '10分').selected, isFalse);
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
        tester.getSemantics(find.bySemanticsLabel('10分')),
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

      expect(find.bySemanticsLabel('9:20 家族に通知'), findsOneWidget);
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
