import 'package:flutter/widgets.dart';

enum DockTarget { top, right, bottom, left, center }

class DragEngine {
  const DragEngine();

  DockTarget resolveTarget({
    required Offset localPosition,
    required Size size,
    double edgeRatio = 0.25,
  }) {
    final dx = localPosition.dx;
    final dy = localPosition.dy;
    final leftZone = size.width * edgeRatio;
    final rightZone = size.width * (1 - edgeRatio);
    final topZone = size.height * edgeRatio;
    final bottomZone = size.height * (1 - edgeRatio);

    if (dy <= topZone) return DockTarget.top;
    if (dy >= bottomZone) return DockTarget.bottom;
    if (dx <= leftZone) return DockTarget.left;
    if (dx >= rightZone) return DockTarget.right;
    return DockTarget.center;
  }
}
