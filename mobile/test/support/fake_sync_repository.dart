import 'dart:async';

import 'package:kazokuai/data/sync_repository.dart';

// 同期の準備と認証コードを、テストが決められるようにする
class FakeSyncRepository implements SyncRepository {
  FakeSyncRepository({this.startError, this.sendError});

  Object? startError;
  Object? sendError;

  int starts = 0;
  final codes = <String>[];

  // 送ったあとに返す。連打が 1 回しか送らないことを確かめるときに使う
  Completer<void>? pendingSend;

  @override
  Future<void> start() async {
    starts++;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendCode(String code) async {
    codes.add(code);
    final pending = pendingSend;
    if (pending != null) await pending.future;
    final error = sendError;
    if (error != null) throw error;
  }
}
