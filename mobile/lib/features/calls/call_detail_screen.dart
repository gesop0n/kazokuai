import 'package:flutter/material.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/sample_calls_data.dart';

class CallDetailScreen extends StatefulWidget {
  const CallDetailScreen({super.key, this.detail});

  final CallDetail? detail;

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  // 下端の薄くなる重なりの、ホームバーより上の高さ
  static const _fadeHeight = 32.0;

  final _utteranceKeys = <Duration, GlobalKey>{};

  CallDetail get _detail => widget.detail ?? sampleCallDetail;

  void _scrollToUtterance(Duration at) {
    final utterance = _utteranceKeys[at]?.currentContext;
    if (utterance == null) return;
    Scrollable.ensureVisible(
      utterance,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNavBar(title: detail.title),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      _fadeHeight + bottomInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        _SummaryCard(
                          detail: detail,
                          onOpenUtterance: _scrollToUtterance,
                          onCorrect: () => showComingSoon(context),
                        ),
                        const Text('会話の内容', style: AppTextStyles.titleM),
                        for (final utterance in detail.utterances)
                          _UtteranceRow(
                            key: _utteranceKeys.putIfAbsent(
                              utterance.at,
                              GlobalKey.new,
                            ),
                            utterance: utterance,
                            parentCallName: detail.parentCallName,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _fadeHeight + bottomInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.paperBase.withAlpha(0),
                      AppColors.paperBase,
                    ],
                    stops: const [0, .6],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.detail,
    required this.onOpenUtterance,
    required this.onCorrect,
  });

  final CallDetail detail;
  final ValueChanged<Duration> onOpenUtterance;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      // AppCard の間隔は 12 で、モックのこのカードは 8
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text('詳細なまとめ', style: AppTextStyles.labelM),
                Text(
                  formatCallStamp(detail.startedAt, detail.duration),
                  style: AppTextStyles.monoS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const AppAiTag(label: 'Geminiのまとめ。右の時刻で元の発言へ移動します'),
            const SizedBox(height: 8),
            for (final point in detail.points)
              _SummaryRow(point: point, onTap: () => onOpenUtterance(point.at)),
            // 行の下の余白がモックの間隔 8 にあたる
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'まとめの間違いを直す',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sFlush,
                leadingIcon: AppIcons.pencil,
                onTap: onCorrect,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 時刻の押せる領域を 44pt にするので、行の高さも 44 以上にする。モックの 1 行の高さは 33
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.point, required this.onTap});

  static const _timeHitWidth = 44.0;

  final SummaryPoint point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = formatElapsed(point.at);
    return Stack(
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 12,
            children: [
              Expanded(child: Text(point.text, style: AppTextStyles.bodyM)),
              ExcludeSemantics(
                // モックの text-underline-offset 3 は行の下端にあたる。Text の下線は位置を変えられない
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.inkPrimary),
                    ),
                  ),
                  child: Text(time, style: AppTextStyles.monoS),
                ),
              ),
            ],
          ),
        ),
        // 文字の配置を変えないように、押せる領域は行の上に重ねる
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: _timeHitWidth,
          child: AppPressable(
            onTap: onTap,
            foregroundColor: AppColors.inkPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            semanticLabel: '$timeの発言へ移動',
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _UtteranceRow extends StatelessWidget {
  const _UtteranceRow({
    super.key,
    required this.utterance,
    required this.parentCallName,
  });

  final Utterance utterance;
  final String parentCallName;

  @override
  Widget build(BuildContext context) {
    final isAi = utterance.speaker == Speaker.ai;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // 文字が大きくなると 10:00 が幅 40 に入らないので、一緒に広げる
            width: MediaQuery.textScalerOf(context).scale(40),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                formatElapsed(utterance.at),
                style: AppTextStyles.monoS.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            // 気になる発言の背景を文字より 8 左に出すので、列の間隔 8 を中に持つ
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    isAi ? 'AIヘルパー' : parentCallName,
                    style: AppTextStyles.labelS.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isAi
                          ? AppColors.speakerAi
                          : AppColors.speakerParent,
                    ),
                  ),
                ),
                if (utterance.needsAttention)
                  Semantics(
                    label: '気になる発言',
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.stateCareSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(utterance.text, style: AppTextStyles.capS),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(utterance.text, style: AppTextStyles.capS),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
