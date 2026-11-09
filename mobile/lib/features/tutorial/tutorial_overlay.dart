import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/tutorial/tutorial_anchor.dart';
import 'package:kazokuai/features/tutorial/tutorial_step.dart';

// 明るい枠。テストが位置を読む。枠の線はスクリムの方に描く
class TutorialHole extends StatelessWidget {
  const TutorialHole({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.step,
    required this.index,
    required this.registry,
    required this.onNext,
    required this.onSkip,
  });

  final TutorialStep step;

  // 0 から
  final int index;
  final TutorialAnchorRegistry registry;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  // モックの placeTut。対象の外へ 6、説明は穴の 12 下。入らなければ上
  static const _pad = 6.0;
  static const _gap = 12.0;
  static const _margin = 16.0;
  static const _bottomClearance = 40.0;
  static const _maxTicks = 90;

  final _tipKey = GlobalKey();
  Rect? _hole;
  double? _tipTop;
  var _ticks = 0;
  var _stable = 0;
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onTarget);
    _arm();
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onTarget);
    super.dispose();
  }

  // 説明する場所が後から載ったときと、動いたり大きさが変わったときに測り直す。
  // 穴があるときも止めたままにしない。返答カードが直近の電話の上に出ると、場所は下がる
  void _onTarget() {
    if (!mounted) return;
    _ticks = 0;
    _stable = 0;
    if (_hole == null) _revealed = false;
    _arm();
  }

  void _arm() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _tick() {
    if (!mounted) return;
    _ticks++;
    final target = widget.registry.contextFor(widget.step.part);
    if (target != null && !_revealed) {
      _revealed = true;
      _revealIfNeeded(target);
      _arm();
      return;
    }
    // 画面が切り替わるまで、説明する場所を待つ
    if (target == null && _ticks < _maxTicks) {
      _arm();
      return;
    }
    final next = _place(target);
    if (next.top == null) {
      if (_ticks < _maxTicks) _arm();
      return;
    }
    final changed = next.hole != _hole || next.top != _tipTop;
    if (changed) {
      setState(() {
        _hole = next.hole;
        _tipTop = next.top;
      });
      _stable = 0;
    } else {
      _stable++;
    }
    // 位置が止まってからも、アニメーションの途中で打ち切らない
    if (_stable < 2 && _ticks < _maxTicks) _arm();
  }

  void _revealIfNeeded(BuildContext target) {
    final scrollable = Scrollable.maybeOf(target);
    if (scrollable == null) return;
    if (!widget.step.alignTop && _fullyVisible(target, scrollable)) return;
    Scrollable.ensureVisible(
      target,
      alignment: widget.step.alignTop ? 0 : 0.05,
      duration: Duration.zero,
    );
  }

  bool _fullyVisible(BuildContext target, ScrollableState scrollable) {
    final viewport = scrollable.context.findRenderObject();
    final box = target.findRenderObject();
    if (viewport is! RenderBox ||
        box is! RenderBox ||
        !box.hasSize ||
        !viewport.hasSize) {
      return false;
    }
    final origin = viewport.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = origin & box.size;
    return rect.top >= -1 &&
        rect.bottom <= viewport.size.height + 1 &&
        rect.left >= -1 &&
        rect.right <= viewport.size.width + 1;
  }

  ({Rect? hole, double? top}) _place(BuildContext? target) {
    final overlay = context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) {
      return (hole: null, top: null);
    }
    final tipBox = _tipKey.currentContext?.findRenderObject();
    final tipHeight = tipBox is RenderBox && tipBox.hasSize
        ? tipBox.size.height
        : 0.0;
    final height = overlay.size.height;
    if (target == null) {
      return (hole: null, top: _center(height, tipHeight));
    }
    final box = target.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      return (hole: null, top: null);
    }
    final origin = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    final hole = (origin & box.size).inflate(_pad);
    return (hole: hole, top: _tipTopFor(hole, tipHeight, height));
  }

  double _tipTopFor(Rect hole, double tipHeight, double height) {
    final below = hole.bottom + _gap;
    if (below + tipHeight <= height - _bottomClearance) return below;
    final above = hole.top - _gap - tipHeight;
    if (above >= _margin) return above;
    return _margin;
  }

  double _center(double height, double tipHeight) {
    final maxTop = height - tipHeight - _margin;
    final top = (height - tipHeight) / 2;
    if (maxTop < _margin) return _margin;
    return top.clamp(_margin, maxTop);
  }

  @override
  Widget build(BuildContext context) {
    final placed = _tipTop != null;
    final number = widget.index + 1;
    return SizedBox.expand(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _ScrimPainter(_hole))),
            if (_hole != null)
              Positioned.fromRect(
                rect: _hole!,
                child: const IgnorePointer(child: TutorialHole()),
              ),
            Positioned(
              left: _margin,
              right: _margin,
              top: _tipTop ?? 0,
              child: IgnorePointer(
                ignoring: !placed,
                child: Opacity(
                  opacity: placed ? 1 : 0,
                  child: _Tip(
                    key: _tipKey,
                    number: number,
                    step: widget.step,
                    onNext: widget.onNext,
                    onSkip: widget.onSkip,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.hole);

  static const _dim = AppColors.tutorialScrim;
  static const _radius = Radius.circular(14);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = this.hole;
    final path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      // 穴が全体の中に収まると、Web では Path.combine の差分が抜けない。
      // 偶奇塗りなら全体と穴を一つの線にして、Web でも iOS でも中が明るく残る
      path
        ..fillType = PathFillType.evenOdd
        ..addRRect(RRect.fromRectAndRadius(hole, _radius));
    }
    canvas.drawPath(path, Paint()..color = _dim);
    if (hole == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, _radius),
      Paint()
        ..color = AppColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) => oldDelegate.hole != hole;
}

