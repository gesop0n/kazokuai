import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/sync_repository.dart';

void main() {
  test('同期の準備は /sync を呼び、200 でも 201 でも終わる', () async {
    for (final status in [200, 201]) {
      final backend = Backend(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sync');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({'expiresAt': '2026-11-10T00:10:00Z'}),
            status,
          );
        }),
      );

      await backend.startSync(idToken: 'token');
    }
  });

  test('同期の準備を始めすぎた 429 は、アプリが見分けられる例外になる', () async {
    final backend = Backend(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'sync_prep_limited'}), 429),
      ),
    );

    expect(
      () => backend.startSync(idToken: 'token'),
      throwsA(isA<SyncPrepLimitedException>()),
    );
  });

  test('それ以外で同期の準備を始められなければ、失敗の例外になる', () async {
    Future<void> expectFailed(http.Client client) {
      return expectLater(
        () => Backend(client).startSync(idToken: 'token'),
        throwsA(isA<SyncFailedException>()),
      );
    }

    await expectFailed(
      MockClient((request) async => http.Response('nope', 500)),
    );
    await expectFailed(
      MockClient(
        (request) async => http.Response(jsonEncode({'error': 'other'}), 429),
      ),
    );
    await expectFailed(
      MockClient((request) async => throw http.ClientException('down')),
    );
    await expectFailed(
      MockClient((request) async => throw TimeoutException('slow')),
    );
  });

  test('認証コードは /sync/code に送り、200 でも 201 でも終わる', () async {
    for (final status in [200, 201]) {
      final backend = Backend(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sync/code');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(request.headers['Content-Type'], 'application/json');
          expect(jsonDecode(request.body), {'code': '123456'});
          return http.Response(jsonEncode({'watchedPersonId': 'hana'}), status);
        }),
      );

      await backend.sendSyncCode(idToken: 'token', code: '123456');
    }
  });

  test('違う認証コードの 400 は、アプリが見分けられる例外になる', () async {
    final backend = Backend(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'sync_code_wrong'}), 400),
      ),
    );

    expect(
      () => backend.sendSyncCode(idToken: 'token', code: '123456'),
      throwsA(isA<SyncCodeWrongException>()),
    );
  });

  test('準備が終わった 409 は、アプリが見分けられる例外になる', () async {
    final backend = Backend(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'sync_prep_ended'}), 409),
      ),
    );

    expect(
      () => backend.sendSyncCode(idToken: 'token', code: '123456'),
      throwsA(isA<SyncPrepEndedException>()),
    );
  });

  test('それ以外で認証コードを送れなければ、失敗の例外になる', () async {
    Future<void> expectFailed(http.Client client) {
      return expectLater(
        () => Backend(client).sendSyncCode(idToken: 'token', code: '123456'),
        throwsA(isA<SyncFailedException>()),
      );
    }

    await expectFailed(
      MockClient((request) async => http.Response('nope', 500)),
    );
    await expectFailed(
      MockClient(
        (request) async => http.Response(jsonEncode({'error': 'other'}), 400),
      ),
    );
    await expectFailed(
      MockClient((request) async => throw http.ClientException('down')),
    );
    await expectFailed(
      MockClient((request) async => throw TimeoutException('slow')),
    );
  });
}
