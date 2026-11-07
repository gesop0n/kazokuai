import 'package:flutter_riverpod/flutter_riverpod.dart';

// L6 の「もどる」が、開く前の画面へ戻すためにルーターと画面で共有する
class SetupReturn {
  // L6 を開く直前にいた場所。読み込み中の画面では覚え直さない
  String? location;

  // true のあいだ、ログアウトしたあとその場所へ戻す
  bool leaving = false;
}

final setupReturnProvider = Provider<SetupReturn>((ref) => SetupReturn());
