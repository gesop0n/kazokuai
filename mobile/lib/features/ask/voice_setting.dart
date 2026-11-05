import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';

enum _VoiceOption { normal, alternative, custom }

// 話し方の 1 項目。選んだ内容の送り先はまだないので、この部品の中だけで持つ。
class VoiceSetting extends StatefulWidget {
  const VoiceSetting({
    super.key,
    required this.label,
    required this.alternativeLabel,
    required this.minLabel,
    required this.maxLabel,
    required this.initialValue,
  });

  final String label;
  final String alternativeLabel;
  final String minLabel;
  final String maxLabel;
  // 0 から 100
  final double initialValue;

  @override
  State<VoiceSetting> createState() => _VoiceSettingState();
}

class _VoiceSettingState extends State<VoiceSetting> {
  _VoiceOption _option = _VoiceOption.custom;
  late double _value = widget.initialValue;

  Widget _chip(String label, _VoiceOption option) => AppChip(
    label: label,
    selected: _option == option,
    size: AppChipSize.s,
    onTap: () => setState(() => _option = option),
  );

  @override
  Widget build(BuildContext context) {
    // 文字を大きくしても「ボリューム」が収まり、2 つの項目でチップの左端が揃う幅
    final labelWidth = MediaQuery.textScalerOf(context).scale(64);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Container(
              width: labelWidth,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text(widget.label, style: AppTextStyles.labelS),
            ),
            // モックは折り返さないが、幅 360 や文字倍率 1.3 では 1 行に収まらない
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  _chip('ふつう', _VoiceOption.normal),
                  _chip(widget.alternativeLabel, _VoiceOption.alternative),
                  _chip('カスタマイズ', _VoiceOption.custom),
                ],
              ),
            ),
          ],
        ),
        if (_option == _VoiceOption.custom)
          Padding(
            padding: EdgeInsets.only(left: labelWidth + 8),
            child: Row(
              // モックの 8 だと、丸を端まで動かしたときに文字に 2 重なる
              spacing: 10,
              children: [
                _SliderEndLabel(widget.minLabel),
                Expanded(
                  child: _VoiceSlider(
                    label: widget.label,
                    value: _value,
                    onChanged: (value) => setState(() => _value = value),
                  ),
                ),
                _SliderEndLabel(widget.maxLabel),
              ],
            ),
          ),
      ],
    );
  }
}

// モックの role="slider" の中の文字で、読み上げには aria-label と値だけを渡す
class _SliderEndLabel extends StatelessWidget {
  const _SliderEndLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        text,
        style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
      ),
    );
  }
}

class _VoiceSlider extends StatelessWidget {
  const _VoiceSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: AppColors.inkPrimary,
        inactiveTrackColor: AppColors.lineStrong,
        trackShape: const _VoiceSliderTrackShape(),
        thumbShape: const _VoiceSliderThumbShape(),
        overlayShape: SliderComponentShape.noOverlay,
        showValueIndicator: ShowValueIndicator.never,
        // モックの線は両端の文字のすぐ隣までで、丸は線の端からはみ出す
        padding: EdgeInsets.zero,
      ),
      // モックの行の高さは 28 だが、押せる領域を 44pt にする
      child: SizedBox(
        height: 44,
        child: Slider(
          value: value,
          max: 100,
          label: label,
          semanticFormatterCallback: (value) => '${value.round()}',
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// 既定では左側の線が 2 太くなるが、モックは左右とも同じ太さ
class _VoiceSliderTrackShape extends RoundedRectSliderTrackShape {
  const _VoiceSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}

// 既定の丸には枠がないので描く。枠の外側の直径がモックの 20
class _VoiceSliderThumbShape extends SliderComponentShape {
  const _VoiceSliderThumbShape();

  static const _diameter = 20.0;
  static const _borderWidth = 2.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_diameter);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas
      ..drawCircle(
        center,
        _diameter / 2,
        Paint()..color = AppColors.paperRaised,
      )
      ..drawCircle(
        center,
        (_diameter - _borderWidth) / 2,
        Paint()
          ..color = AppColors.inkPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = _borderWidth,
      );
  }
}
