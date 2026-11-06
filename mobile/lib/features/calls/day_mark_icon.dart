import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/features/calls/calls_data.dart';

// 電話に出た日の点と、不在の日の ×。印がない日も高さを揃える。
class DayMarkIcon extends StatelessWidget {
  const DayMarkIcon(
    this.mark, {
    super.key,
    this.answeredColor = AppColors.lineStrong,
  });

  final DayMark? mark;
  final Color answeredColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Center(
        child: switch (mark) {
          null => null,
          DayMark.answered => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: answeredColor,
              shape: BoxShape.circle,
            ),
          ),
          DayMark.missed => const CustomPaint(
            size: Size.square(12),
            painter: _MissedMarkPainter(),
          ),
        },
      ),
    );
  }
}

// モックの × は太さ 2.2 で、x.svg を縮めると細くなるので描く
class _MissedMarkPainter extends CustomPainter {
  const _MissedMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentCall
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(2, 2), const Offset(10, 10), paint)
      ..drawLine(const Offset(10, 2), const Offset(2, 10), paint);
  }

  @override
  bool shouldRepaint(_MissedMarkPainter oldDelegate) => false;
}
