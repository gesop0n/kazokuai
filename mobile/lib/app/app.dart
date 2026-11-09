import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/loading_screen.dart';
import 'package:kazokuai/app/phone_column.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_theme.dart';

class KazokuAiApp extends ConsumerStatefulWidget {
  const KazokuAiApp({super.key, this.authReady});

  // 終わるまで最初の画面を選ばない。Firebase Auth がログインの状態を戻すのを待つ。
  // 渡さないときは、すぐに選ぶ。テストはここを遅らせて、読み直しを再現する。
  final Future<void>? authReady;

  @override
  ConsumerState<KazokuAiApp> createState() => _KazokuAiAppState();
}

class _KazokuAiAppState extends ConsumerState<KazokuAiApp> {
  // build で作り直すと開いている画面を失うので、State に持つ。
  // ログインの状態が戻る前に作ると、読み直した家族が別の画面へ飛ぶ。
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    final ready = widget.authReady;
    if (ready == null) {
      _router = _createRouter();
      return;
    }
    ready.then(
      (_) => _showFirstScreen(),
      onError: (Object _, StackTrace _) => _showFirstScreen(),
    );
  }

  GoRouter _createRouter() {
    return createAppRouter(
      auth: ref.read(authRepositoryProvider),
      watchedPerson: ref.read(watchedPersonRepositoryProvider),
    );
  }

  void _showFirstScreen() {
    if (!mounted || _router != null) return;
    setState(() => _router = _createRouter());
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      return MaterialApp(
        title: 'かぞくAI',
        theme: appTheme,
        themeMode: ThemeMode.light,
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // ナビゲーターを作らない。作るとプラットフォームの道を読み、
        // その道がないと怒って / に落ちる。戻ったあと GoRouter がその道から選ぶ。
        builder: (context, _) => _frame(const _AuthRestoring()),
      );
    }

    final signedIn = ref.read(authRepositoryProvider).signedIn;
    final status = ref.read(watchedPersonRepositoryProvider).status;
    return MaterialApp.router(
      title: 'かぞくAI',
      theme: appTheme,
      themeMode: ThemeMode.light,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => _frame(
        _KeepRouteWhileLoading(
          signedIn: signedIn,
          status: status,
          child: child!,
        ),
      ),
      routerConfig: router,
    );
  }
}

// 状態バーの色を指定する画面がないと、前の画面の色が残る。通話中の帯だけ明るい文字にする。
// 文字は 1.3 倍まで。広い画面ではスマホの幅の列にする。
Widget _frame(Widget child) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: PhoneColumn(child: child),
    ),
  );
}

// ログインの状態が戻るまでの画面。最初の画面は、まだ選ばない。
class _AuthRestoring extends StatelessWidget {
  const _AuthRestoring();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(label: '読み込んでいます', child: const SizedBox.expand()),
    );
  }
}

// 見守る方を読み終えるまで、開いている道は残して読み込み中を上に出す。
// 道を /loading に付け替えると、読み終えたあとホームへ戻り、読み直した画面を失う。
class _KeepRouteWhileLoading extends StatelessWidget {
  const _KeepRouteWhileLoading({
    required this.signedIn,
    required this.status,
    required this.child,
  });

  final ValueListenable<bool> signedIn;
  final ValueListenable<WatchedPersonStatus> status;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: signedIn,
      builder: (context, signedInNow, _) {
        return ValueListenableBuilder(
          valueListenable: status,
          builder: (context, statusNow, _) {
            final waiting =
                signedInNow &&
                (statusNow == WatchedPersonStatus.unknown ||
                    statusNow == WatchedPersonStatus.unreadable);
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Offstage(offstage: waiting, child: child),
                ),
                if (waiting) const Positioned.fill(child: LoadingScreen()),
              ],
            );
          },
        );
      },
    );
  }
}
