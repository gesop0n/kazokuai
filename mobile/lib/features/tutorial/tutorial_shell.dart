import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/tutorial_repository.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/tutorial/tutorial_anchor.dart';
import 'package:kazokuai/features/tutorial/tutorial_overlay.dart';
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
  // 見ていないと分かるまで開かない。Firebase のないテストは見たことにして、ホームを読まない
  HomeRepository? _home;
  List<TutorialStep>? _steps;
  int? _step;
  TutorialPlace? _place;
  var _closed = false;
  var _startQueued = false;

  @override
  void initState() {
    super.initState();
    _tutorial = ref.read(tutorialRepositoryProvider);
    _tutorial.seen.addListener(_onSeen);
    if (_tutorial.seen.value == false) {
      _attachHome();
      _queueStart();
    }
  }

  @override
  void dispose() {
    _tutorial.seen.removeListener(_onSeen);
    _home?.view.removeListener(_queueStart);
    super.dispose();
  }

  void _onSeen() {
    if (_tutorial.seen.value == false) _attachHome();
    _queueStart();
  }

  void _attachHome() {
    if (_home != null) return;
    _home = ref.read(homeRepositoryProvider);
    _home!.view.addListener(_queueStart);
  }

  void _queueStart() {
    if (_closed || _step != null || _startQueued) return;
    _startQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startQueued = false;
      if (!mounted) return;
      _tryStart();
    });
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
    // 枝の記録は描き直したあとでしか置き換わらないので、一覧に戻してから次の画面へ進む
    if (previous == TutorialPlace.callDetail && place != TutorialPlace.calls) {
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
    if (_step == null && !_closed && _tutorial.seen.value == false) {
      _queueStart();
    }
    final steps = _steps;
    final index = _step;
    final showing = index != null && steps != null;
    return TutorialAnchors(
      registry: _registry,
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
                onSkip: _finish,
              ),
            ),
        ],
      ),
    );
  }
}
