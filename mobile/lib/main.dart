import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/app.dart';
import 'package:kazokuai/app/licenses.dart';
import 'package:kazokuai/data/firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  await startFirebase();
  // 最初の画面を選ぶ前に、Firebase Auth がログインの状態を戻すのを待つ。
  // Web では読み直した直後、currentUser が空のまま先に画面を選ぶと、
  // ログインした家族がようこそへ飛ばされ、開いていた画面に戻れない。
  // URL は Flutter の既定の #/ のままにする。パスにすると、この戻り先が消える。
  final authReady = FirebaseAuth.instance.authStateChanges().first.then((_) {});
  runApp(ProviderScope(child: KazokuAiApp(authReady: authReady)));
}
