import 'package:flutter/painting.dart';

abstract final class AppColors {
  static const paperBase = Color(0xFFF1F1F1);
  static const paperRaised = Color(0xFFFFFFFF);
  static const paperSunken = Color(0xFFE2E3E6);

  static const inkPrimary = Color(0xFF1A1A1A);
  static const inkSecondary = Color(0xFF4D5359);

  // モックの ink-3。これからの日の文字に使う
  static const inkTertiary = Color(0xFF6E757C);
  static const line = Color(0xFFC8C8CB);
  static const lineStrong = Color(0xFF7F878F);

  static const accentCall = Color(0xFF0041FF);
  static const onAccentCall = Color(0xFFFFFFFF);

  static const stateCareSoft = Color(0xFFFFFF99);
  static const stateOkSoft = Color(0xFFD5F5E3);
  static const stateAlert = Color(0xFFDC3800);
  static const onStateAlert = Color(0xFFFFFFFF);
  static const stateAlertSoft = Color(0xFFFFE3E3);

  static const nightBase = Color(0xFF1F2328);
  static const nightLine = Color(0xFF7F878F);
  static const nightText = Color(0xFFFFFFFF);
  static const nightTextSecondary = Color(0xFFD0D3D8);

  static const speakerAi = Color(0xFF0041FF);
  static const speakerParent = Color(0xFF663300);

  static const onAvatar = Color(0xFFFFFFFF);

  // モックが押せないボタンに直接書く背景
  static const buttonDisabled = Color(0xFFD5D6D9);

  // モックが L1 のアイコンの円に直接書く色
  static const welcomeIconCircle = Color(0xFFB4EBFA);

  // シートの後ろの暗い幕。モックの rgba(0, 0, 0, .5)
  static const scrim = Color(0x80000000);
}
