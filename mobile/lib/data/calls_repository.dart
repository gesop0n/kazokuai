import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_calls_repository.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

// 通話記録と、開いている電話の詳細。画面はこれだけを使い、Firebase の型には触れない
abstract interface class CallsRepository {
  // まだ読み終えていないときは null。電話が 1 件もなくても、読み終えると値がある
  ValueListenable<CallLog?> get log;

  // open した電話の詳細。まだ届いていないときと、その電話がないときは null
  ValueListenable<CallDetail?> get detail;

  void open(String callId);

  void close();
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