class _Tip extends StatelessWidget {
  const _Tip({
    super.key,
    required this.number,
    required this.step,
    required this.onNext,
    required this.onSkip,
  });

  final int number;
  final TutorialStep step;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final last = number == 9;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: '使い方 $number/9',
      // 説明は Scaffold の外に出す。Material が無いと、文字はフォールバックの赤と二重下線になる。
      // 既定の文字はモックの body-m。見出しとラベルはそれぞれの文字にする
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.paperRaised,
          borderRadius: AppRadius.borderRadius,
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.25),
              offset: Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          textStyle: AppTextStyles.bodyM.copyWith(
            color: AppColors.inkPrimary,
            decoration: TextDecoration.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Text(
                      '使い方 $number/9',
                      style: AppTextStyles.labelS.copyWith(
                        color: AppColors.inkSecondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    _Progress(filled: number),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    Text(
                      step.title,
                      style: AppTextStyles.titleM.copyWith(
                        color: AppColors.inkPrimary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      step.body,
                      style: AppTextStyles.bodyM.copyWith(
                        color: AppColors.inkSecondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      // モックの T9 は「はじめる」だけだが、仕様はどの段階にもスキップを置く。
                      // AppButton は親の幅いっぱいに広がるので、文字の幅で押せるようにする
                      _SkipButton(onTap: onSkip),
                      const Spacer(),
                      _NextButton(label: last ? 'はじめる' : '次へ', onTap: onNext),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '9段階のうち$filled段階目',
      child: SizedBox(
        width: 110,
        height: 4,
        // 子は高さ 0 に縮む。親の 4 まで伸ばして、モックの進度を見せる
        child: Row(
          spacing: 6,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 9; i++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: i < filled
                        ? AppColors.inkPrimary
                        : AppColors.lineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkSecondary,
      shape: const RoundedRectangleBorder(),
      minHeight: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // 文字をそのまま置くと最小の高さまで伸び、上に寄って下線が離れる。行の中で中央に置く。
      // 下線は文字の箱の下端。Text の下線ではモックの位置にできない
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.inkSecondary)),
            ),
            child: Text(
              'スキップ',
              style: AppTextStyles.labelM.copyWith(
                color: AppColors.inkSecondary,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.paperRaised,
      backgroundColor: AppColors.inkPrimary,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.borderRadius),
      minHeight: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      // 文字をそのまま置くと最小の高さまで伸び、上に寄る
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.labelM.copyWith(
              color: AppColors.paperRaised,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
