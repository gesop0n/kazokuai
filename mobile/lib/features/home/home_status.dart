import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeStatus { normal, calling, missedCall }

// 不明な値と空の文字は normal にする
HomeStatus homeStatusFromDefine(String value) =>
    HomeStatus.values.asNameMap()[value] ?? HomeStatus.normal;

final homeStatusProvider = NotifierProvider<HomeStatusNotifier, HomeStatus>(
  HomeStatusNotifier.new,
);

class HomeStatusNotifier extends Notifier<HomeStatus> {
  // --dart-define=HOME_STATE=calling または missedCall で初期値を変える
  @override
  HomeStatus build() =>
      homeStatusFromDefine(const String.fromEnvironment('HOME_STATE'));

  // 通話が終わる動きはモックにないので作らない
  void startCall() => state = HomeStatus.calling;
}
