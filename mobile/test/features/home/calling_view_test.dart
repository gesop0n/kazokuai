import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/calling_banner.dart';
import 'package:kazokuai/features/home/home_status.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_watched_person_repository.dart';
import '../../support/layout_matrix.dart';

const _standardLayout = LayoutCase(393, 1.0);

Future<void> _pumpBanner(WidgetTester tester, LayoutCase layout) =>
    pumpScreenInLayout(
      tester,
      layout,
      const Scaffold(body: Column(children: [CallingBanner()])),
    );

void main() {
  group('CallingBanner', () {
    testEachLayout('電話のアイコン 18 と「通話中」が崩れずに出る', (tester, layout) async {
      await _pumpBanner(tester, layout);

      final icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.icon, AppIcons.phone);
      expect(icon.size, 18);
      expect(icon.color, AppColors.onAccentCall);
      expect(find.text('通話中'), findsOneWidget);
    });

    testWidgets('色はモックのとおり', (tester) async {
      await _pumpBanner(tester, _standardLayout);

      final background = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(CallingBanner),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(background.color, AppColors.accentCall);
      expect(
        tester.widget<Text>(find.text('通話中')).style!.color,
        AppColors.onAccentCall,
      );
    });

    testWidgets('アイコンと文字は下に揃い、間隔 8 で中央に並び、下の余白は 10', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 54);
      addTearDown(tester.view.resetPadding);
      await _pumpBanner(tester, _standardLayout);

      final banner = tester.getRect(find.byType(CallingBanner));
      final icon = tester.getRect(find.byType(AppIcon));
      final text = tester.getRect(find.text('通話中'));

      expect(banner.height, 94);
      // モックの align-items:flex-end
      expect(icon.bottom, text.bottom);
      expect(banner.bottom - text.bottom, 10);
      expect(text.left - icon.right, 8);
      expect((icon.left + text.right) / 2, banner.center.dx);
    });

    testEachLayout('文字が大きいときは帯が伸びる', (tester, layout) async {
      await _pumpBanner(tester, layout);

      final banner = tester.getRect(find.byType(CallingBanner));
      final text = tester.getRect(find.text('通話中'));
      expect(banner.bottom - text.bottom, 10);
      expect(text.top, greaterThanOrEqualTo(banner.top));
    });

    testWidgets('状態バーの文字は明るくする', (tester) async {
      await _pumpBanner(tester, _standardLayout);

      expect(
        tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.descendant(
                of: find.byType(CallingBanner),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              ),
            )
            .value,
        SystemUiOverlayStyle.light,
      );
    });

    testWidgets('読み上げはモックの role="status" に合わせ、出たときに知らせる', (tester) async {
      await _pumpBanner(tester, _standardLayout);

      expect(
        tester.getSemantics(find.text('通話中')),
        isSemantics(label: '通話中', isLiveRegion: true),
      );
    });
  });

  group('AskCard の通話中', () {
    testEachLayout('「通話」の代わりに押せない「現在通話中です」を出す', (tester, layout) async {
      await pumpInLayout(
        tester,
        layout,
        AskCard(onOpenAsk: () {}, isCalling: true),
      );

      expect(find.text('通話'), findsNothing);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.label, '現在通話中です');
      expect(button.onTap, isNull);
      expect(button.size, AppButtonSize.l);
      expect(button.leadingIcon, isNull);
    });

    testEachLayout('通話中でない高さと変わらない', (tester, layout) async {
      await pumpInLayout(tester, layout, AskCard(onOpenAsk: () {}));
      final normal = tester.getSize(find.byType(AskCard));

      await pumpInLayout(
        tester,
        layout,
        AskCard(onOpenAsk: () {}, isCalling: true),
      );

      expect(tester.getSize(find.byType(AskCard)), normal);
    });

    testWidgets('見た目はモックの disabledBtn の色', (tester) async {
      await pumpInLayout(
        tester,
        _standardLayout,
        AskCard(onOpenAsk: () {}, isCalling: true),
      );

      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.color, AppColors.buttonDisabled);
      expect(
        tester.widget<Text>(find.text('現在通話中です')).style!.color,
        AppColors.inkSecondary,
      );
    });

    testWidgets('入力欄は押せるままで、ボタンを押しても何も起きない', (tester) async {
      var count = 0;
      await pumpInLayout(
        tester,
        _standardLayout,
        AskCard(onOpenAsk: () => count++, isCalling: true),
      );

      await tester.tap(find.text('現在通話中です'), warnIfMissed: false);
      await tester.pump();
      expect(count, 0);

      await tester.tap(find.byType(AppField));
      await tester.pump();
      expect(count, 1);
    });

    testWidgets('読み上げは押せないボタン', (tester) async {
      await pumpInLayout(
        tester,
        _standardLayout,
        AskCard(onOpenAsk: () {}, isCalling: true),
      );

      expect(
        tester.getSemantics(find.byType(AppButton)),
        isSemantics(
          label: '現在通話中です',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
    });
  });

  testWidgets('通話中のホームの入力欄から 01 を開くと、押せない「現在通話中です」が出る', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeStatusProvider.overrideWithBuild(
            (ref, self) => HomeStatus.calling,
          ),
          signedInAuth(),
          registeredWatchedPerson(),
        ],
        child: const KazokuAiApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('伝えたいことを入力'));
    await tester.pumpAndSettle();

    expect(find.byType(AskScreen), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.descendant(
        of: find.byType(AskScreen),
        matching: find.widgetWithText(AppButton, '現在通話中です'),
      ),
    );
    expect(button.onTap, isNull);
  });
}
