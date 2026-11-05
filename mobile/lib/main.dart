import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/app/licenses.dart';

void main() {
  registerLicenses();
  runApp(const ProviderScope(child: KazokuAiApp()));
}
