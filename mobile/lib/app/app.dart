import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:kazokuai/app/foundation_preview_screen.dart';
import 'package:kazokuai/design/app_theme.dart';

class KazokuAiApp extends StatelessWidget {
  const KazokuAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'かぞくAI',
      theme: appTheme,
      themeMode: ThemeMode.light,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child!,
      ),
      home: const FoundationPreviewScreen(),
    );
  }
}
