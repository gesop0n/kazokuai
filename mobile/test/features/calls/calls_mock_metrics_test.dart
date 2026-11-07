import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/features/calls/calendar_sheet.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/mini_calendar.dart';

import '../../support/layout_matrix.dart';
import 'calls_harness.dart';

// docs/mock/ui.html を headless Chrome で開いて測った値。画面は幅 393 で、上の安全領域は 54。
void _useMockViewport(WidgetTester tester) {
  tester.view.padding = const FakeViewPadding(top: 54);
  addTearDown(tester.view.resetPadding);
}

const _mockLayout = LayoutCase(393, 1.0);

Future<void> _pumpMockCalls(WidgetTester tester) async {
  _useMockViewport(tester);
  await pumpCallsScreen(tester, _mockLayout);
}

Finder _textCard(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

void main() {
  setUpAll(loadBundledFonts);

  group('04 の位置がモックと同じ', () {
    testWidgets('見出し、ミニカレンダー、チップ', (tester) async {
      await _pumpMockCalls(tester);

      expect(tester.getTopLeft(find.text('通話記録')), const Offset(16, 62));
      final mini = find.byType(MiniCalendar);
      expect(tester.getRect(mini), const Rect.fromLTWH(16, 102, 361, 106));
      expect(
        tester.getTopLeft(
          find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5))),
        ),
        const Offset(319, 139),
      );
      expect(
        tester.getSize(find.byKey(MiniCalendar.dayKey(DateTime(2026, 11, 5)))),
        const Size(49, 60),
      );
    });

    testWidgets('チップの幅と位置', (tester) async {
      await _pumpMockCalls(tester);

      // 押せる領域の余白が上下に 4 ずつあるので、モックの見た目より 4 上から始まる
      expect(tester.getTopLeft(filterChip('全部')), const Offset(16, 212));
      expect(tester.getSize(filterChip('全部')).height, 44);
      expect(
        tester.getSize(filterChip('全部')).width,
        moreOrLessEquals(62.56, epsilon: 1),
      );
      expect(
        tester.getSize(filterChip('話し相手')).width,
        moreOrLessEquals(91.13, epsilon: 1),
      );
      expect(
        tester.getTopLeft(filterChip('不在')).dx,
        moreOrLessEquals(355.38, epsilon: 2),
      );
    });

    testWidgets('日の見出しと行の高さ', (tester) async {
      await _pumpMockCalls(tester);

      double headingTop(String text) =>
          tester.getTopLeft(find.text(text)).dy - 8;

      expect(headingTop('今日 11月5日(木)'), 260);
      expect(headingTop('11月4日(水)'), 378);
      expect(headingTop('11月3日(火)'), 574);
      expect(headingTop('11月2日(月)'), 692);
      expect(tester.getSize(_textCard('朝食と薬は済み。膝を気にしている')).height, 68);
      expect(tester.getSize(_textCard('朝食と薬は済み。膝を気にしている')).width, 281);
    });

    testWidgets('不在の行は 1 行に収まり、カードの高さは 46', (tester) async {
      await _pumpMockCalls(tester);

      final card = find.ancestor(
        of: find.text('電話に出ませんでした(3回かけました)'),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(card.first).decoration! as BoxDecoration;
      expect(tester.getSize(card.first).height, 46);
      expect(decoration.color, AppColors.stateAlertSoft);
      expect(
        decoration.border,
        Border.all(color: AppColors.stateAlert, width: 2),
      );
    });

    testWidgets('幅 393 では「不在」のチップが端で切れる(モックと同じ)', (tester) async {
      await _pumpMockCalls(tester);

      expect(tester.getTopRight(filterChip('不在')).dx, greaterThan(393));
    });

    testWidgets('幅 440 では全部のチップが収まる', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(440, 1.0));

      expect(tester.getTopRight(filterChip('不在')).dx, lessThanOrEqualTo(440));
    });
  });

  group('04c の位置がモックと同じ', () {
    // 04c の 12:00 の行は y=176 にある。04 では 496 なので、見出しの分と合わせて 320 動かす
    const offset = 320.0;

    testWidgets('固定部は y=54 から高さ 166 で、影が出る', (tester) async {
      await _pumpMockCalls(tester);

      await scrollCallsTo(tester, offset);

      final pinned = find
          .ancestor(
            of: find.byType(MiniCalendar),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getRect(pinned), const Rect.fromLTWH(0, 54, 393, 166));
      expect(
        tester.getRect(find.byType(MiniCalendar)),
        const Rect.fromLTWH(16, 62, 361, 106),
      );
      expect(
        (tester.widget<Container>(pinned).decoration! as BoxDecoration)
            .boxShadow,
        isNotNull,
      );
    });

    testWidgets('一覧の位置と選んでいる日', (tester) async {
      await _pumpMockCalls(tester);

      await scrollCallsTo(tester, offset);

      expect(tester.getTopLeft(find.text('11月3日(火)')).dy - 8, 254);
      expect(tester.getTopLeft(find.text('11月2日(月)')).dy - 8, 372);
      expect(tester.getTopLeft(find.text('11月1日(日)')).dy - 8, 468);
      expect(tester.getTopLeft(find.text('10月31日(土)')).dy - 8, 586);
      expect(miniSelection(tester), '11月3日');
    });

    testWidgets('見出しが固定部の下端から 40 に入るまでは前の日を選ぶ', (tester) async {
      await _pumpMockCalls(tester);

      // 11月3日の見出しは一覧の先頭から 314
      await scrollCallsTo(tester, 40 + 314 - 40);
      expect(miniSelection(tester), '11月3日');

      await scrollCallsTo(tester, 40 + 314 - 41);
      expect(miniSelection(tester), '11月4日');
    });
  });

  group('04b の高さがモックと同じ', () {
    testWidgets('シートは 482 で、ボタンは幅 361、高さ 56', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpCallsScreen(tester, _mockLayout);

      await openCalendar(tester);

      expect(tester.getSize(find.byType(CalendarSheet)), const Size(393, 482));
      expect(tester.getTopLeft(find.byType(CalendarSheet)).dy, 852 - 482);
      expect(
        tester.getRect(find.widgetWithText(InkWell, '11月5日の記録を見る')),
        const Rect.fromLTWH(16, 762, 361, 56),
      );
    });

    testWidgets('日のマスは 1 行目が y=468 で、行の間隔は 52', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpCallsScreen(tester, _mockLayout);

      await openCalendar(tester);

      final first = tester.getRect(find.bySemanticsLabel('11月1日、電話に出た'));
      final eighth = tester.getRect(find.bySemanticsLabel('11月8日'));
      expect(first.top, 468);
      expect(first.height, 50);
      expect(first.width, moreOrLessEquals(51.57, epsilon: .1));
      expect(eighth.top - first.top, 52);
    });
  });

  group('文字倍率 1.3 の固定部', () {
    testWidgets('19:00 は折り返さない', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(360, 1.3));

      final time = tester.renderObject<RenderBox>(find.text('19:00'));
      expect(
        time.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(time.size.width),
      );
    });

    testWidgets('最小の高さを超える分だけ高くなり、最後の日まで動かせる', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(360, 1.3));

      final pinned = find
          .ancestor(
            of: find.byType(MiniCalendar),
            matching: find.byType(Container),
          )
          .first;
      final pinnedHeight = tester.getSize(pinned).height;
      expect(pinnedHeight, greaterThanOrEqualTo(166));

      await scrollCallsTo(tester, callsPosition(tester).maxScrollExtent);

      expect(
        tester.getTopLeft(find.text('10月31日(土)')).dy - 8,
        moreOrLessEquals(pinnedHeight, epsilon: 1),
      );
    });

    testWidgets('チップは押せる領域も含めて 44 以上', (tester) async {
      await pumpCallsScreen(tester, const LayoutCase(360, 1.3));

      expect(
        tester.getSize(find.byType(AppChip).first).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('05', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      _useMockViewport(tester);
      await pumpScreenInLayout(tester, _mockLayout, const CallDetailScreen());
      await tester.pumpAndSettle();
    }

    testWidgets('カードは y=106 から始まる', (tester) async {
      await pumpDetail(tester);

      expect(tester.getTopLeft(find.text('詳細なまとめ')).dy, 106 + 1 + 16);
    });

    testWidgets('カードの高さはモックの 265 より 18 高い 283', (tester) async {
      await pumpDetail(tester);

      // 時刻の行は 33 から 44 に、ボタンは 32 から 44 にしたぶん高い
      final card = find
          .ancestor(of: find.text('詳細なまとめ'), matching: find.byType(Container))
          .last;
      expect(tester.getSize(card).height, 283);
    });

    testWidgets('まとめの時刻と文字は baseline が揃う', (tester) async {
      await pumpDetail(tester);

      double baselineOf(Finder finder) {
        final paragraph = tester.renderObject<RenderBox>(finder);
        final baseline = paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        )!;
        return paragraph.localToGlobal(Offset(0, baseline)).dy;
      }

      expect(
        baselineOf(find.text('朝ごはんを食べ、よく眠れたそうです')),
        moreOrLessEquals(baselineOf(find.text('0:11').first), epsilon: .01),
      );
    });

    testWidgets('発言の列はモックと同じ位置', (tester) async {
      await pumpDetail(tester);

      expect(tester.getTopLeft(find.text('0:00')).dx, 16);
      expect(tester.getTopLeft(find.text('AIヘルパー').first).dx, 16 + 40 + 8);
    });
  });
}
