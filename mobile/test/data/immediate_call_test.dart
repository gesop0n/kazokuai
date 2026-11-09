import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';

void main() {
  test('今すぐ通話は、伝えたいことと通話内容を送り、201 で終わる', () async {
    final backend = Backend(
      MockClient((request) async {
        expect(request.url.path, '/calls/now');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), {
          'message': '金曜の通院、10時に迎えに行くと伝えて',
          'script': '「ハナさん、美咲さんからご伝言です。」',
        });
        return http.Response(jsonEncode({'id': 'call-1'}), 201);
      }),
    );

    await backend.startImmediateCall(
      idToken: 'token',
      message: '金曜の通院、10時に迎えに行くと伝えて',
      script: '「ハナさん、美咲さんからご伝言です。」',
    );
  });

  test('電話機がつながっていない 409 は、アプリが見分けられる例外になる', () async {
    final backend = Backend(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'phone_not_connected'}), 409),
      ),
    );

    expect(
      () => backend.startImmediateCall(
        idToken: 'token',
        message: '伝えたいこと',
        script: '通話内容',
      ),
      throwsA(isA<PhoneNotConnectedException>()),
    );
  });

  test('電話の最中の 409 は、アプリが見分けられる例外になる', () async {
    final backend = Backend(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'error': 'call_in_progress'}), 409),
      ),
    );

    expect(
      () => backend.startImmediateCall(
        idToken: 'token',
        message: '伝えたいこと',
        script: '通話内容',
      ),
      throwsA(isA<CallInProgressException>()),
    );
  });

  test('それ以外の失敗は、今すぐ通話を始められなかった例外になる', () async {
    final backend = Backend(
      MockClient((request) async => http.Response('nope', 500)),
    );

    expect(
      () => backend.startImmediateCall(
        idToken: 'token',
        message: '伝えたいこと',
        script: '通話内容',
      ),
      throwsA(isA<ImmediateCallException>()),
    );
  });
}
