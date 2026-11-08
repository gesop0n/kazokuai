import 'package:flutter/painting.dart';

// モックの --radius。角の丸みは、丸い部品以外はこの値だけを使う。
abstract final class AppRadius {
  static const value = 8.0;

  static const borderRadius = BorderRadius.all(Radius.circular(value));
}
