import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:kazokuai/data/call_script_repository.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';

// バックエンドのアドレス。ビルドするときに --dart-define=BACKEND_URL=<アドレス> で変えられる。
// 既定値は backend/main.go の addr と合わせる。iOS のシミュレーターからは localhost で Mac に届く。
// Android のエミュレーターでは http://10.0.2.2:8080 を渡す
const _backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

// アプリがバックエンドの API を呼ぶ。家族の Firebase の ID トークンを Authorization ヘッダーに入れる
class Backend {
  Backend(this._client);

  static const _timeout = Duration(seconds: 15);

  final http.Client _client;

  // 見守る方を登録する。登録できなかったときは RegisterWatchedPersonException を投げる
  Future<void> registerWatchedPerson({
    required String idToken,
    required String name,
    required String callName,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_backendUrl/watched-persons'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'name': name, 'callName': callName}),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw const RegisterWatchedPersonException();
    } on TimeoutException {
      throw const RegisterWatchedPersonException();
    }
    if (response.statusCode != 201) {
      throw const RegisterWatchedPersonException();
    }
  }

  // 通話内容の案を頼む。作れなければ CallScriptException を投げる
  Future<String> draftCallScript({
    required String idToken,
    required String message,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_backendUrl/calls/script'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'message': message}),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw const CallScriptException();
    } on TimeoutException {
      throw const CallScriptException();
    }
    if (response.statusCode != 200) throw const CallScriptException();
    try {
      final decoded = jsonDecode(response.body);
      final script = decoded is Map ? decoded['script'] : null;
      if (script is! String || script.trim().isEmpty) {
        throw const CallScriptException();
      }
      return script;
    } on FormatException {
      throw const CallScriptException();
    }
  }

  // 今すぐ通話を始める。電話機がつながっていなければ PhoneNotConnectedException、
  // それ以外で始められなければ ImmediateCallException を投げる
  Future<void> startImmediateCall({
    required String idToken,
    required String message,
    required String script,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_backendUrl/calls/now'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'message': message, 'script': script}),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw const ImmediateCallException();
    } on TimeoutException {
      throw const ImmediateCallException();
    }
    if (response.statusCode == 409 && _isPhoneNotConnected(response.body)) {
      throw const PhoneNotConnectedException();
    }
    if (response.statusCode != 201) {
      throw const ImmediateCallException();
    }
  }
}

// protocol.PhoneNotConnected と合わせる
const _phoneNotConnected = 'phone_not_connected';

bool _isPhoneNotConnected(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['error'] == _phoneNotConnected;
  } on FormatException {
    return false;
  }
}
