import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_avatar.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

import '../../support/layout_matrix.dart';

Widget buildHeader({
  WatchedPerson? person,
  DateTime? now,
  VoidCallback? onOpenNotifications,
}) => HomeHeader(
  person: person ?? sampleHomeData.person,
  now: now ?? sampleHomeData.now,
  onOpenNotifications: onOpenNotifications ?? () {},
);

Widget buildRecentCard({
  Call? call,
  DateTime? now,
  VoidCallback? onOpenConversation,
}) => RecentCallCard(
  call: call ?? sampleHomeData.latestCall,
  now: now ?? sampleHomeData.now,
  onOpenConversation: onOpenConversation ?? () {},
);

// 右のラベルが一番長くなる形。12月25日 19:02 ・ 120分
Widget buildLongStampRecentCard() => buildRecentCard(
  call: Call(
    startedAt: DateTime(2026, 12, 25, 19, 2),
    duration: const Duration(minutes: 120),
    summary: sampleHomeData.latestCall.summary,
  ),
  now: DateTime(2026, 12, 27),
);

// ヘッダーは自分で左右の余白を持つので、pumpInLayout を使わず画面の幅で置く
Future<void> pumpHeader(
  WidgetTester tester,
  LayoutCase layout,
  Widget header,
) => pumpScreenInLayout(tester, layout, Scaffold(body: header));

const standardLayout = LayoutCase(393, 1.0);

