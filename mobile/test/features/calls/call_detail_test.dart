import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

import '../../support/layout_matrix.dart';
import 'calls_harness.dart';

const _mockLayout = LayoutCase(393, 1.0);

Future<void> _pumpDetail(WidgetTester tester, LayoutCase layout) async {
  await pumpScreenInLayout(tester, layout, const CallDetailScreen());
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

Future<void> _scrollTo(WidgetTester tester, double offset) async {
  _position(tester).jumpTo(offset);
  await tester.pumpAndSettle();
}

double _navBarBottom(WidgetTester tester) =>
    tester.getBottomLeft(find.byType(AppNavBar)).dy;

// 時刻の Text を探す。まとめの行と会話の両方にあるので、発言の側を返す
Finder _utteranceTime(String time) => find.text(time).last;

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style?.color;

void main() {
  group('崩れない', () {
    testEachLayout('先頭', (tester, layout) async {
      await _pumpDetail(tester, layout);

      expect(find.text('詳細なまとめ'), findsOneWidget);
    });

    testEachLayout('一番下までスクロールしたとき', (tester, layout) async {
      await _pumpDetail(tester, layout);

      await _scrollTo(tester, _position(tester).maxScrollExtent);

      expect(find.text('飲んだよ。'), findsOneWidget);
    });

    testEachLayout('発言の時刻の桁が多いとき', (tester, layout) async {
      await pumpScreenInLayout(
        tester,
        layout,
        CallDetailScreen(
          detail: CallDetail(
            title: '朝の電話',
            startedAt: DateTime(2026, 11, 5, 19, 2),
            duration: const Duration(minutes: 120, seconds: 12),
            parentCallName: 'ハナさん',
            points: const [
              SummaryPoint(
                text: '昨日の夕方から膝が痛く、階段がつらいそうです。昨日の夕方から膝が痛く、階段がつらいそうです',
                at: Duration(minutes: 119, seconds: 59),
              ),
            ],
            utterances: const [
              Utterance(
                at: Duration(minutes: 119, seconds: 59),
                speaker: Speaker.parent,
                text: '昨日の夕方から膝が痛くてね。階段がつらいの。',
                needsAttention: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('詳細なまとめ'), findsOneWidget);
    });
  });

  group('内容', () {
    testWidgets('モックの文字をすべて出す', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      for (final text in [
        '朝の電話',
        '詳細なまとめ',
        '11/5 9:02 ・ 6分12秒',
        'Geminiのまとめ。右の時刻で元の発言へ移動します',
        '朝ごはんを食べ、よく眠れたそうです',
        '昨日の夕方から膝が痛く、階段がつらいそうです',
        '朝の薬は飲んだと話しています',
        'まとめの間違いを直す',
        '会話の内容',
        'おはようございます、ハナさん。昨夜はよく眠れましたか。',
        'よく眠れたよ。朝ごはんも食べたしね。',
        'それは何よりです。お体の具合はいかがですか。',
        '昨日の夕方から膝が痛くてね。階段がつらいの。',
        'それはおつらいですね。美咲さんにもお伝えしておきましょうか。',
        'そうね、お願いしようかな。',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('4:12 に見本の発言がある', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(find.text('朝の薬は飲みましたか。'), findsOneWidget);
      expect(find.text('飲んだよ。'), findsOneWidget);
      expect(find.text('4:12'), findsNWidgets(2));
    });

    testWidgets('話者の色はモックと同じ', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(_colorOf(tester, 'AIヘルパー'), AppColors.speakerAi);
      expect(_colorOf(tester, 'ハナさん'), AppColors.speakerParent);
    });

    testWidgets('話者の名前は太さ 700', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(
        tester.widget<Text>(find.text('AIヘルパー').first).style?.fontWeight,
        FontWeight.w700,
      );
    });

    testWidgets('気になる発言だけ背景があり、文字より 8 左に出る', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      final flagged = find.ancestor(
        of: find.text('昨日の夕方から膝が痛くてね。階段がつらいの。'),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(flagged.first).decoration! as BoxDecoration;
      expect(decoration.color, AppColors.stateCareSoft);
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(
        tester.getTopLeft(find.text('昨日の夕方から膝が痛くてね。階段がつらいの。')).dx,
        tester.getTopLeft(find.text('それは何よりです。お体の具合はいかがですか。')).dx,
      );
      expect(
        tester.getTopLeft(flagged.first).dx,
        tester.getTopLeft(find.text('それは何よりです。お体の具合はいかがですか。')).dx - 8,
      );

      expect(
        find.ancestor(
          of: find.text('そうね、お願いしようかな。'),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });
  });

  group('まとめの時刻', () {
    testWidgets('押すと該当の発言が画面の上端に来る', (tester) async {
      await _pumpDetail(tester, const LayoutCase(360, 1.3));
      // 画面が低いと、該当の発言を一番上まで動かせる
      tester.view.physicalSize = const Size(360, 480);
      await tester.pumpAndSettle();

      await tapSemantics(tester, '0:11の発言へ移動');

      expect(_position(tester).pixels, greaterThan(0));
      expect(
        tester.getTopLeft(_utteranceTime('0:11')).dy - 2,
        moreOrLessEquals(_navBarBottom(tester)),
      );
    });

    testWidgets('モックの高さでは、動ける分だけ動く', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      await tapSemantics(tester, '1:03の発言へ移動');

      final position = _position(tester);
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('昨日の夕方から膝が痛くてね。階段がつらいの。').hitTestable(), findsOneWidget);
    });

    testWidgets('4:12 は最後の発言まで動かす', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      await tapSemantics(tester, '4:12の発言へ移動');

      final position = _position(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('飲んだよ。').hitTestable(), findsOneWidget);
    });

    testWidgets('最後の発言は、下端の重なりに隠れない', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      await _scrollTo(tester, _position(tester).maxScrollExtent);

      final fadeTop = tester.getTopLeft(_fade).dy;
      expect(
        tester.getBottomLeft(find.text('飲んだよ。')).dy,
        lessThanOrEqualTo(fadeTop),
      );
    });

    testWidgets('押せる領域は 44pt 以上ある', (tester) async {
      await _pumpDetail(tester, const LayoutCase(360, 1.0));

      for (final time in ['0:11', '1:03', '4:12']) {
        final hit = tester.getSize(find.bySemanticsLabel('$timeの発言へ移動'));
        expect(hit.width, greaterThanOrEqualTo(44), reason: time);
        expect(hit.height, greaterThanOrEqualTo(44), reason: time);
      }
    });

    testWidgets('時刻の文字を押すと動く', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      await tester.tap(find.text('1:03').first);
      await tester.pumpAndSettle();

      expect(_position(tester).pixels, greaterThan(0));
    });

    testWidgets('押せる領域を重ねても、文字と時刻の間隔はモックの 12 のまま', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      final text = tester.getTopRight(find.text('朝ごはんを食べ、よく眠れたそうです'));
      final time = tester.getTopLeft(find.text('0:11').first);

      expect(text.dx, lessThanOrEqualTo(time.dx - 12));
    });
  });

  group('まとめの間違いを直す', () {
    testWidgets('押すと「準備中です」と出す', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      await tester.tap(find.text('まとめの間違いを直す'));
      await tester.pump();

      expect(find.text('準備中です'), findsOneWidget);
    });

    testWidgets('押せる領域は 44pt 以上ある', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      final button = tester.getSize(
        find.ancestor(
          of: find.text('まとめの間違いを直す'),
          matching: find.byType(InkWell),
        ),
      );
      expect(button.width, greaterThanOrEqualTo(44));
      expect(button.height, greaterThanOrEqualTo(44));
    });
  });

  group('下端の重なり', () {
    testWidgets('モックと同じグラデーションで、高さは 32 と下の安全領域', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpDetail(tester, _mockLayout);

      expect(tester.getSize(_fade).height, 32 + 34);
      expect(tester.getBottomLeft(_fade).dy, 852);
      expect(tester.getSize(_fade).width, 393);

      final gradient =
          (tester.widget<DecoratedBox>(_fade).decoration as BoxDecoration)
                  .gradient!
              as LinearGradient;
      expect(gradient.colors, [
        AppColors.paperBase.withAlpha(0),
        AppColors.paperBase,
      ]);
      expect(gradient.stops, [0, .6]);
    });

    testWidgets('重なりの下の発言も押せるように、タップを通す', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(tester.widget<IgnorePointer>(_fadeIgnorePointer).ignoring, isTrue);
    });
  });

  group('読み上げ', () {
    testWidgets('戻るボタンは「もどる」', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(find.bySemanticsLabel('もどる'), findsOneWidget);
    });

    testWidgets('まとめの時刻は移動するボタンとして読み、時刻を二重に読まない', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(
        tester.getSemantics(find.bySemanticsLabel('0:11の発言へ移動')),
        isSemantics(label: '0:11の発言へ移動', isButton: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel('0:11'), findsNothing);
    });

    testWidgets('発言は時刻、話者、文字をまとめて読む', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(
        find.bySemanticsLabel('0:11\nハナさん\nよく眠れたよ。朝ごはんも食べたしね。'),
        findsOneWidget,
      );
    });

    testWidgets('気になる発言は、色だけでなく言葉でも伝える', (tester) async {
      await _pumpDetail(tester, _mockLayout);

      expect(find.bySemanticsLabel(RegExp('気になる発言')), findsOneWidget);
    });
  });
}

// 下端の重なり。IgnorePointer はフレームワークの中にも多いので、グラデーションで探す
Finder get _fade => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).gradient != null,
);

Finder get _fadeIgnorePointer =>
    find.ancestor(of: _fade, matching: find.byType(IgnorePointer)).first;
