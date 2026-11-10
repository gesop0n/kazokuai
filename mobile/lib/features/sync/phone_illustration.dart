import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// モックの固定電話。showHash のとき、同期に使う「＃」を赤い点線で囲む。
class PhoneIllustration extends StatelessWidget {
  const PhoneIllustration({super.key, required this.showHash});

  final bool showHash;

  static const svgHeight = 208.0;
  static const _viewWidth = 1465.0;
  static const _viewHeight = 1675.0;
  static const svgWidth = svgHeight * _viewWidth / _viewHeight;

  // viewBox の左上は (235, 125)。＃のキーは (1450, 1366)。点線の先は x=1730。
  static const _hashX = (1450 - 235) / _viewWidth;
  static const _hashY = (1366 - 125) / _viewHeight;
  static const _lineEndX = (1730 - 235) / _viewWidth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paperSunken,
        borderRadius: AppRadius.borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final left = math.max(0.0, (constraints.maxWidth - svgWidth) / 2);
            final hashY = svgHeight * _hashY;
            // 文字が画面の外へ出ないように、点線の先から右へ寄せすぎない
            final reserve = MediaQuery.textScalerOf(context).scale(64);
            final labelLeft = math.min(
              left + svgWidth * _lineEndX + 4,
              math.max(0.0, constraints.maxWidth - reserve),
            );
            return SizedBox(
              height: svgHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    width: svgWidth,
                    height: svgHeight,
                    child: SvgPicture.asset(
                      'assets/icons/phone-device.svg',
                      excludeFromSemantics: true,
                    ),
                  ),
                  if (showHash)
                    Positioned(
                      left: left,
                      top: 0,
                      width: svgWidth,
                      height: svgHeight,
                      child: const CustomPaint(
                        painter: _HashRingPainter(),
                        child: SizedBox.expand(),
                      ),
                    ),
                  if (showHash)
                    Positioned(
                      left: labelLeft,
                      top: hashY - 8,
                      child: const Text('＃ボタン', style: AppTextStyles.labelS),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// モックの device() が＃のキーに描く赤い点線と、その右への線。
class _HashRingPainter extends CustomPainter {
  const _HashRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 1675;
    final center = Offset(
      size.width * PhoneIllustration._hashX,
      size.height * PhoneIllustration._hashY,
    );
    final ring = Paint()
      ..color = AppColors.stateAlert
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18 * scale;
    // 点線は viewBox 上で 40 の線と 40 の空き。半径 150 なので角度は弧の長さ÷半径。
    const dash = 40.0 / 150;
    const gap = 40.0 / 150;
    final radius = 150 * scale;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var angle = 0.0;
    while (angle < math.pi * 2) {
      canvas.drawArc(rect, angle, dash, false, ring);
      angle += dash + gap;
    }
    final line = Paint()
      ..color = AppColors.stateAlert
      ..strokeWidth = 12 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * (1600 - 235) / 1465, center.dy),
      Offset(size.width * PhoneIllustration._lineEndX, center.dy),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _HashRingPainter oldDelegate) => false;
}
