import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/tutorial_repository.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/tutorial/tutorial_anchor.dart';
import 'package:kazokuai/features/tutorial/tutorial_overlay.dart';
import 'package:kazokuai/features/tutorial/tutorial_replay.dart';
import 'package:kazokuai/features/tutorial/tutorial_step.dart';

// ホーム、通話記録、予約電話の上に使い方を出す。
// router.dart を読むと循環するので、通話の詳細の道はここで文字列のまま持つ
class TutorialShell extends ConsumerStatefulWidget {
  const TutorialShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<TutorialShell> createState() => _TutorialShellState();
}

class _TutorialShellState extends ConsumerState<TutorialShell> {
  final _registry = TutorialAnchorRegistry();
  late final TutorialRepository _tutorial;
  late final TutorialReplay _replay;
  // 見ていないと分かるまで開かない。Firebase のないテストは見たことにして、ホームを読まない
  HomeRepository? _home;
  List<TutorialStep>? _steps;
  int? _step;
  TutorialPlace? _place;
  var _closed = false;
  var _frameQueued = false;

  @override
  void initState() {
    super.initState();
    _tutorial = ref.read(tutorialRepositoryProvider);
    _tutorial.seen.addListener(_onSeen);
    _replay = ref.read(tutorialReplayProvider);
    _replay.addListener(_onReplay);
    if (_replay.pending) {
      _onReplay();
    } else if (_tutorial.seen.value == false) {
      _attachHome();
      _queueFrame();
    }
  }

  @override
  void dispose() {
    _tutorial.seen.removeListener(_onSeen);
    _replay.removeListener(_onReplay);
    _home?.view.removeListener(_onHome);
    super.dispose();
  }

  void _onSeen() {
    if (_tutorial.seen.value == false) _attachHome();
    _queueFrame();
  }

  void _onReplay() {
    if (!_replay.pending) return;
    _closed = false;
    _attachHome();
    _queueFrame();
  }

  void _onHome() => _queueFrame();

  void _attachHome() {
    if (_home != null) return;
    _home = ref.read(homeRepositoryProvider);
    _home!.view.addListener(_onHome);
  }

  void _queueFrame() {
    if (_frameQueued) return;
    _frameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (!mounted) return;
      if (_replay.pending) {
        _tryReplay();
        return;
      }
      _tryStart();
    });
    // 記録の通知だけでは描画が起きないので、開始するフレームを自分で要求する
    WidgetsBinding.instance.scheduleFrame();
  }

  // 08e から。見た記録は残したまま、ホームの T1 に戻す
  void _tryReplay() {
    if (!_replay.pending) return;
    final view = _home?.view.value;
    if (view == null) return;
    _replay.take();
    final previous = _place;
    setState(() {
      _closed = false;
      _steps = tutorialStepsFor(view.person.callName);
      _step = 0;
      _place = TutorialPlace.home;
    });
    _open(TutorialPlace.home, previous: previous);
  }

  // 見守る方のホームを初めて開いたときだけ。途中で閉じると、次は最初から
  void _tryStart() {
    if (_closed || _step != null) return;
    if (_tutorial.seen.value != false) return;
    final view = _home?.view.value;
    if (view == null) return;
    if (GoRouterState.of(context).uri.path != '/home') return;
    setState(() {
      _steps = tutorialStepsFor(view.person.callName);
      _step = 0;
      _place = TutorialPlace.home;
    });
  }

  void _advance() {
    final steps = _steps;
    final index = _step;
    if (steps == null || index == null) return;
    if (index + 1 >= steps.length) {
      _finish();
      return;
    }
    final next = steps[index + 1];
    _open(next.place, previous: _place);
    setState(() {
      _step = index + 1;
      _place = next.place;
    });
  }

  // 一つ前の段階へ。後ろの画面も、その段階の場所に戻す
  void _back() {
    final steps = _steps;
    final index = _step;
    if (steps == null || index == null || index == 0) return;
    final previousStep = steps[index - 1];
    _open(previousStep.place, previous: _place);
    setState(() {
      _step = index - 1;
      _place = previousStep.place;
    });
  }

  void _finish() {
    if (_closed) return;
    final previous = _place;
    _closed = true;
    setState(() => _step = null);
    _open(TutorialPlace.home, previous: previous);
    unawaited(_markSeen());
  }

  Future<void> _markSeen() async {
    try {
      await _tutorial.markSeen();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
  }

  void _open(TutorialPlace place, {required TutorialPlace? previous}) {
    if (previous == place) return;
    // 詳細を残すと、次に通話記録を開いたとき詳しい内容のままになる。
    // 別の枝から詳細へ戻るときも、古い詳細が残ったまま新しい詳細を足すと、
    // 説明する場所の鍵が重なる。枝の記録は描き直したあとでしか置き換わらないので、
    // いったん一覧に戻してから次の画面へ進む
    final leavingDetail =
        previous == TutorialPlace.callDetail && place != TutorialPlace.calls;
    final enteringDetailFromElsewhere =
        place == TutorialPlace.callDetail && previous != TutorialPlace.calls;
    if (leavingDetail || enteringDetailFromElsewhere) {
      _go(TutorialPlace.calls);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _go(place);
      });
      return;
    }
    _go(place);
  }

  void _go(TutorialPlace place) {
    switch (place) {
      case TutorialPlace.home:
        widget.navigationShell.goBranch(0);
      case TutorialPlace.calls:
        widget.navigationShell.goBranch(1, initialLocation: true);
      case TutorialPlace.callDetail:
        // ID を付けないと見本の詳細が出る
        context.go('/calls/detail');
      case TutorialPlace.booking:
        widget.navigationShell.goBranch(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_replay.pending ||
        (_step == null && !_closed && _tutorial.seen.value == false)) {
      _queueFrame();
    }
    final steps = _steps;
    final index = _step;
    final showing = index != null && steps != null;
    return TutorialAnchors(
      registry: _registry,
      sampling: showing,
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: showing,
            child: Scaffold(
              // 本文をタブバーの下まで伸ばす。タブバーの高さは本文の MediaQuery の padding.bottom に入る
              extendBody: true,
              body: widget.navigationShell,
              bottomNavigationBar: AppTabBar(
                currentIndex: widget.navigationShell.currentIndex,
                onSelected: showing ? (_) {} : widget.navigationShell.goBranch,
              ),
            ),
          ),
          if (showing)
            Positioned.fill(
              child: TutorialOverlay(
                key: ValueKey(steps[index].part),
                step: steps[index],
                index: index,
                registry: _registry,
                onNext: _advance,
                onBack: index == 0 ? null : _back,
                onSkip: _finish,
              ),
            ),
        ],
      ),
    );
  }
}
