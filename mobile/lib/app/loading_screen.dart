import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';

// ログインした家族に見守る方がいるかを読み終えるまでの画面。
// すぐに読めることが多いので、待っているあいだは何も描かない。
// 読み取りが失敗したときと、サーバーの答えが 10 秒来ないときは、知らせと読み直しのボタンを出す。
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  // 答えが来ないときに、知らせを出すまでの時間
  static const _answerLimit = Duration(seconds: 10);

  Timer? _answerTimer;
  bool _answerTimedOut = false;

  @override
  void initState() {
    super.initState();
    _waitForAnswer();
  }

  @override
  void dispose() {
    _answerTimer?.cancel();
    super.dispose();
  }

  // 読み直したあとも、また 10 秒待つ。前のタイマーの残りでは知らせを出さない
  void _waitForAnswer() {
    _answerTimer?.cancel();
    _answerTimedOut = false;
    _answerTimer = Timer(_answerLimit, () {
      if (!mounted) return;
      setState(() => _answerTimedOut = true);
    });
  }

  void _reload() {
    setState(_waitForAnswer);
    ref.read(watchedPersonRepositoryProvider).reload();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(watchedPersonRepositoryProvider).status;
    return ValueListenableBuilder(
      valueListenable: status,
      builder: (context, value, _) {
        final showNotice =
            value == WatchedPersonStatus.unreadable || _answerTimedOut;
        if (!showNotice) {
          return Scaffold(
            body: Semantics(label: '読み込んでいます', child: const SizedBox.expand()),
          );
        }
        return Scaffold(
          body: SafeArea(
            // ほかの画面と同じく、ボタンをホームバーから離す
            minimum: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _Notice(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppButton(
                    label: 'もう一度読み込む',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.l,
                    onTap: _reload,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Text('見守る方の情報を読み込めませんでした。', style: AppTextStyles.titleL),
    );
  }
}
