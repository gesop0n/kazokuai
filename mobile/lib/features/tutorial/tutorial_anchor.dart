import 'package:flutter/widgets.dart';

import 'package:kazokuai/features/tutorial/tutorial_step.dart';

// 説明する場所。シェルが 1 つ持ち、画面の部品はここへ自分の位置を登録する
class TutorialAnchorRegistry {
  final _keys = <TutorialPart, GlobalKey<_AnchorState>>{};

  GlobalKey<_AnchorState> _keyFor(TutorialPart part) =>
      _keys.putIfAbsent(part, GlobalKey<_AnchorState>.new);

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
    required super.child,
  });

  final TutorialAnchorRegistry registry;

  static TutorialAnchorRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TutorialAnchors>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(TutorialAnchors oldWidget) =>
      registry != oldWidget.registry;
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
    return _Anchored(key: registry._keyFor(part), child: child);
  }
}

class _Anchored extends StatefulWidget {
  const _Anchored({super.key, required this.child});

  final Widget child;

  @override
  State<_Anchored> createState() => _AnchorState();
}

class _AnchorState extends State<_Anchored> {
  @override
  Widget build(BuildContext context) => widget.child;
}