void main() {
  group('overflow', () {
    testEachLayout('ヘッダー', (tester, layout) async {
      await pumpHeader(tester, layout, buildHeader());
    });

    testEachLayout('直近の電話のカード', (tester, layout) async {
      await pumpInLayout(tester, layout, buildRecentCard());
    });

    testEachLayout('直近の電話のカード(日時の文字が長いとき)', (tester, layout) async {
      await pumpInLayout(tester, layout, buildLongStampRecentCard());
    });

    testEachLayout('AIに伝えてもらうのカード', (tester, layout) async {
      await pumpInLayout(tester, layout, AskCard(onOpenAsk: () {}));
    });

    testEachLayout('ホーム画面', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        Scaffold(body: HomeScreen(data: sampleHomeData)),
      );

      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(RecentCallCard), findsOneWidget);
      expect(find.byType(AskCard), findsOneWidget);
    });
  });

  group('ヘッダー', () {
    testWidgets('サンプルデータから文字を作る', (tester) async {
      await pumpHeader(tester, standardLayout, buildHeader());

      expect(find.text('ハ'), findsOneWidget);
      expect(find.text('田中ハナさん'), findsOneWidget);
      expect(find.text('11月5日(木) 10:24 時点'), findsOneWidget);
    });

    testWidgets('別のデータなら別の文字になる', (tester) async {
      await pumpHeader(
        tester,
        standardLayout,
        buildHeader(
          person: const WatchedPerson(
            name: '佐藤タロウ',
            callName: 'タロウさん',
            initial: 'タ',
          ),
          now: DateTime(2026, 12, 7, 8, 5),
        ),
      );

      expect(find.text('タ'), findsOneWidget);
      expect(find.text('佐藤タロウさん'), findsOneWidget);
      expect(find.text('12月7日(月) 8:05 時点'), findsOneWidget);
    });

    testWidgets('アバターの色は話し手の親の色になる', (tester) async {
      await pumpHeader(tester, standardLayout, buildHeader());

      expect(
        tester.widget<AppAvatar>(find.byType(AppAvatar)).color,
        AppColors.speakerParent,
      );
    });

    testWidgets('高さは最小で 60 になる', (tester) async {
      await pumpHeader(tester, standardLayout, buildHeader());

      expect(tester.getSize(find.byType(HomeHeader)).height, 60);
    });

    testWidgets('文字が増えると、高さは 60 を超えて伸びる', (tester) async {
      await pumpHeader(tester, const LayoutCase(360, 1.3), buildHeader());

      expect(tester.getSize(find.byType(HomeHeader)).height, greaterThan(60));
    });

    testWidgets('ベルで onOpenNotifications を呼ぶ', (tester) async {
      var count = 0;
      await pumpHeader(
        tester,
        standardLayout,
        buildHeader(onOpenNotifications: () => count++),
      );

      await tester.tap(find.bySemanticsLabel('通知'));

      expect(count, 1);
    });
  });

  group('直近の電話のカード', () {
    testWidgets('サンプルデータから文字を作る', (tester) async {
      await pumpInLayout(tester, standardLayout, buildRecentCard());

      final summary = sampleHomeData.latestCall.summary;
      expect(find.text('直近の電話'), findsOneWidget);
      expect(find.text('今日 9:02 ・ 6分'), findsOneWidget);
      expect(find.text('Geminiのまとめ'), findsNothing);
      expect(find.text(summary.headline), findsOneWidget);
      expect(find.text(summary.quote.text), findsOneWidget);
      expect(find.text('9:03'), findsOneWidget);
      expect(find.textContaining('の言葉'), findsNothing);
      expect(find.text('会話を見る'), findsOneWidget);
    });

    testWidgets('別の日の電話は月日で書く', (tester) async {
      await pumpInLayout(
        tester,
        standardLayout,
        buildRecentCard(now: DateTime(2026, 11, 7, 8)),
      );

      expect(find.text('11月5日 9:02 ・ 6分'), findsOneWidget);
      expect(find.textContaining('今日'), findsNothing);
    });

    testWidgets('別のデータなら別の文字になる', (tester) async {
      await pumpInLayout(
        tester,
        standardLayout,
        buildRecentCard(
          call: Call(
            startedAt: DateTime(2026, 11, 5, 18, 30),
            duration: const Duration(minutes: 12, seconds: 40),
            summary: CallSummary(
              headline: '夕方に散歩をしたそうです。',
              quote: Quote(
                text: '「今日は風が気持ちよかった。」',
                spokenAt: DateTime(2026, 11, 5, 18, 41),
              ),
              conditions: const [],
            ),
          ),
        ),
      );

      expect(find.text('今日 18:30 ・ 12分'), findsOneWidget);
      expect(find.text('夕方に散歩をしたそうです。'), findsOneWidget);
      expect(find.text('「今日は風が気持ちよかった。」'), findsOneWidget);
      expect(find.textContaining('の言葉'), findsNothing);
    });

    testWidgets('間隔はモックの margin-top と同じになる', (tester) async {
      await pumpInLayout(tester, standardLayout, buildRecentCard());

      final summary = sampleHomeData.latestCall.summary;
      final title = tester.getRect(find.text('直近の電話'));
      final headline = tester.getRect(find.text(summary.headline));
      final time = tester.getRect(find.text('9:03'));
      final quote = tester.getRect(find.text(summary.quote.text));
      final button = tester.getRect(find.byType(AppButton));

      expect(headline.top - title.bottom, 12);
      expect(time.top - headline.bottom, 12);
      expect(quote.top - time.bottom, 2);
      expect(button.top - quote.bottom, 16);
    });

    testWidgets('引用は線と余白の分だけ字下げする', (tester) async {
      await pumpInLayout(tester, standardLayout, buildRecentCard());

      final summary = sampleHomeData.latestCall.summary;
      expect(
        tester.getTopLeft(find.text(summary.quote.text)).dx -
            tester.getTopLeft(find.text(summary.headline)).dx,
        14,
      );
    });

    testWidgets('ボタンは light の M で、幅いっぱいに広がる', (tester) async {
      await pumpInLayout(tester, standardLayout, buildRecentCard());

      final finder = find.byType(AppButton);
      final button = tester.widget<AppButton>(finder);
      expect(button.variant, AppButtonVariant.light);
      expect(button.size, AppButtonSize.m);
      expect(button.trailingIcon, AppIcons.chevronRight);
      // 画面の余白 16 とカードの余白 20 を左右で引く
      expect(tester.getSize(finder).width, 393 - 72);
    });

    testWidgets('会話を見るで onOpenConversation を呼ぶ', (tester) async {
      var count = 0;
      await pumpInLayout(
        tester,
        standardLayout,
        buildRecentCard(onOpenConversation: () => count++),
      );

      await tester.tap(find.text('会話を見る'));

      expect(count, 1);
    });
  });

  group('AIに伝えてもらうのカード', () {
    testWidgets('見出しと入力欄と通話ボタンを表示する', (tester) async {
      await pumpInLayout(tester, standardLayout, AskCard(onOpenAsk: () {}));

      expect(find.text('AIに伝えてもらう'), findsOneWidget);
      expect(find.text('予約もできます'), findsNothing);
      expect(find.text('伝えたいことを入力'), findsOneWidget);
      expect(find.text('通話'), findsOneWidget);

      final field = find.byType(AppField);
      expect(tester.widget<AppField>(field).minHeight, 48);

      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.variant, AppButtonVariant.record);
      expect(button.size, AppButtonSize.l);
      expect(button.leadingIcon, AppIcons.phone);
    });

    testWidgets('入力欄で onOpenAsk を呼ぶ', (tester) async {
      var count = 0;
      await pumpInLayout(
        tester,
        standardLayout,
        AskCard(onOpenAsk: () => count++),
      );

      await tester.tap(find.text('伝えたいことを入力'));

      expect(count, 1);
    });

    testWidgets('通話ボタンで onOpenAsk を呼ぶ', (tester) async {
      var count = 0;
      await pumpInLayout(
        tester,
        standardLayout,
        AskCard(onOpenAsk: () => count++),
      );

      await tester.tap(find.text('通話'));

      expect(count, 1);
    });
  });

  group('見出しと右のラベルの行', () {
    testWidgets('直近の電話の行も、入らないときは折り返す', (tester) async {
      await pumpInLayout(
        tester,
        const LayoutCase(360, 1.3),
        buildLongStampRecentCard(),
      );

      final title = tester.getRect(find.text('直近の電話'));
      final label = tester.getRect(find.text('12月25日 19:02 ・ 120分'));
      expect(label.top, greaterThanOrEqualTo(title.bottom));
    });
  });

  testEachLayout('押せる領域はどれも 44 以上になる', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      Scaffold(body: HomeScreen(data: sampleHomeData)),
    );

    final finders = [
      find.byType(HomeHeader),
      find.byType(RecentCallCard),
      find.byType(AskCard),
    ];
    for (final parent in finders) {
      final pressables = find.descendant(
        of: parent,
        matching: find.byType(InkWell),
      );
      expect(pressables, findsWidgets);
      for (final element in pressables.evaluate()) {
        final size = (element.renderObject! as RenderBox).size;
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    }
  });

  group('formatRelativeDay', () {
    final startedAt = DateTime(2026, 11, 5, 9, 2);

    test('同じ日なら今日と書く', () {
      expect(formatRelativeDay(startedAt, DateTime(2026, 11, 5, 23, 59)), '今日');
      expect(formatRelativeDay(startedAt, DateTime(2026, 11, 5)), '今日');
    });

    test('日が変われば、24 時間以内でも昨日と書く', () {
      expect(
        formatRelativeDay(DateTime(2026, 11, 4, 23, 59), DateTime(2026, 11, 5)),
        '昨日',
      );
    });

    test('月が違えば、同じ日でも月日で書く', () {
      expect(formatRelativeDay(startedAt, DateTime(2026, 12, 5)), '11月5日');
    });

    test('年が違えば、同じ月日でも月日で書く', () {
      expect(formatRelativeDay(startedAt, DateTime(2027, 11, 5)), '11月5日');
    });
  });
}
