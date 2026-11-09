import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/call_progress_repository.dart';

// 電話の最中かを、テストが直接決める
class FakeCallProgressRepository implements CallProgressRepository {
  FakeCallProgressRepository({bool inProgress = false})
    : _progress = _SeenProgress(inProgress);

  final _SeenProgress _progress;

  @override
  CallProgress get inProgress => _progress;

  // read で届いた値を返す。まだ read されていない false は、読み終えていないだけで、終わったことではない
  @override
  Future<bool?> refresh() async {
    if (!_progress.seen) return null;
    _progress.read(_progress.value);
    return _progress.value;
  }
}

class _SeenProgress extends CallProgress {
  _SeenProgress(super.value);

  bool seen = false;

  @override
  void read(bool inProgress) {
    seen = true;
    super.read(inProgress);
  }
}

// 電話の最中ではない。アプリ全体のテストが Firestore を起動せずに 01 を開くために使う
Override idleCallProgress() => callProgressRepositoryProvider.overrideWithValue(
  FakeCallProgressRepository(),
);
