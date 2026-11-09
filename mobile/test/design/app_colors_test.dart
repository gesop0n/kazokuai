import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_colors.dart';

void main() {
  // 期待する値は docs/mock/ui.html の CSS と、その場に書いてある色
  test('色の名前は最新のモックの値を持つ', () {
    expect(AppColors.paperBase, const Color(0xFFF5F5F5));
    expect(AppColors.paperRaised, const Color(0xFFFFFFFF));
    expect(AppColors.paperSunken, const Color(0xFFE2E3E6));
    expect(AppColors.inkPrimary, const Color(0xFF1A1A1A));
    expect(AppColors.inkSecondary, const Color(0xFF4D5359));
    expect(AppColors.inkTertiary, const Color(0xFF6E757C));
    expect(AppColors.line, const Color(0xFFC8C8CB));
    expect(AppColors.lineStrong, const Color(0xFF7F878F));
    expect(AppColors.stateCareSoft, const Color(0xFFFFFF99));
    expect(AppColors.stateOkSoft, const Color(0xFFD5F5E3));
    expect(AppColors.stateAlert, const Color(0xFFDC3800));
    expect(AppColors.onStateAlert, const Color(0xFFFFFFFF));
    expect(AppColors.stateAlertSoft, const Color(0xFFFFE3E3));
    expect(AppColors.nightBase, const Color(0xFF1F2328));
    expect(AppColors.nightLine, const Color(0xFF7F878F));
    expect(AppColors.nightText, const Color(0xFFFFFFFF));
    expect(AppColors.nightTextSecondary, const Color(0xFFD0D3D8));
    expect(AppColors.speakerAi, const Color(0xFF0041FF));
    expect(AppColors.speakerParent, const Color(0xFF663300));
    expect(AppColors.onAvatar, const Color(0xFFFFFFFF));
    expect(AppColors.white, const Color(0xFFFFFFFF));
    expect(AppColors.buttonDisabled, const Color(0xFFD5D6D9));
    expect(AppColors.welcomeIconCircle, const Color(0xFFB4EBFA));
    expect(AppColors.scrim, const Color(0x80000000));
    expect(AppColors.tutorialScrim, const Color.fromRGBO(0, 0, 0, 0.62));
  });
}
