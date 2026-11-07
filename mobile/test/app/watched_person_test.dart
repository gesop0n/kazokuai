import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_watched_person_repository.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeWatchedPersonRepository watchedPerson,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        watchedPersonRepositoryProvider.overrideWithValue(watchedPerson),
      ],
      child: const KazokuAiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterNames(
  WidgetTester tester, {
  required String name,
  required String callName,
}) async {
  await tester.enterText(find.bySemanticsLabel('お名前'), name);
  await tester.enterText(find.bySemanticsLabel('電話での呼び方'), callName);
  // 入力すると押せるようになるので、描き直してから押す
  await tester.pump();
}

Future<void> tapNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, '次へ'));
  await tester.pumpAndSettle();
}

bool canGoNext(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, '次へ')).onTap !=
    null;

void main() {
  group('ログインした家族が開く画面', () {
    testWidgets('見守る方がいなければ L6 が開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.none,
        ),
      );

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('見守る方がいればホームが開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: FakeWatchedPersonRepository(),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('見守る方がいるかを読み終えるまでは、L6 もホームも開かない', (tester) async {
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: watchedPerson,
      );

      expect(find.byType(WatchedPersonNameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);

      watchedPerson.status.value = WatchedPersonStatus.none;
      await tester.pumpAndSettle();

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
    });

    testWidgets('ログインしていなければ、見守る方がいなくても L1 が開く', (tester) async {
      await pumpApp(
        tester,
        auth: FakeAuthRepository(),
        watchedPerson: FakeWatchedPersonRepository(
          status: WatchedPersonStatus.none,
        ),
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('L2 でログインしたあと、見守る方がいなければ L6 が開く', (tester) async {
      final auth = FakeAuthRepository(
        accounts: {'misaki@example.com': 'hanasan1234'},
      );
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.unknown,
      );
      await pumpApp(tester, auth: auth, watchedPerson: watchedPerson);
      await tester.tap(find.text('アカウントをお持ちの方はログイン'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('メールアドレス'),
        'misaki@example.com',
      );
      await tester.enterText(find.bySemanticsLabel('パスワード'), 'hanasan1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'ログイン'));
      // ログインすると、データ層が見守る方を読み始める
      watchedPerson.status.value = WatchedPersonStatus.none;
      await tester.pumpAndSettle();

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('L6', () {
    Future<FakeWatchedPersonRepository> openL6(
      WidgetTester tester, {
      bool failing = false,
    }) async {
      final watchedPerson = FakeWatchedPersonRepository(
        status: WatchedPersonStatus.none,
        failing: failing,
      );
      await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: true),
        watchedPerson: watchedPerson,
      );
      return watchedPerson;
    }

    testWidgets('入れた名前と呼び方がデータ層に届き、ホームが開く', (tester) async {
      final watchedPerson = await openL6(tester);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      await tapNext(tester);

      expect(watchedPerson.registrations, [(name: '田中 ハナ', callName: 'ハナさん')]);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WatchedPersonNameScreen), findsNothing);
    });

    testWidgets('名前と呼び方の前後の空白は除いて渡す', (tester) async {
      final watchedPerson = await openL6(tester);

      await enterNames(tester, name: ' 田中 ハナ　', callName: 'ハナさん ');
      await tapNext(tester);

      expect(watchedPerson.registrations, [(name: '田中 ハナ', callName: 'ハナさん')]);
    });

    testWidgets('名前と呼び方の両方を入れるまで、次へを押せない', (tester) async {
      await openL6(tester);

      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: '');
      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: '　');
      expect(canGoNext(tester), isFalse);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      expect(canGoNext(tester), isTrue);
    });

    testWidgets('登録できなかったときは、L6 にメッセージが出て、入力を直すと消える', (tester) async {
      await openL6(tester, failing: true);

      await enterNames(tester, name: '田中 ハナ', callName: 'ハナさん');
      await tapNext(tester);

      expect(find.byType(WatchedPersonNameScreen), findsOneWidget);
      expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('電話での呼び方'), 'ハナちゃん');
      await tester.pump();

      expect(find.text('登録できませんでした。時間をおいて、もう一度お試しください'), findsNothing);
    });
  });
}
