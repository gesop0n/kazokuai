import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 08 の「チュートリアル確認」。
// 見たという記録は変えず、ホームで T1 からもう一度出す。
class TutorialReplay extends ChangeNotifier {
  var _generation = 0;
  var _handled = 0;

  bool get pending => _generation != _handled;

  void request() {
    _generation++;
    notifyListeners();
  }

  // 案内を出したら、同じ要求では二度出さない。
  // 出す前にシェルが作り直されても、要求は残る
  void take() {
    if (!pending) return;
    _handled = _generation;
  }
}

final tutorialReplayProvider = Provider<TutorialReplay>((ref) {
  final replay = TutorialReplay();
  ref.onDispose(replay.dispose);
  return replay;
});
