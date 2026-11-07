import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

// モックと同じ画面。下の安全領域が 34 なので、タブバーは tabH と同じ 98 になる
void useMockScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 54 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

// 本物のアプリを起動して、通話記録タブを開く
Future<void> pumpCallsTab(WidgetTester tester) async {
  useMockScreen(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [signedInAuth(), registeredWatchedPerson()],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text('通話記録')),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpCallsScreen(WidgetTester tester, LayoutCase layout) async {
  await pumpScreenInLayout(tester, layout, const Scaffold(body: CallsScreen()));
  await tester.pumpAndSettle();
}

// 条件のチップも横に動くので、一番外側の Scrollable を選ぶ
ScrollPosition callsPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CallsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> scrollCallsTo(WidgetTester tester, double offset) async {
  callsPosition(tester).jumpTo(offset);
  await tester.pumpAndSettle();
}

Finder filterChip(String label) => find.widgetWithText(AppChip, label);

// 幅が狭いと右のチップは画面の外にあるので、チップの列だけを動かしてから押す。
// tester.ensureVisible は外側の一覧まで動かしてしまう。
Future<void> tapFilter(WidgetTester tester, String label) async {
  final chip = filterChip(label);
  final row = tester
      .state<ScrollableState>(
        find.ancestor(of: chip, matching: find.byType(Scrollable)).first,
      )
      .position;
  final screenWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  if (tester.getTopRight(chip).dx > screenWidth) {
    row.jumpTo(row.maxScrollExtent);
  } else if (tester.getTopLeft(chip).dx < 0) {
    row.jumpTo(0);
  }
  await tester.pump();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Finder get miniCalendarSemantics => find.bySemanticsLabel('カレンダーを開いて日付を選ぶ');

// ミニカレンダーで選ばれている日。読み上げの value と同じ
String? miniSelection(WidgetTester tester) =>
    tester.getSemantics(miniCalendarSemantics).value;

Future<void> openCalendar(WidgetTester tester) async {
  await tester.tap(miniCalendarSemantics);
  await tester.pumpAndSettle();
}

Future<void> tapSemantics(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

// 高さと baseline は文字の幅とフォントの値で変わるので、同梱のフォントを読み込んで測る。
// 読み込んだフォントは呼んだテストファイルにだけ効く。
Future<void> loadBundledFonts() async {
  const families = {
    'BIZUDPGothic': ['BIZUDPGothic-Regular', 'BIZUDPGothic-Bold'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}
