import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/ask/voice_setting.dart';

import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

List<bool> _selected(WidgetTester tester, Finder setting) => tester
    .widgetList<AppChip>(
      find.descendant(of: setting, matching: find.byType(AppChip)),
    )
    .map((chip) => chip.selected)
    .toList();

Finder _setting(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(VoiceSetting));

Finder _sliderOf(String label) =>
    find.descendant(of: _setting(label), matching: find.byType(Slider));

double _sliderValue(WidgetTester tester, String label) =>
    tester.widget<Slider>(_sliderOf(label)).value;

// 読み上げの木からスライダーの節を集める
List<SemanticsData> _sliderSemantics(WidgetTester tester) {
  final found = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isSlider) {
      found.add(data);
    }
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

void main() {
  group('初期状態', () {
    testEachLayout('どちらもカスタマイズで、35 と 70 のスライダーが出る', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      expect(find.text('話し方'), findsOneWidget);
      expect(_selected(tester, _setting('はやさ')), [false, false, true]);
      expect(_selected(tester, _setting('ボリューム')), [false, false, true]);
      expect(_sliderValue(tester, 'はやさ'), 35);
      expect(_sliderValue(tester, 'ボリューム'), 70);
    });

    testWidgets('文言はモックのとおり', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      for (final text in ['ゆっくり', 'おおきい', 'おそい', 'はやい', '小さい', '大きい']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('ふつう'), findsNWidgets(2));
      expect(find.text('カスタマイズ'), findsNWidgets(2));
    });

    testWidgets('チップは AppChip の小さい方', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      expect(
        tester
            .widgetList<AppChip>(find.byType(AppChip))
            .map((chip) => chip.size)
            .toSet(),
        {AppChipSize.s},
      );
    });
  });

  group('選ぶ', () {
    testEachLayout('カスタマイズのときだけスライダーが出て、ほかの項目には影響しない', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      await tester.tap(find.widgetWithText(AppChip, 'ふつう').first);
      await tester.pump();

      expect(_selected(tester, _setting('はやさ')), [true, false, false]);
      expect(_sliderOf('はやさ'), findsNothing);
      expect(_selected(tester, _setting('ボリューム')), [false, false, true]);
      expect(_sliderOf('ボリューム'), findsOneWidget);
      expect(find.text('おそい'), findsNothing);
      expect(find.text('はやい'), findsNothing);

      await tester.tap(find.widgetWithText(AppChip, 'おおきい'));
      await tester.pump();

      expect(_selected(tester, _setting('ボリューム')), [false, true, false]);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('カスタマイズに戻すと前の値のスライダーが出る', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      await tester.drag(_sliderOf('はやさ'), const Offset(60, 0));
      await tester.pump();
      final moved = _sliderValue(tester, 'はやさ');
      expect(moved, isNot(35));

      await tester.tap(_chipFinder('ゆっくり'));
      await tester.pump();
      expect(_sliderOf('はやさ'), findsNothing);

      await tester.tap(find.widgetWithText(AppChip, 'カスタマイズ').first);
      await tester.pump();

      expect(_sliderValue(tester, 'はやさ'), moved);
    });

    testWidgets('スライダーを動かすと、その項目だけ値が変わる', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      await tester.drag(_sliderOf('ボリューム'), const Offset(-40, 0));
      await tester.pump();

      expect(_sliderValue(tester, 'はやさ'), 35);
      expect(_sliderValue(tester, 'ボリューム'), lessThan(70));
    });

    testWidgets('スライダーの線を押すと、その位置に動く', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      final slider = tester.getRect(_sliderOf('はやさ'));
      await tester.tapAt(slider.centerLeft + Offset(slider.width * 0.8, 0));
      await tester.pump();

      expect(_sliderValue(tester, 'はやさ'), closeTo(80, 1));
    });

    testEachLayout('スライダーの上下の端も押せる', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      final slider = tester.getRect(_sliderOf('はやさ'));
      await tester.tapAt(slider.topCenter + const Offset(0, 1));
      await tester.pump();
      expect(_sliderValue(tester, 'はやさ'), closeTo(50, 1));
    });
  });

  group('押せる領域', () {
    testEachLayout('スライダーとチップは 44pt 以上', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        final size = tester.getSize(find.byWidget(slider));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      final chips = find.byType(AppChip);
      for (var i = 0; i < chips.evaluate().length; i++) {
        final size = tester.getSize(chips.at(i));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
    });
  });

  group('レイアウト', () {
    testEachLayout('2 つの項目でチップとスライダーの左端が揃い、右端は余白の内側', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      final first = tester.getTopLeft(find.widgetWithText(AppChip, 'ゆっくり'));
      final second = tester.getTopLeft(find.widgetWithText(AppChip, 'おおきい'));
      expect(first.dx, second.dx);

      expect(
        tester.getTopLeft(find.text('おそい')).dx,
        tester.getTopLeft(_chipFinder('ふつう')).dx,
      );
      expect(
        tester.getTopLeft(find.text('小さい')).dx,
        tester.getTopLeft(_chipFinder('ふつう')).dx,
      );
      expect(tester.getTopRight(find.text('はやい')).dx, layout.width - 16);
      expect(tester.getTopRight(find.text('大きい')).dx, layout.width - 16);
    });

    testEachLayout('丸を端まで動かしても、両端の文字に重ならない', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      final slider = tester.getRect(_sliderOf('はやさ'));
      const thumbRadius = 10;
      expect(
        slider.left - tester.getTopRight(find.text('おそい')).dx,
        greaterThanOrEqualTo(thumbRadius),
      );
      expect(
        tester.getTopLeft(find.text('はやい')).dx - slider.right,
        greaterThanOrEqualTo(thumbRadius),
      );
    });

    testEachLayout('ラベルは 1 行に収まる幅がある', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      expect(
        tester.getSize(find.text('ボリューム')).height,
        tester.getSize(find.text('はやさ')).height,
      );
    });

    testWidgets('話し方の見出しからチップまで、見た目の間隔はモックの 8', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      // 部品の高さ 44 のうち、見た目の面は上下 6 の内側
      final chipSurfaceTop = tester.getTopLeft(_chipFinder('ふつう')).dy + 6;
      expect(chipSurfaceTop - tester.getBottomLeft(find.text('話し方')).dy, 8);
    });
  });

  group('スライダーの見た目', () {
    Future<RenderObject> pumpSlider(WidgetTester tester) async {
      await pumpInLayout(
        tester,
        _standardLayout,
        const VoiceSetting(
          label: 'はやさ',
          alternativeLabel: 'ゆっくり',
          minLabel: 'おそい',
          maxLabel: 'はやい',
          initialValue: 35,
        ),
      );
      return tester.renderObject(find.byType(Slider));
    }

    testWidgets('線は太さ 4 で、丸の中心までが濃く、線は部品の幅いっぱい', (tester) async {
      final slider = await pumpSlider(tester);
      final size = tester.getSize(find.byType(Slider));

      // 両端を丸めた線を 2 本、丸の下で重ねて描く。上下とも 20 から 24 で、濃い線も太くならない
      final thumbX = size.width * .35;
      const radius = Radius.circular(2);
      expect(
        slider,
        paints
          ..rrect(
            rrect: RRect.fromLTRBR(thumbX - 2, 20, size.width, 24, radius),
            color: AppColors.lineStrong,
          )
          ..rrect(
            rrect: RRect.fromLTRBR(0, 20, thumbX + 2, 24, radius),
            color: AppColors.inkPrimary,
          ),
      );
    });

    testWidgets('丸は直径 20、枠 2 で、線の中央に乗る', (tester) async {
      final slider = await pumpSlider(tester);
      final size = tester.getSize(find.byType(Slider));

      expect(
        slider,
        paints
          ..circle(
            x: size.width * .35,
            y: 22,
            radius: 10,
            color: AppColors.paperRaised,
          )
          ..circle(
            x: size.width * .35,
            y: 22,
            radius: 9,
            color: AppColors.inkPrimary,
            style: PaintingStyle.stroke,
            strokeWidth: 2,
          ),
      );
    });

    testWidgets('押しても波紋は出ない', (tester) async {
      final slider = await pumpSlider(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await tester.pumpAndSettle();

      // 押している間も、円は丸の 2 つだけ
      var circles = 0;
      expect(
        slider,
        paints..everything((method, arguments) {
          if (method == #drawCircle) circles++;
          return true;
        }),
      );
      expect(circles, 2);
      await gesture.up();
    });
  });

  group('読み上げ', () {
    testEachLayout('スライダーはモックの aria-label と値で読む', (tester, layout) async {
      await pumpScreenInLayout(tester, layout, const AskScreen());

      final sliders = _sliderSemantics(tester);
      expect(sliders.map((data) => data.label), ['はやさ', 'ボリューム']);
      expect(sliders.map((data) => data.value), ['35', '70']);
    });

    testWidgets('動かす操作ができて、値が 0 から 100 で読まれる', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      final data = _sliderSemantics(tester).first;
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(int.parse(data.increasedValue), greaterThan(35));
      expect(int.parse(data.decreasedValue), lessThan(35));
    });

    testWidgets('端の文字は読み上げない', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      for (final text in ['おそい', 'はやい', '小さい', '大きい']) {
        expect(find.bySemanticsLabel(text), findsNothing, reason: text);
      }
    });

    testWidgets('チップは選択の状態を読む', (tester) async {
      await pumpScreenInLayout(tester, _standardLayout, const AskScreen());

      final chip = find.descendant(
        of: find.widgetWithText(AppChip, 'カスタマイズ').first,
        matching: find.byType(InkWell),
      );
      expect(
        tester.getSemantics(chip),
        isSemantics(
          label: 'カスタマイズ',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    });
  });
}

Finder _chipFinder(String label) => find.widgetWithText(AppChip, label).first;
