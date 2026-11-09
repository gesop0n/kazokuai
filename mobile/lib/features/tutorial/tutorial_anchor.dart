import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:kazokuai/features/tutorial/tutorial_step.dart';

// 説明する場所。シェルが 1 つ持ち、画面の部品はここへ自分の位置を登録する。
// 場所が後から載ったときと、動いたり大きさが変わったときに、案内が位置を測り直す
class TutorialAnchorRegistry extends ChangeNotifier {
  final _keys = <TutorialPart, GlobalKey<_AnchorState>>{};

  GlobalKey<_AnchorState> _keyFor(TutorialPart part) =>
      _keys.putIfAbsent(part, GlobalKey<_AnchorState>.new);

  void _changed() => notifyListeners();

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
      widget.registry._changed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _LayoutSignal(
      onChanged: widget.registry._changed,
      child: widget.child,
    );
  }
}

// 場所の大きさか画面上の位置が変わったら知らせる。上にカードが増えて下がるときも含まれる
class _LayoutSignal extends SingleChildRenderObjectWidget {
  const _LayoutSignal({required this.onChanged, required super.child});

  final VoidCallback onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayoutSignal(onChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLayoutSignal renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderLayoutSignal extends RenderProxyBox {
  _RenderLayoutSignal(this.onChanged);

  VoidCallback onChanged;
  Size? _size;
  Offset? _origin;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!hasSize || !attached) return;
    final size = this.size;
    final origin = localToGlobal(Offset.zero);
    if (size == _size && origin == _origin) return;
    _size = size;
    _origin = origin;
    // 描画の途中では測り直さない。このフレームの配置が終わってから知らせる
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached) return;
      onChanged();
    });
  }
}
