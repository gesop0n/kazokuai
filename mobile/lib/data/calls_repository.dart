import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_calls_repository.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

// 詳細の 1 画面が持つ、1 件の電話の読み込み。閉じてもほかの画面は止まらない
abstract interface class CallSubscription
    implements ValueListenable<CallDetail?> {
  void close();
}

// 通話記録と、開いている電話の詳細。画面はこれだけを使い、Firebase の型には触れない
abstract interface class CallsRepository {
  // まだ読み終えていないときは null。電話が 1 件もなくても、読み終えると値がある
  ValueListenable<CallLog?> get log;

  // この画面だけの読み込みを始める。届くまでは null
  CallSubscription open(String callId);
}

// テストでは偽物に差し替える
final callsRepositoryProvider = Provider<CallsRepository>((ref) {
  final repository = FirebaseCallsRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    binding: WidgetsBinding.instance,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
