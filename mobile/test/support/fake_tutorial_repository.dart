import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/tutorial_repository.dart';

// 使い方を見たかは、テストが直接決める
class FakeTutorialRepository implements TutorialRepository {
  FakeTutorialRepository({bool? seen = false}) : seen = ValueNotifier(seen);

  @override
  final ValueNotifier<bool?> seen;

  int markCount = 0;

  @override
  Future<void> markSeen() async {
    markCount++;
    seen.value = true;
  }
}
