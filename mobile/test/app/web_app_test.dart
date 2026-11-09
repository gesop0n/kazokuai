import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_calls_repository.dart';
import '../support/fake_home_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpSignedInApp(
  WidgetTester tester, {
  Future<void>? authReady,
  FakeAuthRepository? auth,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        auth == null
            ? signedInAuth()
            : authRepositoryProvider.overrideWithValue(auth),
        registeredWatchedPerson(),
        sampleHome(),
        sampleCalls(),
      ],
      child: KazokuAiApp(authReady: authReady),
    ),
  );
}

void useScreen(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..padding = FakeViewPadding.zero;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('広い画面では、アプリが真ん中のスマホの幅の列になる', (tester) async {
    const screen = Size(1200, 800);
    useScreen(tester, screen);
    await pumpSignedInApp(tester);
    await tester.pumpAndSettle();

    final home = tester.getRect(find.byType(HomeScreen));
    expect(home.width, 430);
    expect(home.left, (screen.width - 430) / 2);
    expect(home.right, screen.width - home.left);
  });

  testWidgets('スマホの幅では、アプリが画面の幅いっぱいになる', (tester) async {
    const screen = Size(393, 852);
    useScreen(tester, screen);
    await pumpSignedInApp(tester);
    await tester.pumpAndSettle();

    final home = tester.getRect(find.byType(HomeScreen));
    expect(home.width, screen.width);
    expect(home.left, 0);
  });

  testWidgets('読み直しても、ログインした家族は開いていた画面にいる', (tester) async {
    final ready = Completer<void>();
    final auth = FakeAuthRepository();
    useScreen(tester, const Size(393, 852));
    tester.platformDispatcher.defaultRouteNameTestValue = '/calls';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await pumpSignedInApp(tester, authReady: ready.future, auth: auth);
    await tester.pump();

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(CallsScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);

    auth.signedIn.value = true;
    ready.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('おかしな道の値でも画面が出て、アプリは落ちない', (tester) async {
    useScreen(tester, const Size(393, 852));
    tester.platformDispatcher.defaultRouteNameTestValue = '/booking/edit/x';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await pumpSignedInApp(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('このページは開けません'), findsOneWidget);
    expect(find.byType(BookingEditScreen), findsNothing);
  });
}
