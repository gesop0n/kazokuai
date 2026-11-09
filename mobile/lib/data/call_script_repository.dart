import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_call_script_repository.dart';

// 01 の通話内容の案。画面はこれだけを使い、Firebase の型には触れない
abstract interface class CallScriptRepository {
  // 伝えたいことから通話内容の案を作る。作れなければ CallScriptException を投げる
  Future<String> draft({required String message});
}

// 通話内容の案を作れなかった
class CallScriptException implements Exception {
  const CallScriptException();

  @override
  String toString() => 'CallScriptException';
}

// テストでは偽物に差し替える
final callScriptRepositoryProvider = Provider<CallScriptRepository>((ref) {
  final client = http.Client();
  final repository = FirebaseCallScriptRepository(
    auth: FirebaseAuth.instance,
    backend: Backend(client),
  );
  ref.onDispose(client.close);
  return repository;
});
