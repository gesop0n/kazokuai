import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/call_script_repository.dart';

void main() {
  test('通話内容の案は、伝えたいことを送り、返った案を読む', () async {
    const script = '「ハナさん、金曜の通院は朝10時にお迎えに行くそうです。」';
    final backend = Backend(
      MockClient((request) async {
        expect(request.url.path, '/calls/script');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), {'message': '金曜の通院、10時に迎えに行くと伝えて'});
        return http.Response.bytes(
          utf8.encode(jsonEncode({'script': script})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    expect(
      await backend.draftCallScript(
        idToken: 'token',
        message: '金曜の通院、10時に迎えに行くと伝えて',
      ),
      script,
    );
  });

  test('案を作れなかったときと、空の案は、案を作れなかった例外になる', () async {
    for (final response in [
      http.Response('nope', 502),
      http.Response(jsonEncode({'script': '  '}), 200),
      http.Response('not-json', 200),
    ]) {
      final backend = Backend(MockClient((request) async => response));
      expect(
        () => backend.draftCallScript(idToken: 'token', message: '伝えたいこと'),
        throwsA(isA<CallScriptException>()),
      );
    }
  });
}
