import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/tutorial_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/calls/mini_calendar.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/tutorial/tutorial_anchor.dart';
import 'package:kazokuai/features/tutorial/tutorial_overlay.dart';
import 'package:kazokuai/features/tutorial/tutorial_step.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_calls_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_tutorial_repository.dart';
import '../../support/fake_watched_person_repository.dart';

// モックと同じ 393×852。下の安全領域が 34 なので、タブバーの高さもモックと揃う
void _usePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 54 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeTutorialRepository tutorial,
  HomeRepository? home,
  CallsRepository? calls,
}) async {
  _usePhone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuth(),
        registeredWatchedPerson(),
        if (home == null)
          sampleHome()
        else
          homeRepositoryProvider.overrideWithValue(home),
        if (calls == null)
          sampleCalls()
        else
          callsRepositoryProvider.overrideWithValue(calls),
        tutorialRepositoryProvider.overrideWithValue(tutorial),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectHoleContains(WidgetTester tester, Finder target) {
  expect(target, findsOneWidget);
  expect(find.byType(TutorialHole), findsOneWidget);
  final hole = tester.getRect(find.byType(TutorialHole));
  final rect = tester.getRect(target);
  expect(hole.contains(rect.center), isTrue);
  expect(hole.left, lessThanOrEqualTo(rect.left + 1));
  expect(hole.top, lessThanOrEqualTo(rect.top + 1));
  expect(hole.right, greaterThanOrEqualTo(rect.right - 1));
  expect(hole.bottom, greaterThanOrEqualTo(rect.bottom - 1));
  // 画面全体を明るくしない。端の部品は、6 の余白が画面の外にはみ出す
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(
    hole.width < screen.width - 1 || hole.height < screen.height - 1,
    isTrue,
  );
}

Future<void> _openHome(WidgetTester tester) async {
  if (find.byType(HomeScreen).evaluate().isNotEmpty) return;
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text('ホーム')),
  );
  await tester.pumpAndSettle();
}

Rect _glyphRect(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      )
      .first
      .toRect();
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), box);
}

void _expectTipLooksLikeMock(WidgetTester tester) {
  final overlay = find.byType(TutorialOverlay);

  void expectStyle(
    String text, {
    required Color color,
    required double fontSize,
  }) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: overlay, matching: find.text(text)),
    );
    final style = (paragraph.text as TextSpan).style!;
    expect(style.color, color);
    expect(style.decoration, TextDecoration.none);
    expect(style.fontFamily, 'BIZUDPGothic');
    expect(style.fontSize, fontSize);
  }

  expectStyle('使い方 1/9', color: AppColors.inkSecondary, fontSize: 12);
  expectStyle('直近の電話', color: AppColors.inkPrimary, fontSize: 18);
  expectStyle(
    'AIがハナさんにかけた電話の内容を短くまとめてここに届けます。「会話を見る」で全文も読めます。',
    color: AppColors.inkSecondary,
    fontSize: 15,
  );

  final bars = find.descendant(
    of: find.bySemanticsLabel('9段階のうち1段階目'),
    matching: find.byType(DecoratedBox),
  );
  expect(bars, findsNWidgets(9));
  final colors = <Color?>[];
  for (final element in bars.evaluate()) {
    expect(tester.getSize(find.byWidget(element.widget)).height, 4);
    colors.add(
      ((element.widget as DecoratedBox).decoration as BoxDecoration).color,
    );
  }
  expect(colors.where((color) => color == AppColors.inkPrimary), hasLength(1));
  expect(colors.where((color) => color == AppColors.lineStrong), hasLength(8));

  final next = find.text('次へ');
  final nextButton = find.ancestor(
    of: next,
    matching: find.byType(AppPressable),
  );
  expect(
    _glyphRect(tester, next).center.dy,
    closeTo(tester.getRect(nextButton).center.dy, 1),
  );

  final skip = find.text('スキップ');
  final skipGlyphs = _glyphRect(tester, skip);
  final underline = find.ancestor(
    of: skip,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.border?.bottom.color == AppColors.inkSecondary;
    }),
  );
  final line = tester.getRect(underline);
  expect(line.bottom, greaterThan(skipGlyphs.bottom - 1));
  expect(line.bottom, lessThan(skipGlyphs.bottom + 8));
  expect(
    skipGlyphs.center.dy,
    closeTo(
      tester
          .getRect(find.ancestor(of: skip, matching: find.byType(AppPressable)))
          .center
          .dy,
      1,
    ),
  );
}

void _expectHoleFits(WidgetTester tester, Finder target) {
  _expectHoleContains(tester, target);
  final hole = tester.getRect(find.byType(TutorialHole));
  final rect = tester.getRect(target);
  expect(hole.left, closeTo(rect.left - 6, 2));
  expect(hole.top, closeTo(rect.top - 6, 2));
  expect(hole.width, closeTo(rect.width + 12, 3));
  expect(hole.height, closeTo(rect.height + 12, 3));
}

