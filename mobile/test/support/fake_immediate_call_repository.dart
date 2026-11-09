import 'package:kazokuai/data/immediate_call_repository.dart';

// 今すぐ通話を、テストが直接決める
class FakeImmediateCallRepository implements ImmediateCallRepository {
  FakeImmediateCallRepository({
    this.disconnected = false,
    this.inProgress = false,
    this.failing = false,
  });

  final bool disconnected;
  final bool inProgress;
  final bool failing;
  final List<({String message, String script})> started = [];

  @override
  Future<void> start({required String message, required String script}) async {
    if (disconnected) throw const PhoneNotConnectedException();
    if (inProgress) throw const CallInProgressException();
    if (failing) throw const ImmediateCallException();
    started.add((message: message, script: script));
  }
}
