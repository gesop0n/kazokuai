import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
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
    testWidgets('見出しとミニカレンダー', (tester) async {
      await _pumpMockCalls(tester);

      expect(tester.getTopLeft(find.text('通話記録')), const Offset(16, 62));
      expect(find.text('過去7日間'), findsOneWidget);
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

    testWidgets('日の見出しと行の高さ', (tester) async {
      await _pumpMockCalls(tester);

      double headingTop(String text) =>
          tester.getTopLeft(find.text(text)).dy - 8;

      // モックの流れる 04 は 212、330、526、644。
      // 04 と 04c は同じ固定部で、04c の下の余白 8 に合わせるので、04 は 4 だけ下になる。
      expect(headingTop('今日 11月5日(木)'), 216);
      expect(headingTop('11月4日(水)'), 334);
      expect(headingTop('11月3日(火)'), 530);
      expect(headingTop('11月2日(月)'), 648);
      expect(tester.getSize(_textCard('朝食と薬は済み。膝を気にしている')).height, 68);
      expect(tester.getSize(_textCard('朝食と薬は済み。膝を気にしている')).width, 281);
    });

    testWidgets('不在の行は 1 行に収まり、カードの高さは 48', (tester) async {
      await _pumpMockCalls(tester);

      final card = find.ancestor(
        of: find.text('電話に出ませんでした(3回かけました)'),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(card.first).decoration! as BoxDecoration;
      expect(tester.getSize(card.first).height, 48);
      expect(decoration.color, AppColors.stateAlertSoft);
      expect(
        decoration.border,
        Border.all(color: AppColors.stateAlert, width: 2),
      );
    });
  });

  group('04c の位置がモックと同じ', () {
    // 11月3日の見出しは一覧の先頭から 314、タイトルは 40。
    // 04c はその見出しが固定部の下端から 34 の位置なので、320 動かす
    const offset = 320.0;

    testWidgets('固定部は y=54 から高さ 122 で、影が出る', (tester) async {
      await _pumpMockCalls(tester);

      await scrollCallsTo(tester, offset);

      final pinned = find
          .ancestor(
            of: find.byType(MiniCalendar),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getRect(pinned), const Rect.fromLTWH(0, 54, 393, 122));
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

      expect(tester.getTopLeft(find.text('11月3日(火)')).dy - 8, 210);
      expect(tester.getTopLeft(find.text('11月2日(月)')).dy - 8, 328);
      expect(tester.getTopLeft(find.text('11月1日(日)')).dy - 8, 426);
      expect(tester.getTopLeft(find.text('10月31日(土)')).dy - 8, 544);
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
      expect(pinnedHeight, greaterThanOrEqualTo(122));

      await scrollCallsTo(tester, callsPosition(tester).maxScrollExtent);

      expect(
        tester.getTopLeft(find.text('10月31日(土)')).dy - 8,
        moreOrLessEquals(pinnedHeight, epsilon: 1),
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

      expect(tester.getTopLeft(find.text('通話時間')).dy, 106 + 1 + 16);
    });

    testWidgets('カードの高さはモックの 241 より 18 高い 259', (tester) async {
      await pumpDetail(tester);

      // 時刻の行は 33 から 44 に、ボタンは 32 から 44 にしたぶん高い
      final card = find
          .ancestor(of: find.text('通話時間'), matching: find.byType(Container))
          .last;
      expect(tester.getSize(card).height, 259);
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
