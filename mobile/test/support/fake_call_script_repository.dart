import 'dart:async';

import 'package:kazokuai/data/call_script_repository.dart';

// 通話内容の案を、テストが直接決める
class FakeCallScriptRepository implements CallScriptRepository {
  FakeCallScriptRepository({
    this.script = '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」',
    this.failing = false,
    this.pending,
    this.onDraft,
  });

  final String script;
  final bool failing;

  // これが終わるまで案を返さない。待っているあいだの表示を見るときに使う
  final Completer<void>? pending;

  // 文ごとの案。渡したときは script と failing と pending は使わない
  final Future<String> Function(String message)? onDraft;

  final List<String> messages = [];

  @override
  Future<String> draft({required String message}) async {
    messages.add(message);
    final onDraft = this.onDraft;
    if (onDraft != null) return onDraft(message);
    final pending = this.pending;
    if (pending != null) await pending.future;
    if (failing) throw const CallScriptException();
    return script;
  }
}
