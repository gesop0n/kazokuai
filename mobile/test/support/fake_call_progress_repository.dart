import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/call_progress_repository.dart';

// 電話の最中かを、テストが直接決める
class FakeCallProgressRepository implements CallProgressRepository {
  FakeCallProgressRepository({bool inProgress = false})
    : inProgress = ValueNotifier(inProgress);

  @override
  final ValueNotifier<bool> inProgress;
}

// 電話の最中ではない。アプリ全体のテストが Firestore を起動せずに 01 を開くために使う
Override idleCallProgress() => callProgressRepositoryProvider.overrideWithValue(
  FakeCallProgressRepository(),
);
