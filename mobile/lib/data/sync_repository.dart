import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/app_config.dart';
import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_sync_repository.dart';

// ログインした家族の同期。画面はこれだけを使い、Firebase の型には触れない。
abstract interface class SyncRepository {
  // 同期の準備を始める。すでに始まっていれば、それを続ける。
  // 1 時間に始めすぎたときは SyncPrepLimitedException、
  // それ以外で始められなければ SyncFailedException を投げる。
  Future<void> start();

  // 6 桁の認証コードを送る。
  // 違うときは SyncCodeWrongException、
  // 準備が終わっているとき（切れたときと、5 回目の間違い）は SyncPrepEndedException、
  // 送れなければ SyncFailedException を投げる。
  Future<void> sendCode(String code);
}

// 1 時間に同期の準備を始めすぎた
class SyncPrepLimitedException implements Exception {
  const SyncPrepLimitedException();

  @override
  String toString() => 'SyncPrepLimitedException';
}

// 認証コードが違う。同期の準備はまだ続く
class SyncCodeWrongException implements Exception {
  const SyncCodeWrongException();

  @override
  String toString() => 'SyncCodeWrongException';
}

// 同期の準備が終わっている。切れたときと、5 回目の間違い
class SyncPrepEndedException implements Exception {
  const SyncPrepEndedException();

  @override
  String toString() => 'SyncPrepEndedException';
}

// 同期の準備を始められなかった、または認証コードを送れなかった
class SyncFailedException implements Exception {
  const SyncFailedException();

  @override
  String toString() => 'SyncFailedException';
}

// テストでは偽物に差し替える
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final client = http.Client();
  final repository = FirebaseSyncRepository(
    auth: FirebaseAuth.instance,
    backend: Backend(client, baseUrl: appConfig.backendUrl),
  );
  ref.onDispose(client.close);
  return repository;
});
