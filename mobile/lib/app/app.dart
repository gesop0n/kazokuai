import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_theme.dart';

class KazokuAiApp extends ConsumerStatefulWidget {
  const KazokuAiApp({super.key});

  @override
  ConsumerState<KazokuAiApp> createState() => _KazokuAiAppState();
}

class _KazokuAiAppState extends ConsumerState<KazokuAiApp> {
  // build で作り直すと開いている画面を失うので、State に持つ
  late final GoRouter _router = createAppRouter(
    auth: ref.read(authRepositoryProvider),
    watchedPerson: ref.read(watchedPersonRepositoryProvider),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'かぞくAI',
      theme: appTheme,
      themeMode: ThemeMode.light,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        // 状態バーの色を指定する画面がないと、前の画面の色が残る。通話中の帯だけ明るい文字にする
        value: SystemUiOverlayStyle.dark,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child!,
        ),
      ),
      routerConfig: _router,
    );
  }
}
