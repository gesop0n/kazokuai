import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/app_config.dart';
import 'package:kazokuai/data/backend.dart';

void main() {
  test('define を渡さないビルドはエミュレーターと localhost を使う', () {
    expect(appConfig.useEmulators, isTrue);
    expect(appConfig.firebase.projectId, 'demo-kazokuai');
    expect(appConfig.backendUrl, 'http://localhost:8080');
  });

  test('ブラウザの OS が macOS でも、Web では Web のアプリ ID を使う', () {
    final config = appConfigFrom(
      target: '',
      web: true,
      platform: TargetPlatform.macOS,
    );

    expect(config.useEmulators, isTrue);
    expect(config.firebase.appId, '1:1:web:1');
    expect(config.firebase.projectId, 'demo-kazokuai');
    expect(config.firebase.authDomain, 'localhost');
    expect(config.backendUrl, 'http://localhost:8080');
  });

  test('Android のエミュレーターは Android のアプリ ID を使う', () {
    final config = appConfigFrom(
      target: 'emulators',
      web: false,
      platform: TargetPlatform.android,
      backendUrl: 'http://10.0.2.2:8080',
    );

    expect(config.useEmulators, isTrue);
    expect(config.firebase.appId, '1:1:android:1');
    expect(config.backendUrl, 'http://10.0.2.2:8080');
  });

  test('本物のプロジェクトは渡した Firebase の設定と /api を使う', () {
    final config = appConfigFrom(
      target: 'production',
      web: true,
      platform: TargetPlatform.macOS,
      backendUrl: 'http://localhost:8080',
      firebaseApiKey: 'key-from-terraform',
      firebaseAppId: '1:4242:web:abcd',
      firebaseMessagingSenderId: '4242',
      firebaseProjectId: 'kazokuai-prod',
      firebaseAuthDomain: 'kazokuai-prod.firebaseapp.com',
      firebaseStorageBucket: 'kazokuai-prod.appspot.com',
    );

    expect(config.useEmulators, isFalse);
    expect(config.backendUrl, '/api');
    expect(config.firebase.apiKey, 'key-from-terraform');
    expect(config.firebase.appId, '1:4242:web:abcd');
    expect(config.firebase.messagingSenderId, '4242');
    expect(config.firebase.projectId, 'kazokuai-prod');
    expect(config.firebase.authDomain, 'kazokuai-prod.firebaseapp.com');
    expect(config.firebase.storageBucket, 'kazokuai-prod.appspot.com');
  });

  test('本物のプロジェクトに設定が足りないと、起動しない', () {
    expect(
      () => appConfigFrom(
        target: 'production',
        web: true,
        platform: TargetPlatform.macOS,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('FIREBASE_API_KEY'),
            contains('FIREBASE_APP_ID'),
            contains('FIREBASE_AUTH_DOMAIN'),
          ),
        ),
      ),
    );
  });

  test('/api の下で、今すぐ通話と見守る方の登録と通話内容の案を呼ぶ', () async {
    final paths = <String>[];
    final backend = Backend(
      MockClient((request) async {
        paths.add(request.url.toString());
        final script = request.url.path == '/api/calls/script';
        return http.Response(
          jsonEncode(script ? {'script': 'draft'} : {'id': 'call-1'}),
          script ? 200 : 201,
        );
      }),
      baseUrl: '/api',
    );

    await backend.startImmediateCall(
      idToken: 'token',
      message: '伝えたいこと',
      script: '通話内容',
    );
    await backend.registerWatchedPerson(
      idToken: 'token',
      name: '田中 ハナ',
      callName: 'ハナさん',
    );
    expect(
      await backend.draftCallScript(idToken: 'token', message: '伝えたいこと'),
      'draft',
    );

    expect(paths, [
      '/api/calls/now',
      '/api/watched-persons',
      '/api/calls/script',
    ]);
  });
}
