import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kazokuai/data/app_config.dart';
import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/firebase_watched_person_repository.dart';

// ログインした家族の見守る方。画面はこれだけを使い、Firebase の型には触れない
abstract interface class WatchedPersonRepository {
  // ログインした家族に見守る方がいるかどうか
  ValueListenable<WatchedPersonStatus> get status;

  // バックエンドを通して、ログインした家族の見守る方を登録する。
  // 登録できると status が registered になる。できなかったときは RegisterWatchedPersonException を投げる
  Future<void> register({required String name, required String callName});

  // 同期で名前のない見守る方ができたとき、Firestore の知らせを待たずに unnamed にする。
  // すでに名前があるときは変えない。
  void noteLinkedWithoutName();

  // 見守る方を読み直す。待っているあいだ status は unknown になり、画面は何も描かない
  void reload();
}

enum WatchedPersonStatus {
  // まだ読み終えていない。ログインしていないときもこれ
  unknown,
  // 家族に見守る方がいない。新規登録は L3 から始める
  none,
  // 見守る方はいるが、名前が空。同期のあと、L6 で名前を入れる
  unnamed,
  // 見守る方に名前がある。電話機がなくてもホームを開く
  registered,

  // 読み取りが失敗した。いるかどうかは、まだ分からない
  unreadable,
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
    backend: Backend(client, baseUrl: appConfig.backendUrl),
  );
  ref.onDispose(() {
    repository.dispose();
    client.close();
  });
  return repository;
});
