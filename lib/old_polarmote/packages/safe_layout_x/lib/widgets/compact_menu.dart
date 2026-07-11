import 'package:flutter/material.dart';

Future<T?> showCompactMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<PopupMenuEntry<T>> items,
  double minWidth = 108,
  double elevation = 6,
  double radius = 8,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: items,
    elevation: elevation,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    constraints: BoxConstraints(minWidth: minWidth),
    useRootNavigator: true,
    clipBehavior: Clip.antiAlias,
    shadowColor: Colors.black.withValues(alpha: 0.08),
  );
}

PopupMenuItem<T> compactMenuItem<T>({
  required T value,
  required String label,
  bool enabled = true,
  double height = 28,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10),
}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height,
    padding: padding,
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}
