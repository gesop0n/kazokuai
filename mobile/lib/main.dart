import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/app/licenses.dart';
import 'package:kazokuai/data/firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  await startFirebase();
  runApp(const ProviderScope(child: KazokuAiApp()));
}
