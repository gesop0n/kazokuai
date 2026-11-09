import 'package:flutter/widgets.dart';

import 'package:kazokuai/features/tutorial/tutorial_step.dart';

// 説明する場所。シェルが 1 つ持ち、画面の部品はここへ自分の位置を登録する。
// 場所が後から載ったら、案内が位置を測り直す
class TutorialAnchorRegistry extends ChangeNotifier {
  final _keys = <TutorialPart, GlobalKey<_AnchorState>>{};

  GlobalKey<_AnchorState> _keyFor(TutorialPart part) =>
      _keys.putIfAbsent(part, GlobalKey<_AnchorState>.new);

  void _attached() => notifyListeners();

  BuildContext? contextFor(TutorialPart part) {
    final current = _keys[part]?.currentContext;
    if (current == null || !current.mounted || _offstage(current)) return null;
    return current;
  }
}

// タブの裏に残っている部品は、まだ説明する場所ではない
bool _offstage(BuildContext context) {
  var offstage = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) {
      offstage = true;
      return false;
    }
    return true;
  });
  return offstage;
}

class TutorialAnchors extends InheritedWidget {
  const TutorialAnchors({
    super.key,
    required this.registry,
    required this.sampling,
    required super.child,
  });

  final TutorialAnchorRegistry registry;

  // 案内のあいだ、電話がまだない部分はモックの見本を出す
  final bool sampling;

  static TutorialAnchorRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TutorialAnchors>()
        ?.registry;
  }

  static bool samplingOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<TutorialAnchors>()
            ?.sampling ??
        false;
  }

  @override
  bool updateShouldNotify(TutorialAnchors oldWidget) =>
      registry != oldWidget.registry || sampling != oldWidget.sampling;
}

// 登録がない画面では、子をそのまま出す。ギャラリーは案内の枠を持たない
class TutorialAnchor extends StatelessWidget {
  const TutorialAnchor({super.key, required this.part, required this.child});

  final TutorialPart part;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registry = TutorialAnchors.maybeOf(context);
    if (registry == null) return child;
    return _Anchored(
      key: registry._keyFor(part),
      registry: registry,
      child: child,
    );
  }
}

class _Anchored extends StatefulWidget {
  const _Anchored({super.key, required this.registry, required this.child});

  final TutorialAnchorRegistry registry;
  final Widget child;

  @override
  State<_Anchored> createState() => _AnchorState();
}

class _AnchorState extends State<_Anchored> {
  @override
  void initState() {
    super.initState();
    // このフレームの描画が終わってから知らせる。描画の途中では位置を測らない
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.registry._attached();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
