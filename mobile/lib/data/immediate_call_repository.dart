import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/app_config.dart';
import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_immediate_call_repository.dart';

// 01 の今すぐ通話。画面はこれだけを使い、Firebase の型には触れない
abstract interface class ImmediateCallRepository {
  // 伝えたいことと、画面に出ている通話内容で、今すぐ電話をかける。
  // 電話機がつながっていなければ PhoneNotConnectedException、
  // それ以外で始められなければ ImmediateCallException を投げる
  Future<void> start({required String message, required String script});
}

// 電話機がバックエンドにつながっていない
class PhoneNotConnectedException implements Exception {
  const PhoneNotConnectedException();

  @override
  String toString() => 'PhoneNotConnectedException';
}

// 今すぐ通話を始められなかった。つながっていないとき以外
class ImmediateCallException implements Exception {
  const ImmediateCallException();

  @override
  String toString() => 'ImmediateCallException';
}

// テストでは偽物に差し替える
final immediateCallRepositoryProvider = Provider<ImmediateCallRepository>((
  ref,
) {
  final client = http.Client();
  final repository = FirebaseImmediateCallRepository(
    auth: FirebaseAuth.instance,
    backend: Backend(client, baseUrl: appConfig.backendUrl),
  );
  ref.onDispose(client.close);
  return repository;
});
