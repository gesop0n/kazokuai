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
       _details = Map<String, CallDetail>.of(details);

  @override
  final ValueNotifier<CallLog?> log;

  final Map<String, CallDetail> _details;

  @override
  CallSubscription open(String callId) =>
      _FakeCallSubscription(_details[callId]);
}

// 閉じても値は変えない。次に開く画面は、自分の open が値を持つ
class _FakeCallSubscription extends ValueNotifier<CallDetail?>
    implements CallSubscription {
  _FakeCallSubscription(super.value);

  @override
  void close() {}
}

// 見本の通話記録。アプリ全体のテストが、Firestore を起動せずに今までどおり進むために使う
Override sampleCalls() => callsRepositoryProvider.overrideWithValue(
  FakeCallsRepository(log: sampleCallLog),
);
