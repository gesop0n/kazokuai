import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/calls_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';
import 'package:kazokuai/features/calls/sample_calls_data.dart';

class CallDetailScreen extends ConsumerStatefulWidget {
  const CallDetailScreen({super.key, this.detail, this.callId});

  // 見本を確かめるときだけ渡す。callId があるときは Firestore のその電話を出す
  final CallDetail? detail;
  final String? callId;

  @override
  ConsumerState<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends ConsumerState<CallDetailScreen> {
  final _utteranceKeys = <int, GlobalKey>{};
  CallSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _listen(widget.callId);
  }

  @override
  void didUpdateWidget(CallDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detail != null || widget.callId == oldWidget.callId) return;
    _utteranceKeys.clear();
    _listen(widget.callId);
  }

  // 見本の詳細はリポジトリを開かない。閉じるときに ref を使わないよう、開いた読み込みを覚えておく
  void _listen(String? callId) {
    _subscription?.close();
    _subscription = null;
    if (widget.detail != null || callId == null) return;
    _subscription = ref.read(callsRepositoryProvider).open(callId);
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  // 時刻が同じ発言が並んでも、キーは行ごとに分ける。時刻の移動先は、その時刻の最初の行
  void _scrollToUtterance(List<Utterance> utterances, Duration at) {
    final index = utterances.indexWhere((utterance) => utterance.at == at);
    if (index < 0) return;
    final target = _utteranceKeys[index]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // 通話記録のタブに戻す。ホームから開いたときも、戻る先は 04
  void _returnToCallLog() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.goNamed(AppRoutes.calls);
  }

  @override
  Widget build(BuildContext context) {
    final explicit = widget.detail;
    if (explicit != null) return _page(explicit);
    if (widget.callId == null) return _page(sampleCallDetail);
    final subscription = _subscription;
    if (subscription == null) return _loading();
    return ValueListenableBuilder(
      valueListenable: subscription,
      builder: (context, detail, _) {
        if (detail == null) return _loading();
        return _page(detail);
      },
    );
  }

  // 詳細が届くまでは見本を出さない
  Widget _loading() {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: '',
              leadingLabel: '通話記録にもどる',
              onLeadingTap: _returnToCallLog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(CallDetail detail) {
    // タブの中では、この余白がタブバーの高さ。下の余白は 16 を足す
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: detail.title,
              leadingLabel: '通話記録にもどる',
              onLeadingTap: _returnToCallLog,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    _SummaryCard(
                      detail: detail,
                      onOpenUtterance: (at) =>
                          _scrollToUtterance(detail.utterances, at),
                      onCorrect: () => showComingSoon(context),
                    ),
                    const Text('会話の内容', style: AppTextStyles.titleM),
                    for (
                      var index = 0;
                      index < detail.utterances.length;
                      index++
                    )
                      _UtteranceRow(
                        key: _utteranceKeys.putIfAbsent(index, GlobalKey.new),
                        utterance: detail.utterances[index],
                        parentCallName: detail.parentCallName,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                const Text('通話時間', style: AppTextStyles.labelM),
                Text(
                  formatCallStamp(detail.startedAt, detail.duration),
                  style: AppTextStyles.monoS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (detail.summaryFailure case final failure?)
              Text(failure, style: AppTextStyles.bodyM),
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
                  child: Row(
                    spacing: 8,
                    children: [
                      Text(
                        isAi ? 'AIヘルパー' : parentCallName,
                        style: AppTextStyles.labelS.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isAi
                              ? AppColors.speakerAi
                              : AppColors.speakerParent,
                        ),
                      ),
                      if (utterance.needsAttention)
                        const AppPill(
                          variant: AppPillVariant.care,
                          icon: AppIcons.alert,
                          label: '気になる話',
                        ),
                    ],
                  ),
                ),
                if (utterance.needsAttention)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.stateCareSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.inkSecondary),
                    ),
                    child: Text(utterance.text, style: AppTextStyles.capS),
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
