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
  // 電話の最中なら CallInProgressException、
  // それ以外で始められなければ ImmediateCallException を投げる
  Future<void> start({required String message, required String script});
}

// 電話機がバックエンドにつながっていない
class PhoneNotConnectedException implements Exception {
  const PhoneNotConnectedException();

  @override
  String toString() => 'PhoneNotConnectedException';
}

// 見守る方の電話が呼び出し中か通話中なので、2 つ目を始められなかった
class CallInProgressException implements Exception {
  const CallInProgressException();

  @override
  String toString() => 'CallInProgressException';
}

// 今すぐ通話を始められなかった。つながっていないときと、電話の最中以外
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
