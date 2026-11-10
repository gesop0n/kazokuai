import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/bookings_repository.dart';

final _at = DateTime(2026, 11, 6, 8, 30);
const _message = '金曜の通院、10時に迎えに行くと伝えて';
const _script = '「ハナさん、美咲さんからご伝言です。」';

void main() {
  test('予約の保存は、時刻と文を送り、201 で終わる', () async {
    final backend = Backend(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/bookings');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(DateTime.parse(body['at'] as String).toLocal(), _at);
        expect(body['message'], _message);
        expect(body['script'], _script);
        return http.Response(jsonEncode({'id': 'booking-1'}), 201);
      }),
    );

    await backend.createBooking(
      idToken: 'token',
      at: _at,
      message: _message,
      script: _script,
    );
  });

  test('予約の直しは、その予約へ送り、200 で終わる', () async {
    final backend = Backend(
      MockClient((request) async {
        expect(request.url.path, '/bookings/a%2Fb');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(DateTime.parse(body['at'] as String).toLocal(), _at);
        expect(body['message'], '薬の確認');
        expect(body['script'], '「お薬は飲みましたか。」');
        return http.Response(jsonEncode({'id': 'a/b'}), 200);
      }),
    );

    await backend.editBooking(
      idToken: 'token',
      id: 'a/b',
      at: _at,
      message: '薬の確認',
      script: '「お薬は飲みましたか。」',
    );
  });

  test('早すぎる、先すぎる、近い予約は、別の例外になる', () async {
    Future<void> expectCode(String code, Matcher failure) {
      final backend = Backend(
        MockClient(
          (request) async => http.Response(jsonEncode({'error': code}), 409),
        ),
      );
      return expectLater(
        backend.createBooking(
          idToken: 'token',
          at: _at,
          message: _message,
          script: _script,
        ),
        throwsA(failure),
      );
    }

    await expectCode('booking_too_soon', isA<BookingTooSoonException>());
    await expectCode('booking_too_far', isA<BookingTooFarException>());
    await expectCode('booking_too_close', isA<BookingTooCloseException>());
  });

  test('それ以外の失敗は、送れなかった例外になる', () async {
    final responses = [
      http.Response('nope', 500),
      http.Response(jsonEncode({'error': 'booking_not_found'}), 404),
      http.Response(jsonEncode({'error': 'booking_already_called'}), 409),
      http.Response(jsonEncode({'id': 'booking-1'}), 200),
    ];
    for (final response in responses) {
      final backend = Backend(MockClient((request) async => response));
      expect(
        () => backend.createBooking(
          idToken: 'token',
          at: _at,
          message: _message,
          script: _script,
        ),
        throwsA(isA<BookingFailedException>()),
      );
    }

    final dropped = Backend(
      MockClient((request) async => throw http.ClientException('down')),
    );
    expect(
      () => dropped.createBooking(
        idToken: 'token',
        at: _at,
        message: _message,
        script: _script,
      ),
      throwsA(isA<BookingFailedException>()),
    );

    final slow = Backend(
      MockClient((request) async => throw TimeoutException('slow')),
    );
    expect(
      () => slow.createBooking(
        idToken: 'token',
        at: _at,
        message: _message,
        script: _script,
      ),
      throwsA(isA<BookingFailedException>()),
    );
  });
}
