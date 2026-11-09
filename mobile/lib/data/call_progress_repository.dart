import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_call_progress_repository.dart';

// 見守る方の電話が最中かどうか。01 はこれだけを使い、Firebase の型には触れない
abstract interface class CallProgressRepository {
  // 呼び出し中か通話中の電話が 1 つでもあるとき true。
  // まだ読み終えていないときと、電話の最中でないときは false
  ValueListenable<bool> get inProgress;
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
