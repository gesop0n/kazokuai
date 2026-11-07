import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// 本物の Firebase のプロジェクトはまだなく、開発者の Mac のエミュレーターだけを使う。
// demo- で始まるプロジェクトは、エミュレーターの外には届かない
const _projectId = 'demo-kazokuai';

// firebase/firebase.json のポートと合わせる。
// Firestore は既定の 8080 だとバックエンドと重なるので、8081 にしている
const _authEmulatorPort = 9099;
const _firestoreEmulatorPort = 8081;

// flutterfire configure は使わずに手で書く。値は FlutterFire の demoProjectId と同じにする。
// demoProjectId を使うとアプリの名前が [DEFAULT] でなくなり、FirebaseAuth.instance で使えない。
// iOS は appId が 1:<数字>:ios:<16 進数> の形でないと起動しない
FirebaseOptions get _options => FirebaseOptions(
  apiKey: 'ADemoProjectApiKey000000000000000000000',
  appId: switch (defaultTargetPlatform) {
    TargetPlatform.android => '1:1:android:1',
    _ => '1:1:ios:1',
  },
  messagingSenderId: '1',
  projectId: _projectId,
);

Future<void> startFirebase() async {
  await Firebase.initializeApp(options: _options);
  // iOS のシミュレーターからは localhost で届く。Android のエミュレーターでは FlutterFire が 10.0.2.2 に置き換える
  await FirebaseAuth.instance.useAuthEmulator('localhost', _authEmulatorPort);
  FirebaseFirestore.instance
    ..useFirestoreEmulator('localhost', _firestoreEmulatorPort)
    // エミュレーターは止めるとデータが消えるので、消えたデータを端末のキャッシュから出さない
    ..settings = const Settings(persistenceEnabled: false);
}
