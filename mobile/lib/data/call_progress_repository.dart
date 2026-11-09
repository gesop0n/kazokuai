import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_call_progress_repository.dart';

// 見守る方の電話が最中かどうか。01 はこれだけを使い、Firebase の型には触れない
abstract interface class CallProgressRepository {
  // 呼び出し中か通話中の電話が 1 つでもあるとき true。
  // まだ読み終えていないときと、電話の最中でないときは false。
  // 読み取りが届くたびに知らせる。値が同じでも、01 は断ったあとの確認に使う
  ValueListenable<bool> get inProgress;
}

// 電話の最中かの読み取り。届くたびに知らせ、値が同じでも通知する
class CallProgress extends ValueNotifier<bool> {
  CallProgress(super.value);

  void read(bool inProgress) {
    if (value == inProgress) {
      notifyListeners();
      return;
    }
    value = inProgress;
  }
}

// テストでは偽物に差し替える
final callProgressRepositoryProvider = Provider<CallProgressRepository>((ref) {
  final repository = FirebaseCallProgressRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
