import 'package:kazokuai/data/immediate_call_repository.dart';

// 今すぐ通話を、テストが直接決める
class FakeImmediateCallRepository implements ImmediateCallRepository {
  FakeImmediateCallRepository({
    this.disconnected = false,
    this.inProgress = false,
    this.failing = false,
    this.gate,
  });

  final bool disconnected;
  final bool inProgress;
  final bool failing;

  // 渡すと、例外や成功の前にそれを待つ。拒否が届く前の通知を再現する
  final Future<void>? gate;
  final List<({String message, String script})> started = [];

  @override
  Future<void> start({required String message, required String script}) async {
    final gate = this.gate;
    if (gate != null) await gate;
    if (disconnected) throw const PhoneNotConnectedException();
    if (inProgress) throw const CallInProgressException();
    if (failing) throw const ImmediateCallException();
    started.add((message: message, script: script));
  }
}
