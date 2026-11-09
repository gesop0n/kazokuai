import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_tutorial_repository.dart';

// この家族が使い方を見終わったか。画面はこれだけを使い、Firebase の型には触れない
abstract interface class TutorialRepository {
  // null はまだ分からない。false のときだけ案内を出す
  ValueListenable<bool?> get seen;

  Future<void> markSeen();
}

// Firebase を起動していないテストは、案内を出さずに今までどおり進む
final _alreadySeen = _AlreadySeen();

class _AlreadySeen implements TutorialRepository {
  final _seen = ValueNotifier<bool?>(true);

  @override
  ValueListenable<bool?> get seen => _seen;

  @override
  Future<void> markSeen() async {}
}

final tutorialRepositoryProvider = Provider<TutorialRepository>((ref) {
  if (Firebase.apps.isEmpty) return _alreadySeen;
  final repository = FirebaseTutorialRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
