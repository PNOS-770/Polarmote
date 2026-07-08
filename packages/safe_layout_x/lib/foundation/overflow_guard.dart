import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class OverflowGuard extends SingleChildRenderObjectWidget {
  const OverflowGuard({super.key, super.child, this.debugLabel});

  final String? debugLabel;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderOverflowGuard();
  }
}

class _RenderOverflowGuard extends RenderProxyBox {
  ui.Clip? _clipBehavior;

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.hasSize ? child!.size : constraints.smallest;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !child!.hasSize) return;
    if (size.width <= 0.0 || size.height <= 0.0) return;

    final bool doClip = _clipBehavior != ui.Clip.none;
    if (doClip) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
      );
    } else {
      super.paint(context, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null || !child!.hasSize) return false;
    if (size.width <= 0.0 || size.height <= 0.0) return false;

    final bool clipped = _clipBehavior != ui.Clip.none;
    if (clipped) {
      if (!(Offset.zero & size).contains(position)) return false;
    }
    return super.hitTestChildren(result, position: position);
  }

  @override
  void describeSemanticsConfiguration(
    SemanticsConfiguration config,
  ) {
    super.describeSemanticsConfiguration(config);
  }
}
