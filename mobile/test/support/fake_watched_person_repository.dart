import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/watched_person_repository.dart';

// 登録を頼まれた名前と呼び方を覚えておく
class FakeWatchedPersonRepository implements WatchedPersonRepository {
  FakeWatchedPersonRepository({
    WatchedPersonStatus status = WatchedPersonStatus.registered,
    this.failing = false,
  }) : status = ValueNotifier(status);

  @override
  final ValueNotifier<WatchedPersonStatus> status;

  // true のときは、登録がいつも失敗する
  final bool failing;

  final registrations = <({String name, String callName})>[];

  // 画面が読み直しを頼んだ回数
  int reloads = 0;

  @override
  void reload() {
    reloads++;
    status.value = WatchedPersonStatus.unknown;
  }

  @override
  Future<void> register({
    required String name,
    required String callName,
  }) async {
    if (failing) throw const RegisterWatchedPersonException();
    registrations.add((name: name, callName: callName));
    status.value = WatchedPersonStatus.registered;
  }
}

// 見守る方を登録した家族としてアプリを開く。signedInAuth() と一緒に使う
Override registeredWatchedPerson() => watchedPersonRepositoryProvider
    .overrideWithValue(FakeWatchedPersonRepository());
