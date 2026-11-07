import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/design/app_text_styles.dart';

void main() {
  test('どの文字も BIZ UDPGothic で、太さは 400 か 700', () {
    // モックの 500 は 400、900 は 700。大きさ、行の高さ、字間はそのまま。
    const styles = <String, (TextStyle, FontWeight, double, double, double)>{
      'display': (
        AppTextStyles.display,
        FontWeight.w700,
        28,
        38 / 28,
        .02 * 28,
      ),
      'titleL': (AppTextStyles.titleL, FontWeight.w700, 24, 32 / 24, .02 * 24),
      'titleM': (AppTextStyles.titleM, FontWeight.w700, 18, 26 / 18, .02 * 18),
      'labelL': (AppTextStyles.labelL, FontWeight.w700, 16, 24 / 16, .02 * 16),
      'labelM': (AppTextStyles.labelM, FontWeight.w400, 14, 20 / 14, .02 * 14),
      'labelS': (AppTextStyles.labelS, FontWeight.w400, 12, 16 / 12, .02 * 12),
      'bodyM': (AppTextStyles.bodyM, FontWeight.w400, 15, 24 / 15, .02 * 15),
      'bodyS': (AppTextStyles.bodyS, FontWeight.w400, 13, 20 / 13, .02 * 13),
      'capM': (AppTextStyles.capM, FontWeight.w400, 17, 28 / 17, .04 * 17),
      'capS': (AppTextStyles.capS, FontWeight.w400, 14, 22 / 14, .03 * 14),
      'monoM': (AppTextStyles.monoM, FontWeight.w400, 14, 18 / 14, 0),
      'monoS': (AppTextStyles.monoS, FontWeight.w400, 12, 16 / 12, 0),
    };

    for (final MapEntry(key: name, value: expected) in styles.entries) {
      final (style, weight, size, height, letterSpacing) = expected;
      expect(style.fontFamily, 'BIZUDPGothic', reason: name);
      expect(style.fontWeight, weight, reason: name);
      expect(style.fontSize, size, reason: name);
      expect(style.height, height, reason: name);
      expect(style.letterSpacing, letterSpacing, reason: name);
      expect(
        style.fontWeight == FontWeight.w400 ||
            style.fontWeight == FontWeight.w700,
        isTrue,
        reason: name,
      );
    }
  });
}
