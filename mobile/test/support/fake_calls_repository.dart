import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/sample_calls_data.dart';

// 通話記録に出す中身を、テストが直接決める
class FakeCallsRepository implements CallsRepository {
  FakeCallsRepository({
    CallLog? log,
    Map<String, CallDetail> details = const {},
  }) : log = ValueNotifier(log),
       detail = ValueNotifier(null),
       _details = Map<String, CallDetail>.of(details);

  @override
  final ValueNotifier<CallLog?> log;

  @override
  final ValueNotifier<CallDetail?> detail;

  final Map<String, CallDetail> _details;

  @override
  void open(String callId) {
    detail.value = _details[callId];
  }

  // 画面を閉じても通知しない。次に開くときに open が値を入れる
  @override
  void close() {}
}

// 見本の通話記録。アプリ全体のテストが、Firestore を起動せずに今までどおり進むために使う
Override sampleCalls() => callsRepositoryProvider.overrideWithValue(
  FakeCallsRepository(log: sampleCallLog),
);
