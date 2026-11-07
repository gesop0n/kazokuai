import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/features/account/sample_documents.dart';

// L2c。最後まで読むと「読みました」を押せる。押すと、読んだことにして戻る
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.document});

  final SampleDocument document;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  final _scroll = ScrollController();
  double _progress = 0;
  bool _reachedEnd = false;

  // 文が画面より長いとき、一度最後まで届いたあとは上へ戻しても読んだままにする
  bool _confirmedEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final max = position.maxScrollExtent;
    final progress = max <= 0 ? 1.0 : (position.pixels / max).clamp(0.0, 1.0);
    if (max > 0 && position.pixels >= max - 1) _confirmedEnd = true;
    // 文が画面に収まるときは、開いただけで最後まで読んだことになる
    final reachedEnd = _confirmedEnd || max <= 0;
    if (progress == _progress && reachedEnd == _reachedEnd) return;
    setState(() {
      _progress = progress;
      _reachedEnd = reachedEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: document.title,
              leadingIcon: AppIcons.x,
              leadingLabel: '閉じる',
            ),
            _ReadProgressBar(progress: _progress),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.paperSunken,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          document.notice,
                          style: AppTextStyles.labelS,
                        ),
                      ),
                    ),
                    for (final article in document.articles)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 4,
                        children: [
                          Text(article.heading, style: AppTextStyles.labelL),
                          Text(
                            article.body,
                            style: AppTextStyles.bodyM.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: '読みました',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: _reachedEnd ? () => context.pop(true) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadProgressBar extends StatelessWidget {
  const _ReadProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: '読んだ割合',
      value: '${(fraction * 100).round()}%',
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.lineStrong,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: const ColoredBox(color: AppColors.inkPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
