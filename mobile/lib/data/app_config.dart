import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// ビルドのときに --dart-define で選ぶ。
// 既定の emulators は demo-kazokuai のエミュレーター。手元の作業は本物のプロジェクトに触れない。
// production は Terraform の output を渡して作る。値はリポジトリに置かない。
//
//   --dart-define=KAZOKUAI_TARGET=production
//   --dart-define=FIREBASE_API_KEY=...
//   --dart-define=FIREBASE_APP_ID=...        Web アプリの ID
//   --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
//   --dart-define=FIREBASE_PROJECT_ID=...
//   --dart-define=FIREBASE_AUTH_DOMAIN=...
//   --dart-define=FIREBASE_STORAGE_BUCKET=...     任意
//   --dart-define=FIREBASE_MEASUREMENT_ID=...     任意
//
// エミュレーターのバックエンドは --dart-define=BACKEND_URL で変えられる。
// production の Web 版は、同じサイトの /api を使う。
const _emulatorTarget = 'emulators';
const _productionTarget = 'production';

const _emulatorProjectId = 'demo-kazokuai';
const _emulatorApiKey = 'ADemoProjectApiKey000000000000000000000';
const _defaultBackendUrl = 'http://localhost:8080';
const _productionBackendUrl = '/api';

class AppConfig {
  const AppConfig({
    required this.firebase,
    required this.useEmulators,
    required this.backendUrl,
  });

  final FirebaseOptions firebase;

  // true のとき、Auth と Firestore はローカルのエミュレーターにつなぐ
  final bool useEmulators;

  // バックエンドの起点。パスは含まない。production では /api
  final String backendUrl;
}

// target が空か emulators のときはエミュレーター。production は渡した Firebase の設定を使う。
// web が true のときは、ブラウザの OS ではなく Web のアプリ ID を選ぶ。
AppConfig appConfigFrom({
  required String target,
  required bool web,
  required TargetPlatform platform,
  String backendUrl = _defaultBackendUrl,
  String firebaseApiKey = '',
  String firebaseAppId = '',
  String firebaseMessagingSenderId = '',
  String firebaseProjectId = '',
  String firebaseAuthDomain = '',
  String firebaseStorageBucket = '',
  String firebaseMeasurementId = '',
}) {
  final chosen = target.isEmpty ? _emulatorTarget : target;
  if (chosen == _emulatorTarget) {
    return AppConfig(
      useEmulators: true,
      backendUrl: backendUrl,
      firebase: FirebaseOptions(
        apiKey: _emulatorApiKey,
        appId: _emulatorAppId(web: web, platform: platform),
        messagingSenderId: '1',
        projectId: _emulatorProjectId,
        authDomain: web ? 'localhost' : null,
      ),
    );
  }
  if (chosen != _productionTarget) {
    throw ArgumentError(
      'KAZOKUAI_TARGET は $_emulatorTarget か $_productionTarget です: $target',
    );
  }

  final missing = [
    if (firebaseApiKey.isEmpty) 'FIREBASE_API_KEY',
    if (firebaseAppId.isEmpty) 'FIREBASE_APP_ID',
    if (firebaseMessagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
    if (firebaseProjectId.isEmpty) 'FIREBASE_PROJECT_ID',
    if (firebaseAuthDomain.isEmpty) 'FIREBASE_AUTH_DOMAIN',
  ];
  if (missing.isNotEmpty) {
    throw ArgumentError(
      '本物のプロジェクトには次の --dart-define が要ります: ${missing.join(', ')}',
    );
  }
  return AppConfig(
    useEmulators: false,
    backendUrl: _productionBackendUrl,
    firebase: FirebaseOptions(
      apiKey: firebaseApiKey,
      // 渡された Web アプリの ID を、ブラウザの OS では選び直さない
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      authDomain: firebaseAuthDomain,
      storageBucket: firebaseStorageBucket.isEmpty
          ? null
          : firebaseStorageBucket,
      measurementId: firebaseMeasurementId.isEmpty
          ? null
          : firebaseMeasurementId,
    ),
  );
}

// define を読んだ、このビルドの設定。テストは appConfigFrom に値を渡す。
final appConfig = appConfigFrom(
  target: const String.fromEnvironment('KAZOKUAI_TARGET'),
  web: kIsWeb,
  platform: defaultTargetPlatform,
  backendUrl: const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: _defaultBackendUrl,
  ),
  firebaseApiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
  firebaseAppId: const String.fromEnvironment('FIREBASE_APP_ID'),
  firebaseMessagingSenderId: const String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  ),
  firebaseProjectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
  firebaseAuthDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  firebaseStorageBucket: const String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  ),
  firebaseMeasurementId: const String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  ),
);

// Web では defaultTargetPlatform がブラウザの OS になる。
// iOS は appId が 1:<数字>:ios:<16 進数> の形でないと起動しない。
String _emulatorAppId({required bool web, required TargetPlatform platform}) {
  if (web) return '1:1:web:1';
  return switch (platform) {
    TargetPlatform.android => '1:1:android:1',
    _ => '1:1:ios:1',
  };
}