void main() {
  testWidgets('見終わっていなければ T1 から T9 まで案内し、見たと記録する', (tester) async {
    final tutorial = FakeTutorialRepository();
    await _pump(tester, tutorial: tutorial);
    _expectTipLooksLikeMock(tester);

    const steps = [
      (
        progress: '使い方 1/9',
        body: 'AIがハナさんにかけた電話の内容を短くまとめてここに届けます。「会話を見る」で全文も読めます。',
        next: '次へ',
        tight: true,
      ),
      (
        progress: '使い方 2/9',
        body: '伝えたいことを入力するとAIが電話でハナさんに伝えます。日時を決めて予約もできます。',
        next: '次へ',
        tight: true,
      ),
      (
        progress: '使い方 3/9',
        body: '食事、睡眠、体調の3つをハナさんの言葉と一緒にまとめます。気になる話には印が付きます。下には7日間の様子も出ます。',
        next: '次へ',
        tight: true,
      ),
      (
        progress: '使い方 4/9',
        body: '「過去7日間」は横にスクロールすると前の日も見られます。電話に出た日は点、出なかった日は×で示します。押すとカレンダーが開き、もっと前の日付も選べます。',
        next: '次へ',
        tight: true,
      ),
      (
        progress: '使い方 5/9',
        body:
            '電話ごとに話した内容を一言でまとめ、話題の種類と通話時間を並べます。出なかった電話も残します。記録を押すと詳しい内容が開きます。',
        next: '次へ',
        tight: false,
      ),
      (
        progress: '使い方 6/9',
        body: '上のAIのまとめを押すと、その時刻の会話の全文を下に表示します。',
        next: '次へ',
        tight: false,
      ),
      (
        progress: '使い方 7/9',
        body: '決まった時間にかける予定を並べます。押すと、伝える内容と日時を変えられます。「今すぐ通話」もできます。',
        next: '次へ',
        tight: false,
      ),
      (
        progress: '使い方 8/9',
        body: '「AIに伝えてもらう」と同じ画面で、伝えたいことと日時を決めて予約します。',
        next: '次へ',
        tight: false,
      ),
      (
        progress: '使い方 9/9',
        body: 'ハナさんが電話に出ないとき、何分おきに何回かけなおすかを決めます。それでも出ないときは、家族に通知が届きます。',
        next: 'はじめる',
        tight: false,
      ),
    ];
    final targets = [
      find.byType(RecentCallCard),
      find.byType(AskCard),
      find.byType(TodayCard),
      find.byType(MiniCalendar),
      find.text('朝食と薬は済み。膝を気にしている'),
      find.text('通話時間'),
      find.text('予約している電話'),
      find.text('新しい予約'),
      find.text('かけなおしのルール'),
    ];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      expect(find.text(step.progress), findsOneWidget);
      expect(find.text(step.body), findsOneWidget);
      expect(find.text('スキップ'), findsOneWidget);
      expect(find.text(step.next), findsOneWidget);
      if (step.tight) {
        _expectHoleFits(tester, targets[i]);
      } else {
        _expectHoleContains(tester, targets[i]);
      }
      if (i == 3) expect(tutorial.markCount, 0);
      await tester.tap(find.text(step.next));
      await tester.pumpAndSettle();
    }

    expect(tutorial.markCount, 1);
    expect(tutorial.seen.value, isTrue);
    expect(find.text('使い方 9/9'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CallDetailScreen), findsNothing);

    await tester.tap(
      find.descendant(of: find.byType(AppTabBar), matching: find.text('通話記録')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(CallDetailScreen), findsNothing);
    expect(find.text('朝の電話'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, tutorial: tutorial);
    await _openHome(tester);
    expect(find.text('使い方 1/9'), findsNothing);

    // 前のアプリの State を残すと、別の家族の記録を読まない
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, tutorial: FakeTutorialRepository());
    await _openHome(tester);
    expect(find.text('使い方 1/9'), findsOneWidget);
  });

  testWidgets('どの段階でもスキップすると終わり、ホームに戻る', (tester) async {
    final tutorial = FakeTutorialRepository();
    await _pump(tester, tutorial: tutorial);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
    }
    expect(find.text('使い方 4/9'), findsOneWidget);
    expect(find.text('通話記録 日付を選ぶ'), findsOneWidget);
    expect(find.byType(CallsScreen), findsOneWidget);

    await tester.tap(find.text('スキップ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('使い方'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CallsScreen), findsNothing);
    expect(tutorial.markCount, 1);
    expect(tutorial.seen.value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, tutorial: tutorial);
    expect(find.text('使い方 1/9'), findsNothing);
  });

  testWidgets('説明は見守る方の呼び方を使う', (tester) async {
    await _pump(
      tester,
      tutorial: FakeTutorialRepository(),
      home: FakeHomeRepository(
        HomeView(
          person: const WatchedPerson(
            name: '山田花子',
            callName: '花子さん',
            initial: '花',
          ),
          now: sampleHomeData.now,
          latestCall: sampleHomeData.latestCall,
          todayCall: sampleHomeData.latestCall,
        ),
      ),
    );

    expect(
      find.text('AIが花子さんにかけた電話の内容を短くまとめてここに届けます。「会話を見る」で全文も読めます。'),
      findsOneWidget,
    );
    expect(find.textContaining('ハナさん'), findsNothing);
  });

  testWidgets('見ていないと分かったフレームで案内を始める', (tester) async {
    final tutorial = FakeTutorialRepository(seen: null);
    await _pump(tester, tutorial: tutorial);
    expect(find.text('使い方 1/9'), findsNothing);

    tutorial.seen.value = false;
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('使い方 1/9'), findsOneWidget);
  });

  testWidgets('電話がなくても案内のあいだは見本を明るく残し、終わると消す', (tester) async {
    final tutorial = FakeTutorialRepository();
    await _pump(
      tester,
      tutorial: tutorial,
      home: FakeHomeRepository(
        HomeView(
          person: sampleHomeData.person,
          now: sampleHomeData.now,
          latestCall: null,
          todayCall: null,
        ),
      ),
      calls: FakeCallsRepository(
        log: CallLog(today: DateTime(2026, 11, 5), days: const []),
      ),
    );

    expect(find.text('まだ電話がありません'), findsNothing);
    expect(find.text('朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。'), findsOneWidget);
    _expectHoleFits(tester, find.byType(RecentCallCard));

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('使い方 3/9'), findsOneWidget);
    _expectHoleFits(tester, find.byType(TodayCard));

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('使い方 5/9'), findsOneWidget);
    _expectHoleContains(tester, find.text('朝食と薬は済み。膝を気にしている'));

    await tester.tap(find.text('スキップ'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentCallCard), findsNothing);
    expect(find.byType(TodayCard), findsNothing);
    expect(find.text('まだ電話がありません'), findsOneWidget);
    expect(find.text('朝食と薬は済み。膝を気にしている', skipOffstage: false), findsNothing);
  });

  testWidgets('説明する場所が遅れて出ても、明るく残す', (tester) async {
    final registry = TutorialAnchorRegistry();
    final visible = ValueNotifier(false);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialAnchors(
          registry: registry,
          sampling: true,
          child: Stack(
            children: [
              ValueListenableBuilder(
                valueListenable: visible,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.expand();
                  return const Align(
                    alignment: Alignment.topCenter,
                    child: TutorialAnchor(
                      part: TutorialPart.calendar,
                      child: SizedBox(
                        width: 200,
                        height: 40,
                        child: Text('過去7日間'),
                      ),
                    ),
                  );
                },
              ),
              TutorialOverlay(
                step: tutorialStepsFor('ハナさん')[3],
                index: 3,
                registry: registry,
                onNext: () {},
                onSkip: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TutorialHole), findsNothing);
    expect(find.text('使い方 4/9'), findsOneWidget);

    visible.value = true;
    await tester.pumpAndSettle();
    _expectHoleContains(tester, find.text('過去7日間'));
  });

  testWidgets('説明する場所が動いたら、明るい穴も動く', (tester) async {
    final home = FakeHomeRepository(
      HomeView(
        person: sampleHomeData.person,
        now: sampleHomeData.now,
        latestCall: sampleHomeData.latestCall,
        todayCall: sampleHomeData.latestCall,
      ),
    );
    await _pump(tester, tutorial: FakeTutorialRepository(), home: home);
    _expectHoleFits(tester, find.byType(RecentCallCard));
    final before = tester.getRect(find.byType(RecentCallCard)).top;

    home.view.value = HomeView(
      person: sampleHomeData.person,
      now: sampleHomeData.now,
      latestCall: sampleHomeData.latestCall,
      todayCall: sampleHomeData.latestCall,
      reply: Reply(
        told: '金曜の通院は、朝10時にお迎えに来る',
        text: 'わかったよ。玄関で待ってるね。',
        saidAt: DateTime(2026, 11, 4, 19, 29),
      ),
    );
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(RecentCallCard)).top;
    expect(after, greaterThan(before + 40));
    _expectHoleFits(tester, find.byType(RecentCallCard));
  });

  testWidgets('案内が終わると、見本で選んだ日を残さない', (tester) async {
    final tutorial = FakeTutorialRepository();
    await _pump(
      tester,
      tutorial: tutorial,
      home: FakeHomeRepository(
        HomeView(
          person: sampleHomeData.person,
          now: DateTime(2026, 11, 10, 10, 24),
          latestCall: null,
          todayCall: null,
        ),
      ),
      calls: FakeCallsRepository(
        log: CallLog(today: DateTime(2026, 11, 10), days: const []),
      ),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
    }
    expect(find.text('使い方 4/9'), findsOneWidget);
    // 案内中は画面の意味を出さないので、カレンダーの選択日を直接見る
    expect(
      tester.widget<MiniCalendar>(find.byType(MiniCalendar)).selectedDay,
      DateTime(2026, 11, 5),
    );

    await tester.tap(find.text('スキップ'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AppTabBar), matching: find.text('通話記録')),
    );
    await tester.pumpAndSettle();

    expect(find.text('まだ電話がありません'), findsOneWidget);
    expect(
      tester.widget<MiniCalendar>(find.byType(MiniCalendar)).selectedDay,
      DateTime(2026, 11, 10),
    );
  });
}
