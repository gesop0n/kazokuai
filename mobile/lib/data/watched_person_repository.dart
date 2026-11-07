import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_watched_person_repository.dart';

// ログインした家族の見守る方。画面はこれだけを使い、Firebase の型には触れない
abstract interface class WatchedPersonRepository {
  // ログインした家族に見守る方がいるかどうか
  ValueListenable<WatchedPersonStatus> get status;

  // バックエンドを通して、ログインした家族の見守る方を登録する。
  // 登録できると status が registered になる。できなかったときは RegisterWatchedPersonException を投げる
  Future<void> register({required String name, required String callName});
}

enum WatchedPersonStatus {
  // まだ読み終えていない。ログインしていないときもこれ
  unknown,
  // 家族に見守る方がいない
  none,
  // 家族に見守る方がいる
  registered,
}

class RegisterWatchedPersonException implements Exception {
  const RegisterWatchedPersonException();

  @override
  String toString() => 'RegisterWatchedPersonException';
}

// テストでは偽物に差し替える
final watchedPersonRepositoryProvider = Provider<WatchedPersonRepository>((
  ref,
) {
  final client = http.Client();
  final repository = FirebaseWatchedPersonRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    backend: Backend(client),
  );
  ref.onDispose(() {
    repository.dispose();
    client.close();
  });
  return repository;
});
