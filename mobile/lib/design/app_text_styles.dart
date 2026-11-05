import 'package:flutter/painting.dart';

// letterSpacing は em×サイズ、height は 行の高さ÷サイズ で書く。色は持たせない。
abstract final class AppTextStyles {
  static const _zen = 'ZenMaruGothic';
  static const _mincho = 'ShipporiMincho';
  static const _mono = 'DMMono';

  static const display = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w900,
    fontSize: 28,
    height: 38 / 28,
    letterSpacing: .02 * 28,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const titleL = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 32 / 24,
    letterSpacing: .02 * 24,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const titleM = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 26 / 18,
    letterSpacing: .02 * 18,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const labelL = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: .02 * 16,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const labelM = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: .02 * 14,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const labelS = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: .02 * 12,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const bodyM = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 24 / 15,
    letterSpacing: .02 * 15,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const bodyS = TextStyle(
    fontFamily: _zen,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 20 / 13,
    letterSpacing: .02 * 13,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const capM = TextStyle(
    fontFamily: _mincho,
    fontWeight: FontWeight.w500,
    fontSize: 17,
    height: 28 / 17,
    letterSpacing: .04 * 17,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const capS = TextStyle(
    fontFamily: _mincho,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 22 / 14,
    letterSpacing: .03 * 14,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // 親の TextStyle から字間を引き継がないように 0 を明示する
  static const monoM = TextStyle(
    fontFamily: _mono,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 18 / 14,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const monoS = TextStyle(
    fontFamily: _mono,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
}
