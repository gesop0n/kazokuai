import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_theme.dart';

class KazokuAiApp extends StatefulWidget {
  const KazokuAiApp({super.key});

  @override
  State<KazokuAiApp> createState() => _KazokuAiAppState();
}

class _KazokuAiAppState extends State<KazokuAiApp> {
  // build で作り直すと開いている画面を失うので、State に持つ
  final GoRouter _router = createAppRouter();

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
