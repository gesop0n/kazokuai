import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:kazokuai/data/app_config.dart';

// firebase/firebase.json のポートと合わせる。
// Firestore は既定の 8080 だとバックエンドと重なるので、8081 にしている
const _authEmulatorPort = 9099;
const _firestoreEmulatorPort = 8081;

Future<void> startFirebase() async {
  await Firebase.initializeApp(options: appConfig.firebase);
  if (!appConfig.useEmulators) return;
  // iOS のシミュレーターからは localhost で届く。Android のエミュレーターでは FlutterFire が 10.0.2.2 に置き換える
  await FirebaseAuth.instance.useAuthEmulator('localhost', _authEmulatorPort);
  FirebaseFirestore.instance
    ..useFirestoreEmulator('localhost', _firestoreEmulatorPort)
    // エミュレーターは止めるとデータが消えるので、消えたデータを端末のキャッシュから出さない
    ..settings = const Settings(persistenceEnabled: false);
}
