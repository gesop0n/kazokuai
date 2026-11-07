import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_home_repository.dart';
import 'package:kazokuai/features/home/home_data.dart';

// ホームに出す、見守る方と電話。画面はこれだけを使い、Firebase の型には触れない。
// 見守る方がいるかどうかの読み方は、別のリポジトリが受け持つ
abstract interface class HomeRepository {
  // まだ読み終えていないときは null。読み終えると、電話が 1 件もなくても値がある
  ValueListenable<HomeView?> get view;
}

// テストでは偽物に差し替える
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final repository = FirebaseHomeRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    binding: WidgetsBinding.instance,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
